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
  empty: string;
  /** The colors of roles: a waterfall's increase, decrease and total. */
  roles: Record<string, string>;
  series: string[];
  sequential: string[];
  /** The named schemes of a color channel: each ramp's steps, or a categorical order. */
  schemes: Record<string, string[]>;
  barMax: number;
  radius: number;
  gap: number;
  line: number;
  duration: number;
}

// A sequential ramp of one hue, light to dark, in steps that are each told
// apart from the next.
const SEQUENTIAL = "#cde2fb, #9ec5f4, #6da7ec, #3987e5, #256abf, #184f95, #0d366b";

// The named schemes, as fude.css has them in light mode.
const SCHEMES: Record<string, string> = {
  "green": "#d3efd9, #a6dcb3, #74c58c, #42a866, #2a8a4d, #1b6b3a, #0f4a27",
  "orange": "#fde0c5, #fbbf8a, #f69a4f, #e8772a, #c25a14, #96420c, #682c06",
  "purple": "#e4dcf8, #c6b7f0, #a693e6, #8571d9, #6650c0, #4c3896, #33246b",
  "gray": "#e6e5e1, #cac8c1, #aaa79f, #8a877f, #6b6862, #4d4b47, #302f2c",
  "viridis": "#440154, #443983, #31688e, #21918c, #35b779, #90d743, #fde725",
  "red_blue": "#b2182b, #ef8a62, #fddbc7, #f7f7f7, #d1e5f0, #67a9cf, #2166ac",
  "red_green": "#c51b7d, #e9a3c9, #fde0ef, #f7f7f7, #e6f5d0, #a1d76a, #4d9221",
  okabe_ito: "#0072b2, #e69f00, #009e73, #cc79a7, #56b4e9, #d55e00, #f0e442, #5e5c58",
};

const list = (value: string) =>
  value
    .split(",")
    .map((color) => color.trim())
    .filter(Boolean);

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
  const sequential = list(get("--fude-sequential", SEQUENTIAL));
  const schemes: Record<string, string[]> = { blue: sequential, categorical: series };
  for (const [name, fallback] of Object.entries(SCHEMES)) {
    if (name === "okabe_ito") {
      const colors = list(fallback);
      schemes[name] = colors.map((color, i) => get(`--fude-scheme-okabe-ito-${i + 1}`, color));
    } else {
      schemes[name] = list(get(`--fude-scheme-${name.replace("_", "-")}`, fallback));
    }
  }
  const reduced = typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
  return {
    font: get("--fude-font", "system-ui, -apple-system, 'Segoe UI', sans-serif"),
    text: get("--fude-text", "#0b0b0b"),
    secondary: get("--fude-secondary", "#52514e"),
    muted: get("--fude-muted", "#6f6d68"),
    grid: get("--fude-grid", "#e1e0d9"),
    baseline: get("--fude-baseline", "#c3c2b7"),
    surface: get("--fude-surface", "#fcfcfb"),
    empty: get("--fude-map-empty", "#e8e7e1"),
    roles: {
      increase: get("--fude-increase", "#1baf7a"),
      decrease: get("--fude-decrease", "#e34948"),
      total: get("--fude-total", "#5e5c58"),
    },
    series,
    sequential,
    schemes,
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

/** A color along a ramp of steps, at `t` from 0 to 1: between its two nearest steps. */
export function ramp(steps: string[], t: number): string {
  if (steps.length === 0) return "#888";
  if (steps.length === 1) return steps[0]!;
  const at = Math.max(0, Math.min(1, t)) * (steps.length - 1);
  const i = Math.min(steps.length - 2, Math.floor(at));
  return mix(steps[i]!, steps[i + 1]!, at - i);
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
