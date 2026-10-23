// The scales of a chart: from a value of the data to a position in
// pixels. A number or a time scale is widened to round ticks (rules.ts),
// as many as fit the axis's length.

import { nice, ticks, timeTicks, type TimeUnit } from "./rules";
import type { Scale } from "./wire";

export interface Position {
  kind: "band" | "point" | "linear" | "log" | "sqrt" | "time";
  /** The pixel of a value: for a band, the start of its band. */
  at(value: number): number;
  /** The width of a band; 0 for the others. */
  bandwidth: number;
  ticks: number[];
  /** The unit of a time scale's ticks. */
  unit?: TimeUnit;
  domain: [number, number];
  range: [number, number];
  /** The value at a pixel (continuous scales). */
  invert(pixel: number): number;
  /** For a band or a point scale: the index of the band at a pixel. */
  index(pixel: number): number;
  count: number;
}

/** About one tick for each so many pixels of an axis. */
export function tickCount(length: number, spacing: number): number {
  return Math.max(2, Math.round(length / spacing));
}

export function position(scale: Scale, range: [number, number], spacing = 80, padding = 0.25): Position {
  switch (scale.type) {
    case "band":
      return band((scale.domain ?? []).length, range, padding);
    case "point":
      return point((scale.domain ?? []).length, range);
    case "time":
      return time(scale.domain as [number, number] | null, range, spacing);
    default:
      return continuous(scale, range, spacing);
  }
}

function band(count: number, [r0, r1]: [number, number], padding: number): Position {
  const n = Math.max(1, count);
  const length = r1 - r0;
  const step = length / Math.max(1, n - padding + padding * 2);
  const bandwidth = step * (1 - padding);
  const start = r0 + step * padding;
  return {
    kind: "band",
    at: (i) => start + i * step,
    bandwidth,
    ticks: Array.from({ length: count }, (_, i) => i),
    domain: [0, Math.max(0, count - 1)],
    range: [r0, r1],
    invert: (p) => (p - start) / step,
    index: (p) => Math.max(0, Math.min(count - 1, Math.floor((p - start + (step * padding) / 2) / step))),
    count,
  };
}

function point(count: number, [r0, r1]: [number, number]): Position {
  const step = count > 1 ? (r1 - r0) / (count - 1) : 0;
  const at = (i: number) => (count > 1 ? r0 + i * step : (r0 + r1) / 2);
  return {
    kind: "point",
    at,
    bandwidth: 0,
    ticks: Array.from({ length: count }, (_, i) => i),
    domain: [0, Math.max(0, count - 1)],
    range: [r0, r1],
    invert: (p) => (step ? (p - r0) / step : 0),
    index: (p) => (step ? Math.max(0, Math.min(count - 1, Math.round((p - r0) / step))) : 0),
    count,
  };
}

function time(domain: [number, number] | null, range: [number, number], spacing: number): Position {
  let [d0, d1] = domain ?? [0, 1];
  if (d0 === d1) {
    d0 -= 43200000;
    d1 += 43200000;
  }
  const out = timeTicks(d0, d1, tickCount(Math.abs(range[1] - range[0]), spacing * 1.2));
  const linear = map([d0, d1], range);
  return {
    kind: "time",
    at: linear.at,
    bandwidth: 0,
    ticks: out.ticks,
    unit: out.unit,
    domain: [d0, d1],
    range,
    invert: linear.invert,
    index: () => 0,
    count: 0,
  };
}

function continuous(scale: Scale, range: [number, number], spacing: number): Position {
  let [d0, d1] = (scale.domain as [number, number] | null) ?? [0, 1];
  const count = tickCount(Math.abs(range[1] - range[0]), spacing);
  if (scale.type === "log" && d0 > 0 && d1 > 0) return log([d0, d1], range);
  if (scale.nice !== false) [d0, d1] = nice(d0, d1, count);
  else if (d0 === d1) [d0, d1] = nice(d0, d1, count);
  const kind = scale.type === "sqrt" ? "sqrt" : "linear";
  const transform = kind === "sqrt" ? (v: number) => Math.sign(v) * Math.sqrt(Math.abs(v)) : (v: number) => v;
  const inverse = kind === "sqrt" ? (v: number) => Math.sign(v) * v * v : (v: number) => v;
  const linear = map([transform(d0), transform(d1)], range);
  return {
    kind,
    at: (v) => linear.at(transform(v)),
    bandwidth: 0,
    ticks: ticks(d0, d1, count),
    domain: [d0, d1],
    range,
    invert: (p) => inverse(linear.invert(p)),
    index: () => 0,
    count: 0,
  };
}

function log([d0, d1]: [number, number], range: [number, number]): Position {
  const l0 = Math.floor(Math.log10(d0));
  const l1 = Math.ceil(Math.log10(d1));
  const linear = map([l0, l1], range);
  const out: number[] = [];
  for (let p = l0; p <= l1; p++) out.push(Math.pow(10, p));
  return {
    kind: "log",
    at: (v) => linear.at(Math.log10(Math.max(v, Number.MIN_VALUE))),
    bandwidth: 0,
    ticks: out,
    domain: [Math.pow(10, l0), Math.pow(10, l1)],
    range,
    invert: (p) => Math.pow(10, linear.invert(p)),
    index: () => 0,
    count: 0,
  };
}

function map([d0, d1]: [number, number], [r0, r1]: [number, number]) {
  const k = d1 === d0 ? 0 : (r1 - r0) / (d1 - d0);
  return {
    at: (v: number) => r0 + (v - d0) * k,
    invert: (p: number) => (k === 0 ? d0 : d0 + (p - r0) / k),
  };
}
