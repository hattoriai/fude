// How the chart writes numbers and times: with the browser's Intl, in the
// chart's locale (the browser's unless given). Times are in UTC, as they
// came from the server.

import type { TimeUnit } from "./rules";

const numberFormats = new Map<string, Intl.NumberFormat>();
const dateFormats = new Map<string, Intl.DateTimeFormat>();

function numberFormat(locale: string | undefined, options: Intl.NumberFormatOptions): Intl.NumberFormat {
  const key = `${locale}|${JSON.stringify(options)}`;
  let format = numberFormats.get(key);
  if (!format) {
    try {
      format = new Intl.NumberFormat(locale, options);
    } catch {
      format = new Intl.NumberFormat(undefined, options);
    }
    numberFormats.set(key, format);
  }
  return format;
}

function dateFormat(locale: string | undefined, options: Intl.DateTimeFormatOptions): Intl.DateTimeFormat {
  const key = `${locale}|${JSON.stringify(options)}`;
  let format = dateFormats.get(key);
  if (!format) {
    try {
      format = new Intl.DateTimeFormat(locale, { ...options, timeZone: "UTC" });
    } catch {
      format = new Intl.DateTimeFormat(undefined, { ...options, timeZone: "UTC" });
    }
    dateFormats.set(key, format);
  }
  return format;
}

const BYTES = ["byte", "kilobyte", "megabyte", "gigabyte", "terabyte", "petabyte"];

/**
 * A format of the wire and its digits: "number:0" is "number" with no
 * decimals, "currency:EUR:2" a currency with two, ":0" no format with none.
 */
export function parseFormat(format: string | null | undefined): { name: string | null; digits: number | undefined } {
  const match = /^(.*?)(?::(\d+))?$/.exec(format ?? "");
  const name = match?.[1] || null;
  return { name, digits: match?.[2] === undefined ? undefined : Number(match[2]) };
}

// Exactly so many decimals, when they are given.
function fixed(digits: number | undefined): Intl.NumberFormatOptions {
  return digits === undefined ? {} : { minimumFractionDigits: digits, maximumFractionDigits: digits };
}

/**
 * A function that writes a value of a format: "number", "integer",
 * "percent", "compact", "currency:EUR", "bytes", "duration" (seconds), or
 * none (as a number, with no more digits than it needs). The digits of the
 * format ("number:0") are exactly its decimals; the digits given, at most.
 */
export function formatter(format: string | null | undefined, locale?: string, digits?: number): (value: number) => string {
  const parsed = parseFormat(format);
  format = parsed.name;
  // The channel's digits are exact; those given are at most.
  const own = parsed.digits;
  switch (format) {
    case "integer":
      return (v) => numberFormat(locale, { maximumFractionDigits: 0 }).format(v);
    case "number":
      return (v) => numberFormat(locale, own === undefined ? { maximumFractionDigits: digits ?? 2 } : fixed(own)).format(v);
    case "percent":
      return (v) => numberFormat(locale, { style: "percent", maximumFractionDigits: digits ?? 1, ...fixed(own) }).format(v);
    case "compact":
      return (v) => numberFormat(locale, { notation: "compact", maximumFractionDigits: 1, ...fixed(own) }).format(v);
    case "bytes":
      return (v) => {
        let i = 0;
        while (Math.abs(v) >= 1024 && i < BYTES.length - 1) {
          v /= 1024;
          i++;
        }
        return numberFormat(locale, { style: "unit", unit: BYTES[i], unitDisplay: "short", maximumFractionDigits: 1 }).format(v);
      };
    case "duration":
      return (v) => duration(v, locale);
    default:
      if (format && format.startsWith("currency:")) {
        const currency = format.slice(9);
        return (v) =>
          numberFormat(locale, {
            style: "currency",
            currency,
            ...(own === undefined ? { maximumFractionDigits: digits ?? (Math.abs(v) >= 1000 ? 0 : 2) } : fixed(own)),
          }).format(v);
      }
      return (v) => numberFormat(locale, own === undefined ? { maximumFractionDigits: digits ?? fractionDigits(v) } : fixed(own)).format(v);
  }
}

// As many fraction digits as a value needs, up to 3 below 1 and 2 above.
function fractionDigits(value: number): number {
  const abs = Math.abs(value);
  if (abs === 0 || Number.isInteger(value)) return 0;
  return abs < 1 ? 3 : 2;
}

