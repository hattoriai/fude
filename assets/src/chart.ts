// A chart on the page: it reads its config (data-fude), lays out its
// scales as wide as it is, draws its marks on a canvas and its words
// (axes, labels, legend, tooltip) as DOM, and draws again in place when
// the config changes, moving each mark from where it was.

import { alpha, ramp, readTheme, type Theme } from "./theme";
import { formatTime, formatter, tickFormatter, timeTickFormatter } from "./format";
import { position, type Position } from "./scale";
import { draw, easeOut, tween, type Datum, type Paint, type PathShape, type Shape } from "./shapes";
import { loadMap, type LoadedMap } from "./maps";
import type { Config, Layer, Scale } from "./wire";

export interface Transport {
  push(event: string, payload: object, onReply?: (reply: Record<string, unknown>) => void): void;
}

interface Layout {
  width: number;
  height: number;
  left: number;
  top: number;
  right: number;
  bottom: number;
  x?: Position;
  y?: Position;
  labels: { text: string; y: number; at: number; color: string }[];
}

type Hover =
  | { kind: "x"; k: string; px: number }
  | { kind: "mark"; key: string; datum: Datum; px: number; py: number };

const SVG = "http://www.w3.org/2000/svg";
const FONT_SIZE = 12;

export class Chart {
  readonly id: string;
  private el: HTMLElement;
  private plot: HTMLElement | null;
  private stage!: HTMLElement;
  private legend!: HTMLElement;
  private canvas!: HTMLCanvasElement;
  private svg!: SVGSVGElement;
  private grid!: SVGSVGElement;
  private tip!: HTMLElement;
  private live!: HTMLElement;
  private config: Config;
  private raw: string;
  private theme: Theme;
  private locale: string | undefined;
  private layout: Layout | null = null;
  private shapes: Shape[] = [];
  private drawn = new Map<string, Shape>();
  private leaving: Shape[] = [];
  private frame = 0;
  private hover: Hover | null = null;
  private highlight: number | null = null;
  private hidden = new Set<number>();
  private cursor = -1;
  private observers: { disconnect(): void }[] = [];
  private measurer: CanvasRenderingContext2D | null = null;
  private geo: LoadedMap | null = null;
  private note!: HTMLElement;
  private names = new Map<string, string>();

  constructor(el: HTMLElement, _transport: Transport | null) {
    this.el = el;
    this.raw = el.dataset.fude ?? "{}";
    this.config = JSON.parse(this.raw) as Config;
    this.id = this.config.id ?? el.id;
    this.locale = this.config.locale ?? undefined;
    this.theme = readTheme(el);
    this.plot = el.querySelector<HTMLElement>(".fude-plot");
    this.formatSingles();
    if (!this.plot) return;
    this.build(this.plot);
    this.render(true);
    this.observe();
  }

  /** Takes the server's new render: draws again, moving the marks. */
  update(): void {
    const raw = this.el.dataset.fude ?? "{}";
    this.formatSingles();
    if (raw === this.raw) return;
    this.raw = raw;
    this.config = JSON.parse(raw) as Config;
    this.locale = this.config.locale ?? undefined;
    this.hover = null;
    this.hideTip();
    if (this.plot) this.render(true);
  }

  destroy(): void {
    cancelAnimationFrame(this.frame);
    for (const observer of this.observers) observer.disconnect();
    this.observers = [];
  }

  // -- DOM ------------------------------------------------------------------

  private build(plot: HTMLElement): void {
    plot.replaceChildren();
    plot.removeAttribute("role");
    plot.removeAttribute("aria-label");
    this.legend = div("fude-legend");
    this.stage = div("fude-stage");
    this.stage.tabIndex = 0;
    this.stage.setAttribute("role", "group");
    this.stage.setAttribute("aria-roledescription", "chart");
    this.canvas = document.createElement("canvas");
    this.canvas.className = "fude-canvas";
    this.canvas.setAttribute("aria-hidden", "true");
    this.svg = document.createElementNS(SVG, "svg");
    this.svg.setAttribute("class", "fude-axes");
    this.svg.setAttribute("aria-hidden", "true");
    // The grid goes under the marks, the words over them.
    this.grid = document.createElementNS(SVG, "svg");
    this.grid.setAttribute("class", "fude-axes fude-grid");
    this.grid.setAttribute("aria-hidden", "true");
    this.tip = div("fude-tooltip");
    this.tip.setAttribute("aria-hidden", "true");
    this.live = div("fude-live");
    this.live.setAttribute("aria-live", "polite");
    this.note = div("fude-note");
    this.note.hidden = true;
    this.stage.append(this.grid, this.canvas, this.svg, this.tip, this.note);
    plot.append(this.legend, this.stage, this.live);

    this.stage.addEventListener("pointermove", (event) => this.onPointer(event));
    this.stage.addEventListener("pointerleave", () => this.setHover(null));
    this.stage.addEventListener("keydown", (event) => this.onKey(event));
    this.stage.addEventListener("blur", () => this.setHover(null));
  }

  private observe(): void {
    if (typeof ResizeObserver === "function" && this.plot) {
      let width = 0;
      const resize = new ResizeObserver(() => {
        const now = this.stage.clientWidth;
        if (now !== width) {
          width = now;
          this.render(false);
        }
      });
      resize.observe(this.plot);
      this.observers.push(resize);
    }
    const retheme = () => {
      this.theme = readTheme(this.el);
      this.render(false);
    };
    const mutation = new MutationObserver(retheme);
    mutation.observe(document.documentElement, { attributes: true, attributeFilter: ["class", "data-theme"] });
    this.observers.push(mutation);
    if (typeof matchMedia === "function") {
      const query = matchMedia("(prefers-color-scheme: dark)");
      query.addEventListener("change", retheme);
      this.observers.push({ disconnect: () => query.removeEventListener("change", retheme) });
    }
  }

  // The single numbers that the server wrote: in the locale's words.
  private formatSingles(): void {
    for (const data of this.el.querySelectorAll<HTMLDataElement>("data.fude-value, .fude-delta data")) {
      const value = parseFloat(data.value);
      if (!Number.isFinite(value)) continue;
      const format = data.dataset.format;
      if (format === "percent-change") {
        const text = formatter("percent", this.locale, 1)(Math.abs(value));
        data.textContent = `${value >= 0 ? "▲" : "▼"} ${text}`;
      } else {
        data.textContent = formatter(format || (Math.abs(value) >= 100000 ? "compact" : null), this.locale)(value);
      }
    }
  }

  // -- Rendering ------------------------------------------------------------

