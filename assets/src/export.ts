// A chart as a file: SVG, and PNG drawn from it. The marks are drawn by
// the same code as on the screen, into a context that writes SVG instead
// of painting a canvas (SvgContext); the words, axes and grid are the
// chart's own SVG; the title, legend and source are set above and below,
// as on the page.

const SVG = "http://www.w3.org/2000/svg";

type Matrix = [number, number, number, number]; // scale x, scale y, translate x, translate y

/**
 * The part of CanvasRenderingContext2D that the marks use, writing SVG
 * elements: each fill and stroke a <path>.
 */
// A linear gradient of the SVG context: its line, in the page's pixels,
// and its stops, written as a <linearGradient> where a fill uses it.
class SvgGradient {
  readonly stops: [number, string][] = [];
  constructor(
    readonly x0: number,
    readonly y0: number,
    readonly x1: number,
    readonly y1: number,
  ) {}
  addColorStop(offset: number, color: string): void {
    this.stops.push([offset, color]);
  }
}

export class SvgContext {
  globalAlpha = 1;
  fillStyle: string | CanvasGradient | CanvasPattern = "#000";
  strokeStyle: string | CanvasGradient | CanvasPattern = "#000";
  lineWidth = 1;
  lineJoin: CanvasLineJoin = "miter";
  lineCap: CanvasLineCap = "butt";
  readonly parts: string[] = [];
  private d = "";
  private dash: number[] = [];
  private matrix: Matrix = [1, 1, 0, 0];
  private stack: Matrix[] = [];
  private at: [number, number] = [0, 0];

