import { expect, test, type Page } from "@playwright/test";
import { unpack, type Config } from "../../assets/src/wire";
import { openPage } from "./support";

// The server packs a chart's long columns (Fude.Wire). Each chart that came
// packed is drawn again beside itself from its columns unpacked, as plain
// lists: the canvases must be the same, pixel for pixel. That the packed
// columns unpack to the server's very values is tested by both unit suites,
// on test/fixtures/wire.json.

interface Twin {
  id: string;
  packed: string;
  plain: string;
}

/** The charts of the page whose config has a packed column. */
async function packedCharts(page: Page): Promise<{ id: string; raw: string }[]> {
  return page.evaluate(() =>
    [...document.querySelectorAll<HTMLElement>('[phx-hook="Fude"][data-fude]')]
      .filter((el) => el.dataset.fude!.includes('"deltas"'))
      .map((el) => ({ id: el.id, raw: el.dataset.fude! })),
  );
}

/**
 * Mounts a copy of each chart, from the page's first render, at the
 * chart's size, with the config given; then gives each chart's canvas and
 * its copy's.
 */
async function drawTwins(page: Page, charts: { id: string; config: Config }[]): Promise<Twin[]> {
  await page.evaluate(async (charts) => {
    // The bundle, by the page's import map.
    const bundle = "fude";
    const { mountFude } = (await import(bundle)) as { mountFude: (root: ParentNode) => unknown[] };
    const html = await (await fetch(location.href)).text();
    const first = new DOMParser().parseFromString(html, "text/html");
    for (const { id, config } of charts) {
      document.getElementById(`${id}-twin`)?.parentElement?.remove();
      const original = document.getElementById(id)!;
      const copy = first.getElementById(id)!.cloneNode(true) as HTMLElement;
      const twinId = `${id}-twin`;
      copy.id = twinId;
      copy.dataset.fude = JSON.stringify({ ...config, id: twinId, animate: false });
      copy.querySelectorAll<HTMLElement>(`[id^="${id}-"]`).forEach((el) => (el.id = el.id.replace(`${id}-`, `${twinId}-`)));
      const box = original.getBoundingClientRect();
      const holder = document.createElement("div");
      holder.style.cssText = `position:absolute;left:0;top:0;width:${box.width}px;height:${box.height}px;`;
      holder.append(copy);
      original.parentElement!.style.position = "relative";
      original.parentElement!.append(holder);
      mountFude(holder);
    }
  }, charts);
  // The originals' marks move into place on their first draw or an update.
  await page.waitForTimeout(1200);
  return page.evaluate((ids) => {
    const pixels = (id: string) => [...document.querySelectorAll<HTMLCanvasElement>(`#${id} canvas`)].map((c) => `${c.width}x${c.height}:${c.toDataURL()}`).join("|");
    return ids.map((id) => ({ id, packed: pixels(id), plain: pixels(`${id}-twin`) }));
  }, charts.map((c) => c.id));
}

async function expectSameAsPlain(page: Page): Promise<number> {
  const charts = await packedCharts(page);
  const twins = await drawTwins(
    page,
    charts.map(({ id, raw }) => ({ id, config: unpack(JSON.parse(raw) as Config) })),
  );
  for (const twin of twins) {
    expect(twin.plain, `${twin.id}: its copy drew`).not.toBe("");
    expect(twin.packed === twin.plain, `${twin.id}: drawn from packed columns as from plain ones`).toBe(true);
  }
  return twins.length;
}

test.describe("packed columns", () => {
  for (const path of ["/", "/newsroom"]) {
    test(`draw as plain columns do: ${path}`, async ({ page }) => {
      await openPage(page, path);
      expect(await expectSameAsPlain(page)).toBeGreaterThan(2);
    });
  }

  test("draw as plain columns do after the LiveView renders new data", async ({ page }) => {
    await openPage(page);
    const before = (await packedCharts(page)).map((c) => c.raw);
    await page.getByRole("button", { name: "Change the data" }).click();
    await expect.poll(async () => (await packedCharts(page)).map((c) => c.raw)).not.toEqual(before);
    expect(await expectSameAsPlain(page)).toBeGreaterThan(2);
  });
});