  private render(animate: boolean): void {
    const config = this.config;
    if (!config.layers) return;
    this.stage.setAttribute("aria-label", config.description ?? config.title ?? "Chart");
    this.renderLegend();
    const width = this.stage.clientWidth;
    const height = this.stage.clientHeight;
    if (width === 0 || height === 0) return;

    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = Math.round(width * dpr);
    this.canvas.height = Math.round(height * dpr);
    this.canvas.style.width = `${width}px`;
    this.canvas.style.height = `${height}px`;
    for (const svg of [this.svg, this.grid]) {
      svg.setAttribute("width", String(width));
      svg.setAttribute("height", String(height));
      svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    }

    if (!this.prepareMap(animate)) return;
    this.layout = this.computeLayout(width, height);
    const shapes = this.computeShapes(this.layout);

    // What leaves fades from where it was; the rest move from where they are.
    const keys = new Set(shapes.map((shape) => shape.key));
    this.leaving = animate ? [...this.drawn.values()].filter((shape) => !keys.has(shape.key)) : [];
    const from = animate ? new Map(this.drawn) : new Map(shapes.map((shape) => [shape.key, shape] as const));
    this.shapes = shapes;
    this.renderAxes(this.layout);
    this.play(from, animate ? this.theme.duration : 0);
  }

  // The map of a map chart: ready, or loading (the chart draws when it
  // comes), or not registered (the chart says so).
  private prepareMap(animate: boolean): boolean {
    const layer = (this.config.layers ?? []).find((l) => l.mark === "region" || l.mark === "bubble");
    this.note.hidden = true;
    if (!layer) return true;
    const name = String(layer.options.map ?? "world");
    const map = loadMap(name);
    if (map === null) {
      this.showNote(`The map "${name}" is not registered: see registerMap in the Maps guide.`);
      return false;
    }
    if (map instanceof Promise) {
      map.then(() => this.render(animate)).catch((error: Error) => this.showNote(error.message));
      return false;
    }
    this.geo = map;
    return true;
  }

  private showNote(text: string): void {
    this.note.textContent = text;
    this.note.hidden = false;
  }

  private play(from: Map<string, Shape>, duration: number): void {
    cancelAnimationFrame(this.frame);
    const start = performance.now();
    const step = (now: number) => {
      const t = duration > 0 ? Math.min(1, (now - start) / duration) : 1;
      this.paint(from, easeOut(t), t);
      if (t < 1) this.frame = requestAnimationFrame(step);
      else this.leaving = [];
    };
    if (duration > 0) this.frame = requestAnimationFrame(step);
    else step(start);
  }

  private paint(from: Map<string, Shape>, t: number, raw = 1): void {
    const ctx = this.canvas.getContext("2d");
    if (!ctx) return;
    const dpr = window.devicePixelRatio || 1;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    const paint = this.paintOptions();
    for (const shape of this.leaving) draw(ctx, shape, paint, 1 - raw);
    const drawn = new Map<string, Shape>();
    for (const shape of this.shapes) {
      const now = tween(from.get(shape.key), shape, t);
      drawn.set(shape.key, now);
      draw(ctx, now, paint);
    }
    this.drawn = drawn;
    this.paintHover(ctx);
  }

  private repaint(): void {
    if (!this.layout) return;
    cancelAnimationFrame(this.frame);
    this.leaving = [];
    this.paint(new Map(this.shapes.map((shape) => [shape.key, shape] as const)), 1);
  }

  private paintOptions(): Paint {
    const hover = this.hover;
    const highlight = this.highlight;
    return {
      surface: this.theme.surface,
      gap: this.theme.gap,
      radius: this.theme.radius,
      focus: (key, series) => {
        if (highlight !== null) return series === highlight ? 1 : 0.2;
        if (hover && hover.kind === "mark") return key === hover.key ? 1 : 0.55;
        return 1;
      },
    };
  }

  // -- Layout ---------------------------------------------------------------

  private measure(text: string, size = FONT_SIZE): number {
    if (!this.measurer) this.measurer = document.createElement("canvas").getContext("2d");
    if (!this.measurer) return text.length * size * 0.6;
    this.measurer.font = `${size}px ${this.theme.font}`;
    return this.measurer.measureText(text).width;
  }

  private computeLayout(width: number, height: number): Layout {
    const { scales = {}, axes = true } = this.config;
    const xs = scales.x;
    const ys = scales.y;
    const layout: Layout = { width, height, left: 0, top: 0, right: width, bottom: height, labels: [] };
    if (!xs && !ys) return layout;

    const pad = axes ? 8 : 2;
    let top = pad + (axes && ys?.title && ys.type !== "band" ? 20 : 0);
    let bottom = height - (axes ? 26 : 2);
    if (axes && xs?.title && xs.type !== "time" && xs.type !== "band") bottom -= 18;

    // The direct labels at the ends of the lines take a margin on the right.
    const labels = this.directLabels();
    let right = width - pad - (labels ? Math.min(width * 0.25, Math.max(...labels.map((l) => this.measure(l.text))) + 14) : 0);

    // Value labels at the ends of horizontal bars take a margin too.
    const barLabels = (this.config.layers ?? []).find((layer) => layer.mark === "bar" && layer.options.labels === true && layer.horizontal);
    if (barLabels && xs?.domain) {
      const format = formatter(xs.format, this.locale);
      const widest = Math.max(0, ...((barLabels.columns.x ?? []) as (number | null)[]).map((v) => (v == null ? 0 : this.measure(format(v)))));
      right -= widest + 8;
    }

    let left = pad;
    if (axes && ys) {
      if (ys.type === "band") {
        const names = (ys.domain ?? []).map((value, i) => this.bandLabel(ys, value, i));
        left += Math.min(width * 0.35, Math.max(0, ...names.map((name) => this.measure(name)))) + 10;
      } else {
        const probe = position(ys, [bottom, top], 44);
        const format = this.tickFormat(ys, probe);
        left += Math.max(0, ...probe.ticks.map((tick, i) => this.measure(format(tick, i, probe.ticks)))) + 10;
      }
    }
    if (!axes) top = 4;
    if (right - left < 40) right = left + 40;

    layout.left = left;
    layout.top = top;
    layout.right = right;
    layout.bottom = bottom;
    if (xs) layout.x = position(xs, [left, right], xs.type === "time" ? 90 : 80, this.bandPadding("x"));
    // Categories run down from the top; numbers up from the bottom.
    if (ys) layout.y = position(ys, ys.type === "band" || ys.type === "point" ? [top, bottom] : [bottom, top], 44, this.bandPadding("y"));

    if (labels && layout.y) {
      layout.labels = this.placeLabels(labels, layout);
    }
    return layout;
  }

  private bandPadding(axis: "x" | "y"): number {
    const marks = (this.config.layers ?? []).map((layer) => layer.mark);
    if (marks.includes("rect")) return 0;
    return axis === "x" ? 0.28 : 0.3;
  }

