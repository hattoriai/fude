// The Fude hook for a LiveSocket, and `mountFude` for a page without
// LiveView. The hook makes a Chart of its element and gives it the
// server's later renders (`updated`), which it draws in place.

import { Chart, type Transport } from "./chart";
import type { Config } from "./wire";

interface HookContext {
  el: HTMLElement;
  pushEvent(event: string, payload: object, onReply?: (reply: Record<string, unknown>, ref: number) => void): void;
  pushEventTo(target: string | HTMLElement, event: string, payload: object, onReply?: (reply: Record<string, unknown>, ref: number) => void): void;
  handleEvent(event: string, callback: (payload: Record<string, unknown>) => void): void;
}

interface FudeHook extends HookContext {
  chart?: Chart;
}

export const Fude = {
  mounted(this: FudeHook) {
    const hook = this;
    const target = hook.el.getAttribute("phx-target");
    const transport: Transport = {
      push(event, payload, onReply) {
        const reply = onReply ? (response: Record<string, unknown>) => onReply(response) : undefined;
        if (target) hook.pushEventTo(target, event, payload, reply);
        else hook.pushEvent(event, payload, reply);
      },
    };
    hook.chart = new Chart(hook.el, transport);
    hook.handleEvent("fude:export", (payload) => {
      if (payload.id === hook.chart?.id && (payload.format === "svg" || payload.format === "png")) void hook.chart?.download(payload.format);
    });
    hook.handleEvent("fude:append", (payload) => {
      if (payload.id === hook.chart?.id) hook.chart?.append(payload.wire as Config, (payload.max as number | null) ?? null);
    });
  },

  updated(this: FudeHook) {
    this.chart?.update();
  },

  destroyed(this: FudeHook) {
    this.chart?.destroy();
    this.chart = undefined;
  },
};

const mounted = new WeakMap<HTMLElement, Chart>();

/**
 * Mounts the charts under `root` on a page without a LiveSocket (a
 * controller's template): the same charts, drawn once. Returns them; a
 * chart already mounted is skipped.
 */
export function mountFude(root: ParentNode = document): Chart[] {
  const charts: Chart[] = [];
  for (const element of root.querySelectorAll<HTMLElement>('[phx-hook="Fude"]')) {
    if (mounted.has(element)) continue;
    const chart = new Chart(element, null);
    mounted.set(element, chart);
    charts.push(chart);
  }
  return charts;
}
