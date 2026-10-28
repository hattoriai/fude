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

test("a kind that names its columns: a timeline's task, start and end, as the server's table has them", () => {
  const day = 86_400_000;
  const start = Date.parse("2026-03-02");
  const config: Config = {
    ...base,
    kind: "timeline",
    scales: { y: { type: "band", domain: ["Design"], title: "Task" }, x: { type: "time", domain: [start, start + 7 * day], unit: "day", title: "Start" } },
    layers: [
      {
        mark: "bar",
        n: 1,
        columns: { y: [0], x: [7 * day], x0: [start], x1: [start + 7 * day] },
        horizontal: true,
        stack: "range",
        options: { table: [["y", "Task", "y"], ["x0", "Start", "x"], ["x1", "Finish", "x"], ["color", "Team", "color"]] },
        tooltip: [],
      },
    ],
  };
  // A named column the layer does not have (no color) is left out.
  assert.deepEqual(tableOf(config), { heads: ["Task", "Start", "Finish"], rows: [["Design", "2026-03-02", "2026-03-09"]] });
});

test("a map's table names each region, with its color and its shade", () => {
  const config: Config = {
    ...base,
    kind: "choropleth",
    scales: {
      region: { type: "ordinal", domain: ["CA", "TX"], title: "State" },
      color: { type: "ordinal", domain: ["Social", "Forward!"], title: "Leader" },
      shade: { type: "linear", domain: [3.1, 12.5], title: "Lead" },
    },
    layers: [{ mark: "region", n: 2, columns: { region: [0, 1], color: [0, 1], shade: [12.5, 3.1] }, horizontal: false, stack: null, options: {}, tooltip: [] }],
  };
  assert.deepEqual(tableOf(config), { heads: ["State", "Leader", "Lead"], rows: [["CA", "Social", "12.5"], ["TX", "Forward!", "3.1"]] });
});
