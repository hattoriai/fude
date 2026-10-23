// A chart on the page: it reads its config (data-fude), lays out its
// scales as wide as it is, draws its marks on a canvas and its words
// (axes, labels, legend, tooltip) as DOM, and draws again in place when
// the config changes, moving each mark from where it was.

import { alpha, mix, ramp, readTheme, rgb, type Theme } from "./theme";
import { formatTime, formatter, parseFormat, tickFormatter, timeTickFormatter } from "./format";
import { position, type Position } from "./scale";
import { draw, easeOut, tween, type Datum, type Paint, type PathPoint, type PathShape, type Shape } from "./shapes";
import { loadMap, type LoadedMap } from "./maps";
import { png, save, svgDocument, SvgContext } from "./export";
import { categorical, dataValue, datumOf, fraction, matches, same, type Datum as PlaceDatum, type Place } from "./places";
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
  /** The right axis: the y of the layers on it. */
  yRight?: Position;
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
  // Where each keyed word was drawn, so that it travels to its next place.
  private places = new Map<string, [number, number]>();
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
  private cleanups: (() => void)[] = [];

  constructor(el: HTMLElement, _transport: Transport | null) {
    this.el = el;
    this.raw = el.dataset.fude ?? "{}";
    this.config = JSON.parse(this.raw) as Config;
    this.id = this.config.id ?? el.id;
    this.locale = this.config.locale ?? undefined;
    this.theme = readTheme(el);
    this.plot = el.querySelector<HTMLElement>(".fude-plot");
    this.formatSingles();
    el.addEventListener("click", (event) => {
      const button = (event.target as Element).closest?.("[data-fude-export]");
      const format = button?.getAttribute("data-fude-export");
      if (format === "svg" || format === "png") void this.download(format);
    });
    if (!this.plot) return;
    this.build(this.plot);
    this.render(true);
    this.observe();
    this.share();
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

  /**
   * Takes new rows, compiled by the server with the chart's rules
   * (Fude.Live.append): adds them to the marks, keeps the last `max` of
   * them, and draws again, moving.
   */
  append(wire: Config, max: number | null): void {
    if (!this.config.layers || !wire.layers) return;
    this.config = merge(this.config, wire, max);
    this.raw = this.el.dataset.fude ?? "{}";
    if (this.plot) this.render(true);
  }

  /** The chart as a standalone SVG: its words, legend, grid, marks and axes. */
  toSVG(): string {
    const ctx = new SvgContext();
    const hover = this.hover;
    const highlight = this.highlight;
    this.hover = null;
    this.highlight = null;
    const paint = this.paintOptions();
    for (const shape of this.shapes) draw(ctx as unknown as CanvasRenderingContext2D, shape, paint);
    this.hover = hover;
    this.highlight = highlight;
    const color = this.config.scales?.color;
    const legend =
      this.config.legend !== false && color?.type === "ordinal" && (color.domain ?? []).length > 1
        ? (color.domain ?? []).map((name, i) => ({ name: String(name), color: this.color(i) }))
        : [];
    return svgDocument({
      width: this.layout?.width ?? this.stage.clientWidth,
      stageHeight: this.layout?.height ?? this.stage.clientHeight,
      font: this.theme.font,
      surface: this.theme.surface,
      text: this.theme.text,
      secondary: this.theme.secondary,
      muted: this.theme.muted,
      title: this.config.title,
      subtitle: this.config.subtitle,
      caption: this.config.caption,
      source: this.config.source,
      legend,
      ramp: this.exportRamp(),
      grid: this.grid,
      marks: ctx.parts,
      axes: this.svg,
    });
  }

  private exportRamp(): { stops: string[]; low: string; high: string; title?: string } | null {
    const scale = this.config.scales?.color;
    if (!scale || scale.type !== "sequential" || this.config.legend === false) return null;
    const [d0, d1] = (scale.domain as [number, number] | null) ?? [0, 1];
    const format = formatter(scale.format, this.locale);
    const stops = [0, 0.25, 0.5, 0.75, 1].map((t) => this.sequential(d0 + (d1 - d0) * t));
    return { stops, low: format(d0), high: format(d1), title: scale.title };
  }

  /** Saves the chart as a file: "svg", or "png" (at twice its size). */
  async download(format: "svg" | "png"): Promise<void> {
    const svg = this.toSVG();
    const blob = format === "svg" ? new Blob([svg], { type: "image/svg+xml" }) : await png(svg);
    const name = (this.config.title ?? this.id).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "chart";
    save(blob, `${name}.${format}`);
  }

  destroy(): void {
    for (const cleanup of this.cleanups) cleanup();
    this.cleanups = [];
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

  // The single numbers that the server wrote: in the locale's words. The
  // number's count of characters sizes it to its box (see fude.css).
  private formatSingles(): void {
    for (const data of this.el.querySelectorAll<HTMLDataElement>("data.fude-value, .fude-delta data, data.fude-share")) {
      const value = parseFloat(data.value);
      if (!Number.isFinite(value)) continue;
      // With no format, exact under 100,000 and compact from there.
      const { name, digits } = parseFormat(data.dataset.format);
      if (name === "percent-change") {
        const text = formatter("percent", this.locale, digits ?? 1)(Math.abs(value));
        data.textContent = `${value >= 0 ? "▲" : "▼"} ${text}`;
      } else {
        const auto = name || (Math.abs(value) >= 100000 ? "compact" : null);
        data.textContent = formatter(digits === undefined ? auto : `${auto ?? ""}:${digits}`, this.locale)(value);
      }
      if (data.classList.contains("fude-value")) data.style.setProperty("--fude-chars", String(data.textContent.length));
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
    const duration = animate ? this.duration() : 0;
    this.travel(duration);
    this.play(from, duration);
  }

  // How long marks move: never with reduced motion, else the chart's own
  // (#16: animate false, or a duration), else the theme's.
  private duration(): number {
    const animate = this.config.animate;
    if (this.theme.reduced || animate === false) return 0;
    if (animate && typeof animate === "object") return animate.duration;
    return this.theme.duration;
  }

  // The words that belong to a mark or a category (a bar's value, a band's
  // name) travel from where they were to their new places, with the marks;
  // new ones fade in.
  private travel(duration: number): void {
    const now = new Map<string, [number, number]>();
    for (const el of this.svg.querySelectorAll<SVGGraphicsElement>("[data-key]")) {
      const key = el.getAttribute("data-key")!;
      const x = Number(el.getAttribute("x"));
      const y = Number(el.getAttribute("y"));
      now.set(key, [x, y]);
      if (duration <= 0 || typeof el.animate !== "function") continue;
      const was = this.places.get(key);
      const timing = { duration, easing: "cubic-bezier(0.215, 0.61, 0.355, 1)" };
      if (!was) {
        if (this.places.size) el.animate([{ opacity: 0 }, { opacity: 1 }], timing);
      } else if (was[0] !== x || was[1] !== y) {
        el.animate([{ transform: `translate(${was[0] - x}px, ${was[1] - y}px)` }, { transform: "translate(0, 0)" }], timing);
      }
    }
    this.places = now;
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
    // What leaves shrinks to where it grew from as it fades.
    for (const shape of this.leaving) draw(ctx, shape.type === "rect" ? tween(shape, { ...shape, ...shape.from }, t) : shape, paint, 1 - raw);
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

    const yr = scales.yRight;
    const pad = axes ? 8 : 2;
    let top = pad + (axes && ((ys?.title && ys.type !== "band") || yr?.title) ? 20 : 0);
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

    // A funnel has no value axis; its labels outside the bars take the right.
    const funnel = (this.config.layers ?? []).find((layer) => layer.options.funnel === true);
    if (funnel) {
      bottom = height - 2;
      right = funnel.options.labels === false || funnel.options.labels === "inside" ? width - pad : width - pad - Math.min(width * 0.3, 120);
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
    // The right axis: its labels beside the plot, on the right.
    if (axes && yr) {
      const probe = position(yr, [bottom, top], 44);
      const format = this.tickFormat(yr, probe);
      right -= Math.max(0, ...probe.ticks.map((tick, i) => this.measure(format(tick, i, probe.ticks)))) + 10;
    }
    if (!axes) top = 4;
    // A sparkline's dots need room at the edges, and its last value on the right.
    if (this.config.kind === "sparkline") {
      const layer = this.config.layers?.[0];
      if (layer?.options.points === "last" || layer?.options.points === "extremes") {
        top = 6;
        bottom = height - 6;
        left = 6;
        right = width - 6;
      }
      const last = layer ? this.sparkValue(layer) : null;
      if (last) right -= this.measure(last.text) + 10;
    }
    // Labels inside a funnel's bars: room on the right for those that do not fit.
    if (funnel && funnel.options.labels === "inside" && xs?.domain) {
      const span = Math.abs((xs.domain[1] as number) - (xs.domain[0] as number)) || 1;
      const words = this.funnelWords(funnel);
      for (let pass = 0; pass < 3; pass++) {
        const out = words.filter(({ v, text }) => this.measure(text) + 16 > ((right - left) * Math.abs(v)) / span);
        const need = out.length ? Math.min(width * 0.3, Math.max(...out.map(({ text }) => this.measure(text))) + 12) : 0;
        const next = width - pad - need;
        if (next === right) break;
        right = next;
      }
    }
    if (right - left < 40) right = left + 40;

    layout.left = left;
    layout.top = top;
    layout.right = right;
    layout.bottom = bottom;
    if (xs) layout.x = position(xs, [left, right], xs.type === "time" ? 90 : 80, this.bandPadding("x"));
    // Names of categories on two lines take a line more below.
    if (this.wrapsLabels(layout)) layout.bottom = bottom = bottom - 14;
    // Categories run down from the top; numbers up from the bottom.
    if (ys) layout.y = position(ys, ys.type === "band" || ys.type === "point" ? [top, bottom] : [bottom, top], 44, this.bandPadding("y"));
    if (yr) layout.yRight = position(yr, [bottom, top], 44);

    if (labels && layout.y) {
      layout.labels = this.placeLabels(labels, layout);
    }
    return layout;
  }

  // A sparkline's last value, in its y format, when it writes it.
  private sparkValue(layer: Layer): { row: number; text: string } | null {
    if (layer.options.value !== true) return null;
    const ys = layer.columns.y ?? [];
    for (let row = layer.n - 1; row >= 0; row--) {
      const v = ys[row];
      if (v != null) return { row, text: formatter(this.config.scales?.y?.format, this.locale)(v) };
    }
    return null;
  }

  // The words of a funnel's stages: each value, with its share of the first.
  private funnelWords(layer: Layer): { row: number; v: number; text: string }[] {
    const value = formatter(this.config.scales?.x?.format, this.locale);
    const percent = formatter("percent", this.locale);
    const words: { row: number; v: number; text: string }[] = [];
    for (let row = 0; row < layer.n; row++) {
      const v = layer.columns.x?.[row];
      if (v == null) continue;
      const share = layer.columns.share?.[row];
      words.push({ row, v, text: share == null || row === 0 ? value(v) : `${value(v)} · ${percent(share)}` });
    }
    return words;
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
    // A panel of small multiples has the whole chart's legend instead.
    if (paths.length === 0 || !this.config.axes || this.config.legend === false) return null;
    const x = this.config.scales?.x;
    if (!x || x.type === "band") return null;
    // The right axis takes the margin where the labels would go: the legend names the series.
    if (this.config.scales?.yRight) return null;
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
    const scale = this.config.scales?.color;
    // A color by its role (a waterfall's increase), not by its place.
    const role = scale?.roles?.[series];
    if (role && this.theme.roles[role]) return this.theme.roles[role]!;
    const scheme = scale?.scheme;
    if (scheme) {
      // A list of colors, or a categorical order: a color for each
      // category; a ramp: its colors spread over the categories in order.
      const steps = this.steps(scheme);
      if (Array.isArray(scheme) || scheme === "categorical" || scheme === "okabe_ito") return steps[series] ?? this.theme.muted;
      const n = scale?.domain?.length ?? 1;
      return ramp(steps, n > 1 ? series / (n - 1) : 0.5);
    }
    return this.theme.series[series] ?? this.theme.muted;
  }

  // The colors of a scheme: its own list, or the theme's by its name.
  private steps(scheme: string | string[] | undefined): string[] {
    if (Array.isArray(scheme)) return scheme;
    return (scheme && this.theme.schemes[scheme]) || this.theme.sequential;
  }

  private sequential(value: number | null | undefined): string {
    const scale = this.config.scales?.color;
    const [d0, d1] = (scale?.domain as [number, number] | null) ?? [0, 1];
    const steps = this.steps(scale?.scheme);
    if (value === null || value === undefined) return ramp(steps, 0.5);
    const mid = scale?.mid;
    if (mid !== undefined && mid !== null) {
      // Diverging: the middle step at mid, and as far from it on each side
      // for the same distance.
      const reach = Math.max(Math.abs(d0 - mid), Math.abs(d1 - mid)) || 1;
      return ramp(steps, 0.5 + (value - mid) / (2 * reach));
    }
    return ramp(steps, d1 === d0 ? 0.5 : (value - d0) / (d1 - d0));
  }

  private colorOf(layer: Layer, row: number): string {
    const value = layer.columns.color?.[row];
    if (this.config.scales?.color?.type === "sequential") return this.sequential(value);
    if (!layer.columns.color) return this.layerColor(layer);
    return this.color(value ?? null);
  }

  /** The color of a layer with no color channel: the second of the order on the right axis, so that each axis has its color. */
  private layerColor(layer: Layer): string {
    return layer.axis === "right" ? (this.theme.series[1] ?? this.theme.series[0]!) : this.theme.series[0]!;
  }

  // -- Shapes -----------------------------------------------------------------

  private computeShapes(layout: Layout): Shape[] {
    const shapes: Shape[] = [];
    const all = layout;
    (this.config.layers ?? []).forEach((layer, index) => {
      const layout = this.layoutOf(layer, all);
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

  /** The color of an axis's title: its layers' when they have no color channel, else the secondary text's. */
  private axisColor(right: boolean): string {
    const layer = (this.config.layers ?? []).find((l) => (l.axis === "right") === right && l.mark !== "rule" && l.mark !== "text");
    return layer && !layer.columns.color ? this.layerColor(layer) : this.theme.secondary;
  }

  /** A layer's layout: its y is the right axis's when the layer is on it. */
  private layoutOf(layer: Layer, layout: Layout): Layout {
    return layer.axis === "right" ? { ...layout, y: layout.yRight } : layout;
  }

  /** A layer's scales: its y is "yRight" when the layer is on the right axis. */
  private scalesOf(layer: Layer | undefined): Record<string, Scale> {
    const scales = this.config.scales ?? {};
    return layer?.axis === "right" ? { ...scales, y: scales.yRight! } : scales;
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
    const scales = this.scalesOf(layer);
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
      if (layer.stack && layer.stack !== "waterfall" && layer.stack !== "center" && v0 !== 0) {
        if (horizontal) p0 += positive ? gap : -gap;
        else p0 += positive ? -gap : gap;
      }
      const k = String(catCol[i]);
      const end = outer.get(k);
      const isOuter = !layer.stack || !end || (positive ? v1 >= end.max : v1 <= end.min);
      const round =
        layer.stack === "center" ? "all" : !isOuter ? "none" : horizontal ? (positive ? "right" : "left") : positive ? "top" : "bottom";
      const key = `${index}:${this.keyOf(catScale, catCol[i])}|${this.keyOf(scales.color, series)}`;
      const datum = { layer: index, row: i, series };
      let color = this.colorOf(layer, i);
      // A funnel in steps: each stage lighter than the one before.
      if (layer.options.step === true && !colors && layer.n > 1) color = mix(color, this.theme.surface, (0.62 * i) / (layer.n - 1));
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
    const scales = this.scalesOf(layer);
    const c = layer.columns;
    const colors = c.color;
    const ys = layer.stack ? c.y1 : c.y;
    const y0s = layer.stack ? c.y0 : null;
    const zero = Math.max(Math.min(0, y.domain[1]), y.domain[0]);
    const baseline = y.at(zero);
    const bySeries = new Map<number, PathShape>();
    const curve = (layer.options.curve as PathShape["curve"]) ?? (this.config.kind === "sparkline" ? "monotone" : "linear");

    // A sparkline's area: under its line, fading down to nothing.
    const spark = this.config.kind === "sparkline";
    const sparkArea = spark && layer.options.area === true;
    for (let i = 0; i < layer.n; i++) {
      const series = colors ? (colors[i] ?? -1) : -1;
      if (series >= 0 && this.hidden.has(series)) continue;
      let path = bySeries.get(series);
      if (!path) {
        const area = layer.mark === "area";
        path = {
          type: sparkArea ? "area" : (layer.mark as "line" | "area"),
          key: `${index}:${series < 0 ? "" : this.keyOf(scales.color, series)}`,
          points: [],
          color: series < 0 ? this.layerColor(layer) : this.color(series),
          curve,
          fill: sparkArea ? 1 : area ? (layer.stack ? 0.78 : 0.12) : 0,
          width: area && layer.stack ? 0 : this.theme.line,
          baseline,
          series: series < 0 ? null : series,
          layer: index,
          dots: layer.options.points === true,
          gradient: sparkArea,
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
      // A sparkline's dots: at its last value, or at its last, lowest and highest.
      if (spark && (layer.options.points === "last" || layer.options.points === "extremes")) {
        const drawn = path.points.filter((point) => point.y !== null);
        const marks = new Set<PathPoint>();
        if (drawn.length) marks.add(drawn[drawn.length - 1]!);
        if (layer.options.points === "extremes" && drawn.length > 1) {
          marks.add(drawn.reduce((a, b) => (b.y! < a.y! ? b : a)));
          marks.add(drawn.reduce((a, b) => (b.y! > a.y! ? b : a)));
        }
        for (const point of marks) {
          shapes.push({ type: "dot", key: `${path.key}:mark:${point.k}`, x: point.x, y: point.y!, r: 3, color: path.color, ring: true, datum: { layer: index, row: point.row, series: path.series } });
        }
      }
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
    const { x, y } = layout;

    // A sparkline's last value, next to the end of its line.
    const sparkLayer = this.config.kind === "sparkline" ? this.config.layers?.[0] : undefined;
    const last = sparkLayer ? this.sparkValue(sparkLayer) : null;
    if (last && x && y) {
      const xv = sparkLayer!.columns.x?.[last.row];
      const yv = sparkLayer!.columns.y?.[last.row];
      if (xv != null && yv != null) {
        const px = x.kind === "band" || x.kind === "point" ? x.at(xv) + (x.kind === "band" ? x.bandwidth / 2 : 0) : x.at(xv);
        text(svg, last.text, px + 8, Math.min(layout.height - 8, Math.max(8, y.at(yv))), { anchor: "start", baseline: "middle", fill: theme.text, tabular: true });
      }
    }

    if (!axes) return;

    // The frame of a sequence of renders (a race of bars): its label, large,
    // under the marks in the plot's corner.
    if (this.config.frame) {
      const size = Math.max(18, Math.min(56, (layout.bottom - layout.top) / 4));
      text(this.grid, this.config.frame, layout.right - 4, layout.bottom - 10, { anchor: "end", baseline: "alphabetic", fill: theme.muted, tabular: true, size, weight: 600 });
    }

    // The value axis: hairline grids at its ticks, labels beside them.
    if (y && scales.y) {
      const format = this.tickFormat(scales.y, y);
      y.ticks.forEach((tick, i) => {
        const py = y.kind === "band" || y.kind === "point" ? y.at(tick) + y.bandwidth / 2 : Math.round(y.at(tick)) + 0.5;
        if (y.kind !== "band" && y.kind !== "point") {
          line(grid, layout.left, py, layout.right, py, tick === 0 ? theme.baseline : theme.grid);
        }
        const band = y.kind === "band" || y.kind === "point";
        text(svg, format(tick, i, y.ticks), layout.left - 8, py, { anchor: "end", baseline: "middle", fill: theme.muted, tabular: true, key: band ? `y:${scales.y!.domain?.[tick]}` : undefined });
      });
      if (scales.y.title && y.kind !== "band") {
        // With a right axis, each title has its layers' color: which line is on which axis.
        const fill = scales.yRight ? this.axisColor(false) : theme.secondary;
        text(svg, scales.y.title, 0, layout.top - 12, { anchor: "start", baseline: "alphabetic", fill });
      }
    }

    // The right axis: its labels beside the plot, with no grid of its own
    // (the left axis's lines would cross its own).
    const yr = layout.yRight;
    if (yr && scales.yRight) {
      const format = this.tickFormat(scales.yRight, yr);
      yr.ticks.forEach((tick, i) => {
        const py = Math.round(yr.at(tick)) + 0.5;
        text(svg, format(tick, i, yr.ticks), layout.right + 8, py, { anchor: "start", baseline: "middle", fill: theme.muted, tabular: true });
      });
      if (scales.yRight.title) {
        text(svg, scales.yRight.title, layout.width, layout.top - 12, { anchor: "end", baseline: "alphabetic", fill: this.axisColor(true) });
      }
    }

    const funnel = (this.config.layers ?? []).some((layer) => layer.options.funnel === true);
    if (x && scales.x && !funnel) {
      const format = this.tickFormat(scales.x, x);
      const ticks = this.thinTicks(x, format);
      const vertical = x.kind !== "band" && x.kind !== "point";
      for (const [tick, lines] of ticks) {
        const px = x.kind === "band" ? x.at(tick) + x.bandwidth / 2 : Math.round(x.at(tick)) + 0.5;
        if (vertical && y && (y.kind === "band" || this.isHorizontalBars())) line(grid, px, layout.top, px, layout.bottom, tick === 0 ? theme.baseline : theme.grid);
        lines.forEach((label, i) => {
          const key = x.kind === "band" || x.kind === "point" ? `x:${scales.x!.domain?.[tick]}:${i}` : undefined;
          text(svg, label, px, layout.bottom + 16 + i * 14, { anchor: "middle", baseline: "alphabetic", fill: theme.muted, tabular: true, key });
        });
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

    // The connectors of a waterfall: from the end of each bar to the next.
    (this.config.layers ?? []).forEach((layer, index) => {
      if (layer.mark !== "bar" || layer.options.connectors !== true || !y) return;
      const bars = this.shapes.filter((shape) => shape.type === "rect" && shape.datum.layer === index) as Extract<Shape, { type: "rect" }>[];
      bars.sort((a, b) => a.datum.row - b.datum.row);
      for (let i = 0; i + 1 < bars.length; i++) {
        const level = layer.columns.y1?.[bars[i]!.datum.row];
        if (level == null) continue;
        const py = Math.round(y.at(level)) + 0.5;
        line(svg, bars[i]!.x + bars[i]!.w, py, bars[i + 1]!.x, py, theme.muted);
      }
    });

    // A funnel's stages: each value, with its share of the first stage,
    // inside its bar when asked and it fits, in the color that reads on it.
    (this.config.layers ?? []).forEach((layer, index) => {
      if (layer.mark !== "bar" || layer.options.funnel !== true || layer.options.labels === false) return;
      const words = new Map(this.funnelWords(layer).map((w) => [w.row, w.text]));
      const inside = layer.options.labels === "inside";
      for (const shape of this.shapes) {
        if (shape.type !== "rect" || shape.datum.layer !== index) continue;
        const label = words.get(shape.datum.row);
        if (label === undefined) continue;
        const cy = shape.y + shape.h / 2;
        if (inside && this.measure(label) + 16 <= shape.w && shape.h >= 14) {
          text(svg, label, shape.x + shape.w / 2, cy, { anchor: "middle", baseline: "middle", fill: onColor(shape.color), tabular: true, key: `v:${shape.key}` });
        } else {
          text(svg, label, shape.x + shape.w + 8, cy, { anchor: "start", baseline: "middle", fill: theme.secondary, halo: theme.surface, tabular: true, key: `v:${shape.key}` });
        }
      }
    });

    // Value labels at the ends of bars.
    (this.config.layers ?? []).forEach((layer, index) => {
      if (layer.mark !== "bar" || layer.options.labels !== true) return;
      const value = formatter(scales[layer.horizontal ? "x" : "y"]?.format, this.locale);
      for (const shape of this.shapes) {
        if (shape.type !== "rect" || shape.datum.layer !== index) continue;
        const v = (layer.horizontal ? layer.columns.x : layer.columns.y)?.[shape.datum.row];
        if (v == null) continue;
        const key = `v:${shape.key}`;
        if (layer.horizontal) text(svg, value(v), shape.x + shape.w + 6, shape.y + shape.h / 2, { anchor: "start", baseline: "middle", fill: theme.secondary, halo: theme.surface, tabular: true, key });
        else text(svg, value(v), shape.x + shape.w / 2, shape.y - 6, { anchor: "middle", baseline: "alphabetic", fill: theme.secondary, halo: theme.surface, tabular: true, key });
      }
    });

    this.renderAnnotations(layout);

    const cross = document.createElementNS(SVG, "g");
    cross.setAttribute("class", "fude-cross");
    svg.append(cross);
  }

  // The notes on the chart: bands under the marks; lines, and labels with a
  // line to their point, over them. A label goes where it stays inside the
  // plot: up and to the right of its point, else left, else below.
  private renderAnnotations(layout: Layout): void {
    const { x, y } = layout;
    const theme = this.theme;
    const at = (pos: Position | undefined, value: number | null, end = false) => {
      if (!pos || value === null || value === undefined) return null;
      if (pos.kind === "band") return pos.at(value) + (end ? pos.bandwidth : 0);
      if (pos.kind === "point") return pos.at(value);
      return pos.at(value);
    };
    const center = (pos: Position | undefined, value: number | null) => {
      const p = at(pos, value);
      return p === null ? null : p + (pos?.kind === "band" ? pos.bandwidth / 2 : 0);
    };

    for (const note of this.config.annotations ?? []) {
      if (note.type === "band") {
        let x0 = layout.left;
        let x1 = layout.right;
        let y0 = layout.top;
        let y1 = layout.bottom;
        if (note.x !== null && note.x2 !== null) {
          const a = at(x, note.x);
          const b = at(x, note.x2, true);
          if (a === null || b === null) continue;
          [x0, x1] = [Math.min(a, b), Math.max(a, b)];
        } else if (note.y !== null && note.y2 !== null) {
          const a = at(y, note.y);
          const b = at(y, note.y2, true);
          if (a === null || b === null) continue;
          [y0, y1] = [Math.min(a, b), Math.max(a, b)];
        } else continue;
        const band = document.createElementNS(SVG, "rect");
        band.setAttribute("x", String(x0));
        band.setAttribute("y", String(y0));
        band.setAttribute("width", String(Math.max(1, x1 - x0)));
        band.setAttribute("height", String(Math.max(1, y1 - y0)));
        band.setAttribute("fill", theme.text);
        band.setAttribute("fill-opacity", "0.06");
        this.grid.append(band);
        if (note.text) text(this.svg, note.text, x0 + 6, y0 + 14, { anchor: "start", baseline: "alphabetic", fill: theme.secondary, halo: theme.surface });
        continue;
      }

      if (note.type === "line") {
        const px = center(x, note.x);
        const py = center(y, note.y);
        if (py !== null && note.x === null) {
          dashed(this.svg, layout.left, py, layout.right, py, theme.secondary);
          if (note.text) text(this.svg, note.text, layout.left + 4, py - 6, { anchor: "start", baseline: "alphabetic", fill: theme.secondary, halo: theme.surface });
        } else if (px !== null) {
          dashed(this.svg, px, layout.top, px, layout.bottom, theme.secondary);
          if (note.text) text(this.svg, note.text, px + 6, layout.top + 12, { anchor: "start", baseline: "alphabetic", fill: theme.secondary, halo: theme.surface });
        }
        continue;
      }

      // A label.
      const px = center(x, note.x) ?? (layout.left + layout.right) / 2;
      const py = center(y, note.y) ?? layout.top + 4;
      if (!note.text) continue;
      const lines = this.wrap(note.text, 150) ?? [note.text];
      const width = Math.max(...lines.map((line) => this.measure(line)));
      const right = px + 18 + width < layout.right;
      const below = py - 24 - lines.length * 14 < layout.top;
      const tx = right ? px + 18 : px - 18;
      const ty = below ? py + 28 : py - 22 - (lines.length - 1) * 14;
      line(this.svg, px, py, right ? tx - 4 : tx + 4, below ? ty - 12 : ty + 4 + (lines.length - 1) * 14, theme.secondary);
      const dot = document.createElementNS(SVG, "circle");
      dot.setAttribute("cx", String(px));
      dot.setAttribute("cy", String(py));
      dot.setAttribute("r", "2.5");
      dot.setAttribute("fill", theme.text);
      this.svg.append(dot);
      lines.forEach((words, i) => {
        text(this.svg, words, tx, ty + i * 14, { anchor: right ? "start" : "end", baseline: "alphabetic", fill: theme.text, halo: theme.surface });
      });
    }
  }

  private isHorizontalBars(): boolean {
    return (this.config.layers ?? []).some((layer) => layer.mark === "bar" && layer.horizontal);
  }

  // The tick labels that fit, at least a label's width apart.
  // The tick labels that fit, at least a label's width apart. The names of
  // categories wrap onto two lines first, as a graphics desk sets them;
  // only names that do not fit on two lines are thinned.
  private thinTicks(x: Position, format: (value: number, index: number, ticks: number[]) => string): [number, string[]][] {
    const labels = x.ticks.map((tick, i) => [tick, format(tick, i, x.ticks)] as [number, string]);
    if (labels.length < 2) return labels.map(([tick, label]) => [tick, [label]]);
    const spacing = Math.abs(x.at(x.ticks[1]!) - x.at(x.ticks[0]!));
    const room = Math.max(1, spacing - 8);
    if (x.kind === "band") {
      const wrapped = labels.map(([tick, label]) => [tick, this.wrap(label, room)] as [number, string[] | null]);
      if (wrapped.every(([, lines]) => lines !== null)) return wrapped as [number, string[]][];
      // Staggered: every other name on a second line, each with two bands.
      const wide = Math.max(1, spacing * 2 - 8);
      if (labels.every(([, label]) => this.measure(label) <= wide)) {
        return labels.map(([tick, label], i) => [tick, i % 2 === 0 ? [label] : ["", label]]);
      }
    }
    const widest = Math.max(...labels.map(([, label]) => this.measure(label)));
    const every = Math.max(1, Math.ceil((widest + 10) / Math.max(1, spacing)));
    return labels.filter((_, i) => i % every === 0).map(([tick, label]) => [tick, [label]]);
  }

  // A label in at most two lines of a width, or null when it does not fit.
  private wrap(label: string, width: number): string[] | null {
    if (this.measure(label) <= width) return [label];
    const words = label.split(/\s+/);
    if (words.length < 2) return null;
    for (let i = words.length - 1; i > 0; i--) {
      const first = words.slice(0, i).join(" ");
      const second = words.slice(i).join(" ");
      if (this.measure(first) <= width && this.measure(second) <= width) return [first, second];
    }
    return null;
  }

  private wrapsLabels(layout: Layout): boolean {
    const { x } = layout;
    const xs = this.config.scales?.x;
    if (!x || !xs || x.kind !== "band" || this.config.axes === false) return false;
    return this.thinTicks(x, this.tickFormat(xs, x)).some(([, lines]) => lines.length > 1);
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

  // -- Places (Fude.Issho.Place) -------------------------------------------

  /**
   * Issho's pointers, through the symbols it reads (no import of it): a
   * person's pointer over a mark is that mark's data (`placeAt`), and each
   * screen draws it on the same data (`locate`), whatever its size.
   */
  private share(): void {
    const element = this.el as unknown as Record<symbol, unknown>;
    const locator = (at: unknown) => this.locate(at);
    const pointer = (x: number, y: number) => this.placeAt(x, y);
    element[Symbol.for("issho.locator")] = locator;
    element[Symbol.for("issho.point")] = pointer;
    this.cleanups.push(() => {
      if (element[Symbol.for("issho.locator")] === locator) delete element[Symbol.for("issho.locator")];
      if (element[Symbol.for("issho.point")] === pointer) delete element[Symbol.for("issho.point")];
    });
  }

  /** The datum of a mark: the values of its channels that name it, not those it measures. */
  private datumOf(shape: Shape): PlaceDatum | null {
    if (!("datum" in shape) || !shape.datum) return null;
    const { layer: li, row } = shape.datum;
    const layer = this.config.layers?.[li];
    const scales = this.scalesOf(layer);
    if (!layer) return null;
    const datum: PlaceDatum = {};
    if (layer.columns.region) {
      const region = this.regionId(dataValue(scales.region, layer.columns.region[row]));
      if (region !== null) datum.region = region;
    }
    for (const channel of ["x", "y", "color"]) {
      const scale = scales[channel];
      const column = layer.columns[channel];
      if (!column || !scale || !(categorical(scale) || scale.type === "time" || scale.bins)) continue;
      const value = dataValue(scale, column[row]);
      if (value !== null) datum[channel] = value;
    }
    if (Object.keys(datum).length === 0) {
      // Points of two amounts (a scatter): named by both.
      for (const channel of ["x", "y"]) {
        const value = dataValue(scales[channel], layer.columns[channel]?.[row]);
        if (value !== null) datum[channel] = value;
      }
    }
    return Object.keys(datum).length ? datum : null;
  }

  /** A region by its map's id (its code), from any of its codes or names. */
  private regionId(value: unknown): string | null {
    if (value === null || value === undefined) return null;
    const index = this.geo?.find(value);
    return index === undefined ? String(value) : (this.geo!.map.regions[index]?.id ?? String(value));
  }

  /** A shape's box in the viewport. */
  private boxOf(shape: Shape, stage: DOMRect): DOMRect | null {
    switch (shape.type) {
      case "rect":
        return new DOMRect(stage.left + shape.x, stage.top + shape.y, shape.w, shape.h);
      case "dot":
        return new DOMRect(stage.left + shape.x - shape.r, stage.top + shape.y - shape.r, shape.r * 2, shape.r * 2);
      case "arc":
      case "region": {
        const { px, py } = this.anchor(shape);
        return new DOMRect(stage.left + px, stage.top + py, 0, 0);
      }
      default:
        return null;
    }
  }

  /** Where a place of the chart is in the viewport: its mark, its point on a line, or its value on an axis. */
  private locate(at: unknown): DOMRect | null {
    const given = datumOf(at);
    const layout = this.layout;
    if (!given || !layout) return null;
    const wanted = given.region === undefined ? given : { ...given, region: this.regionId(given.region) };
    const stage = this.stage.getBoundingClientRect();
    for (const shape of this.marks()) {
      const datum = this.datumOf(shape);
      if (datum && matches(wanted, datum)) return this.boxOf(shape, stage);
    }
    const scales = this.config.scales ?? {};
    const layers = this.config.layers ?? [];
    for (const shape of this.shapes) {
      if (shape.type !== "line" && shape.type !== "area") continue;
      const layer = layers[shape.layer];
      const color = shape.series === null ? null : dataValue(scales.color, shape.series);
      for (const point of shape.points) {
        if (point.y === null || !layer) continue;
        const x = dataValue(scales.x, layer.columns.x?.[point.row]);
        const datum: PlaceDatum = {};
        if (x !== null) datum.x = x;
        if (color !== null) datum.color = color;
        if (matches(wanted, datum)) return new DOMRect(stage.left + point.x - 3, stage.top + point.y - 3, 6, 6);
      }
    }
    // A value of an axis: across the plot there.
    const px = this.axisPixel("x", wanted.x);
    const py = this.axisPixel("y", wanted.y);
    if (px !== null && py !== null) return new DOMRect(stage.left + px, stage.top + py, 0, 0);
    if (px !== null) return new DOMRect(stage.left + px, stage.top + layout.top, 0, layout.bottom - layout.top);
    if (py !== null) return new DOMRect(stage.left + layout.left, stage.top + py, layout.right - layout.left, 0);
    return null;
  }

  /** The pixel of a value on an axis (the middle of a band), or null. */
  private axisPixel(axis: "x" | "y", value: unknown): number | null {
    const position = this.layout?.[axis];
    const scale = this.config.scales?.[axis];
    if (value === undefined || value === null || !position || !scale) return null;
    if (categorical(scale)) {
      for (let i = 0; i < (scale.domain?.length ?? 0); i++) {
        const name = dataValue(scale, i);
        if (name !== null && same(value, name)) return position.at(i) + position.bandwidth / 2;
      }
      return null;
    }
    const number = typeof value === "number" ? value : scale.type === "time" ? Date.parse(String(value)) : Number(value);
    if (!Number.isFinite(number)) return null;
    const pixel = position.at(number);
    const [r0, r1] = position.range;
    return pixel >= Math.min(r0, r1) - 1 && pixel <= Math.max(r0, r1) + 1 ? pixel : null;
  }

  /** The place under a point of the viewport, as the others find it, or null over no mark. */
  private placeAt(clientX: number, clientY: number): Place | null {
    const layout = this.layout;
    if (!layout) return null;
    const stage = this.stage.getBoundingClientRect();
    const px = clientX - stage.left;
    const py = clientY - stage.top;
    if (px < 0 || py < 0 || px > stage.width || py > stage.height) return null;
    if (this.crosshair()) {
      const stops = this.stops();
      if (!stops.length || px < layout.left || px > layout.right) return null;
      let best = stops[0]!;
      for (const stop of stops) if (Math.abs(stop.px - px) < Math.abs(best.px - px)) best = stop;
      const scale = this.config.scales?.x;
      const x = categorical(scale) ? best.k : dataValue(scale, Number(best.k));
      if (x === null) return null;
      return { datum: { x }, y: fraction(py, layout.top, layout.bottom - layout.top) };
    }
    const hit = this.hit(px, py);
    const datum = hit ? this.datumOf(hit) : null;
    if (!hit || !datum) return null;
    const box = this.boxOf(hit, stage);
    if (!box || box.width === 0 || box.height === 0) return { datum };
    return { datum, x: fraction(clientX, box.left, box.width), y: fraction(clientY, box.top, box.height) };
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

  // The rows of the tooltip: a title, then each value with its series,
  // then the fields of the layer's tooltip.
  private tipRows(): { title: string; rows: TipRow[] } | null {
    const tip = this.markRows();
    const hover = this.hover;
    if (!tip || !hover) return tip;
    const layers = this.config.layers ?? [];
    // Under each value, what the tooltip adds to it; a history on a hovered mark only.
    const rows: TipRow[] = [];
    for (const row of tip.rows) {
      rows.push(row);
      const layer = row.at ? layers[row.at.layer] : undefined;
      if (layer && row.at) rows.push(...this.extras(layer, row.at.row, hover.kind !== "x", row.color));
    }
    tip.rows = rows;
    if (hover.kind === "x") {
      // At a crosshair, the fields of each series, named by it.
      const color = this.config.scales?.color;
      for (const layer of layers) {
        if (!layer.tooltip.length) continue;
        for (const row of this.rowsAt(layer, hover.k)) {
          const series = layer.columns.color?.[row];
          if (series != null && this.hidden.has(series)) continue;
          const of = series == null || color?.type !== "ordinal" ? "" : this.valueText(series, color);
          tip.rows.push(...this.tipFields(layer, row).map((field) => ({ ...field, name: of ? `${field.name} · ${of}` : field.name })));
        }
      }
    } else {
      const layer = layers[hover.datum.layer];
      if (layer) tip.rows.push(...this.tipFields(layer, hover.datum.row));
    }
    return tip;
  }

  // A mark's place along its categories (an index, a time, a number), its
  // value, and its series (a heatmap's row), by its mark.
  private marksOf(layer: Layer): { cat: (number | null)[]; val: (number | null)[]; group: (number | null)[] | null; catScale: Scale | undefined } | null {
    const c = layer.columns;
    const scales = this.scalesOf(layer);
    if (layer.mark === "bar" && !c.x2) {
      return layer.horizontal
        ? { cat: c.y ?? [], val: c.x ?? [], group: c.color ?? null, catScale: scales.y }
        : { cat: c.x ?? [], val: c.y ?? [], group: c.color ?? null, catScale: scales.x };
    }
    if (layer.mark === "line" || layer.mark === "area") return { cat: c.x ?? [], val: c.y ?? [], group: c.color ?? null, catScale: scales.x };
    if (layer.mark === "rect" && scales.color?.type === "sequential") return { cat: c.x ?? [], val: c.color ?? [], group: c.y ?? null, catScale: scales.x };
    return null;
  }

  // What the tooltip adds under a mark's value (#15): its change from the
  // point before, its share of the whole (by default on stacked marks), its
  // rank among its series, and, on a hovered mark, its series' history.
  private extras(layer: Layer, row: number, hovered: boolean, color: string | null): TipRow[] {
    const marks = this.marksOf(layer);
    if (!marks || layer.options.funnel === true || layer.stack === "waterfall") return [];
    const tips = layer.tips ?? {};
    const stacked = layer.stack === "zero" || layer.stack === "normalize";
    const { cat, val, group, catScale } = marks;
    const v = val[row];
    const at = cat[row];
    if (v == null || at == null) return [];
    const g = group ? group[row] : null;
    // The marks of the same series, in the order of their categories.
    const same: number[] = [];
    for (let i = 0; i < layer.n; i++) if ((group ? group[i] : null) === g && cat[i] != null && val[i] != null) same.push(i);
    same.sort((a, b) => cat[a]! - cat[b]!);
    const percent = formatter("percent", this.locale);
    const out: TipRow[] = [];

    if (tips.change === true) {
      const index = same.indexOf(row);
      const before = index > 0 ? same[index - 1]! : null;
      const v0 = before === null ? null : val[before]!;
      if (before !== null && v0 !== null && v0 !== 0) {
        const change = (v - v0) / Math.abs(v0);
        out.push({ value: `${change >= 0 ? "▲" : "▼"} ${percent(Math.abs(change))} vs ${this.valueText(cat[before], catScale)}`, name: "", color: null, sub: true, tone: change >= 0 ? "up" : "down" });
      }
    }

    if (tips.share ?? stacked) {
      let total = 0;
      if (stacked) {
        // A segment: of its stack, the shown series at its category.
        for (let i = 0; i < layer.n; i++) {
          const s = group ? group[i] : null;
          if (cat[i] === at && val[i] != null && val[i]! > 0 && !(s != null && this.hidden.has(s))) total += val[i]!;
        }
        if (total > 0) out.push({ value: `${percent(v / total)} of ${this.valueText(at, catScale)}`, name: "", color: null, sub: true });
      } else {
        for (const i of same) if (val[i]! > 0) total += val[i]!;
        if (total > 0) out.push({ value: `${percent(v / total)} of total`, name: "", color: null, sub: true });
      }
    }

    if (tips.rank === true && same.length > 1) {
      const rank = same.filter((i) => val[i]! > v).length + 1;
      out.push({ value: `#${rank} of ${same.length}`, name: "", color: null, sub: true });
    }

    if (tips.history === true && hovered && same.length > 1) {
      out.push({ value: "", name: "", color: null, history: { values: same.map((i) => val[i]!), at: same.indexOf(row), color: color ?? this.theme.series[0]! } });
    }
    return out;
  }

  // The rows of a layer at a place of x, by its key: one for each series.
  private rowsAt(layer: Layer, k: string): number[] {
    const xs = this.scalesOf(layer).x;
    const rows: number[] = [];
    for (let i = 0; i < layer.n; i++) if (this.keyOf(xs, layer.columns.x?.[i]) === k) rows.push(i);
    return rows;
  }

  // The values of the fields of a layer's tooltip at a row: a number in its
  // format, a time in full, a text as it is.
  private tipFields(layer: Layer, row: number): TipRow[] {
    const rows: TipRow[] = [];
    for (const field of layer.tooltip) {
      const value = field.values?.[row];
      if (value === null || value === undefined) continue;
      let text: string;
      if (typeof value === "number") {
        text = field.time !== null && field.time !== undefined ? formatTime(value, field.time || undefined, this.locale) : formatter(field.format, this.locale)(value);
      } else {
        text = String(value);
      }
      rows.push({ value: text, name: field.title ?? "", color: null });
    }
    return rows;
  }

  // The rows of the marks at the pointer.
  private markRows(): { title: string; rows: TipRow[] } | null {
    const hover = this.hover;
    const scales = this.config.scales ?? {};
    const layers = this.config.layers ?? [];
    if (!hover) return null;
    if (hover.kind === "x") {
      const rows: TipRow[] = [];
      let title = "";
      // The bars at the same x, as a chart of bars and a line has them.
      for (const shape of this.shapes) {
        if (shape.type !== "rect" || !shape.datum) continue;
        const layer = layers[shape.datum.layer];
        if (!layer || layer.mark !== "bar" || layer.horizontal) continue;
        const ls = this.scalesOf(layer);
        const row = shape.datum.row;
        if (this.keyOf(ls.x, layer.columns.x?.[row]) !== hover.k) continue;
        title = this.valueText(layer.columns.x?.[row], ls.x);
        const name = shape.datum.series === null ? (ls.y?.title ?? "") : this.valueText(shape.datum.series, scales.color);
        rows.push({ value: this.valueText(layer.columns.y?.[row], ls.y), name, color: shape.color, at: { layer: shape.datum.layer, row } });
      }
      for (const shape of this.shapes) {
        if (shape.type !== "line" && shape.type !== "area") continue;
        const point = shape.points.find((p) => p.k === hover.k);
        if (!point) continue;
        const layer = layers[shape.layer]!;
        const ys = this.scalesOf(layer).y;
        title = this.valueText(layer.columns.x?.[point.row], scales.x);
        const name = shape.series === null ? (ys?.title ?? "") : this.valueText(shape.series, scales.color);
        rows.push({ value: this.valueText(layer.columns.y?.[point.row], ys), name, color: shape.color, at: { layer: shape.layer, row: point.row } });
      }
      if (this.highlight !== null) rows.sort((a, b) => (a.color === this.color(this.highlight) ? -1 : b.color === this.color(this.highlight) ? 1 : 0));
      return { title, rows };
    }
    const { layer: li, row, series } = hover.datum;
    const layer = layers[li]!;
    const ls = this.scalesOf(layer);
    const c = layer.columns;
    const color = series === null ? this.colorOf(layer, row) : this.color(series);
    switch (layer.mark) {
      case "bar": {
        const horizontal = layer.horizontal;
        const catScale = horizontal ? ls.y : scales.x;
        let title = this.valueText((horizontal ? c.y : c.x)?.[row], catScale);
        if (c.x2) title = `${formatter(null, this.locale)(c.x![row]!)}–${formatter(null, this.locale)(c.x2[row]!)}`;
        const valueScale = horizontal ? scales.x : ls.y;
        const value = (horizontal ? c.x : c.y)?.[row];
        const name = series === null ? (valueScale?.title ?? "") : this.valueText(series, scales.color);
        const rows: TipRow[] = [
          { value: this.valueText(value, { ...valueScale!, format: valueScale?.format === "percent" ? undefined : valueScale?.format } as Scale), name, color, at: { layer: li, row } },
        ];
        // A waterfall's step: its change, and the total after it.
        if (layer.stack === "waterfall" && c.y1) rows.push({ value: this.valueText(c.y1[row], valueScale), name: "Total", color: null });
        if (layer.options.funnel === true && c.share && row > 0) rows.push({ value: formatter("percent", this.locale)(c.share[row] ?? 0), name: "of the first", color: null });
        return { title, rows };
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
        const rows: TipRow[] = [];
        if (c.size) rows.push({ value: this.valueText(c.size[row], scales.size), name: scales.size?.title ?? "", color: null });
        if (c.color) rows.push({ value: this.valueText(c.color[row], scales.color), name: scales.color?.title ?? "", color });
        return { title: this.names.get(hover.key) ?? this.valueText(c.region?.[row], scales.region), rows };
      }
      case "rect":
        return {
          title: `${this.valueText(c.x?.[row], scales.x)} · ${this.valueText(c.y?.[row], ls.y)}`,
          rows: c.color ? [{ value: this.valueText(c.color[row], scales.color), name: scales.color?.title ?? "", color, at: { layer: li, row } }] : [],
        };
      default: {
        const rows = [
          { value: this.valueText(c.x?.[row], scales.x), name: scales.x?.title ?? "x", color: null },
          { value: this.valueText(c.y?.[row], ls.y), name: ls.y?.title ?? "y", color: null },
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
      if (row.history) {
        box.append(tipHistory(row.history));
        continue;
      }
      if (row.sub) {
        box.append(div(`fude-tooltip-sub${row.tone ? ` fude-${row.tone}` : ""}`, row.value));
        continue;
      }
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
    if (this.config.legend === false) {
      legend.hidden = true;
      return;
    }
    if (color && color.type === "sequential") return this.renderRamp(color);
    if (!color || color.type !== "ordinal" || color.legend === false) {
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

// -- Appending rows ------------------------------------------------------------

/**
 * A line of the tooltip: a value with its name and color; a line under it
 * (its change, its share, its rank) in the secondary color; or a small
 * history of its series. `at` is the mark it is about.
 */
interface TipRow {
  value: string;
  name: string;
  color: string | null;
  at?: { layer: number; row: number };
  sub?: boolean;
  tone?: "up" | "down";
  history?: { values: number[]; at: number; color: string };
}

const SCALE_OF: Record<string, string> = { x: "x", x2: "x", x0: "x", x1: "x", y: "y", y0: "y", y1: "y", y2: "y", color: "color", size: "size", region: "region" };
const CATEGORICAL = new Set(["band", "point", "ordinal"]);

/**
 * A chart's config with the rows of another of the same chart added: a
 * category goes by its name into the chart's scale (a new one at its end),
 * a number or a time as it is; the scales of numbers and times then fit
 * the rows that stay.
 */
export function merge(config: Config, add: Config, max: number | null): Config {
  const scales: Record<string, Scale> = structuredClone(config.scales ?? {});
  const layers = (config.layers ?? []).map((layer, i) => {
    const more = add.layers?.[i];
    if (!more || more.mark !== layer.mark) return layer;
    const columns: Record<string, (number | null)[]> = {};
    for (const [name, values] of Object.entries(layer.columns)) {
      const scaleName = SCALE_OF[name];
      const scale = scaleName ? scales[scaleName] : undefined;
      const from = scaleName ? add.scales?.[scaleName] : undefined;
      const extra = (more.columns[name] ?? []).map((value) => {
        if (value === null || !scale || !from || !CATEGORICAL.has(scale.type)) return value;
        const category = from.domain?.[value];
        const domain = (scale.domain ??= []);
        let index = domain.findIndex((known) => known === category);
        if (index < 0) index = domain.push(category) - 1;
        return index;
      });
      const all = values.concat(extra);
      columns[name] = max && all.length > max ? all.slice(all.length - max) : all;
    }
    const n = Object.values(columns)[0]?.length ?? 0;
    // The fields of the tooltip: their values follow the rows that stay.
    const tooltip = layer.tooltip.map((field, f) => {
      const all = (field.values ?? []).concat(more.tooltip[f]?.values ?? []);
      return { ...field, values: max && all.length > max ? all.slice(all.length - max) : all };
    });
    return { ...layer, columns, n, tooltip };
  });

  // Numbers and times: the extent of the rows that stay (with zero, if
  // the scale had it).
  for (const [name, scale] of Object.entries(scales)) {
    if (CATEGORICAL.has(scale.type) || !scale.domain || scale.bins) continue;
    let lo = Infinity;
    let hi = -Infinity;
    for (const layer of layers) {
      for (const [column, values] of Object.entries(layer.columns)) {
        if (SCALE_OF[column] !== name) continue;
        for (const value of values) {
          if (value === null) continue;
          if (value < lo) lo = value;
          if (value > hi) hi = value;
        }
      }
    }
    if (lo > hi) continue;
    const [d0, d1] = scale.domain as [number, number];
    const zero = d0 <= 0 && d1 >= 0 && scale.type !== "time";
    scale.domain = zero ? [Math.min(lo, 0), Math.max(hi, 0)] : [lo, hi];
  }
  return { ...config, scales, layers };
}

// A series' history in the tooltip: a small line, with the hovered point.
function tipHistory({ values, at, color }: { values: number[]; at: number; color: string }): SVGSVGElement {
  const w = 132;
  const h = 30;
  const pad = 3;
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const x = (i: number) => pad + ((w - 2 * pad) * i) / Math.max(1, values.length - 1);
  const y = (v: number) => (hi === lo ? h / 2 : h - pad - ((h - 2 * pad) * (v - lo)) / (hi - lo));
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("class", "fude-tooltip-history");
  svg.setAttribute("width", String(w));
  svg.setAttribute("height", String(h));
  svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(SVG, "path");
  path.setAttribute("d", values.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(""));
  path.setAttribute("fill", "none");
  path.setAttribute("stroke", color);
  path.setAttribute("stroke-width", "1.5");
  path.setAttribute("stroke-linejoin", "round");
  const dot = document.createElementNS(SVG, "circle");
  dot.setAttribute("cx", x(at).toFixed(1));
  dot.setAttribute("cy", y(values[at]!).toFixed(1));
  dot.setAttribute("r", "2.75");
  dot.setAttribute("fill", color);
  svg.append(path, dot);
  return svg;
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

function dashed(parent: Element, x1: number, y1: number, x2: number, y2: number, stroke: string): void {
  line(parent, x1, y1, x2, y2, stroke);
  (parent.lastChild as SVGElement).setAttribute("stroke-dasharray", "4 4");
}

// The text that reads on a color: white on a dark one, ink on a light one,
// by the color's relative luminance.
function onColor(color: string): string {
  const [r, g, b] = rgb(color).map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  }) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.3 ? "#16161a" : "#ffffff";
}

function text(
  parent: Element,
  content: string,
  x: number,
  y: number,
  options: { anchor: "start" | "middle" | "end"; baseline: "middle" | "alphabetic"; fill: string; tabular?: boolean; halo?: string; key?: string; size?: number; weight?: number },
): void {
  const el = document.createElementNS(SVG, "text");
  el.setAttribute("x", String(x));
  el.setAttribute("y", String(y));
  el.setAttribute("text-anchor", options.anchor);
  el.setAttribute("dominant-baseline", options.baseline === "middle" ? "central" : "alphabetic");
  el.setAttribute("fill", options.fill);
  el.setAttribute("font-size", String(options.size ?? FONT_SIZE));
  if (options.weight) el.setAttribute("font-weight", String(options.weight));
  if (options.key) el.setAttribute("data-key", options.key);
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
  if (options.halo && typeof el.getBBox === "function") {
    // A plate of the surface behind words over marks: a line under them
    // does not show between the letters.
    const box = el.getBBox();
    if (box.width > 0) {
      const plate = document.createElementNS(SVG, "rect");
      plate.setAttribute("x", String(box.x - 3));
      plate.setAttribute("y", String(box.y - 1));
      plate.setAttribute("width", String(box.width + 6));
      plate.setAttribute("height", String(box.height + 2));
      plate.setAttribute("rx", "2");
      plate.setAttribute("fill", options.halo);
      plate.setAttribute("fill-opacity", "0.88");
      // The plate travels with its words.
      if (options.key) plate.setAttribute("data-key", `${options.key}#plate`);
      parent.insertBefore(plate, el);
    }
  }
}

