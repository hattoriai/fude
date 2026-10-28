import { test } from "node:test";
import assert from "node:assert/strict";
import { position, windowBand } from "../src/scale";

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

test("a window of a band's categories fills the range; the others are outside it", () => {
  const all = position({ type: "band", domain: ["a", "b", "c", "d", "e"] }, [0, 500], 80, 0);
  const window = windowBand([1, 3], [0, 300], 0);
  assert.equal(all.bandwidth, 100);
  assert.equal(window.bandwidth, 100);
  assert.equal(window.at(1), 0);
  assert.equal(window.at(3), 200);
  assert.ok(window.at(0) < 0 && window.at(4) >= 300);
  assert.deepEqual(window.ticks, [1, 2, 3]);
  assert.equal(window.index(150), 2);
});