  // The series a line or an area chart labels at its end: four or fewer.
  private directLabels(): { series: number; text: string }[] | null {
    const layers = this.config.layers ?? [];
    const color = this.config.scales?.color;
    const paths = layers.filter((layer) => layer.mark === "line" || layer.mark === "area");
    if (paths.length === 0 || !this.config.axes) return null;
    const x = this.config.scales?.x;
    if (!x || x.type === "band") return null;
    if (!color || color.type !== "ordinal") return null;
    const domain = color.domain ?? [];
    if (domain.length < 1 || domain.length > 4) return null;
    return domain.map((value, series) => ({ series, text: String(value) }));
  }

  // Each label at its line's last value, moved apart where they would
  // touch; a label moved off its line gets a leader (drawn in renderAxes).
  private placeLabels(labels: { series: number; text: string }[], layout: Layout): Layout["labels"] {
    const y = layout.y!;
    const ends: { text: string; y: number; at: number; color: string }[] = [];
    for (const { series, text } of labels) {
      if (this.hidden.has(series)) continue;
      const end = this.lastValue(series);
      if (end === null) continue;
      ends.push({ text, y: y.at(end), at: y.at(end), color: this.color(series) });
    }
    ends.sort((a, b) => a.y - b.y);
    const gap = 15;
    for (let i = 1; i < ends.length; i++) {
      if (ends[i]!.y - ends[i - 1]!.y < gap) ends[i]!.y = ends[i - 1]!.y + gap;
    }
    const overflow = ends.length ? ends[ends.length - 1]!.y - layout.bottom : 0;
    if (overflow > 0) for (const end of ends) end.y -= overflow;
    return ends;
  }

  private lastValue(series: number): number | null {
    for (const layer of this.config.layers ?? []) {
      if (layer.mark !== "line" && layer.mark !== "area") continue;
      const colors = layer.columns.color;
      const ys = layer.stack ? layer.columns.y1 : layer.columns.y;
      if (!ys) continue;
      for (let i = layer.n - 1; i >= 0; i--) {
        if ((colors ? colors[i] : 0) === series && ys[i] != null) return ys[i]!;
      }
    }
    return null;
  }

  // -- Colors -----------------------------------------------------------------

  private color(series: number | null | undefined): string {
    if (series === null || series === undefined) return this.theme.series[0]!;
    return this.theme.series[series] ?? this.theme.muted;
  }

  private sequential(value: number | null | undefined): string {
    const scale = this.config.scales?.color;
    const [d0, d1] = (scale?.domain as [number, number] | null) ?? [0, 1];
    const t = value === null || value === undefined || d1 === d0 ? 0.5 : (value - d0) / (d1 - d0);
    return ramp(this.theme.sequential, t);
  }

  private colorOf(layer: Layer, row: number): string {
    const value = layer.columns.color?.[row];
    if (this.config.scales?.color?.type === "sequential") return this.sequential(value);
    return this.color(value ?? null);
  }

  // -- Shapes -----------------------------------------------------------------

  private computeShapes(layout: Layout): Shape[] {
    const shapes: Shape[] = [];
    (this.config.layers ?? []).forEach((layer, index) => {
      switch (layer.mark) {
        case "bar":
          this.bars(layer, index, layout, shapes);
          break;
        case "line":
        case "area":
          this.paths(layer, index, layout, shapes);
          break;
        case "point":
          this.points(layer, index, layout, shapes);
          break;
        case "arc":
          this.arcs(layer, index, layout, shapes);
          break;
        case "rect":
          this.cells(layer, index, layout, shapes);
          break;
        case "region":
        case "bubble":
          this.regions(layer, index, layout, shapes);
          break;
        case "rule":
          this.rules(layer, index, layout, shapes);
          break;
      }
    });
    return shapes;
  }

  private keyOf(scale: Scale | undefined, value: number | null | undefined): string {
    if (value === null || value === undefined) return "∅";
    if (scale && (scale.type === "band" || scale.type === "point" || scale.type === "ordinal")) return String(scale.domain?.[value]);
    return String(value);
  }

  private bars(layer: Layer, index: number, layout: Layout, shapes: Shape[]): void {
    const horizontal = layer.horizontal;
    const cat = horizontal ? layout.y : layout.x;
    const val = horizontal ? layout.x : layout.y;
    if (!cat || !val) return;
    const scales = this.config.scales ?? {};
    const catScale = horizontal ? scales.y : scales.x;
    const c = layer.columns;
    const catCol = (horizontal ? c.y : c.x) ?? [];
    const valCol = (horizontal ? c.x : c.y) ?? [];
    const v0Col = horizontal ? c.x0 : c.y0;
    const v1Col = horizontal ? c.x1 : c.y1;
    const binned = !horizontal && !!c.x2;
    const colors = c.color;
    const groups = colors && !layer.stack && cat.kind === "band" ? (scales.color?.domain ?? []).length : 1;
    const zero = Math.max(Math.min(0, val.domain[1]), val.domain[0]);
    const base = val.at(zero);
    const gap = this.theme.gap;

    // The ends of each stack: only the outer segment is round.
    const outer = new Map<string, { max: number; min: number }>();
    if (layer.stack && v1Col && v0Col) {
      for (let i = 0; i < layer.n; i++) {
        const k = String(catCol[i]);
        const end = outer.get(k) ?? { max: 0, min: 0 };
        end.max = Math.max(end.max, v1Col[i] ?? 0, v0Col[i] ?? 0);
        end.min = Math.min(end.min, v1Col[i] ?? 0, v0Col[i] ?? 0);
        outer.set(k, end);
      }
    }

    for (let i = 0; i < layer.n; i++) {
      const series = colors ? (colors[i] ?? null) : null;
      if (series !== null && this.hidden.has(series)) continue;
      const v0 = layer.stack && v0Col ? (v0Col[i] ?? 0) : zero;
      const v1 = layer.stack && v1Col ? v1Col[i] : valCol[i];
      if (v1 === null || v1 === undefined || catCol[i] === null || catCol[i] === undefined) continue;

      let lo: number;
      let thickness: number;
      if (binned) {
        lo = cat.at(catCol[i]!) + gap / 2;
        thickness = Math.max(1, cat.at(c.x2![i]!) - gap / 2 - lo);
      } else {
        const bw = cat.bandwidth;
        if (groups > 1) {
          const slot = bw / groups;
          thickness = Math.min(slot - gap, this.theme.barMax);
          lo = cat.at(catCol[i]!) + slot * (series ?? 0) + (slot - thickness) / 2;
        } else {
          thickness = Math.min(bw, this.theme.barMax * (colors && layer.stack ? 1.4 : 1.6));
          lo = cat.at(catCol[i]!) + (bw - thickness) / 2;
        }
      }

      let p0 = val.at(v0);
      let p1 = val.at(v1);
      const positive = v1 >= v0;
      // The surface gap between stacked segments: at the inner end.
      if (layer.stack && v0 !== 0) {
        if (horizontal) p0 += positive ? gap : -gap;
        else p0 += positive ? -gap : gap;
      }
      const k = String(catCol[i]);
      const end = outer.get(k);
      const isOuter = !layer.stack || !end || (positive ? v1 >= end.max : v1 <= end.min);
      const round = !isOuter ? "none" : horizontal ? (positive ? "right" : "left") : positive ? "top" : "bottom";
      const key = `${index}:${this.keyOf(catScale, catCol[i])}|${this.keyOf(scales.color, series)}`;
      const datum = { layer: index, row: i, series };
      const color = this.colorOf(layer, i);
      if (horizontal) {
        const x = Math.min(p0, p1);
        shapes.push({ type: "rect", key, x, y: lo, w: Math.abs(p1 - p0), h: thickness, color, round, from: { x: base, y: lo, w: 0, h: thickness }, datum });
      } else {
        const y = Math.min(p0, p1);
        shapes.push({ type: "rect", key, x: lo, y, w: thickness, h: Math.abs(p1 - p0), color, round, from: { x: lo, y: base, w: thickness, h: 0 }, datum });
      }
    }
  }

