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
