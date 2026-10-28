// Linked hover (#14): charts that share a link name show the same place
// together. The hovered chart sends the value under the pointer in its
// data's terms (a time, a category's name, a number), never its pixels;
// each linked chart finds that value on its own axis. In the browser only,
// on `document`: no round trip to the server.

import { floor, type TimeUnit } from "./rules";

/** A value on an x axis: a time (in milliseconds, with its unit), or a name or a number. */
export type LinkValue = { time: number; unit?: string | null } | { value: string | number };

export interface LinkMessage {
  link: string;
  /** The chart that sent it, so that it does not follow itself. */
  from: unknown;
  /** The value hovered, or null when the pointer left. */
  at: LinkValue | null;
}

const EVENT = "fude:link";

const UNITS: TimeUnit[] = ["millisecond", "second", "minute", "hour", "day", "week", "month", "quarter", "year"];

/** Sends a chart's hovered value to the charts of its link. */
export function publish(message: LinkMessage): void {
  document.dispatchEvent(new CustomEvent<LinkMessage>(EVENT, { detail: message }));
}

/** Listens to the values of every link; gives the function that stops. */
export function subscribe(listener: (message: LinkMessage) => void): () => void {
  const handler = (event: Event) => listener((event as CustomEvent<LinkMessage>).detail);
  document.addEventListener(EVENT, handler);
  return () => document.removeEventListener(EVENT, handler);
}

function unitOf(unit: string | null | undefined): TimeUnit | null {
  return unit && (UNITS as string[]).includes(unit) ? (unit as TimeUnit) : null;
}

/** The coarser of two units of time: a day in March is March on a chart of months. */
function coarser(a: string | null | undefined, b: string | null | undefined): TimeUnit | null {
  const ua = unitOf(a);
  const ub = unitOf(b);
  if (!ua || !ub) return ua ?? ub;
  return UNITS.indexOf(ua) >= UNITS.indexOf(ub) ? ua : ub;
}

/**
 * The places of a chart that show a value sent by another: a time within
 * the coarser of the two axes' units, the nearest of those (the first of
 * March, on a chart of days, for March); a name or a number, the same. All
 * the places at the nearest (the bars of a stack) are given, in order; none
 * when the chart does not have the value.
 */
export function matching(sent: LinkValue, own: (LinkValue | null)[]): number[] {
  let best = Infinity;
  let found: number[] = [];
  own.forEach((value, i) => {
    if (value === null) return;
    let distance: number;
    if ("time" in sent) {
      if (!("time" in value)) return;
      const unit = coarser(sent.unit, value.unit);
      if (unit ? floor(sent.time, unit) !== floor(value.time, unit) : sent.time !== value.time) return;
      distance = Math.abs(value.time - sent.time);
    } else {
      if (!("value" in value) || String(value.value) !== String(sent.value)) return;
      distance = 0;
    }
    if (distance < best) {
      best = distance;
      found = [i];
    } else if (distance === best) found.push(i);
  });
  return found;
}
