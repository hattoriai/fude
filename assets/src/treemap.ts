// The tiles of a treemap: squarified (Bruls, Huizing and van Wijk), each
// row of tiles along the shorter side of what is left, as near to square
// as it can be. Tiles of the same group (a color) are laid out in their
// group's tile, so that they stay together.

export interface Tile {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** Tiles for the values, in their order (largest first reads best), filling the box: each tile's area its share of the total. */
export function squarify(values: number[], box: Tile): Tile[] {
  const tiles: Tile[] = new Array(values.length);
  const total = values.reduce((sum, v) => sum + Math.max(0, v), 0);
  if (!values.length || total <= 0 || box.w <= 0 || box.h <= 0) return values.map(() => ({ x: box.x, y: box.y, w: 0, h: 0 }));
  const scale = (box.w * box.h) / total;
  const areas = values.map((v) => Math.max(0, v) * scale);
  let rest = { ...box };
  let start = 0;
  while (start < areas.length) {
    const side = Math.min(rest.w, rest.h);
    // Add tiles to the row while its worst aspect ratio gets better.
    let end = start + 1;
    let worstSoFar = worst(areas.slice(start, end), side);
    while (end < areas.length) {
      const next = worst(areas.slice(start, end + 1), side);
      if (next > worstSoFar) break;
      worstSoFar = next;
      end++;
    }
    const row = areas.slice(start, end);
    const sum = row.reduce((a, b) => a + b, 0);
    const thickness = side > 0 ? sum / side : 0;
    let along = 0;
    row.forEach((area, i) => {
      const length = thickness > 0 ? area / thickness : 0;
      tiles[start + i] =
        rest.w >= rest.h
          ? { x: rest.x, y: rest.y + along, w: thickness, h: length }
          : { x: rest.x + along, y: rest.y, w: length, h: thickness };
      along += length;
    });
    rest = rest.w >= rest.h ? { x: rest.x + thickness, y: rest.y, w: rest.w - thickness, h: rest.h } : { x: rest.x, y: rest.y + thickness, w: rest.w, h: rest.h - thickness };
    start = end;
  }
  return tiles;
}

// The worst aspect ratio of a row of areas laid along a side.
function worst(row: number[], side: number): number {
  const sum = row.reduce((a, b) => a + b, 0);
  if (sum <= 0 || side <= 0) return Infinity;
  const max = Math.max(...row);
  const min = Math.min(...row);
  return Math.max((side * side * max) / (sum * sum), (sum * sum) / (side * side * min));
}

/**
 * Tiles for values in groups: the groups laid out by their totals, then
 * each group's values in its tile. A value with no group is a group alone.
 */
export function squarifyGroups(values: number[], groups: (number | null)[], box: Tile): Tile[] {
  const order: (number | string)[] = [];
  const members = new Map<number | string, number[]>();
  values.forEach((_, i) => {
    const group = groups[i] ?? `alone:${i}`;
    if (!members.has(group)) {
      members.set(group, []);
      order.push(group);
    }
    members.get(group)!.push(i);
  });
  const totals = order.map((group) => members.get(group)!.reduce((sum, i) => sum + Math.max(0, values[i]!), 0));
  // The largest group first, as the largest tile.
  const sorted = order.map((group, i) => ({ group, total: totals[i]! })).sort((a, b) => b.total - a.total);
  const outer = squarify(
    sorted.map((g) => g.total),
    box,
  );
  const tiles: Tile[] = new Array(values.length);
  sorted.forEach(({ group }, g) => {
    const inside = members.get(group)!.sort((a, b) => values[b]! - values[a]!);
    squarify(
      inside.map((i) => values[i]!),
      outer[g]!,
    ).forEach((tile, k) => (tiles[inside[k]!] = tile));
  });
  return tiles;
}
