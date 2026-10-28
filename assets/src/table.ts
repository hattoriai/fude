// The data of a chart as a table, written by the hook from the chart's
// config (#4): the first layer's columns by their titles, a category by its
// name, a time as a date (a unit of a day or more) or a time to the second,
// as `Fude.Compile.table/1` gives it on the server. The page carries the data
// once, in the config, and the table's rows are made only when it is opened.

import type { Config, Scale } from "./wire";

const DAYS = ["day", "week", "month", "quarter", "year"];
const MAX = 1000;

export interface Table {
  heads: string[];
  rows: (string | null)[][];
}

export function tableOf(config: Config): Table {
  const layer = config.layers?.[0];
  const scales = config.scales ?? {};
  if (!layer) return { heads: [], rows: [] };
  const columns = (
    [
      ["x", "x"],
      ["y", "y"],
      ["color", "color"],
      ["size", "size"],
      ["value", null],
    ] as [string, string | null][]
  ).filter(([name]) => layer.columns[name] !== undefined);
  const heads = columns.map(([name, scale]) => (name === "value" ? "Value" : (scales[scale!]?.title ?? name)));
  const rows: (string | null)[][] = [];
  for (let row = 0; row < Math.min(layer.n, MAX); row++) {
    rows.push(columns.map(([name, scale]) => cell(layer.columns[name]![row], scale ? scales[scale] : undefined)));
  }
  return { heads, rows };
}

function cell(value: number | null | undefined, scale: Scale | undefined): string | null {
  if (value === null || value === undefined) return null;
  let plain: unknown = value;
  if (scale && (scale.type === "band" || scale.type === "point" || scale.type === "ordinal")) plain = scale.domain?.[value];
  if (plain === null || plain === undefined) return null;
  const unit = scale?.type === "time" ? scale.unit : scale?.time;
  if (typeof plain === "number" && (scale?.type === "time" || scale?.time)) {
    const iso = new Date(plain).toISOString();
    return unit && DAYS.includes(unit) ? iso.slice(0, 10) : iso.replace(".000Z", "Z");
  }
  return String(plain);
}

/** The table as HTML elements: a header row and a row for each row of the data. */
export function tableElement(table: Table): HTMLTableElement {
  const element = document.createElement("table");
  const head = element.createTHead().insertRow();
  for (const name of table.heads) {
    const th = document.createElement("th");
    th.scope = "col";
    th.textContent = name;
    head.append(th);
  }
  const body = element.createTBody();
  for (const row of table.rows) {
    const tr = body.insertRow();
    for (const value of row) tr.insertCell().textContent = value ?? "";
  }
  return element;
}
