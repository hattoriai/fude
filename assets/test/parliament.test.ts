import { test } from "node:test";
import assert from "node:assert/strict";
import { chamber, rowsFor } from "../src/parliament";

const sizes = [1, 2, 7, 50, 101, 230, 349, 650, 720, 2977];

test("a seat for each, in rows of half circles", () => {
  for (const n of sizes) {
    const room = chamber(n);
    assert.equal(room.seats.length, n, `${n} seats`);
    assert.equal(room.rows, rowsFor(n));
    for (const seat of room.seats) {
      assert.ok(seat.y >= -1e-9 && seat.y <= 1 + 1e-9, `${n}: above the floor, under the top`);
      assert.ok(Math.abs(Math.hypot(seat.x, seat.y) - (room.rows === 1 ? 1 : 0.4 + (0.6 * seat.row) / (room.rows - 1))) < 1e-9, `${n}: on its row`);
    }
  }
});

test("no two seats overlap", () => {
  for (const n of sizes.filter((n) => n <= 720)) {
    const { seats, radius } = chamber(n);
    for (let i = 0; i < seats.length; i++) {
      for (let j = i + 1; j < seats.length; j++) {
        const d = Math.hypot(seats[i]!.x - seats[j]!.x, seats[i]!.y - seats[j]!.y);
        assert.ok(d >= 2 * radius - 1e-9, `${n}: seats ${i} and ${j} are ${d.toFixed(4)} apart, dots ${(2 * radius).toFixed(4)} wide`);
      }
    }
  }
});

test("seats go from left to right, so that a party's run of seats is a wedge", () => {
  for (const n of sizes) {
    const { seats } = chamber(n);
    for (let i = 1; i < seats.length; i++) assert.ok(seats[i]!.angle <= seats[i - 1]!.angle + 1e-12, `${n}: seat ${i}`);
  }
  // Half the seats are on the left: a majority is at the top.
  const { seats } = chamber(230);
  assert.ok(seats.slice(0, 115).every((s) => s.x <= 1e-9));
  assert.ok(seats.slice(115).every((s) => s.x >= -1e-9));
});

test("more seats, more rows, smaller dots; none is none", () => {
  for (let i = 1; i < sizes.length; i++) {
    assert.ok(chamber(sizes[i]!).rows >= chamber(sizes[i - 1]!).rows);
    assert.ok(chamber(sizes[i]!).radius <= chamber(sizes[i - 1]!).radius);
  }
  assert.deepEqual(chamber(0), { seats: [], rows: 0, radius: 0 });
});
