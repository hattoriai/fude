import { test } from "node:test";
import assert from "node:assert/strict";
import { dataValue, datumOf, fraction, matches, same, timeText } from "../src/places";
import type { Scale } from "../src/wire";

const regions: Scale = { type: "band", domain: ["North", "South"] };
const months: Scale = { type: "band", domain: [Date.UTC(2026, 0, 1), Date.UTC(2026, 1, 1)], time: "month" };
const time: Scale = { type: "time", domain: [0, 1], unit: "hour" };
const amount: Scale = { type: "linear", domain: [0, 100] };

test("a column's value in the data's terms: a name, a day, a time, a number", () => {
  assert.equal(dataValue(regions, 1), "South");
  assert.equal(dataValue(months, 1), "2026-02-01");
  assert.equal(dataValue(time, Date.UTC(2026, 2, 1, 9, 30)), "2026-03-01T09:30:00Z");
  assert.equal(dataValue(amount, 42.5), 42.5);
  assert.equal(dataValue(regions, 7), null);
  assert.equal(dataValue(amount, null), null);
});

test("a place's value is the data's: the same name, number or time", () => {
  assert.ok(same("South", "South"));
  assert.ok(same(42, 42));
  assert.ok(same("42", 42));
  assert.ok(same("2026-02-01", "2026-02-01T00:00:00Z"));
  assert.ok(same(Date.UTC(2026, 1, 1), "2026-02-01"));
  assert.ok(!same("North", "South"));
  assert.ok(!same({}, "South"));
});

test("a datum is the one a place names when each of its values is the same", () => {
  const datum = { x: "North", color: "Online" };
  assert.ok(!matches({ x: "North" }, datum));
  assert.ok(matches({ x: "North" }, { x: "North" }));
  assert.ok(matches({ x: "North", color: "Online" }, datum));
  assert.ok(!matches({ x: "North", color: "Retail" }, datum));
  assert.ok(!matches({ region: "BRA" }, datum));
  assert.ok(!matches({}, datum));
  assert.ok(!matches({ size: 3 }, datum));
});

test("the datum of a place, and fractions within a box", () => {
  assert.deepEqual(datumOf({ datum: { x: "North" }, x: 0.5 }), { x: "North" });
  assert.equal(datumOf({ cell: [1, "a"] }), null);
  assert.equal(datumOf(null), null);
  assert.equal(fraction(15, 10, 20), 0.25);
  assert.equal(fraction(50, 10, 20), 1);
  assert.equal(fraction(5, 10, 0), 0.5);
  assert.equal(timeText(Date.UTC(2026, 4, 1), "month"), "2026-05-01");
});
