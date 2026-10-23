import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { lookup, type FudeMap } from "../src/maps";

const world = JSON.parse(readFileSync(new URL("../maps/world.json", import.meta.url), "utf8")) as FudeMap;
const states = JSON.parse(readFileSync(new URL("../maps/us-states.json", import.meta.url), "utf8")) as FudeMap;

const id = (map: FudeMap, value: unknown) => {
  const i = lookup(map).find(value);
  return i === undefined ? undefined : map.regions[i]!.id;
};

test("finds a country by its codes, in any case", () => {
  for (const code of ["PRT", "pt", "620", " Portugal "]) assert.equal(id(world, code), "PRT", code);
});

test("finds a country by its other names", () => {
  assert.equal(id(world, "Bosnia and Herzegovina"), "BIH");
  assert.equal(id(world, "United States"), "USA");
  assert.equal(id(world, "Russian Federation"), "RUS");
  assert.equal(id(world, "Kosovo"), "XKX");
});

test("a name that two countries have is the one whose own name it is", () => {
  assert.equal(id(world, "Congo"), "COG");
});

test("finds a state by its postal code, its FIPS code and its name", () => {
  for (const code of ["CA", "06", "US-CA", "California"]) assert.equal(id(states, code), "CA", code);
});

test("finds nothing for what is not on the map", () => {
  assert.equal(id(world, "Atlantis"), undefined);
  assert.equal(id(world, null), undefined);
});
