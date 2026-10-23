// The rules of a chart's scales that the browser and the server both
// apply: nice domains, the ticks of a number axis and of a time axis, the
// bins of a histogram and the units of a time. The same as Fude.Rules on
// the server, word for word: a change here is a change there. Both test
// suites run the cases of test/fixtures/rules.json.
//
// Times are milliseconds since 1970 in UTC.

const e10 = Math.sqrt(50);
const e5 = Math.sqrt(10);
const e2 = Math.sqrt(2);

const SECOND = 1000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const WEEK = 7 * DAY;
const MONTH = 30 * DAY;
const YEAR = 365 * DAY;

export type TimeUnit = "millisecond" | "second" | "minute" | "hour" | "day" | "week" | "month" | "quarter" | "year";

function factor(error: number): number {
  return error >= e10 ? 10 : error >= e5 ? 5 : error >= e2 ? 2 : 1;
}

/**
 * The step between ticks of about `count` ticks from `start` to `stop`: a
 * positive number, or, for a step under 1, minus its inverse (-10 is a
 * step of 0.1), which keeps it exact.
 */
export function increment(start: number, stop: number, count: number): number {
  const step = (stop - start) / Math.max(0, count);
  const power = Math.floor(Math.log10(step));
  const error = step / Math.pow(10, power);
  const f = factor(error);
  return power >= 0 ? f * Math.pow(10, power) : -Math.pow(10, -power) / f;
}

function spec(start: number, stop: number, count: number): [number, number, number] {
  const step = (stop - start) / Math.max(0, count);
  const power = Math.floor(Math.log10(step));
  const error = step / Math.pow(10, power);
  const f = factor(error);
  let i1: number;
  let i2: number;
  let inc: number;
  if (power < 0) {
    inc = Math.pow(10, -power) / f;
    i1 = Math.round(start * inc);
    i2 = Math.round(stop * inc);
    if (i1 / inc < start) ++i1;
    if (i2 / inc > stop) --i2;
    inc = -inc;
  } else {
    inc = Math.pow(10, power) * f;
    i1 = Math.round(start / inc);
    i2 = Math.round(stop / inc);
    if (i1 * inc < start) ++i1;
    if (i2 * inc > stop) --i2;
  }
  if (i2 < i1 && 0.5 <= count && count < 2) return spec(start, stop, count * 2);
  return [i1, i2, inc];
}

/** About `count` ticks between `start` and `stop`, at round numbers, in order. */
export function ticks(start: number, stop: number, count: number): number[] {
  if (count <= 0) return [];
  if (start === stop) return [start];
  if (stop < start) return ticks(stop, start, count).reverse();
  const [i1, i2, inc] = spec(start, stop, count);
  if (i2 < i1) return [];
  const out: number[] = [];
  for (let i = i1; i <= i2; i++) out.push(inc < 0 ? i / -inc : i * inc);
  return out;
}

/**
 * The domain from `start` to `stop` widened to round numbers, so that its
 * ends are ticks of about `count` ticks. A domain of one value widens
 * around it.
 */
export function nice(start: number, stop: number, count = 10): [number, number] {
  if (start === stop) {
    if (start === 0) return [0, 1];
    const pad = Math.abs(start) / 10;
    return nice(start - pad, start + pad, count);
  }
  if (start > stop) {
    const [a, b] = nice(stop, start, count);
    return [b, a];
  }
  let prestep: number | undefined;
  for (let left = 10; left > 0; left--) {
    const step = increment(start, stop, count);
    if (step === prestep) return [start, stop];
    if (step > 0) {
      start = Math.floor(start / step) * step;
      stop = Math.ceil(stop / step) * step;
    } else if (step < 0) {
      start = Math.ceil(start * step) / step;
      stop = Math.floor(stop * step) / step;
    } else {
      return [start, stop];
    }
    prestep = step;
  }
  return [start, stop];
}

/**
 * The bins of the numbers from `min` to `max`, about `count` of them, at
 * round numbers: [start, step, n], the first bin [start, start + step) and
 * the last one closed, so that `max` is in it.
 */
export function bins(min: number, max: number, count: number): [number, number, number] {
  if (min === max) return [min, 1, 1];
  const inc = increment(min, max, count);
  const step = inc < 0 ? 1 / -inc : inc;
  const start = Math.floor(min / step) * step;
  let n = Math.max(1, Math.ceil((max - start) / step));
  if (start + n * step < max) n += 1;
  return [start, step, n];
}

/** The bin of a value among the bins [start, step, n]: from 0 to n - 1. */
export function bin([start, step, n]: [number, number, number], value: number): number {
  return Math.min(n - 1, Math.max(0, Math.floor((value - start) / step)));
}

function floorDiv(a: number, b: number): number {
  return Math.floor(a / b);
}

function mod(a: number, b: number): number {
  return ((a % b) + b) % b;
}