  private paths(layer: Layer, index: number, layout: Layout, shapes: Shape[]): void {
    const x = layout.x;
    const y = layout.y;
    if (!x || !y) return;
    const scales = this.config.scales ?? {};
    const c = layer.columns;
    const colors = c.color;
    const ys = layer.stack ? c.y1 : c.y;
    const y0s = layer.stack ? c.y0 : null;
    const zero = Math.max(Math.min(0, y.domain[1]), y.domain[0]);
    const baseline = y.at(zero);
    const bySeries = new Map<number, PathShape>();
    const curve = (layer.options.curve as PathShape["curve"]) ?? (this.config.kind === "sparkline" ? "monotone" : "linear");

    for (let i = 0; i < layer.n; i++) {
      const series = colors ? (colors[i] ?? -1) : -1;
      if (series >= 0 && this.hidden.has(series)) continue;
      let path = bySeries.get(series);
      if (!path) {
        const area = layer.mark === "area";
        path = {
          type: layer.mark as "line" | "area",
          key: `${index}:${series < 0 ? "" : this.keyOf(scales.color, series)}`,
          points: [],
          color: this.color(series < 0 ? null : series),
          curve,
          fill: area ? (layer.stack ? 0.78 : 0.12) : 0,
          width: area && layer.stack ? 0 : this.theme.line,
          baseline,
          series: series < 0 ? null : series,
          layer: index,
          dots: layer.options.points === true,
        };
        bySeries.set(series, path);
      }
      const xv = c.x?.[i];
      if (xv === null || xv === undefined) continue;
      const value = ys?.[i];
      path.points.push({
        k: this.keyOf(scales.x, xv),
        x: x.kind === "band" ? x.at(xv) + x.bandwidth / 2 : x.at(xv),
        y: value === null || value === undefined ? null : y.at(value),
        y0: y0s ? y.at(y0s[i] ?? 0) : baseline,
        row: i,
      });
    }
    for (const path of bySeries.values()) {
      shapes.push(path);
      // A dot at the end of a line with a direct label.
      if (layout.labels.length && path.type === "line") {
        const last = [...path.points].reverse().find((point) => point.y !== null);
        if (last) {
          shapes.push({ type: "dot", key: `${path.key}:end`, x: last.x, y: last.y!, r: 3.5, color: path.color, ring: true, datum: { layer: index, row: last.row, series: path.series } });
        }
      }
    }
  }

  private points(layer: Layer, index: number, layout: Layout, shapes: Shape[]): void {
    const x = layout.x;
    const y = layout.y;
    if (!x || !y) return;
    const c = layer.columns;
    const size = this.config.scales?.size;
    const [s0, s1] = (size?.domain as [number, number] | null) ?? [0, 1];
    const ring = layer.n <= 600;
    for (let i = 0; i < layer.n; i++) {
      const series = c.color?.[i] ?? null;
      if (series !== null && this.hidden.has(series) && this.config.scales?.color?.type !== "sequential") continue;
      const xv = c.x?.[i];
      const yv = c.y?.[i];
      if (xv == null || yv == null) continue;
      const sv = c.size?.[i];
      const r = sv == null || s1 === s0 ? 4 : 3 + Math.sqrt(Math.max(0, (sv - s0) / (s1 - s0))) * 17;
      const px = x.kind === "band" ? x.at(xv) + x.bandwidth / 2 : x.at(xv);
      const py = y.kind === "band" ? y.at(yv) + y.bandwidth / 2 : y.at(yv);
      shapes.push({ type: "dot", key: `${index}:${i}`, x: px, y: py, r, color: this.colorOf(layer, i), ring, datum: { layer: index, row: i, series } });
    }
  }

  private arcs(layer: Layer, index: number, layout: Layout, shapes: Shape[]): void {
    const c = layer.columns;
    const cx = layout.width / 2;
    const cy = layout.height / 2;
    const r1 = Math.max(10, Math.min(layout.width, layout.height) / 2 - 6);
    const inner = typeof layer.options.inner === "number" ? layer.options.inner : 0;
    for (let i = 0; i < layer.n; i++) {
      const series = c.color?.[i] ?? null;
      shapes.push({
        type: "arc",
        key: `${index}:${this.keyOf(this.config.scales?.color, series)}`,
        cx,
        cy,
        r0: r1 * inner,
        r1,
        a0: c.a0?.[i] ?? 0,
        a1: c.a1?.[i] ?? 0,
        color: this.color(series),
        datum: { layer: index, row: i, series },
      });
    }
  }

  private cells(layer: Layer, index: number, layout: Layout, shapes: Shape[]): void {
    const x = layout.x;
    const y = layout.y;
    if (!x || !y) return;
    const scales = this.config.scales ?? {};
    const c = layer.columns;
    const gap = this.theme.gap;
    for (let i = 0; i < layer.n; i++) {
      const xv = c.x?.[i];
      const yv = c.y?.[i];
      if (xv == null || yv == null) continue;
      const px = x.at(xv) + gap / 2;
      const py = y.at(yv) + gap / 2;
      const w = Math.max(1, x.bandwidth - gap);
      const h = Math.max(1, y.bandwidth - gap);
      shapes.push({
        type: "rect",
        key: `${index}:${this.keyOf(scales.x, xv)}|${this.keyOf(scales.y, yv)}`,
        x: px,
        y: py,
        w,
        h,
        color: c.color ? this.colorOf(layer, i) : this.color(null),
        round: "none",
        from: { x: px + w / 2, y: py + h / 2, w: 0, h: 0 },
        datum: { layer: index, row: i, series: null },
      });
    }
  }

