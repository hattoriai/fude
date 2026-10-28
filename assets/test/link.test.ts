import { test } from "node:test";
import assert from "node:assert/strict";
import { matching, publish, subscribe, type LinkValue } from "../src/link";

const day = (iso: string): LinkValue => ({ time: Date.parse(iso), unit: "day" });
const month = (iso: string): LinkValue => ({ time: Date.parse(iso), unit: "month" });

test("a time matches within the coarser unit: a day is its month on a chart of months", () => {
  const months = [month("2026-02-01"), month("2026-03-01"), month("2026-04-01")];
  assert.deepEqual(matching(day("2026-03-14"), months), [1]);
});

test("a month on a chart of days is its nearest day: the first", () => {
  const days = [day("2026-02-28"), day("2026-03-01"), day("2026-03-02"), day("2026-04-01")];
  assert.deepEqual(matching(month("2026-03-01"), days), [1]);
});

test("every place at the nearest: the bars of a stack", () => {
  const bars = [month("2026-03-01"), month("2026-03-01"), month("2026-04-01")];
  assert.deepEqual(matching(month("2026-03-01"), bars), [0, 1]);
});

test("a chart that does not have the value shows nothing", () => {
  assert.deepEqual(matching(month("2025-06-01"), [month("2026-01-01"), month("2026-02-01")]), []);
  assert.deepEqual(matching({ value: "West" }, [{ value: "North" }, null]), []);
});

test("a category matches by its name, a number by itself", () => {
  assert.deepEqual(matching({ value: "North" }, [{ value: "South" }, { value: "North" }]), [1]);
  assert.deepEqual(matching({ value: 3 }, [{ value: 2 }, { value: "3" }]), [1]);
});

test("times of no unit match exactly; a time never matches a name", () => {
  const at = { time: 1000 };
  assert.deepEqual(matching(at, [{ time: 999 }, { time: 1000 }]), [1]);
  assert.deepEqual(matching(at, [{ value: 1000 }]), []);
});

test("messages go to every listener on the document, until it stops", () => {
  const target = new EventTarget();
  (globalThis as { document?: EventTarget }).document = target;
  const seen: unknown[] = [];
  const stop = subscribe((message) => seen.push(message.at));
  publish({ link: "months", from: null, at: { value: "North" } });
  stop();
  publish({ link: "months", from: null, at: null });
  assert.deepEqual(seen, [{ value: "North" }]);
});
