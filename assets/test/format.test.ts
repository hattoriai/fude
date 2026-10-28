import { test } from "node:test";
import assert from "node:assert/strict";
import { formatter, parseFormat, tickFormatter } from "../src/format";

test("a format of the wire carries its digits after a colon", () => {
  assert.deepEqual(parseFormat("number:0"), { name: "number", digits: 0, suffix: null });
  assert.deepEqual(parseFormat("currency:EUR:2"), { name: "currency:EUR", digits: 2, suffix: null });
  assert.deepEqual(parseFormat("currency:EUR"), { name: "currency:EUR", digits: undefined, suffix: null });
  assert.deepEqual(parseFormat(":1"), { name: null, digits: 1, suffix: null });
  assert.deepEqual(parseFormat(null), { name: null, digits: undefined, suffix: null });
});

test("a format of the wire carries its suffix after a bar", () => {
  assert.deepEqual(parseFormat("number:1|×"), { name: "number", digits: 1, suffix: "×" });
  assert.deepEqual(parseFormat("|×"), { name: null, digits: undefined, suffix: "×" });
  assert.deepEqual(parseFormat("decimal_bytes| a|b"), { name: "decimal_bytes", digits: undefined, suffix: " a|b" });
});

test("a suffix follows every value, and every tick", () => {
  assert.equal(formatter("number:1|×", "en")(24.1641), "24.2×");
  assert.equal(formatter("|×", "en")(2.5), "2.5×");
  assert.equal(formatter("currency:EUR:2| a month", "en")(12), "€12.00 a month");
  assert.deepEqual([0, 50, 100].map(tickFormatter("number|%", [0, 50, 100], "en")), ["0%", "50%", "100%"]);
});

test("bytes count in 1,024s, decimal bytes in 1,000s, with the format's digits", () => {
  assert.equal(formatter("bytes", "en")(1024 * 1024), "1 MB");
  assert.equal(formatter("decimal_bytes", "en")(618.6e6), "618.6 MB");
  assert.equal(formatter("decimal_bytes:2|/s", "en")(4.65e9), "4.65 GB/s");
  const ticks = [1e7, 1e8, 1e9, 1e10];
  assert.deepEqual(ticks.map(tickFormatter("decimal_bytes:2|/s", ticks, "en")), ["10 MB/s", "100 MB/s", "1 GB/s", "10 GB/s"]);
});

test("digits are exactly the decimals of a number, a compact, a percent and a currency", () => {
  assert.equal(formatter("number:0", "en")(6893913.6), "6,893,914");
  assert.equal(formatter("number:2", "en")(6893913.6), "6,893,913.60");
  assert.equal(formatter("compact:2", "en")(6893913.6), "6.89M");
  assert.equal(formatter("compact:0", "en")(6893913.6), "7M");
  assert.equal(formatter("percent:0", "en")(0.256), "26%");
  assert.equal(formatter("percent:2", "en")(0.25), "25.00%");
  assert.equal(formatter("currency:EUR:2", "en")(1234.5), "€1,234.50");
  assert.equal(formatter(":0", "en")(12.75), "13");
});

test("a number with no digits keeps its decimals up to 2", () => {
  assert.equal(formatter("number", "en")(6893913.6), "6,893,913.6");
  assert.equal(formatter("number", "en")(12.345), "12.35");
  assert.equal(formatter("number", "en")(0.125), "0.13");
  assert.equal(formatter("number", "en")(42), "42");
});

test("without digits, the formats write as before", () => {
  assert.equal(formatter("compact", "en")(6893913.6), "6.9M");
  assert.equal(formatter("percent", "en")(0.256), "25.6%");
  assert.equal(formatter("currency:EUR", "en")(1234.5), "€1,235");
  assert.equal(formatter(null, "en")(0.1234), "0.123");
});

test("ticks take the digits of their step, not the channel's", () => {
  const ticks = [0, 0.5, 1, 1.5];
  const tick = tickFormatter("number:3", ticks, "en");
  assert.deepEqual(ticks.map(tick), ["0.0", "0.5", "1.0", "1.5"]);
  assert.deepEqual([0, 0.1, 0.2].map(tickFormatter("percent:3", [0, 0.1, 0.2], "en")), ["0%", "10%", "20%"]);
});