  // The regions of a map, colored by their value (or empty), fitted to the
  // stage; a bubble map adds a circle at each region's center.
  private regions(layer: Layer, index: number, layout: Layout, shapes: Shape[]): void {
    const geo = this.geo;
    if (!geo) return;
    const map = geo.map;
    const k = Math.min(layout.width / map.width, layout.height / map.height);
    const tx = (layout.width - map.width * k) / 2;
    const ty = (layout.height - map.height * k) / 2;
    const c = layer.columns;
    const domain = this.config.scales?.region?.domain ?? [];
    const rows = new Map<number, number>();
    const unmatched: unknown[] = [];
    for (let i = 0; i < layer.n; i++) {
      const value = domain[c.region?.[i] ?? -1];
      const region = geo.find(value);
      if (region === undefined) unmatched.push(value);
      else rows.set(region, i);
    }
    if (unmatched.length) console.warn(`Fude: ${unmatched.length} regions of chart ${this.id} are not on the map ${map.name}:`, unmatched.slice(0, 20));

    const bubble = layer.mark === "bubble";
    map.regions.forEach((region, r) => {
      const row = bubble ? undefined : rows.get(r);
      const key = `${index}:${region.id}`;
      const center: [number, number] = [tx + region.center[0] * k, ty + region.center[1] * k];
      this.names.set(key, region.name);
      shapes.push({
        type: "region",
        key,
        path: geo.path(r),
        k,
        tx,
        ty,
        center,
        color: row === undefined ? this.theme.empty : this.colorOf(layer, row),
        name: region.name,
        datum: row === undefined ? null : { layer: index, row, series: c.color?.[row] ?? null },
      });
    });
    if (!bubble) return;

    const [, max] = (this.config.scales?.size?.domain as [number, number] | null) ?? [0, 1];
    const largest = Math.max(6, Math.min(layout.width, layout.height) / 18);
    const circles = [...rows.entries()].sort(([, a], [, b]) => (c.size?.[b] ?? 0) - (c.size?.[a] ?? 0));
    for (const [r, row] of circles) {
      const region = map.regions[r]!;
      const value = c.size?.[row] ?? 0;
      const key = `${index}:${region.id}:bubble`;
      this.names.set(key, region.name);
      shapes.push({
        type: "dot",
        key,
        x: tx + region.center[0] * k,
        y: ty + region.center[1] * k,
        r: max > 0 ? Math.max(2, Math.sqrt(Math.max(0, value) / max) * largest) : 2,
        color: alpha(c.color ? this.colorOf(layer, row) : this.color(null), 0.78),
        ring: true,
        datum: { layer: index, row, series: c.color?.[row] ?? null },
      });
    }
  }

  private rules(layer: Layer, index: number, layout: Layout, shapes: Shape[]): void {
    const c = layer.columns;
    for (let i = 0; i < layer.n; i++) {
      const color = this.theme.secondary;
      const dashed = layer.options.dashed !== false;
      const yv = c.y?.[i];
      const xv = c.x?.[i];
      if (yv != null && layout.y && xv == null) {
        const py = layout.y.at(yv) + layout.y.bandwidth / 2;
        shapes.push({ type: "rule", key: `${index}:y:${yv}`, x1: layout.left, y1: py, x2: layout.right, y2: py, color, dashed });
      } else if (xv != null && layout.x) {
        const px = layout.x.at(xv) + layout.x.bandwidth / 2;
        shapes.push({ type: "rule", key: `${index}:x:${xv}`, x1: px, y1: layout.top, x2: px, y2: layout.bottom, color, dashed });
      }
    }
  }

  // -- Axes and words -------------------------------------------------------

  private tickFormat(scale: Scale, pos: Position): (value: number, index: number, ticks: number[]) => string {
    if (pos.kind === "time") return timeTickFormatter(pos.unit ?? "day", this.locale);
    if (pos.kind === "band" || pos.kind === "point") return (value, i) => this.bandLabel(scale, scale.domain?.[value], i);
    const format = tickFormatter(scale.format, pos.ticks, this.locale);
    return (value) => format(value);
  }

  private bandLabel(scale: Scale, value: unknown, index: number): string {
    if (scale.time && typeof value === "number") {
      return timeTickFormatter(scale.time as never, this.locale)(value, index, (scale.domain ?? []) as number[]);
    }
    return value === null || value === undefined ? "" : String(value);
  }

  private renderAxes(layout: Layout): void {
    const svg = this.svg;
    const grid = this.grid;
    svg.replaceChildren();
    grid.replaceChildren();
    const { scales = {}, axes = true } = this.config;
    const theme = this.theme;
    svg.style.fontFamily = theme.font;
    if (!axes) return;
    const { x, y } = layout;

    // The value axis: hairline grids at its ticks, labels beside them.
    if (y && scales.y) {
      const format = this.tickFormat(scales.y, y);
      y.ticks.forEach((tick, i) => {
        const py = y.kind === "band" || y.kind === "point" ? y.at(tick) + y.bandwidth / 2 : Math.round(y.at(tick)) + 0.5;
        if (y.kind !== "band" && y.kind !== "point") {
          line(grid, layout.left, py, layout.right, py, tick === 0 ? theme.baseline : theme.grid);
        }
        text(svg, format(tick, i, y.ticks), layout.left - 8, py, { anchor: "end", baseline: "middle", fill: theme.muted, tabular: true });
      });
      if (scales.y.title && y.kind !== "band") {
        text(svg, scales.y.title, 0, layout.top - 12, { anchor: "start", baseline: "alphabetic", fill: theme.secondary });
      }
    }

    if (x && scales.x) {
      const format = this.tickFormat(scales.x, x);
      const ticks = this.thinTicks(x, format);
      const vertical = x.kind !== "band" && x.kind !== "point";
      for (const [tick, label] of ticks) {
        const px = x.kind === "band" ? x.at(tick) + x.bandwidth / 2 : Math.round(x.at(tick)) + 0.5;
        if (vertical && y && (y.kind === "band" || this.isHorizontalBars())) line(grid, px, layout.top, px, layout.bottom, tick === 0 ? theme.baseline : theme.grid);
        text(svg, label, px, layout.bottom + 16, { anchor: "middle", baseline: "alphabetic", fill: theme.muted, tabular: true });
      }
      // The baseline under bars and columns.
      if (!vertical || (y && y.kind !== "band")) {
        if (!(y && y.domain[0] < 0)) line(svg, layout.left, layout.bottom + 0.5, layout.right, layout.bottom + 0.5, theme.baseline);
      }
      if (scales.x.title && scales.x.type !== "time" && scales.x.type !== "band") {
        text(svg, scales.x.title, layout.right, layout.bottom + 34, { anchor: "end", baseline: "alphabetic", fill: theme.secondary });
      }
    }

    // Labels of rules.
    (this.config.layers ?? []).forEach((layer) => {
      if (layer.mark !== "rule" || typeof layer.options.label !== "string") return;
      const yv = layer.columns.y?.[0];
      if (yv != null && y) text(svg, layer.options.label, layout.left + 4, y.at(yv) - 6, { anchor: "start", baseline: "alphabetic", fill: theme.secondary, halo: theme.surface });
    });

    // Direct labels: at the end of each line, with a leader when moved.
    for (const label of layout.labels) {
      const lx = layout.right + 8;
      if (Math.abs(label.y - label.at) > 3) line(svg, layout.right + 2, label.at, lx - 2, label.y, theme.muted);
      const key = document.createElementNS(SVG, "rect");
      key.setAttribute("x", String(lx));
      key.setAttribute("y", String(label.y - 1));
      key.setAttribute("width", "8");
      key.setAttribute("height", "2");
      key.setAttribute("rx", "1");
      key.setAttribute("fill", label.color);
      svg.append(key);
      text(svg, label.text, lx + 12, label.y, { anchor: "start", baseline: "middle", fill: theme.text });
    }

    // Value labels at the ends of bars.
    (this.config.layers ?? []).forEach((layer, index) => {
      if (layer.mark !== "bar" || layer.options.labels !== true) return;
      const value = formatter(scales[layer.horizontal ? "x" : "y"]?.format, this.locale);
      for (const shape of this.shapes) {
        if (shape.type !== "rect" || shape.datum.layer !== index) continue;
        const v = (layer.horizontal ? layer.columns.x : layer.columns.y)?.[shape.datum.row];
        if (v == null) continue;
        if (layer.horizontal) text(svg, value(v), shape.x + shape.w + 6, shape.y + shape.h / 2, { anchor: "start", baseline: "middle", fill: theme.secondary, halo: theme.surface });
        else text(svg, value(v), shape.x + shape.w / 2, shape.y - 6, { anchor: "middle", baseline: "alphabetic", fill: theme.secondary, halo: theme.surface });
      }
    });

    const cross = document.createElementNS(SVG, "g");
    cross.setAttribute("class", "fude-cross");
    svg.append(cross);
  }

