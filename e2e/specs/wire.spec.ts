import { expect, test, type Page } from "@playwright/test";
import { unpack, type Config } from "../../assets/src/wire";
import { openPage } from "./support";

// The server packs a chart's long columns (Fude.Wire). Each chart of the
// page that came packed is mounted twice, side by side at its size, with
// no animation: once from the config as the server sent it (the hook
// unpacks it), once from its columns unpacked here, as plain lists. The
// canvases must be the same, pixel for pixel. That the packed columns
// unpack to the server's very values is tested by both unit suites, on
// test/fixtures/wire.json.

interface Pair {
  id: string;
  /** The config the packed copy is mounted with: the server's, as sent. */
  packed: string;
  /** The server's next config, as sent, which the packed copy then takes as an update. */
  next?: string;
  /** The config of the plain copy: the packed copy's last, unpacked. */
  plain: string;
}

const still = (config: object) => JSON.stringify({ ...config, animate: false });
const packed = (raw: string) => still(JSON.parse(raw));
const plain = (raw: string) => still(unpack(JSON.parse(raw) as Config));

/** The charts of the page whose config has a packed column, by id. */
async function packedCharts(page: Page): Promise<Map<string, string>> {
  const charts = await page.evaluate(() =>
    [...document.querySelectorAll<HTMLElement>('[phx-hook="Fude"][data-fude]')]
      .filter((el) => el.dataset.fude!.includes('"deltas"'))
      .map((el) => [el.id, el.dataset.fude!] as [string, string]),
  );
  return new Map(charts);
}

/** Draws each pair from the page's first render of its chart, and gives the canvases of its two copies. */
async function drawPairs(page: Page, pairs: Pair[]): Promise<{ id: string; packed: string; plain: string }[]> {
  await page.evaluate(async (pairs) => {
    // The bundle, by the page's import map.
    const bundle = "fude";
    const { mountFude } = (await import(bundle)) as { mountFude: (root: ParentNode) => { update(): void }[] };
    const html = await (await fetch(location.href)).text();
    const first = new DOMParser().parseFromString(html, "text/html");

    const copy = (id: string, suffix: string, config: string): HTMLElement => {
      const original = document.getElementById(id)!;
      const twinId = `${id}-${suffix}`;
      document.getElementById(twinId)?.parentElement?.remove();
      const element = first.getElementById(id)!.cloneNode(true) as HTMLElement;
      element.id = twinId;
      element.dataset.fude = config.replace(`"id":"${id}"`, `"id":"${twinId}"`);
      element.querySelectorAll<HTMLElement>(`[id^="${id}-"]`).forEach((el) => (el.id = el.id.replace(`${id}-`, `${twinId}-`)));
      const box = original.getBoundingClientRect();
      const holder = document.createElement("div");
      holder.style.cssText = `position:absolute;left:0;top:0;width:${box.width}px;height:${box.height}px;`;
      holder.append(element);
      original.parentElement!.style.position = "relative";
      original.parentElement!.append(holder);
      return holder;
    };

    for (const pair of pairs) {
      const [chart] = mountFude(copy(pair.id, "packed", pair.packed));
      if (pair.next) {
        // An update, as the hook takes one: the new config in the attribute.
        document.getElementById(`${pair.id}-packed`)!.dataset.fude = pair.next.replace(`"id":"${pair.id}"`, `"id":"${pair.id}-packed"`);
        chart!.update();
      }
      mountFude(copy(pair.id, "plain", pair.plain));
    }
  }, pairs);
  await page.waitForTimeout(500);
  return page.evaluate((ids) => {
    const pixels = (id: string) => [...document.querySelectorAll<HTMLCanvasElement>(`#${id} canvas`)].map((c) => `${c.width}x${c.height}:${c.toDataURL()}`).join("|");
    return ids.map((id) => ({ id, packed: pixels(`${id}-packed`), plain: pixels(`${id}-plain`) }));
  }, pairs.map((p) => p.id));
}

async function expectSame(page: Page, pairs: Pair[], least: number): Promise<void> {
  expect(pairs.length, "charts with packed columns").toBeGreaterThanOrEqual(least);
  for (const pair of await drawPairs(page, pairs)) {
    expect(pair.plain, `${pair.id}: its plain copy drew`).not.toBe("");
    const sizes = (pixels: string) => pixels.split("|").map((c) => c.split(":")[0]).join(", ");
    expect(pair.packed === pair.plain, `${pair.id}: drawn from packed columns as from plain ones (${sizes(pair.packed)} and ${sizes(pair.plain)})`).toBe(true);
  }
}

test.describe("packed columns", () => {
  for (const path of ["/", "/newsroom"]) {
    test(`draw as plain columns do: ${path}`, async ({ page }) => {
      await openPage(page, path);
      const charts = await packedCharts(page);
      await expectSame(page, [...charts].map(([id, raw]) => ({ id, packed: packed(raw), plain: plain(raw) })), 3);
    });
  }

  test("draw as plain columns do after an update", async ({ page }) => {
    await openPage(page);
    const before = await packedCharts(page);
    await page.getByRole("button", { name: "Change the data" }).click();
    await expect.poll(async () => [...(await packedCharts(page)).values()]).not.toEqual([...before.values()]);
    const after = await packedCharts(page);
    const pairs = [...after]
      .filter(([id, raw]) => before.has(id) && before.get(id) !== raw)
      .map(([id, raw]) => ({ id, packed: packed(before.get(id)!), next: packed(raw), plain: plain(raw) }));
    await expectSame(page, pairs, 1);
  });
});
