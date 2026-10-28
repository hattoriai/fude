// The seats of a parliament chart: rows of half circles, each seat a dot,
// the seats in order of their angle from left to right, so that a party's
// seats, taken in that order, are a wedge of the chamber (as Wikipedia's
// parliament diagrams have them).

export interface Seat {
  /** Across, from -1 (left) to 1 (right). */
  x: number;
  /** Up, from 0 (the floor) to 1 (the top of the outer row). */
  y: number;
  /** Its angle, from π (left) to 0 (right). */
  angle: number;
  row: number;
}

export interface Chamber {
  seats: Seat[];
  rows: number;
  /** The radius of a dot, in the same units: a little less than half the step between rows. */
  radius: number;
}

// The inner row's radius, of the outer's: the hole in the middle.
const INNER = 0.4;

// The radii of the rows, from the inner to the outer.
function radii(rows: number): number[] {
  if (rows === 1) return [1];
  return Array.from({ length: rows }, (_, i) => INNER + ((1 - INNER) * i) / (rows - 1));
}

// How far apart the dots are, for a number of rows: the step between rows.
function spacing(rows: number): number {
  return rows === 1 ? (1 - INNER) / 1.5 : (1 - INNER) / (rows - 1);
}

// How many seats a row of a radius holds, at a spacing.
function capacity(radius: number, step: number): number {
  return Math.max(1, Math.floor((Math.PI * radius) / step) + 1);
}

/** The fewest rows that hold the seats: the largest dots. */
export function rowsFor(total: number): number {
  for (let rows = 1; rows < 100; rows++) {
    const step = spacing(rows);
    if (radii(rows).reduce((sum, r) => sum + capacity(r, step), 0) >= total) return rows;
  }
  return 100;
}

/** The seats of a chamber of `total`, in order from left to right. */
export function chamber(total: number): Chamber {
  if (total <= 0) return { seats: [], rows: 0, radius: 0 };
  const rows = rowsFor(total);
  const rs = radii(rows);
  const step = spacing(rows);
  // Each row's share of the seats, as its length is of all the rows'
  // (largest remainders), and never more than it holds.
  const length = rs.reduce((sum, r) => sum + r, 0);
  const exact = rs.map((r) => (total * r) / length);
  const counts = exact.map(Math.floor);
  let left = total - counts.reduce((a, b) => a + b, 0);
  const order = exact.map((v, i) => ({ i, rest: v - Math.floor(v) })).sort((a, b) => b.rest - a.rest);
  for (const { i } of order) {
    if (left <= 0) break;
    counts[i]!++;
    left--;
  }
  for (let i = 0; i < rows; i++) {
    const room = capacity(rs[i]!, step);
    if (counts[i]! > room) {
      // Too many for this row: the rest go to the outer rows that have room.
      let extra = counts[i]! - room;
      counts[i] = room;
      for (let j = rows - 1; j >= 0 && extra > 0; j--) {
        const add = Math.min(extra, capacity(rs[j]!, step) - counts[j]!);
        if (add > 0) {
          counts[j]! += add;
          extra -= add;
        }
      }
    }
  }
  const seats: Seat[] = [];
  rs.forEach((r, row) => {
    const n = counts[row]!;
    for (let k = 0; k < n; k++) {
      const angle = n === 1 ? Math.PI / 2 : Math.PI - (k * Math.PI) / (n - 1);
      seats.push({ x: Math.cos(angle) * r, y: Math.sin(angle) * r, angle, row });
    }
  });
  // From left to right; at the same angle, from the inside out.
  seats.sort((a, b) => b.angle - a.angle || a.row - b.row);
  return { seats, rows, radius: step * 0.42 };
}