  private isHorizontalBars(): boolean {
    return (this.config.layers ?? []).some((layer) => layer.mark === "bar" && layer.horizontal);
  }

  // The tick labels that fit, at least a label's width apart.
  private thinTicks(x: Position, format: (value: number, index: number, ticks: number[]) => string): [number, string][] {
    const labels = x.ticks.map((tick, i) => [tick, format(tick, i, x.ticks)] as [number, string]);
    if (labels.length < 2) return labels;
    const widest = Math.max(...labels.map(([, label]) => this.measure(label)));
    const spacing = Math.abs(x.at(x.ticks[1]!) - x.at(x.ticks[0]!));
    const every = Math.max(1, Math.ceil((widest + 10) / Math.max(1, spacing)));
    return labels.filter((_, i) => i % every === 0);
  }

  // -- Hover, keyboard and tooltip -------------------------------------------

  private crosshair(): boolean {
    const layers = this.config.layers ?? [];
    return layers.some((layer) => layer.mark === "line" || layer.mark === "area");
  }

  // The x positions of the lines and areas, in order: where the crosshair
  // stops.
  private stops(): { k: string; px: number }[] {
    const seen = new Map<string, number>();
    for (const shape of this.shapes) {
      if (shape.type !== "line" && shape.type !== "area") continue;
      for (const point of shape.points) if (point.y !== null) seen.set(point.k, point.x);
    }
    return [...seen.entries()].map(([k, px]) => ({ k, px })).sort((a, b) => a.px - b.px);
  }

  private marks(): Shape[] {
    return this.shapes
      .filter((shape) => shape.type === "rect" || shape.type === "dot" || shape.type === "arc" || (shape.type === "region" && shape.datum !== null))
      .filter((shape) => !shape.key.endsWith(":end"));
  }

  private onPointer(event: PointerEvent): void {
    if (!this.layout) return;
    const rect = this.stage.getBoundingClientRect();
    const px = event.clientX - rect.left;
    const py = event.clientY - rect.top;
    if (this.crosshair()) {
      const stops = this.stops();
      if (!stops.length || px < this.layout.left - 20 || px > this.layout.right + 20) return this.setHover(null);
      let best = stops[0]!;
      for (const stop of stops) if (Math.abs(stop.px - px) < Math.abs(best.px - px)) best = stop;
      this.cursor = stops.indexOf(best);
      return this.setHover({ kind: "x", k: best.k, px: best.px });
    }
    const hit = this.hit(px, py);
    this.cursor = hit ? this.marks().indexOf(hit) : -1;
    this.setHover(hit && "datum" in hit && hit.datum ? { kind: "mark", key: hit.key, datum: hit.datum, ...this.anchor(hit) } : null);
  }

  private hit(px: number, py: number): Shape | null {
    let best: Shape | null = null;
    let bestDistance = 24;
    // Circles over regions: the circles first, the smallest on top.
    const marks = this.marks();
    const ordered = marks.some((shape) => shape.type === "region") ? [...marks].reverse() : marks;
    for (const shape of ordered) {
      if (shape.type === "region") {
        if (best) return best;
        if (this.inRegion(shape, px, py)) return shape;
        continue;
      }
      if (shape.type === "rect") {
        const slack = 3;
        if (px >= shape.x - slack && px <= shape.x + shape.w + slack && py >= shape.y - slack && py <= shape.y + shape.h + slack) return shape;
      } else if (shape.type === "dot") {
        const d = Math.hypot(shape.x - px, shape.y - py) - shape.r;
        if (d < bestDistance) {
          bestDistance = d;
          best = shape;
        }
      } else if (shape.type === "arc") {
        const dx = px - shape.cx;
        const dy = py - shape.cy;
        const r = Math.hypot(dx, dy);
        if (r < shape.r0 || r > shape.r1) continue;
        let a = (Math.atan2(dy, dx) + Math.PI / 2) / (Math.PI * 2);
        if (a < 0) a += 1;
        if (a >= shape.a0 && a < shape.a1) return shape;
      }
    }
    return best;
  }

  private hitContext: CanvasRenderingContext2D | null = null;

  private inRegion(shape: Extract<Shape, { type: "region" }>, px: number, py: number): boolean {
    this.hitContext ??= document.createElement("canvas").getContext("2d");
    return !!this.hitContext?.isPointInPath(shape.path, (px - shape.tx) / shape.k, (py - shape.ty) / shape.k);
  }

  private anchor(shape: Shape): { px: number; py: number } {
    switch (shape.type) {
      case "region":
        return { px: shape.center[0], py: shape.center[1] };
      case "rect":
        return { px: shape.x + shape.w / 2, py: shape.y };
      case "dot":
        return { px: shape.x, py: shape.y - shape.r };
      case "arc": {
        const a = -Math.PI / 2 + ((shape.a0 + shape.a1) / 2) * Math.PI * 2;
        const r = (shape.r0 + shape.r1) / 2;
        return { px: shape.cx + Math.cos(a) * r, py: shape.cy + Math.sin(a) * r };
      }
      default:
        return { px: 0, py: 0 };
    }
  }