/** The day of a time in the proleptic Gregorian calendar (Hinnant). */
export function civil(time: number): [number, number, number] {
  const z = floorDiv(time, DAY) + 719468;
  const era = floorDiv(z, 146097);
  const doe = z - era * 146097;
  const yoe = Math.trunc((doe - Math.trunc(doe / 1460) + Math.trunc(doe / 36524) - Math.trunc(doe / 146096)) / 365);
  const y = yoe + era * 400;
  const doy = doe - (365 * yoe + Math.trunc(yoe / 4) - Math.trunc(yoe / 100));
  const mp = Math.trunc((5 * doy + 2) / 153);
  const d = doy - Math.trunc((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  return [m <= 2 ? y + 1 : y, m, d];
}

/** The days since 1970 of a day of the proleptic Gregorian calendar (Hinnant). */
export function days(year: number, month: number, day: number): number {
  const y = month <= 2 ? year - 1 : year;
  const era = floorDiv(y, 400);
  const yoe = y - era * 400;
  const mp = month > 2 ? month - 3 : month + 9;
  const doy = Math.trunc((153 * mp + 2) / 5) + day - 1;
  const doe = yoe * 365 + Math.trunc(yoe / 4) - Math.trunc(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}

/** The start of a time's unit; a week starts on Monday. */
export function floor(time: number, unit: TimeUnit): number {
  switch (unit) {
    case "millisecond":
      return time;
    case "second":
      return floorDiv(time, SECOND) * SECOND;
    case "minute":
      return floorDiv(time, MINUTE) * MINUTE;
    case "hour":
      return floorDiv(time, HOUR) * HOUR;
    case "day":
      return floorDiv(time, DAY) * DAY;
    case "week": {
      const d = floorDiv(time, DAY);
      // 1970-01-01 was a Thursday, the fourth day from Monday.
      return (d - mod(d + 3, 7)) * DAY;
    }
    case "month": {
      const [y, m] = civil(time);
      return days(y, m, 1) * DAY;
    }
    case "quarter": {
      const [y, m] = civil(time);
      return days(y, m - ((m - 1) % 3), 1) * DAY;
    }
    case "year": {
      const [y] = civil(time);
      return days(y, 1, 1) * DAY;
    }
  }
}

/** The time `step` units after a time at the start of its unit. */
export function offset(time: number, unit: TimeUnit, step: number): number {
  switch (unit) {
    case "millisecond":
      return time + step;
    case "second":
      return time + step * SECOND;
    case "minute":
      return time + step * MINUTE;
    case "hour":
      return time + step * HOUR;
    case "day":
      return time + step * DAY;
    case "week":
      return time + step * WEEK;
    case "month": {
      const [y, m] = civil(time);
      const months = y * 12 + (m - 1) + step;
      return days(floorDiv(months, 12), mod(months, 12) + 1, 1) * DAY;
    }
    case "quarter":
      return offset(time, "month", step * 3);
    case "year":
      return offset(time, "month", step * 12);
  }
}

const INTERVALS: [TimeUnit, number, number][] = [
  ["second", 1, SECOND],
  ["second", 5, 5 * SECOND],
  ["second", 15, 15 * SECOND],
  ["second", 30, 30 * SECOND],
  ["minute", 1, MINUTE],
  ["minute", 5, 5 * MINUTE],
  ["minute", 15, 15 * MINUTE],
  ["minute", 30, 30 * MINUTE],
  ["hour", 1, HOUR],
  ["hour", 3, 3 * HOUR],
  ["hour", 6, 6 * HOUR],
  ["hour", 12, 12 * HOUR],
  ["day", 1, DAY],
  ["day", 2, 2 * DAY],
  ["week", 1, WEEK],
  ["month", 1, MONTH],
  ["month", 3, 3 * MONTH],
  ["year", 1, YEAR],
];

/** The unit and the step of about `count` ticks of a time axis. */
export function timeInterval(start: number, stop: number, count: number): [TimeUnit, number] {
  const target = Math.abs(stop - start) / count;
  const i = INTERVALS.findIndex(([, , length]) => length > target);
  if (i === -1) {
    const step = increment(start / YEAR, stop / YEAR, count);
    return ["year", Math.max(1, Math.trunc(step < 0 ? 1 : step))];
  }
  if (i === 0) return ["millisecond", Math.max(1, Math.trunc(Math.max(increment(start, stop, count), 1)))];
  const [unitA, stepA, lengthA] = INTERVALS[i - 1]!;
  const [unitB, stepB, lengthB] = INTERVALS[i]!;
  return target / lengthA < lengthB / target ? [unitA, stepA] : [unitB, stepB];
}

// The field that a step counts: the seconds of the minute, the day of the
// month from 0, the month from 0, the year.
function field(time: number, unit: TimeUnit): number {
  switch (unit) {
    case "second":
      return mod(floorDiv(time, SECOND), 60);
    case "minute":
      return mod(floorDiv(time, MINUTE), 60);
    case "hour":
      return mod(floorDiv(time, HOUR), 24);
    case "day":
      return civil(time)[2] - 1;
    case "month":
      return civil(time)[1] - 1;
    case "quarter":
      return Math.trunc((civil(time)[1] - 1) / 3);
    case "year":
      return civil(time)[0];
    default:
      return 0;
  }
}

/**
 * About `count` ticks of a time axis from `start` to `stop`, at the
 * starts of round units, with the unit that says how to write them.
 */
export function timeTicks(start: number, stop: number, count: number): { unit: TimeUnit; step: number; ticks: number[] } {
  if (stop < start) {
    const out = timeTicks(stop, start, count);
    return { ...out, ticks: out.ticks.reverse() };
  }
  const [unit, step] = timeInterval(start, stop, count);
  const out: number[] = [];
  if (unit === "millisecond") {
    for (let t = Math.ceil(start / step) * step; t <= stop; t += step) out.push(t);
    return { unit, step, ticks: out };
  }
  let t = floor(start, unit);
  if (t < start) t = offset(t, unit, 1);
  for (; t <= stop; t = offset(t, unit, 1)) {
    if (field(t, unit) % step === 0) out.push(t);
  }
  return { unit, step, ticks: out };
}
