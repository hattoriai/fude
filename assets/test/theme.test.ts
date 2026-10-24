import { test } from "node:test";
import assert from "node:assert/strict";
import { accentRamp, rgb } from "../src/theme";

const light = (color: string) => {
  const [r, g, b] = rgb(color.startsWith("rgb") ? hex(color) : color);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const hex = (color: string) =>
  "#" + color.match(/\d+/g)!.map((n) => Number(n).toString(16).padStart(2, "0")).join("");

test("the ramp of the accent goes from the page, through the accent, to the text", () => {
  // Snow: indigo on near-white, ink text.
  const steps = accentRamp("#285cc2", "#fdfdfe", "#1c1d21");
  assert.equal(steps.length, 7);
  assert.equal(hex(steps[3]!), "#285cc2");
  // Each step darker than the one before: light to dark on a light page.
  for (let i = 1; i < steps.length; i++) assert.ok(light(steps[i]!) < light(steps[i - 1]!), `step ${i}`);
});

test("on a dark page the ramp goes from dark to light, so low values fade into the page", () => {
  // Smoke: jade on smoky grey, paper text.
  const steps = accentRamp("#37be95", "#2a2b2e", "#ebe7df");
  for (let i = 1; i < steps.length; i++) assert.ok(light(steps[i]!) > light(steps[i - 1]!), `step ${i}`);
});