  private onKey(event: KeyboardEvent): void {
    const keys = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "Escape"];
    if (!keys.includes(event.key)) return;
    event.preventDefault();
    if (event.key === "Escape") {
      this.cursor = -1;
      this.highlight = null;
      return this.setHover(null);
    }
    if (this.crosshair()) {
      const stops = this.stops();
      if (!stops.length) return;
      if (event.key === "ArrowUp" || event.key === "ArrowDown") {
        const count = (this.config.scales?.color?.domain ?? []).length;
        if (count > 1) {
          const next = this.highlight === null ? 0 : (this.highlight + (event.key === "ArrowDown" ? 1 : count - 1)) % count;
          this.highlight = next;
        }
        if (this.cursor < 0) this.cursor = stops.length - 1;
      } else {
        this.cursor = this.move(this.cursor, stops.length, event.key);
      }
      const stop = stops[this.cursor]!;
      this.setHover({ kind: "x", k: stop.k, px: stop.px });
    } else {
      const marks = this.marks();
      if (!marks.length) return;
      this.cursor = this.move(this.cursor, marks.length, event.key);
      const mark = marks[this.cursor]!;
      if ("datum" in mark && mark.datum) this.setHover({ kind: "mark", key: mark.key, datum: mark.datum, ...this.anchor(mark) });
    }
    this.live.textContent = this.tipText();
  }

  private move(cursor: number, count: number, key: string): number {
    if (key === "Home") return 0;
    if (key === "End") return count - 1;
    if (cursor < 0) return key === "ArrowLeft" || key === "ArrowUp" ? count - 1 : 0;
    const delta = key === "ArrowLeft" || key === "ArrowUp" ? -1 : 1;
    return Math.max(0, Math.min(count - 1, cursor + delta));
  }

  private setHover(hover: Hover | null): void {
    const same = JSON.stringify(hover) === JSON.stringify(this.hover);
    this.hover = hover;
    if (!hover && this.highlight !== null && document.activeElement !== this.stage) this.highlight = null;
    if (!same) this.repaint();
    this.renderCross();
    if (hover) this.showTip();
    else this.hideTip();
  }

  // The crosshair: a hairline at the x, and a dot on each line there.
  private renderCross(): void {
    const cross = this.svg.querySelector(".fude-cross");
    if (!cross || !this.layout) return;
    cross.replaceChildren();
    const hover = this.hover;
    if (!hover || hover.kind !== "x") return;
    line(cross, Math.round(hover.px) + 0.5, this.layout.top, Math.round(hover.px) + 0.5, this.layout.bottom, this.theme.muted);
  }

  private paintHover(ctx: CanvasRenderingContext2D): void {
    const hover = this.hover;
    if (!hover || hover.kind !== "x") return;
    for (const shape of this.shapes) {
      if (shape.type !== "line" && shape.type !== "area") continue;
      const point = shape.points.find((p) => p.k === hover.k);
      if (!point || point.y === null) continue;
      if (this.highlight !== null && shape.series !== this.highlight) continue;
      draw(ctx, { type: "dot", key: "", x: point.x, y: point.y, r: 4, color: shape.color, ring: true, datum: { layer: shape.layer, row: point.row, series: shape.series } }, this.paintOptions());
    }
  }

  private valueText(value: number | null | undefined, scale: Scale | undefined): string {
    if (value === null || value === undefined) return "—";
    if (!scale) return formatter(null, this.locale)(value);
    if (scale.type === "band" || scale.type === "point" || scale.type === "ordinal") {
      const name = scale.domain?.[value];
      if (scale.time && typeof name === "number") return formatTime(name, scale.time, this.locale);
      return String(name ?? "");
    }
    if (scale.type === "time") return formatTime(value, scale.unit ?? undefined, this.locale);
    return formatter(scale.format, this.locale)(value);
  }

  // The rows of the tooltip: a title, then each value with its series.
  private tipRows(): { title: string; rows: { value: string; name: string; color: string | null }[] } | null {
    const hover = this.hover;
    const scales = this.config.scales ?? {};
    const layers = this.config.layers ?? [];
    if (!hover) return null;
    if (hover.kind === "x") {
      const rows: { value: string; name: string; color: string | null }[] = [];
      let title = "";
      for (const shape of this.shapes) {
        if (shape.type !== "line" && shape.type !== "area") continue;
        const point = shape.points.find((p) => p.k === hover.k);
        if (!point) continue;
        const layer = layers[shape.layer]!;
        title = this.valueText(layer.columns.x?.[point.row], scales.x);
        const name = shape.series === null ? (scales.y?.title ?? "") : this.valueText(shape.series, scales.color);
        rows.push({ value: this.valueText(layer.columns.y?.[point.row], scales.y), name, color: shape.color });
      }
      if (this.highlight !== null) rows.sort((a, b) => (a.color === this.color(this.highlight) ? -1 : b.color === this.color(this.highlight) ? 1 : 0));
      return { title, rows };
    }
    const { layer: li, row, series } = hover.datum;
    const layer = layers[li]!;
    const c = layer.columns;
    const color = series === null ? this.colorOf(layer, row) : this.color(series);
    switch (layer.mark) {
      case "bar": {
        const horizontal = layer.horizontal;
        const catScale = horizontal ? scales.y : scales.x;
        let title = this.valueText((horizontal ? c.y : c.x)?.[row], catScale);
        if (c.x2) title = `${formatter(null, this.locale)(c.x![row]!)}–${formatter(null, this.locale)(c.x2[row]!)}`;
        const valueScale = horizontal ? scales.x : scales.y;
        const value = (horizontal ? c.x : c.y)?.[row];
        const name = series === null ? (valueScale?.title ?? "") : this.valueText(series, scales.color);
        return { title, rows: [{ value: this.valueText(value, { ...valueScale!, format: valueScale?.format === "percent" ? undefined : valueScale?.format } as Scale), name, color }] };
      }
      case "arc": {
        const share = (c.a1?.[row] ?? 0) - (c.a0?.[row] ?? 0);
        return {
          title: this.valueText(series, scales.color),
          rows: [{ value: `${formatter(null, this.locale)(c.value?.[row] ?? 0)} · ${formatter("percent", this.locale)(share)}`, name: "", color }],
        };
      }
      case "region":
      case "bubble": {
        const rows: { value: string; name: string; color: string | null }[] = [];
        if (c.size) rows.push({ value: this.valueText(c.size[row], scales.size), name: scales.size?.title ?? "", color: null });
        if (c.color) rows.push({ value: this.valueText(c.color[row], scales.color), name: scales.color?.title ?? "", color });
        return { title: this.names.get(hover.key) ?? this.valueText(c.region?.[row], scales.region), rows };
      }
      case "rect":
        return {
          title: `${this.valueText(c.x?.[row], scales.x)} · ${this.valueText(c.y?.[row], scales.y)}`,
          rows: c.color ? [{ value: this.valueText(c.color[row], scales.color), name: scales.color?.title ?? "", color }] : [],
        };
      default: {
        const rows = [
          { value: this.valueText(c.x?.[row], scales.x), name: scales.x?.title ?? "x", color: null },
          { value: this.valueText(c.y?.[row], scales.y), name: scales.y?.title ?? "y", color: null },
        ];
        if (c.size) rows.push({ value: this.valueText(c.size[row], scales.size), name: scales.size?.title ?? "size", color: null });
        const title = c.color && scales.color?.type === "ordinal" ? this.valueText(series, scales.color) : "";
        return { title, rows };
      }
    }
  }

  private tipText(): string {
    const tip = this.tipRows();
    if (!tip) return "";
    return [tip.title, ...tip.rows.map((row) => (row.name ? `${row.name}: ${row.value}` : row.value))].filter(Boolean).join(". ");
  }

  private showTip(): void {
    const tip = this.tipRows();
    const hover = this.hover;
    if (!tip || !hover || !this.layout) return this.hideTip();
    const box = this.tip;
    box.replaceChildren();
    if (tip.title) box.append(div("fude-tooltip-title", tip.title));
    for (const row of tip.rows) {
      const line = div("fude-tooltip-row");
      if (row.color) {
        const key = div("fude-tooltip-key");
        key.style.background = row.color;
        line.append(key);
      }
      line.append(div("fude-tooltip-value", row.value));
      if (row.name) line.append(div("fude-tooltip-name", row.name));
      box.append(line);
    }
    box.classList.add("fude-tooltip-on");
    const width = box.offsetWidth;
    const height = box.offsetHeight;
    const ax = hover.px;
    const ay = hover.kind === "mark" ? hover.py : this.layout.top;
    let left = ax + 12;
    if (left + width > this.layout.width) left = ax - width - 12;
    let top = hover.kind === "mark" ? ay - height - 8 : ay;
    if (top < 0) top = Math.min(this.layout.height - height, ay + 16);
    box.style.transform = `translate(${Math.max(0, Math.round(left))}px, ${Math.max(0, Math.round(top))}px)`;
  }

  private hideTip(): void {
    this.tip?.classList.remove("fude-tooltip-on");
  }

  // -- Legend ---------------------------------------------------------------

  // The legend of a sequential color: its ramp, from its lowest value to
  // its highest.
  private renderRamp(scale: Scale): void {
    const legend = this.legend;
    const [d0, d1] = (scale.domain as [number, number] | null) ?? [0, 1];
    const format = formatter(scale.format, this.locale);
    legend.hidden = false;
    const ramp = div("fude-ramp");
    if (scale.title) ramp.append(div("fude-ramp-title", scale.title));
    const bar = div("fude-ramp-bar");
    const stops = [0, 0.25, 0.5, 0.75, 1].map((t) => this.sequential(d0 + (d1 - d0) * t));
    bar.style.background = `linear-gradient(to right, ${stops.join(", ")})`;
    ramp.append(div("fude-ramp-end", format(d0)), bar, div("fude-ramp-end", format(d1)));
    legend.append(ramp);
  }

  private renderLegend(): void {
    const legend = this.legend;
    legend.replaceChildren();
    const color = this.config.scales?.color;
    const layers = this.config.layers ?? [];
    if (color && color.type === "sequential") return this.renderRamp(color);
    if (!color || color.type !== "ordinal") {
      legend.hidden = true;
      return;
    }
    const domain = color.domain ?? [];
    const arcs = layers.every((layer) => layer.mark === "arc");
    if (domain.length < 2 && !arcs) {
      legend.hidden = true;
      return;
    }
    legend.hidden = false;
    const mark = layers.find((layer) => layer.columns.color)?.mark ?? "bar";
    const toggles = layers.every((layer) => layer.mark === "line" || layer.mark === "point");
    domain.forEach((value, series) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "fude-legend-item";
      const swatch = div(`fude-swatch fude-swatch-${mark === "line" ? "line" : mark === "point" ? "dot" : "box"}`);
      swatch.style.background = this.color(series);
      item.append(swatch, document.createTextNode(String(value)));
      if (toggles) {
        item.setAttribute("aria-pressed", String(!this.hidden.has(series)));
        item.addEventListener("click", () => {
          if (this.hidden.has(series)) this.hidden.delete(series);
          else if (this.hidden.size < domain.length - 1) this.hidden.add(series);
          this.render(true);
        });
      } else {
        item.tabIndex = -1;
      }
      item.addEventListener("pointerenter", () => {
        this.highlight = series;
        this.repaint();
      });
      item.addEventListener("pointerleave", () => {
        this.highlight = null;
        this.repaint();
      });
      legend.append(item);
    });
  }
}

