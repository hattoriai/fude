import { alpha, mix } from "./theme";

// The shapes a chart draws, in pixels, each with the key that keeps its
// identity from one render to the next: a bar moves to its new height, a
// line's points to their new places, a new mark grows from the baseline.

export interface Datum {
  layer: number;
  row: number;
  series: number | null;
}

export interface RectShape {
  type: "rect";
  key: string;
  x: number;
  y: number;
  w: number;
  h: number;
  color: string;
  /** Which corners are round: the end of a bar away from its baseline. */
  round: "top" | "bottom" | "left" | "right" | "all" | "none";
  /** Where the shape grows from when it is new. */
  from: { x: number; y: number; w: number; h: number };
  datum: Datum;
  label?: string;
  labelInside?: boolean;
}

export interface PathPoint {
  k: string;
  x: number;
  y: number | null;
  y0: number;
  row: number;
}

export interface PathShape {
  type: "line" | "area";
  key: string;
  points: PathPoint[];
  color: string;
  curve: "linear" | "monotone" | "step";
  fill: number;
  width: number;
  baseline: number;
  series: number | null;
  layer: number;
  dots: boolean;
  /** The fill of an area fades from its line down to nothing (a sparkline's). */
  gradient?: boolean;
}

export interface DotShape {
  type: "dot";
  key: string;
  x: number;
  y: number;
  r: number;
  color: string;
  ring: boolean;
  datum: Datum;
}

export interface ArcShape {
  type: "arc";
  key: string;
  cx: number;
  cy: number;
  r0: number;
  r1: number;
  a0: number;
  a1: number;
  color: string;
  datum: Datum;
}

export interface RuleShape {
  type: "rule";
  key: string;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  color: string;
  dashed: boolean;
  /** The width of its line: 1.5 unless given. */
  width?: number;
}

/** A region of a map: its path in the map's units, placed by `k`, `tx`, `ty`. */
export interface RegionShape {
  type: "region";
  key: string;
  path: Path2D;
  k: number;
  tx: number;
  ty: number;
  color: string;
  name: string;
  /** Its center in pixels: where its tooltip points. */
  center: [number, number];
  datum: Datum | null;
}

/**
 * A box of a box plot or a candlestick, at x (its middle) and w wide: a
 * body from b0 to b1 (a candle's open and close, a box's quartiles), a line
 * across at mid (a median), a whisker or a wick from lo to hi. In pixels.
 */
export interface BoxShape {
  type: "box";
  key: string;
  x: number;
  w: number;
  lo: number;
  b0: number;
  mid: number | null;
  b1: number;
  hi: number;
  color: string;
  /** The color of its whiskers and median: the text's on a box, its own on a candle. */
  ink: string;
  datum: Datum;
}

/** A closed shape through its points (a radar's series), filled faintly, its line in its color. */
export interface PolyShape {
  type: "poly";
  key: string;
  cx: number;
  cy: number;
  points: { x: number; y: number }[];
  color: string;
  series: number | null;
}

export type Shape = RectShape | PathShape | DotShape | ArcShape | RuleShape | RegionShape | BoxShape | PolyShape;

// -- Tweening ---------------------------------------------------------------

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

