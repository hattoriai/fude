import { test } from "node:test";
import assert from "node:assert/strict";
import fixture from "../../test/fixtures/wire.json";
import { unpack, unpackColumn, type Config, type PackedColumn } from "../src/wire";

// The columns of Fude.Wire's tests, packed by the server: each unpacks here
// to exactly its values, so the browser draws the numbers the server had.

type Value = number | string | boolean | null;
const cases = fixture.columns as { name: string; values: Value[]; packed: Value[] | PackedColumn }[];

test("each packed column of the fixture unpacks to its values", () => {
  assert.ok(cases.some((c) => !Array.isArray(c.packed)), "the fixture has packed columns");
  for (const { name, values, packed } of cases) {
    const got = unpackColumn(packed);
    assert.equal(got.length, values.length, name);
    // Object.is: the very same number, not one close to it.
    values.forEach((want, i) => assert.ok(Object.is(got[i], want), `${name}, value ${i}: got ${got[i]}, want ${want}`));
  }
});

test("a plain column is itself", () => {
  const column = [1, null, 3];
  assert.equal(unpackColumn(column), column);
});

test("a packed column", () => {
  assert.deepEqual(unpackColumn({ from: 1672531200000, step: 86400000, deltas: [0, 1, 1] }), [1672531200000, 1672617600000, 1672704000000]);
  assert.deepEqual(unpackColumn({ from: 150, step: 25, decimals: 2, deltas: [0, 1, 1] }), [1.5, 1.75, 2]);
  assert.deepEqual(unpackColumn({ from: 10, step: 5, deltas: [null, 0, null, 2, -1, null] }), [null, 10, null, 20, 15, null]);
  assert.deepEqual(unpackColumn({ from: 0, step: 1, deltas: [] }), []);
});

test("refuses decimals it does not know", () => {
  assert.throws(() => unpackColumn({ from: 1, step: 1, decimals: 9, deltas: [0] }), /9 decimals/);
});

test("unpack: the layers' columns and tooltips, nothing else", () => {
  const days: PackedColumn = { from: 1672531200000, step: 86400000, deltas: [0, 1, 1] };
  const config = {
    v: 1,
    id: "c",
    kind: "line",
    scales: { x: { type: "time", domain: [1672531200000, 1672704000000] } },
    layers: [
      {
        mark: "line",
        n: 3,
        columns: { x: days, y: [1, 2, 3] },
        horizontal: false,
        stack: null,
        options: {},
        tooltip: [{ title: "Day", format: null, values: days }, { title: "Note", format: null, values: ["a", "b", "c"] }, { title: "None", format: null }],
      },
    ],
  } as unknown as Config;

  const got = unpack(config);
  const layer = got.layers![0]!;
  assert.deepEqual(layer.columns.x, [1672531200000, 1672617600000, 1672704000000]);
  assert.deepEqual(layer.columns.y, [1, 2, 3]);
  assert.deepEqual(layer.tooltip[0]!.values, [1672531200000, 1672617600000, 1672704000000]);
  assert.deepEqual(layer.tooltip[1]!.values, ["a", "b", "c"]);
  assert.equal(layer.tooltip[2]!.values, undefined);
  assert.equal(got.scales, config.scales);
  assert.equal(layer.n, 3);
});

test("unpack: a config without layers is itself", () => {
  const config = { v: 1, id: "n", kind: "number", single: { value: 3 } } as unknown as Config;
  assert.equal(unpack(config), config);
});