  setTransform(): void {
    this.matrix = [1, 1, 0, 0];
  }
  clearRect(): void {}
  save(): void {
    this.stack.push([...this.matrix]);
  }
  restore(): void {
    this.matrix = this.stack.pop() ?? [1, 1, 0, 0];
  }
  translate(x: number, y: number): void {
    const [sx, sy, tx, ty] = this.matrix;
    this.matrix = [sx, sy, tx + x * sx, ty + y * sy];
  }
  scale(x: number, y: number): void {
    const [sx, sy, tx, ty] = this.matrix;
    this.matrix = [sx * x, sy * y, tx, ty];
  }
  createLinearGradient(x0: number, y0: number, x1: number, y1: number): CanvasGradient {
    const [sx, sy, tx, ty] = this.matrix;
    return new SvgGradient(tx + x0 * sx, ty + y0 * sy, tx + x1 * sx, ty + y1 * sy) as unknown as CanvasGradient;
  }
  setLineDash(dash: number[]): void {
    this.dash = dash;
  }
  beginPath(): void {
    this.d = "";
  }
  private p(x: number, y: number): string {
    const [sx, sy, tx, ty] = this.matrix;
    return `${round(tx + x * sx)},${round(ty + y * sy)}`;
  }
  moveTo(x: number, y: number): void {
    this.d += `M${this.p(x, y)}`;
    this.at = [x, y];
  }
  lineTo(x: number, y: number): void {
    this.d += `L${this.p(x, y)}`;
    this.at = [x, y];
  }
  bezierCurveTo(a: number, b: number, c: number, d: number, x: number, y: number): void {
    this.d += `C${this.p(a, b)} ${this.p(c, d)} ${this.p(x, y)}`;
    this.at = [x, y];
  }
  // A rounded corner: from the line before the corner (x1, y1) to the
  // line after it, towards (x2, y2).
  arcTo(x1: number, y1: number, x2: number, y2: number, r: number): void {
    const [x0, y0] = this.at;
    const a = unit(x0 - x1, y0 - y1);
    const b = unit(x2 - x1, y2 - y1);
    const start = [x1 + a[0] * r, y1 + a[1] * r] as const;
    const end = [x1 + b[0] * r, y1 + b[1] * r] as const;
    const sweep = (x1 - x0) * (y2 - y1) - (y1 - y0) * (x2 - x1) > 0 ? 1 : 0;
    const k = this.matrix[0];
    this.d += `L${this.p(start[0], start[1])}A${round(r * k)},${round(r * k)} 0 0 ${sweep} ${this.p(end[0], end[1])}`;
    this.at = [end[0], end[1]];
  }
  arc(cx: number, cy: number, r: number, a0: number, a1: number, ccw = false): void {
    const k = this.matrix[0];
    const point = (a: number) => [cx + Math.cos(a) * r, cy + Math.sin(a) * r] as const;
    let span = ccw ? a0 - a1 : a1 - a0;
    if (span >= Math.PI * 2 - 1e-9) {
      // A whole circle: two halves.
      const [sx, sy] = point(a0);
      const [mx, my] = point(a0 + Math.PI);
      this.d += `${this.d ? "L" : "M"}${this.p(sx, sy)}A${round(r * k)},${round(r * k)} 0 1 1 ${this.p(mx, my)}A${round(r * k)},${round(r * k)} 0 1 1 ${this.p(sx, sy)}`;
      this.at = [sx, sy];
      return;
    }
    span = ((span % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
    const [sx, sy] = point(a0);
    const [ex, ey] = point(a1);
    this.d += `${this.d ? "L" : "M"}${this.p(sx, sy)}A${round(r * k)},${round(r * k)} 0 ${span > Math.PI ? 1 : 0} ${ccw ? 0 : 1} ${this.p(ex, ey)}`;
    this.at = [ex, ey];
  }
  closePath(): void {
    this.d += "Z";
  }
  fill(path?: Path2D & { d?: string }): void {
    let fill = color(this.fillStyle);
    if (this.fillStyle instanceof SvgGradient) {
      const g = this.fillStyle;
      const id = `fude-gradient-${this.parts.length}`;
      const stops = g.stops.map(([offset, c]) => `<stop offset="${round(offset)}" stop-color="${escape(c)}"/>`).join("");
      this.parts.push(`<defs><linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="${round(g.x0)}" y1="${round(g.y0)}" x2="${round(g.x1)}" y2="${round(g.y1)}">${stops}</linearGradient></defs>`);
      fill = `url(#${id})`;
    }
    this.parts.push(this.element(path, `fill="${fill}"${this.opacity("fill-opacity")}`));
  }
  stroke(path?: Path2D & { d?: string }): void {
    const dash = this.dash.length ? ` stroke-dasharray="${this.dash.join(" ")}"` : "";
    const attrs = `fill="none" stroke="${color(this.strokeStyle)}" stroke-width="${round(this.lineWidth * (path ? 1 : this.matrix[0]))}" stroke-linejoin="${this.lineJoin}" stroke-linecap="${this.lineCap}"${dash}${this.opacity("stroke-opacity")}`;
    this.parts.push(this.element(path, attrs));
  }
  private opacity(name: string): string {
    return this.globalAlpha < 1 ? ` ${name}="${round(this.globalAlpha)}"` : "";
  }
  // A Path2D of a map region carries its path data (see Chart.regions):
  // drawn with the context's transform.
  private element(path: (Path2D & { d?: string }) | undefined, attrs: string): string {
    if (path?.d) {
      const [sx, sy, tx, ty] = this.matrix;
      return `<path d="${path.d}" transform="matrix(${round(sx)} 0 0 ${round(sy)} ${round(tx)} ${round(ty)})" ${attrs} vector-effect="non-scaling-stroke"/>`;
    }
    return `<path d="${this.d}" ${attrs}/>`;
  }
}

function unit(x: number, y: number): [number, number] {
  const length = Math.hypot(x, y) || 1;
  return [x / length, y / length];
}

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

function color(style: string | CanvasGradient | CanvasPattern): string {
  return typeof style === "string" ? escape(style) : "#000";
}

export function escape(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

export interface Page {
  width: number;
  stageHeight: number;
  font: string;
  surface: string;
  text: string;
  secondary: string;
  muted: string;
  title?: string | null;
  subtitle?: string | null;
  caption?: string | null;
  source?: string | null;
  legend: { name: string; color: string }[];
  /** The ramp of a sequential color: its stops, its ends, its title. */
  ramp?: { stops: string[]; low: string; high: string; title?: string } | null;
  grid: SVGSVGElement;
  marks: string[];
  axes: SVGSVGElement;
}

/** The chart as a standalone SVG document: its words, legend, grid, marks and axes. */
export function svgDocument(page: Page): string {
  const pad = 16;
  const lines: string[] = [];
  let y = pad;
  const words = (text: string, size: number, fill: string, weight = 400) => {
    y += size * 1.25;
    lines.push(`<text x="${pad}" y="${round(y)}" font-size="${size}" font-weight="${weight}" fill="${escape(fill)}">${escape(text)}</text>`);
  };
  if (page.title) words(page.title, 17, page.text, 600);
  if (page.subtitle) words(page.subtitle, 14, page.secondary);
  if (page.title || page.subtitle) y += 10;

  if (page.legend.length) {
    let x = pad;
    y += 14;
    for (const item of page.legend) {
      lines.push(`<rect x="${x}" y="${round(y - 9)}" width="10" height="10" rx="2" fill="${escape(item.color)}"/>`);
      lines.push(`<text x="${x + 15}" y="${round(y)}" font-size="13" fill="${escape(page.secondary)}">${escape(item.name)}</text>`);
      x += 30 + item.name.length * 7;
    }
    y += 10;
  }

  if (page.ramp) {
    const ramp = page.ramp;
    if (ramp.title) words(ramp.title, 13, page.secondary);
    y += 14;
    const lowWidth = ramp.low.length * 7;
    lines.push(`<text x="${pad}" y="${round(y)}" font-size="12" fill="${escape(page.secondary)}">${escape(ramp.low)}</text>`);
    const stops = ramp.stops.map((stop, i) => `<stop offset="${round(i / Math.max(1, ramp.stops.length - 1))}" stop-color="${escape(stop)}"/>`).join("");
    lines.push(`<defs><linearGradient id="fude-ramp">${stops}</linearGradient></defs>`);
    lines.push(`<rect x="${pad + lowWidth + 6}" y="${round(y - 8)}" width="128" height="8" rx="2" fill="url(#fude-ramp)"/>`);
    lines.push(`<text x="${pad + lowWidth + 140}" y="${round(y)}" font-size="12" fill="${escape(page.secondary)}">${escape(ramp.high)}</text>`);
    y += 10;
  }

  const stageTop = y;
  y += page.stageHeight + 8;
  const foot = [page.caption, page.source ? `Source: ${page.source}` : null].filter(Boolean).join("   ");
  if (foot) {
    y += 12;
    lines.push(`<text x="${pad}" y="${round(y)}" font-size="12" fill="${escape(page.muted)}">${escape(foot)}</text>`);
  }
  const height = Math.ceil(y + pad);
  const width = Math.ceil(page.width + pad * 2);
  const inner = (svg: SVGSVGElement) => new XMLSerializer().serializeToString(svg).replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");

  return [
    `<svg xmlns="${SVG}" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" font-family="${escape(page.font)}">`,
    `<rect width="100%" height="100%" fill="${escape(page.surface)}"/>`,
    ...lines,
    `<g transform="translate(${pad} ${round(stageTop)})">`,
    inner(page.grid),
    ...page.marks,
    inner(page.axes),
    "</g>",
    "</svg>",
  ].join("\n");
}

/** A PNG of an SVG document, at a scale (2: sharp on a high-density screen). */
export function png(svg: string, scale = 2): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    const url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }));
    image.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = image.width * scale;
      canvas.height = image.height * scale;
      const ctx = canvas.getContext("2d");
      if (!ctx) return reject(new Error("Fude: no canvas to draw the PNG"));
      ctx.scale(scale, scale);
      ctx.drawImage(image, 0, 0);
      URL.revokeObjectURL(url);
      canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("Fude: the PNG was not made"))), "image/png");
    };
    image.onerror = () => reject(new Error("Fude: the SVG did not load"));
    image.src = url;
  });
}

/** Saves a file, as the browser saves a download. */
export function save(blob: Blob, name: string): void {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
