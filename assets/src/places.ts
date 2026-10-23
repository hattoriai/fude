// Places in a chart, in its data's terms (Fude.Issho.Place): a mark is
// named by the values of its channels (a category's name, a time as ISO
// 8601 text, a number), never by pixels, so that each person's pointer is
// on the same data on every screen, at every size.

import type { Scale } from "./wire";

/** The values of a mark's channels: `x`, `y`, `color`, `region`. */
export type Datum = Record<string, string | number>;

/** A place of a chart, as Issho shares it: a datum, and where in it (0 to 1). */
export interface Place {
  datum: Datum;
  x?: number;
  y?: number;
}

const CHANNELS = ["x", "y", "color", "region"];

/** Whether a scale's values are names (categories) rather than amounts. */
export function categorical(scale: Scale | undefined): boolean {
  return !!scale && (scale.type === "band" || scale.type === "point" || scale.type === "ordinal");
}

/** Whether a scale is of times, as milliseconds (a time axis, or bands of months). */
function timed(scale: Scale | undefined): boolean {
  return !!scale && (scale.type === "time" || !!scale.time);
}

/** A time as the place names it: a day as its date, else to the second. */
export function timeText(ms: number, unit?: string): string {
  const iso = new Date(ms).toISOString();
  return unit && ["day", "week", "month", "quarter", "year"].includes(unit) ? iso.slice(0, 10) : iso.replace(".000Z", "Z");
}

/** A value of a column (an index into a category scale, a time, a number), in the data's terms. */
export function dataValue(scale: Scale | undefined, value: number | null | undefined): string | number | null {
  if (value === null || value === undefined) return null;
  const plain = categorical(scale) ? scale!.domain?.[value] : value;
  if (plain === null || plain === undefined) return null;
  if (timed(scale) && typeof plain === "number") return timeText(plain, scale!.time ?? scale!.unit);
  return typeof plain === "number" || typeof plain === "string" ? plain : String(plain);
}

/** Whether a value a place gives is a value of the data: the same name, number or time. */
export function same(wanted: unknown, value: string | number): boolean {
  if (wanted === value || String(wanted) === String(value)) return true;
  if (typeof wanted !== "string" && typeof wanted !== "number") return false;
  const a = typeof wanted === "number" ? wanted : Date.parse(wanted);
  const b = typeof value === "number" ? value : Date.parse(value);
  return Number.isFinite(a) && Number.isFinite(b) && a === b;
}

/**
 * Whether a mark's datum is the one a place names: each of its values,
 * the same, and none left out (a time alone names no one line of several:
 * it is the time across the plot).
 */
export function matches(wanted: Record<string, unknown>, datum: Datum): boolean {
  const keys = Object.keys(wanted).filter((key) => CHANNELS.includes(key));
  return (
    keys.length > 0 &&
    keys.every((key) => datum[key] !== undefined && same(wanted[key], datum[key]!)) &&
    Object.keys(datum).every((key) => key in wanted)
  );
}

/** The datum of a place, or null for a place that is not a chart's. */
export function datumOf(at: unknown): Record<string, unknown> | null {
  if (typeof at !== "object" || at === null) return null;
  const datum = (at as { datum?: unknown }).datum;
  return typeof datum === "object" && datum !== null && !Array.isArray(datum) ? (datum as Record<string, unknown>) : null;
}

/** A fraction from 0 to 1, rounded to hundredths, of a point within a span. */
export function fraction(value: number, from: number, size: number): number {
  return Math.round(Math.min(1, Math.max(0, size > 0 ? (value - from) / size : 0.5)) * 100) / 100;
}
