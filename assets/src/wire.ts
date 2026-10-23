// What the server sends (Fude.Compile): the chart's scales with their
// domains, and each layer's mark with its columns. A category is its
// index in its scale's domain; a time is milliseconds since 1970 (UTC).

export type MarkType = "bar" | "line" | "area" | "point" | "arc" | "rect" | "rule" | "text";

export interface Scale {
  type: "band" | "point" | "linear" | "log" | "sqrt" | "time" | "ordinal" | "sequential";
  domain: unknown[] | null;
  title?: string;
  format?: string;
  nice?: boolean;
  unit?: string;
  time?: string;
  bins?: { start: number; step: number };
}

export interface Layer {
  mark: MarkType;
  n: number;
  columns: Record<string, (number | null)[]>;
  horizontal: boolean;
  stack: "zero" | "normalize" | "center" | null;
  options: Record<string, unknown>;
  tooltip: { title: string | null; format: string | null }[];
}

export interface Single {
  value: number | string | null;
  label: string | null;
  format: string | null;
  compare: number | null;
  goal: number | null;
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
}