function duration(seconds: number, locale?: string): string {
  const units: [string, number][] = [
    ["day", 86400],
    ["hour", 3600],
    ["minute", 60],
    ["second", 1],
  ];
  const abs = Math.abs(seconds);
  for (const [unit, size] of units) {
    if (abs >= size || unit === "second") {
      return numberFormat(locale, { style: "unit", unit, unitDisplay: "narrow", maximumFractionDigits: 1 }).format(seconds / size);
    }
  }
  return String(seconds);
}

/**
 * The labels of number ticks: as many digits as the step between them
 * needs (not the format's own), compact from 1,000 up (1K, 2K), in the
 * axis's format.
 */
export function tickFormatter(format: string | null | undefined, ticks: number[], locale?: string): (value: number) => string {
  format = parseFormat(format).name;
  const step = ticks.length > 1 ? Math.abs(ticks[1]! - ticks[0]!) : 1;
  const digits = Math.max(0, -Math.floor(Math.log10(step) + 1e-9));
  const max = Math.max(...ticks.map(Math.abs), 0);
  if (format === "percent") return formatter("percent", locale, Math.max(0, digits - 2));
  if (format && format.startsWith("currency:")) {
    if (max >= 1000) {
      const currency = format.slice(9);
      return (v) => numberFormat(locale, { style: "currency", currency, notation: "compact", maximumFractionDigits: 1 }).format(v);
    }
    return formatter(format, locale, digits);
  }
  if (format === "bytes" || format === "duration") return formatter(format, locale);
  if (max >= 1000 && format !== "integer" && format !== "number") {
    return (v) => numberFormat(locale, { notation: "compact", maximumFractionDigits: compactDigits(step, max) }).format(v);
  }
  return (v) => numberFormat(locale, { maximumFractionDigits: digits, minimumFractionDigits: digits }).format(v);
}

// The digits of compact ticks: 1.5K needs one, 1K, 2K none.
function compactDigits(step: number, max: number): number {
  const scale = Math.pow(1000, Math.floor(Math.log10(max) / 3));
  const scaled = step / scale;
  return scaled >= 1 ? 0 : Math.min(2, Math.ceil(-Math.log10(scaled)));
}

/**
 * The labels of time ticks: each with the parts that its unit needs, and
 * the larger part where it changes (the year at January, the day at
 * midnight).
 */
export function timeTickFormatter(unit: TimeUnit, locale?: string): (value: number, index: number, ticks: number[]) => string {
  return (value, index, ticks) => {
    const date = new Date(value);
    const prev = index > 0 ? new Date(ticks[index - 1]!) : null;
    switch (unit) {
      case "year":
        return dateFormat(locale, { year: "numeric" }).format(date);
      case "quarter":
      case "month":
        if (!prev || prev.getUTCFullYear() !== date.getUTCFullYear()) {
          return dateFormat(locale, { month: "short", year: "numeric" }).format(date);
        }
        return dateFormat(locale, { month: "short" }).format(date);
      case "week":
      case "day":
        if (!prev || prev.getUTCMonth() !== date.getUTCMonth() || prev.getUTCFullYear() !== date.getUTCFullYear()) {
          return dateFormat(locale, { day: "numeric", month: "short" }).format(date);
        }
        return dateFormat(locale, { day: "numeric" }).format(date);
      case "hour":
      case "minute":
        if (!prev || Math.floor(prev.getTime() / 86400000) !== Math.floor(value / 86400000)) {
          return dateFormat(locale, { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" }).format(date);
        }
        return dateFormat(locale, { hour: "numeric", minute: "2-digit" }).format(date);
      default:
        return dateFormat(locale, { hour: "numeric", minute: "2-digit", second: "2-digit" }).format(date);
    }
  };
}

/** A time written in full, by the unit of its data: "15 March 2027", "March 2027". */
export function formatTime(value: number, unit: string | undefined, locale?: string): string {
  const date = new Date(value);
  switch (unit) {
    case "year":
      return dateFormat(locale, { year: "numeric" }).format(date);
    case "quarter": {
      const q = Math.floor(date.getUTCMonth() / 3) + 1;
      return `Q${q} ${date.getUTCFullYear()}`;
    }
    case "month":
      return dateFormat(locale, { month: "long", year: "numeric" }).format(date);
    case "week":
    case "day":
      return dateFormat(locale, { day: "numeric", month: "short", year: "numeric" }).format(date);
    default:
      return dateFormat(locale, { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit" }).format(date);
  }
}
