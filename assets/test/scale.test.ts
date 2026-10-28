import { test } from "node:test";
import assert from "node:assert/strict";
import { position } from "../src/scale";

test("a log scale widens to whole powers of ten", () => {
  const log = position({ type: "log", domain: [25.6e6, 13.4e9], nice: true }, [0, 400]);
  assert.deepEqual(log.domain, [1e7, 1e11]);
  assert.deepEqual(log.ticks, [1e7, 1e8, 1e9, 1e10, 1e11]);
});

test("a log scale of its own domain keeps it, with the powers of ten inside it", () => {
  const log = position({ type: "log", domain: [1e7, 2.5e10], nice: false }, [0, 400]);
  assert.ok(Math.abs(log.domain[1] - 2.5e10) < 1);
  assert.deepEqual(log.ticks, [1e7, 1e8, 1e9, 1e10]);
  assert.equal(log.at(1e7), 0);
  assert.ok(Math.abs(log.at(2.5e10) - 400) < 1e-6);
});

test("a log scale of one value widens to its powers of ten, nice or not", () => {
  const log = position({ type: "log", domain: [500, 500], nice: false }, [0, 400]);
  assert.deepEqual(log.domain, [100, 1000]);
});