export function easeOut(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

/**
 * The shape between where it was (`prev`) and where it goes, at `t` from 0
 * to 1. A shape that is new comes from its start: a bar from its baseline,
 * a point from nothing, an arc from its start angle.
 */
export function tween(prev: Shape | undefined, next: Shape, t: number): Shape {
  if (t >= 1) return next;
  switch (next.type) {
    case "rect": {
      const p = prev && prev.type === "rect" ? prev : { ...next, ...next.from };
      return { ...next, x: lerp(p.x, next.x, t), y: lerp(p.y, next.y, t), w: lerp(p.w, next.w, t), h: lerp(p.h, next.h, t) };
    }
    case "line":
    case "area": {
      const before = new Map<string, PathPoint>();
      if (prev && (prev.type === "line" || prev.type === "area")) for (const point of prev.points) before.set(point.k, point);
      // A point new to a path that was there (a point streamed in) comes
      // from where the path was before it, not from the baseline.
      let last: PathPoint | undefined;
      const points = next.points.map((point) => {
        const from = before.get(point.k) ?? (before.size ? last : undefined);
        if (before.has(point.k)) last = before.get(point.k);
        const startY = from ? from.y : next.baseline;
        const startY0 = from ? from.y0 : next.baseline;
        const startX = from ? from.x : point.x;
        return {
          ...point,
          x: lerp(startX, point.x, t),
          y: point.y === null ? null : lerp(startY ?? next.baseline, point.y, t),
          y0: lerp(startY0, point.y0, t),
        };
      });
      return { ...next, points };
    }
    case "dot": {
      const p = prev && prev.type === "dot" ? prev : { ...next, r: 0 };
      return { ...next, x: lerp(p.x, next.x, t), y: lerp(p.y, next.y, t), r: lerp(p.r, next.r, t) };
    }
    case "arc": {
      const p = prev && prev.type === "arc" ? prev : { ...next, a1: next.a0 };
      return { ...next, a0: lerp(p.a0, next.a0, t), a1: lerp(p.a1, next.a1, t), r0: lerp(p.r0, next.r0, t), r1: lerp(p.r1, next.r1, t) };
    }
    case "region": {
      // A region keeps its place; its color moves to the new one.
      const p = prev && prev.type === "region" ? prev : null;
      return p && p.color !== next.color ? { ...next, color: mix(p.color, next.color, t) } : next;
    }
    case "rule": {
      const p = prev && prev.type === "rule" ? prev : next;
      return { ...next, x1: lerp(p.x1, next.x1, t), y1: lerp(p.y1, next.y1, t), x2: lerp(p.x2, next.x2, t), y2: lerp(p.y2, next.y2, t) };
    }
    case "box": {
      // A new box opens from the middle of its body.
      const middle = (next.b0 + next.b1) / 2;
      const p = prev && prev.type === "box" ? prev : { ...next, lo: middle, b0: middle, mid: next.mid === null ? null : middle, b1: middle, hi: middle };
      const mid = next.mid === null ? null : lerp(p.mid ?? next.mid, next.mid, t);
      return { ...next, x: lerp(p.x, next.x, t), w: lerp(p.w, next.w, t), lo: lerp(p.lo, next.lo, t), b0: lerp(p.b0, next.b0, t), mid, b1: lerp(p.b1, next.b1, t), hi: lerp(p.hi, next.hi, t) };
    }
    case "poly": {
      // A new shape grows from the center; one of as many points moves to its new place.
      const from = prev && prev.type === "poly" && prev.points.length === next.points.length ? prev.points : next.points.map(() => ({ x: next.cx, y: next.cy }));
      return { ...next, points: next.points.map((point, i) => ({ x: lerp(from[i]!.x, point.x, t), y: lerp(from[i]!.y, point.y, t) })) };
    }
  }
}

// -- Drawing ----------------------------------------------------------------

export interface Paint {
  surface: string;
  gap: number;
  radius: number;
  /** The key of the mark in focus, and how much the others fade. */
  focus: (key: string, series: number | null) => number;
}

export function draw(ctx: CanvasRenderingContext2D, shape: Shape, paint: Paint, opacity = 1): void {
  switch (shape.type) {
    case "rect":
      return drawRect(ctx, shape, paint, opacity);
    case "line":
    case "area":
      return drawPath(ctx, shape, paint, opacity);
    case "dot":
      return drawDot(ctx, shape, paint, opacity);
    case "arc":
      return drawArc(ctx, shape, paint, opacity);
    case "rule":
      return drawRule(ctx, shape, opacity);
    case "region":
      return drawRegion(ctx, shape, paint, opacity);
    case "box":
      return drawBox(ctx, shape, paint, opacity);
    case "poly":
      return drawPoly(ctx, shape, paint, opacity);
  }
}

function drawBox(ctx: CanvasRenderingContext2D, s: BoxShape, paint: Paint, opacity: number): void {
  if (s.w <= 0.1) return;
  ctx.globalAlpha = opacity * paint.focus(s.key, s.datum.series);
  const x = Math.round(s.x) + 0.5;
  const top = Math.min(s.b0, s.b1);
  const height = Math.max(1, Math.abs(s.b1 - s.b0));
  // The whisker (a wick), behind the body.
  ctx.strokeStyle = s.ink;
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(x, s.hi);
  ctx.lineTo(x, s.lo);
  if (s.mid !== null) {
    // A box's whiskers end in short caps.
    const cap = s.w / 4;
    ctx.moveTo(x - cap, Math.round(s.hi) + 0.5);
    ctx.lineTo(x + cap, Math.round(s.hi) + 0.5);
    ctx.moveTo(x - cap, Math.round(s.lo) + 0.5);
    ctx.lineTo(x + cap, Math.round(s.lo) + 0.5);
  }
  ctx.stroke();
  ctx.fillStyle = s.color;
  const r = Math.min(paint.radius / 2, s.w / 2, height / 2);
  ctx.beginPath();
  ctx.moveTo(s.x - s.w / 2 + r, top);
  ctx.arcTo(s.x + s.w / 2, top, s.x + s.w / 2, top + height, r);
  ctx.arcTo(s.x + s.w / 2, top + height, s.x - s.w / 2, top + height, r);
  ctx.arcTo(s.x - s.w / 2, top + height, s.x - s.w / 2, top, r);
  ctx.arcTo(s.x - s.w / 2, top, s.x + s.w / 2, top, r);
  ctx.closePath();
  ctx.fill();
  if (s.mid !== null) {
    // The median across the body, in the surface's color so that it reads on any.
    ctx.strokeStyle = paint.surface;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(s.x - s.w / 2, s.mid);
    ctx.lineTo(s.x + s.w / 2, s.mid);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
}

function drawPoly(ctx: CanvasRenderingContext2D, s: PolyShape, paint: Paint, opacity: number): void {
  if (s.points.length < 2) return;
  const focus = paint.focus(s.key, s.series);
  ctx.beginPath();
  s.points.forEach((point, i) => (i === 0 ? ctx.moveTo(point.x, point.y) : ctx.lineTo(point.x, point.y)));
  ctx.closePath();
  ctx.globalAlpha = opacity * focus * 0.14;
  ctx.fillStyle = s.color;
  ctx.fill();
  ctx.globalAlpha = opacity * focus;
  ctx.strokeStyle = s.color;
  ctx.lineWidth = 2;
  ctx.lineJoin = "round";
  ctx.stroke();
  ctx.globalAlpha = 1;
}

function drawRegion(ctx: CanvasRenderingContext2D, s: RegionShape, paint: Paint, opacity: number): void {
  ctx.save();
  ctx.translate(s.tx, s.ty);
  ctx.scale(s.k, s.k);
  ctx.globalAlpha = opacity * (s.datum ? paint.focus(s.key, null) : 1);
  ctx.fillStyle = s.color;
  ctx.fill(s.path);
  ctx.globalAlpha = opacity;
  ctx.lineWidth = 0.75 / s.k;
  ctx.lineJoin = "round";
  ctx.strokeStyle = paint.surface;
  ctx.stroke(s.path);
  ctx.restore();
}

function drawRect(ctx: CanvasRenderingContext2D, s: RectShape, paint: Paint, opacity: number): void {
  if (s.w <= 0.1 || s.h <= 0.1) return;
  ctx.globalAlpha = opacity * paint.focus(s.key, s.datum.series);
  ctx.fillStyle = s.color;
  const r = Math.min(paint.radius, s.w / 2, s.h / 2);
  const [tl, tr, br, bl] =
    s.round === "top"
      ? [r, r, 0, 0]
      : s.round === "bottom"
        ? [0, 0, r, r]
        : s.round === "right"
          ? [0, r, r, 0]
          : s.round === "left"
            ? [r, 0, 0, r]
            : s.round === "all"
              ? [r, r, r, r]
              : [0, 0, 0, 0];
  ctx.beginPath();
  ctx.moveTo(s.x + tl, s.y);
  ctx.lineTo(s.x + s.w - tr, s.y);
  if (tr) ctx.arcTo(s.x + s.w, s.y, s.x + s.w, s.y + tr, tr);
  ctx.lineTo(s.x + s.w, s.y + s.h - br);
  if (br) ctx.arcTo(s.x + s.w, s.y + s.h, s.x + s.w - br, s.y + s.h, br);
  ctx.lineTo(s.x + bl, s.y + s.h);
  if (bl) ctx.arcTo(s.x, s.y + s.h, s.x, s.y + s.h - bl, bl);
  ctx.lineTo(s.x, s.y + tl);
  if (tl) ctx.arcTo(s.x, s.y, s.x + tl, s.y, tl);
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = 1;
}

// The runs of a path: its points between gaps (a null).
function runs(points: PathPoint[]): PathPoint[][] {
  const out: PathPoint[][] = [];
  let run: PathPoint[] = [];
  for (const point of points) {
    if (point.y === null) {
      if (run.length) out.push(run);
      run = [];
    } else {
      run.push(point);
    }
  }
  if (run.length) out.push(run);
  return out;
}

function trace(ctx: CanvasRenderingContext2D, points: { x: number; y: number }[], curve: PathShape["curve"], move: boolean): void {
  if (points.length === 0) return;
  const first = points[0]!;
  if (move) ctx.moveTo(first.x, first.y);
  else ctx.lineTo(first.x, first.y);
  if (curve === "step") {
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(points[i]!.x, points[i - 1]!.y);
      ctx.lineTo(points[i]!.x, points[i]!.y);
    }
  } else if (curve === "monotone" && points.length > 2) {
    monotone(ctx, points);
  } else {
    for (let i = 1; i < points.length; i++) ctx.lineTo(points[i]!.x, points[i]!.y);
  }
}

// A monotone cubic through the points (Fritsch–Carlson): smooth, with no
// overshoot past a value the data does not have.
function monotone(ctx: CanvasRenderingContext2D, p: { x: number; y: number }[]): void {
  const n = p.length;
  const slopes: number[] = [];
  const tangents: number[] = new Array(n).fill(0);
  for (let i = 0; i < n - 1; i++) {
    const dx = p[i + 1]!.x - p[i]!.x;
    slopes.push(dx === 0 ? 0 : (p[i + 1]!.y - p[i]!.y) / dx);
  }
  tangents[0] = slopes[0]!;
  tangents[n - 1] = slopes[n - 2]!;
  for (let i = 1; i < n - 1; i++) {
    const a = slopes[i - 1]!;
    const b = slopes[i]!;
    tangents[i] = a * b <= 0 ? 0 : (3 * a * b) / (Math.max(a, b) + 2 * Math.min(a, b));
  }
  for (let i = 0; i < n - 1; i++) {
    const a = p[i]!;
    const b = p[i + 1]!;
    const dx = (b.x - a.x) / 3;
    ctx.bezierCurveTo(a.x + dx, a.y + dx * tangents[i]!, b.x - dx, b.y - dx * tangents[i + 1]!, b.x, b.y);
  }
}

function drawPath(ctx: CanvasRenderingContext2D, s: PathShape, paint: Paint, opacity: number): void {
  const focus = paint.focus(s.key, s.series);
  for (const run of runs(s.points)) {
    const top = run.map((point) => ({ x: point.x, y: point.y as number }));
    if (s.type === "area" && s.fill > 0) {
      const bottom = run.map((point) => ({ x: point.x, y: point.y0 })).reverse();
      ctx.beginPath();
      trace(ctx, top, s.curve, true);
      trace(ctx, bottom, s.curve, false);
      ctx.closePath();
      ctx.globalAlpha = opacity * focus * s.fill;
      if (s.gradient) {
        const top = Math.min(...run.map((point) => point.y as number));
        const gradient = ctx.createLinearGradient(0, top, 0, s.baseline);
        gradient.addColorStop(0, alpha(s.color, 0.32));
        gradient.addColorStop(1, alpha(s.color, 0));
        ctx.fillStyle = gradient;
      } else {
        ctx.fillStyle = s.color;
      }
      ctx.fill();
    }
    if (s.width > 0) {
      ctx.beginPath();
      trace(ctx, top, s.curve, true);
      ctx.globalAlpha = opacity * focus;
      ctx.strokeStyle = s.color;
      ctx.lineWidth = s.width;
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      ctx.stroke();
    }
    if (s.dots || (run.length === 1 && s.width > 0)) {
      for (const point of top) {
        drawDot(ctx, { type: "dot", key: "", x: point.x, y: point.y, r: 3.5, color: s.color, ring: true, datum: { layer: s.layer, row: 0, series: s.series } }, paint, opacity * focus);
      }
    }
  }
  ctx.globalAlpha = 1;
}

function drawDot(ctx: CanvasRenderingContext2D, s: DotShape, paint: Paint, opacity: number): void {
  if (s.r <= 0.1) return;
  ctx.globalAlpha = opacity * (s.key ? paint.focus(s.key, s.datum.series) : 1);
  if (s.ring) {
    ctx.beginPath();
    ctx.arc(s.x, s.y, s.r + 2, 0, Math.PI * 2);
    ctx.fillStyle = paint.surface;
    ctx.fill();
  }
  ctx.beginPath();
  ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
  ctx.fillStyle = s.color;
  ctx.fill();
  ctx.globalAlpha = 1;
}

function drawArc(ctx: CanvasRenderingContext2D, s: ArcShape, paint: Paint, opacity: number): void {
  if (s.a1 - s.a0 <= 0) return;
  ctx.globalAlpha = opacity * paint.focus(s.key, s.datum.series);
  const start = -Math.PI / 2 + s.a0 * Math.PI * 2;
  const end = -Math.PI / 2 + s.a1 * Math.PI * 2;
  ctx.beginPath();
  ctx.arc(s.cx, s.cy, s.r1, start, end);
  if (s.r0 > 0) ctx.arc(s.cx, s.cy, s.r0, end, start, true);
  else ctx.lineTo(s.cx, s.cy);
  ctx.closePath();
  ctx.fillStyle = s.color;
  ctx.fill();
  ctx.lineWidth = paint.gap;
  ctx.strokeStyle = paint.surface;
  ctx.lineJoin = "round";
  ctx.stroke();
  ctx.globalAlpha = 1;
}

function drawRule(ctx: CanvasRenderingContext2D, s: RuleShape, opacity: number): void {
  ctx.globalAlpha = opacity;
  ctx.strokeStyle = s.color;
  ctx.lineWidth = s.width ?? 1.5;
  ctx.setLineDash(s.dashed ? [4, 4] : []);
  ctx.beginPath();
  ctx.moveTo(s.x1, s.y1);
  ctx.lineTo(s.x2, s.y2);
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.globalAlpha = 1;
}
