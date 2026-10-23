import { test } from "node:test";
import assert from "node:assert/strict";
import fixture from "../../test/fixtures/rules.json";
import { bins, floor, increment, nice, offset, ticks, timeTicks, type TimeUnit } from "../src/rules";

// The same cases as Fude.Rules's tests: the browser and the server agree.

test("increment", () => {
  for (const { args, expected } of fixture.increment) {
    const [a, b, c] = args as [number, number, number];
    assert.equal(increment(a, b, c), expected, `increment(${args})`);
  }
});

test("ticks", () => {
  for (const { args, expected } of fixture.ticks) {
    const [a, b, c] = args as [number, number, number];
    assert.deepEqual(ticks(a, b, c), expected, `ticks(${args})`);
  }
});

test("nice", () => {
  for (const { args, expected } of fixture.nice) {
    const [a, b, c] = args as [number, number, number];
    assert.deepEqual(nice(a, b, c), expected, `nice(${args})`);
  }
});

test("bins", () => {
  for (const { args, expected } of fixture.bins) {
    const [a, b, c] = args as [number, number, number];
    assert.deepEqual(bins(a, b, c), expected, `bins(${args})`);
  }
});

test("floor", () => {
  for (const { args, expected } of fixture.floor) {
    const [time, unit] = args as [number, TimeUnit];
    assert.equal(floor(time, unit), expected, `floor(${args})`);
  }
});

test("offset", () => {
  for (const { args, expected } of fixture.offset) {
    const [time, unit, step] = args as [number, TimeUnit, number];
    assert.equal(offset(time, unit, step), expected, `offset(${args})`);
  }
});

test("timeTicks", () => {
  for (const { args, expected } of fixture.timeTicks) {
    const [a, b, c] = args as [number, number, number];
    assert.deepEqual(timeTicks(a, b, c), expected, `timeTicks(${args})`);
  }
});
