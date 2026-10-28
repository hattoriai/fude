// The range of a brush (#13): what a drag across the x axis chose, snapped
// to the axis (whole units of a time, whole bins, round numbers), written
// for the reader while dragging ("Mar–May 2026"), and sent to the server
// in the axis's terms (a date's ISO text, a number).

import { formatter } from "./format";
import { timeText } from "./places";
import { floor, type TimeUnit } from "./rules";

const UNITS: TimeUnit[] = ["millisecond", "second", "minute", "hour", "day", "week", "month", "quarter", "year"];

/** A unit of a time, or null for a time with none (or not a time). */
export function timeUnit(unit: string | null | undefined): TimeUnit | null {
  return unit && (UNITS as string[]).includes(unit) ? (unit as TimeUnit) : null;
}

/** Two values in order. */
export function ordered(a: number, b: number): [number, number] {
  return a <= b ? [a, b] : [b, a];
}

/** A range of times, snapped to whole units: the first and the last unit it touches. */
export function snapTimes(a: number, b: number, unit: TimeUnit | null): [number, number] {
  const [from, to] = ordered(a, b);
  return unit ? [floor(from, unit), floor(to, unit)] : [Math.round(from), Math.round(to)];
}

/** A range of numbers in bins (a histogram's): out to the edges of the bins it touches. */
export function snapBins(a: number, b: number, start: number, step: number): [number, number] {
  const [from, to] = ordered(a, b);
  return [start + Math.floor((from - start) / step) * step, start + Math.ceil((to - start) / step) * step];
}

/** A range of numbers, rounded to a thousandth of the axis's span, so that it reads as the axis does. */
export function snapNumbers(a: number, b: number, span: number): [number, number] {
  const [from, to] = ordered(a, b);
  const digits = span > 0 ? Math.max(0, Math.min(12, -Math.floor(Math.log10(span / 1000)))) : 2;
  const round = (v: number) => Number(v.toFixed(digits));
  return [round(from), round(to)];
}

const ranges = new Map<string, Intl.DateTimeFormat>();

function dateRange(locale: string | undefined, options: Intl.DateTimeFormatOptions): Intl.DateTimeFormat {
  const key = `${locale}|${JSON.stringify(options)}`;
  let format = ranges.get(key);
  if (!format) {
    try {
      format = new Intl.DateTimeFormat(locale, { ...options, timeZone: "UTC" });
    } catch {
      format = new Intl.DateTimeFormat(undefined, { ...options, timeZone: "UTC" });
    }
    ranges.set(key, format);
  }
  return format;
}

function quarter(ms: number): string {
  const date = new Date(ms);
  return `Q${Math.floor(date.getUTCMonth() / 3) + 1}`;
}

/**
 * A range of times as the reader says it, in the parts its unit needs
 * ("Mar – May 2026", "3 – 17 Mar 2026"); one unit alone as itself.
 */
export function timeRangeLabel(from: number, to: number, unit: TimeUnit | null, locale?: string): string {
  if (unit === "quarter") {
    const [y0, y1] = [new Date(from).getUTCFullYear(), new Date(to).getUTCFullYear()];
    if (from === to) return `${quarter(from)} ${y0}`;
    return y0 === y1 ? `${quarter(from)}–${quarter(to)} ${y0}` : `${quarter(from)} ${y0}–${quarter(to)} ${y1}`;
  }
  const options: Intl.DateTimeFormatOptions =
    unit === "year"
      ? { year: "numeric" }
      : unit === "month"
        ? { month: "short", year: "numeric" }
        : unit === "week" || unit === "day"
          ? { day: "numeric", month: "short", year: "numeric" }
          : { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" };
  const format = dateRange(locale, options);
  if (from === to) return format.format(new Date(from));
  return format.formatRange(new Date(from), new Date(to));
}

/** A range of numbers in the axis's format: "1,200–3,400". */
export function numberRangeLabel(from: number, to: number, format: string | null | undefined, locale?: string): string {
  const write = formatter(format, locale);
  return from === to ? write(from) : `${write(from)}–${write(to)}`;
}

/** A value of a range as the server hears it: a time as its ISO text (a date for a unit of a day or more), a number as itself. */
export function sentValue(value: number, time: boolean, unit: TimeUnit | null): string | number {
  return time ? timeText(value, unit ?? undefined) : value;
}
