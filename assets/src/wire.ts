// What the server sends (Fude.Compile): the chart's scales with their
// domains, and each layer's mark with its columns. A category is its
// index in its scale's domain; a time is milliseconds since 1970 (UTC).

export type MarkType = "bar" | "line" | "area" | "point" | "arc" | "rect" | "rule" | "text" | "region" | "bubble";

export interface Scale {
  type: "band" | "point" | "linear" | "log" | "sqrt" | "time" | "ordinal" | "sequential";
  domain: unknown[] | null;
  title?: string;
  format?: string;
  nice?: boolean;
  unit?: string;
  time?: string;
  bins?: { start: number; step: number };
  /** The roles of an ordinal scale's values, which pick their colors. */
  roles?: string[];
  /** A color scale's scheme: a name of the theme's, or a list of colors. */
  scheme?: string | string[];
  /** The value at the middle of a diverging scheme. */
  mid?: number;
  /** The series that keep their colors; the others are gray. */
  highlight?: unknown[];
  /** False for a color with no legend: a funnel's stages, which its axis names. */
  legend?: boolean;
}

export interface Layer {
  mark: MarkType;
  n: number;
  columns: Record<string, (number | null)[]>;
  /** "right" for a layer on the right axis, of the scale "yRight". */
  axis?: "right" | null;
  horizontal: boolean;
  stack: "zero" | "normalize" | "center" | "waterfall" | null;
  options: Record<string, unknown>;
  /** The fields of the tooltip beyond the channels: a value for each row; a time in milliseconds, with its unit ("" for a time of a day). */
  tooltip: { title: string | null; format: string | null; time?: string | null; values?: (number | string | boolean | null)[] }[];
  /** What the tooltip adds to a mark's values; each unset one takes its default. */
  tips?: { change?: boolean; share?: boolean; rank?: boolean; history?: boolean } | null;
}

export interface Single {
  value: number | string | null;
  label: string | null;
  format: string | null;
  compare: number | null;
  goal: number | null;
  /** Centered in its box and sized to it, or at the start at a fixed size. */
  align?: "center" | "start";
}

export interface Config {
  v: 1;
  id: string;
  kind: string;
  title?: string | null;
  subtitle?: string | null;
  caption?: string | null;
  source?: string | null;
  description?: string;
  height?: number | null;
  locale?: string | null;
  axes?: boolean;
  layers?: Layer[];
  scales?: Record<string, Scale>;
  single?: Single;
  annotations?: Annotation[];
  /** False for a panel of small multiples: the legend is the whole chart's. */
  legend?: boolean;
  /** False for no motion, or a duration of the chart's own; the theme's when not given. */
  animate?: false | { duration: number } | null;
  /** The label of a frame of a sequence of renders (a race of bars), large in a corner. */
  frame?: string | null;
  /** What a drag across the x axis does (#13): zoom in place, or select a range for the server. */
  brush?: "zoom" | "select" | null;
}

export interface Annotation {
  type: "label" | "band" | "line";
  x: number | null;
  x2: number | null;
  y: number | null;
  y2: number | null;
  text: string | null;
}

// -- Packed columns ------------------------------------------------------------

/**
 * A column as the server may pack it (Fude.Wire): each value `from + step * k`,
 * `k` the sum of the deltas up to it, divided by 10 to `decimals` when it is
 * given; a null delta is a null value and does not move `k`.
 */
export interface PackedColumn {
  from: number;
  step: number;
  deltas: (number | null)[];
  decimals?: number;
}

// Exact powers of ten, as the server divides by them.
const POWERS = [1, 10, 100, 1000, 10000, 100000, 1000000];

/** A column's values: a packed column unpacked, an array as it is. */
export function unpackColumn<T>(column: T[] | PackedColumn): (T | number | null)[] {
  if (Array.isArray(column)) return column;
  const { from, step, deltas, decimals } = column;
  const power = decimals === undefined ? 1 : POWERS[decimals];
  if (power === undefined) throw new Error(`Fude: a packed column with ${decimals} decimals`);
  const values: (number | null)[] = new Array(deltas.length);
  let k = 0;
  for (let i = 0; i < deltas.length; i++) {
    const delta = deltas[i];
    if (delta === null || delta === undefined) {
      values[i] = null;
      continue;
    }
    k += delta;
    const n = from + step * k;
    values[i] = power === 1 ? n : n / power;
  }
  return values;
}

function unpackLayer(layer: Layer): Layer {
  const columns: Layer["columns"] = {};
  for (const [name, column] of Object.entries(layer.columns ?? {})) columns[name] = unpackColumn(column as (number | null)[] | PackedColumn) as (number | null)[];
  const tooltip = layer.tooltip?.map((tip) =>
    tip.values ? { ...tip, values: unpackColumn(tip.values as NonNullable<typeof tip.values> | PackedColumn) as typeof tip.values } : tip,
  );
  return { ...layer, columns, tooltip };
}

/** The config as the chart reads it, with every packed column unpacked: the inverse of Fude.Wire.pack. */
export function unpack(config: Config): Config {
  if (!config.layers) return config;
  return { ...config, layers: config.layers.map(unpackLayer) };
}
