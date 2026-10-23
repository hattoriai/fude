import { test } from "node:test";
import assert from "node:assert/strict";
import { merge } from "../src/chart";
import type { Config } from "../src/wire";

const base: Config = {
  v: 1,
  id: "load",
  kind: "line",
  scales: {
    x: { type: "time", domain: [0, 2000] },
    y: { type: "linear", domain: [1, 3], nice: true },
    color: { type: "ordinal", domain: ["a"] },
  },
  layers: [
    { mark: "line", n: 3, columns: { x: [0, 1000, 2000], y: [1, 2, 3], color: [0, 0, 0] }, horizontal: false, stack: null, options: {}, tooltip: [] },
  ],
};

const more: Config = {
  v: 1,
  id: "load",
  kind: "line",
  scales: { x: { type: "time", domain: [3000, 3000] }, y: { type: "linear", domain: [9, 9] }, color: { type: "ordinal", domain: ["b"] } },
  layers: [{ mark: "line", n: 1, columns: { x: [3000], y: [9], color: [0] }, horizontal: false, stack: null, options: {}, tooltip: [] }],
};

test("adds the new rows, a new category at the end of its scale", () => {
  const merged = merge(base, more, null);
  const layer = merged.layers![0]!;
  assert.deepEqual(layer.columns.x, [0, 1000, 2000, 3000]);
  assert.deepEqual(layer.columns.color, [0, 0, 0, 1]);
  assert.deepEqual(merged.scales!.color!.domain, ["a", "b"]);
  assert.equal(layer.n, 4);
});

test("keeps the last rows, and fits the scales to them", () => {
  const merged = merge(base, more, 2);
  assert.deepEqual(merged.layers![0]!.columns.x, [2000, 3000]);
  assert.deepEqual(merged.scales!.x!.domain, [2000, 3000]);
  assert.deepEqual(merged.scales!.y!.domain, [3, 9]);
});

test("leaves the chart it merges into as it was", () => {
  merge(base, more, 2);
  assert.deepEqual(base.layers![0]!.columns.x, [0, 1000, 2000]);
  assert.deepEqual(base.scales!.color!.domain, ["a"]);
});

test("the fields of the tooltip follow the rows that stay", () => {
  const tip = (values: (number | string | null)[]) => [{ title: "Note", format: null, values }];
  const a: Config = { ...base, layers: [{ ...base.layers![0]!, tooltip: tip(["x", "y", "z"]) }] };
  const b: Config = { ...more, layers: [{ ...more.layers![0]!, tooltip: tip(["w"]) }] };
  assert.deepEqual(merge(a, b, null).layers![0]!.tooltip[0]!.values, ["x", "y", "z", "w"]);
  assert.deepEqual(merge(a, b, 2).layers![0]!.tooltip[0]!.values, ["z", "w"]);
});
