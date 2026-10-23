// The chart's colors and type, read from the --fude-* custom properties of
// its element (fude.css, fude-sumi.css, or the app's own). Read again when
// the page's theme changes: the chart repaints, it does not rebuild.

export interface Theme {
  font: string;
  text: string;
  secondary: string;
  muted: string;
  grid: string;
  baseline: string;
  surface: string;
  series: string[];
  sequential: [string, string];
  barMax: number;
  radius: number;
  gap: number;
  line: number;
  duration: number;
}

const FALLBACK_SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"];

export function readTheme(el: Element): Theme {
  const style = getComputedStyle(el);
  const get = (name: string, fallback: string) => style.getPropertyValue(name).trim() || fallback;
  const num = (name: string, fallback: number) => {
    const value = parseFloat(style.getPropertyValue(name));
    return Number.isFinite(value) ? value : fallback;
  };
  const series: string[] = [];
  for (let i = 1; i <= 8; i++) series.push(get(`--fude-series-${i}`, FALLBACK_SERIES[i - 1]!));
  const reduced = typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
  return {
    font: get("--fude-font", "system-ui, -apple-system, 'Segoe UI', sans-serif"),
    text: get("--fude-text", "#0b0b0b"),
    secondary: get("--fude-secondary", "#52514e"),
    muted: get("--fude-muted", "#6f6d68"),
    grid: get("--fude-grid", "#e1e0d9"),
    baseline: get("--fude-baseline", "#c3c2b7"),
    surface: get("--fude-surface", "#fcfcfb"),
    series,
    sequential: [get("--fude-sequential-low", "#cde2fb"), get("--fude-sequential-high", "#0d366b")],
    barMax: num("--fude-bar-max", 40),
    radius: num("--fude-bar-radius", 4),
    gap: num("--fude-gap", 2),
    line: num("--fude-line", 2),
    duration: reduced ? 0 : num("--fude-duration", 450),
  };
}

// Colors as [r, g, b] for mixing a sequential ramp, from any CSS color the
// canvas understands.
const parsed = new Map<string, [number, number, number]>();

export function rgb(color: string): [number, number, number] {
  const cached = parsed.get(color);
  if (cached) return cached;
  let out: [number, number, number] = [0, 0, 0];
  const hex = /^#([0-9a-f]{6})$/i.exec(color);
  if (hex) {
    const n = parseInt(hex[1]!, 16);
    out = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  } else if (typeof document !== "undefined") {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1;
    const ctx = canvas.getContext("2d");
    if (ctx) {
      ctx.fillStyle = color;
      ctx.fillRect(0, 0, 1, 1);
      const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
      out = [r!, g!, b!];
    }
  }
  parsed.set(color, out);
  return out;
}

/** A color between two, in linear-light RGB so the middle is not muddy. */
export function mix(a: string, b: string, t: number): string {
  const [ar, ag, ab] = rgb(a);
  const [br, bg, bb] = rgb(b);
  const lin = (c: number) => Math.pow(c / 255, 2.2);
  const gam = (c: number) => Math.round(255 * Math.pow(c, 1 / 2.2));
  const m = (x: number, y: number) => gam(lin(x) + (lin(y) - lin(x)) * t);
  return `rgb(${m(ar, br)}, ${m(ag, bg)}, ${m(ab, bb)})`;
}

export function alpha(color: string, a: number): string {
  const [r, g, b] = rgb(color);
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}