function div(className: string, text?: string): HTMLDivElement {
  const el = document.createElement("div");
  el.className = className;
  if (text !== undefined) el.textContent = text;
  return el;
}

function line(parent: Element, x1: number, y1: number, x2: number, y2: number, stroke: string): void {
  const el = document.createElementNS(SVG, "line");
  el.setAttribute("x1", String(x1));
  el.setAttribute("y1", String(y1));
  el.setAttribute("x2", String(x2));
  el.setAttribute("y2", String(y2));
  el.setAttribute("stroke", stroke);
  el.setAttribute("stroke-width", "1");
  el.setAttribute("shape-rendering", "crispEdges");
  parent.append(el);
}

function text(
  parent: Element,
  content: string,
  x: number,
  y: number,
  options: { anchor: "start" | "middle" | "end"; baseline: "middle" | "alphabetic"; fill: string; tabular?: boolean; halo?: string },
): void {
  const el = document.createElementNS(SVG, "text");
  el.setAttribute("x", String(x));
  el.setAttribute("y", String(y));
  el.setAttribute("text-anchor", options.anchor);
  el.setAttribute("dominant-baseline", options.baseline === "middle" ? "central" : "alphabetic");
  el.setAttribute("fill", options.fill);
  el.setAttribute("font-size", String(FONT_SIZE));
  if (options.tabular) el.setAttribute("font-variant-numeric", "tabular-nums");
  if (options.halo) {
    // A ring of the surface around the letters, so that a label over a
    // line or a mark stays legible.
    el.setAttribute("stroke", options.halo);
    el.setAttribute("stroke-width", "3");
    el.setAttribute("stroke-linejoin", "round");
    el.setAttribute("paint-order", "stroke");
  }
  el.textContent = content;
  parent.append(el);
}

