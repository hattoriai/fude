import { test } from "node:test";
import assert from "node:assert/strict";
import { numberRangeLabel, sentValue, snapBins, snapNumbers, snapTimes, timeRangeLabel, timeUnit } from "../src/brush";

const ms = (iso: string) => Date.parse(iso);

test("a range of times snaps to the first and the last unit it touches, in order", () => {
  assert.deepEqual(snapTimes(ms("2026-05-20"), ms("2026-03-14"), "month"), [ms("2026-03-01"), ms("2026-05-01")]);
  assert.deepEqual(snapTimes(ms("2026-03-14T10:20:00Z"), ms("2026-03-16T23:00:00Z"), "day"), [ms("2026-03-14"), ms("2026-03-16")]);
});

test("a time with no unit keeps its millisecond", () => {
  assert.deepEqual(snapTimes(1000.4, 20.6, null), [21, 1000]);
});

test("a histogram's range goes out to the edges of its bins", () => {
  assert.deepEqual(snapBins(23, 47, 0, 10), [20, 50]);
  assert.deepEqual(snapBins(47, 23, 5, 10), [15, 55]);
});

test("numbers round to a thousandth of the axis's span", () => {
  assert.deepEqual(snapNumbers(12.34567, 3.21987, 100), [3.2, 12.3]);
  assert.deepEqual(snapNumbers(1234.5, 5678.9, 10000), [1235, 5679]);
});

test("a range of months reads as the reader says it", () => {
  const label = timeRangeLabel(ms("2026-03-01"), ms("2026-05-01"), "month", "en-GB");
  assert.match(label, /^Mar\s?–\s?May 2026$/);
  assert.equal(timeRangeLabel(ms("2026-03-01"), ms("2026-03-01"), "month", "en-GB"), "Mar 2026");
  assert.match(timeRangeLabel(ms("2025-11-01"), ms("2026-02-01"), "month", "en-GB"), /Nov 2025\s?–\s?Feb 2026/);
});

test("quarters and years", () => {
  assert.equal(timeRangeLabel(ms("2026-01-01"), ms("2026-07-01"), "quarter"), "Q1–Q3 2026");
  assert.equal(timeRangeLabel(ms("2025-10-01"), ms("2026-01-01"), "quarter"), "Q4 2025–Q1 2026");
  assert.match(timeRangeLabel(ms("2024-01-01"), ms("2026-01-01"), "year", "en-GB"), /^2024\s?–\s?2026$/);
});

test("numbers read in the axis's format", () => {
  assert.equal(numberRangeLabel(1200, 3400, "number", "en"), "1,200–3,400");
  assert.equal(numberRangeLabel(2, 2, "number:1|×", "en"), "2.0×");
});

test("the server hears a time as a date for a unit of a day or more, else to the second; a number as itself", () => {
  assert.equal(sentValue(ms("2026-03-01"), true, "month"), "2026-03-01");
  assert.equal(sentValue(ms("2026-03-01T10:30:00Z"), true, "hour"), "2026-03-01T10:30:00Z");
  assert.equal(sentValue(ms("2026-03-01T10:30:00Z"), true, null), "2026-03-01T10:30:00Z");
  assert.equal(sentValue(12.5, false, null), 12.5);
});

test("a unit is one of the units of a time", () => {
  assert.equal(timeUnit("month"), "month");
  assert.equal(timeUnit(""), null);
  assert.equal(timeUnit("fortnight"), null);
});
