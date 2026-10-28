import { test } from "node:test";
import assert from "node:assert/strict";
import { squarify, squarifyGroups, type Tile } from "../src/treemap";

const box: Tile = { x: 10, y: 20, w: 600, h: 300 };
const area = (t: Tile) => t.w * t.h;
const overlap = (a: Tile, b: Tile) => Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
const inside = (t: Tile, b: Tile) => t.x >= b.x - 1e-6 && t.y >= b.y - 1e-6 && t.x + t.w <= b.x + b.w + 1e-6 && t.y + t.h <= b.y + b.h + 1e-6;

// Values made from a seed: the same on every run.
function values(n: number, seed: number): number[] {
  let s = seed;
  return Array.from({ length: n }, () => {
    s = (s * 1103515245 + 12345) % 2147483648;
    return 1 + (s % 1000);
  }).sort((a, b) => b - a);
}

test("each tile's area is its share of the box, in the box, over no other", () => {
  for (const [n, seed] of [[1, 1], [2, 2], [7, 3], [40, 4], [200, 5]] as const) {
    const vs = values(n, seed);
    const total = vs.reduce((a, b) => a + b, 0);
    const tiles = squarify(vs, box);
    assert.equal(tiles.length, n);
    tiles.forEach((tile, i) => {
      assert.ok(Math.abs(area(tile) - (vs[i]! / total) * area(box)) < 1e-6 * area(box), `tile ${i} of ${n}: its area`);
      assert.ok(inside(tile, box), `tile ${i} of ${n}: in the box`);
    });
    for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) assert.ok(overlap(tiles[i]!, tiles[j]!) < 1e-6, `tiles ${i} and ${j} of ${n}`);
    assert.ok(Math.abs(tiles.reduce((sum, t) => sum + area(t), 0) - area(box)) < 1e-6 * area(box), "the tiles fill the box");
  }
});

test("equal values are near square", () => {
  const tiles = squarify([1, 1, 1, 1], { x: 0, y: 0, w: 200, h: 200 });
  for (const tile of tiles) assert.ok(Math.max(tile.w / tile.h, tile.h / tile.w) < 1.01);
});

test("nothing to lay out: tiles of no size", () => {
  assert.deepEqual(squarify([], box), []);
  assert.ok(squarify([0, 0], box).every((t) => area(t) === 0));
  assert.ok(squarify([3, 2], { x: 0, y: 0, w: 0, h: 50 }).every((t) => area(t) === 0));
});

test("tiles of a group stay together, in their group's share of the box", () => {
  const vs = [50, 40, 30, 20, 10, 5];
  const groups = [0, 1, 0, 1, 2, 0];
  const tiles = squarifyGroups(vs, groups, box);
  const total = vs.reduce((a, b) => a + b, 0);
  vs.forEach((v, i) => assert.ok(Math.abs(area(tiles[i]!) - (v / total) * area(box)) < 1e-6 * area(box), `tile ${i}`));
  // Each group's tiles fill a rectangle that no other group's tile enters.
  for (const g of [0, 1, 2]) {
    const own = tiles.filter((_, i) => groups[i] === g);
    const bounds = {
      x: Math.min(...own.map((t) => t.x)),
      y: Math.min(...own.map((t) => t.y)),
      w: Math.max(...own.map((t) => t.x + t.w)) - Math.min(...own.map((t) => t.x)),
      h: Math.max(...own.map((t) => t.y + t.h)) - Math.min(...own.map((t) => t.y)),
    };
    const sum = vs.filter((_, i) => groups[i] === g).reduce((a, b) => a + b, 0);
    assert.ok(Math.abs(area(bounds) - (sum / total) * area(box)) < 1e-6 * area(box), `group ${g} fills its share`);
    tiles.forEach((t, i) => {
      if (groups[i] !== g) assert.ok(overlap(t, bounds) < 1e-6, `tile ${i} is out of group ${g}`);
    });
  }
});
