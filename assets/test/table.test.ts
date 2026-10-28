import { test } from "node:test";
import assert from "node:assert/strict";
import { tableOf } from "../src/table";
import type { Config } from "../src/wire";

const base = { v: 1, id: "t", kind: "bar" } as const;

test("a table is the first layer's columns by their titles, a category by its name", () => {
  const config: Config = {
    ...base,
    scales: { x: { type: "band", domain: ["North", "South"], title: "Region" }, y: { type: "linear", domain: [0, 200], title: "Revenue" } },
    layers: [{ mark: "bar", n: 2, columns: { x: [0, 1], y: [120, 60.5] }, horizontal: false, stack: null, options: {}, tooltip: [] }],
  };
  assert.deepEqual(tableOf(config), { heads: ["Region", "Revenue"], rows: [["North", "120"], ["South", "60.5"]] });
});

test("a time is a date for a unit of a day or more, else a time to the second", () => {
  const march = Date.parse("2026-03-01");
  const config: Config = {
    ...base,
    scales: { x: { type: "time", domain: [march, march], unit: "month", title: "Month" }, color: { type: "ordinal", domain: ["Online"], title: "Channel" } },
    layers: [{ mark: "line", n: 1, columns: { x: [march], y: [5], color: [0] }, horizontal: false, stack: null, options: {}, tooltip: [] }],
  };
  assert.deepEqual(tableOf(config).rows, [["2026-03-01", "5", "Online"]]);
  config.scales!.x!.unit = "hour";
  assert.equal(tableOf(config).rows[0]![0], "2026-03-01T00:00:00Z");
  assert.deepEqual(tableOf(config).heads, ["Month", "y", "Channel"]);
});

test("a chart with no layer has no table", () => {
  assert.deepEqual(tableOf({ ...base }), { heads: [], rows: [] });
});
