import { expect, test, type Page } from "@playwright/test";
import { openPage, pointAt, stage, tooltip } from "./support";

test.describe("the gallery", () => {
  test("draws every chart with no error", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await openPage(page);
    await expect(page.locator("#revenue-lines .fude-axes text").first()).toBeVisible();
    await expect(page.locator("#world .fude-stage canvas")).toBeVisible();
    expect(errors).toEqual([]);
  });

  test("a line chart's tooltip lists every series at the pointer", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "revenue-lines", 0.6, 0.5);
    const text = await tooltip(page, "revenue-lines");
    for (const series of ["Online", "Retail", "Partners"]) expect(text).toContain(series);
    expect(text).toMatch(/€[\d,]+/);
  });

  test("a bar's tooltip names its category and series", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "revenue-regions", 0.36, 0.85);
    const text = await tooltip(page, "revenue-regions");
    expect(text).toMatch(/North|South|East|West|Central/);
  });

  test("the keyboard moves through the data and says each value", async ({ page }) => {
    await openPage(page);
    await stage(page, "status").focus();
    await page.keyboard.press("ArrowRight");
    await page.keyboard.press("ArrowRight");
    await expect(page.locator("#status .fude-live")).toHaveText(/Shipped\. 1,630 · 23\.8%/);
    await page.keyboard.press("Escape");
    await expect(page.locator("#status .fude-tooltip")).not.toHaveClass(/fude-tooltip-on/);
  });

  test("the legend of a line chart hides a series", async ({ page }) => {
    await openPage(page);
    const retail = page.locator("#revenue-lines .fude-legend-item", { hasText: "Retail" });
    await retail.click();
    await expect(retail).toHaveAttribute("aria-pressed", "false");
    await expect(page.locator("#revenue-lines .fude-axes text", { hasText: /^Retail$/ })).toHaveCount(0);
  });

  test("the data moves when it changes", async ({ page }) => {
    await openPage(page);
    const before = await page.locator("#revenue-regions").getAttribute("data-fude");
    await page.click("text=Change the data");
    await expect.poll(() => page.locator("#revenue-regions").getAttribute("data-fude")).not.toBe(before);
  });

  test("a chart with a field that is not in the data says why", async ({ page }) => {
    await openPage(page);
    await expect(page.locator("#broken .fude-error")).toHaveText(/did you mean "region"\?/);
  });

  test("a map draws its regions and names one in its tooltip", async ({ page }) => {
    await openPage(page);
    // Brazil, in the middle of South America.
    await pointAt(page, "world", 0.36, 0.6);
    expect(await tooltip(page, "world")).toContain("Brazil");
  });

  test("numbers are written in the page's locale", async ({ page }) => {
    await openPage(page, "/?locale=de-DE");
    await expect(page.locator("#mrr .fude-value")).toHaveText(/184\.321/);
  });

  test("saves a chart as SVG and as PNG", async ({ page }) => {
    await openPage(page);
    for (const format of ["svg", "png"]) {
      const [download] = await Promise.all([
        page.waitForEvent("download"),
        page.click(`#revenue-lines [data-fude-export=${format}]`),
      ]);
      expect(download.suggestedFilename()).toBe(`online-keeps-growing.${format}`);
    }
  });
});

test.describe("the live page", () => {
  test("takes the new points without the data again", async ({ page }) => {
    let appends = 0;
    page.on("websocket", (socket) =>
      socket.on("framereceived", (frame) => {
        if (String(frame.payload).includes("fude:append")) appends++;
      }),
    );
    await openPage(page, "/live");
    const config = await page.locator("#load").getAttribute("data-fude");
    await expect.poll(() => appends, { timeout: 5000 }).toBeGreaterThan(1);
    expect(await page.locator("#load").getAttribute("data-fude")).toBe(config);
  });
});

// Issho's pointers (Fude.Issho): the symbols a chart sets on its element,
// read by Issho's script with no import of Fude.
test.describe("places for Issho", () => {
  async function placeAt(page: Page, id: string, x: number, y: number): Promise<unknown> {
    await stage(page, id).scrollIntoViewIfNeeded();
    const box = (await stage(page, id).boundingBox())!;
    return page.evaluate(
      ([id, cx, cy]) => {
        const el = document.getElementById(id as string) as unknown as Record<symbol, (x: number, y: number) => unknown>;
        return el[Symbol.for("issho.point")]!(cx as number, cy as number);
      },
      [id, box.x + box.width * x, box.y + box.height * y] as const,
    );
  }

  async function locate(page: Page, id: string, at: unknown): Promise<{ left: number; top: number; width: number; height: number } | null> {
    return page.evaluate(
      ([id, at]) => {
        const el = document.getElementById(id as string) as unknown as Record<symbol, (at: unknown) => DOMRect | null>;
        const box = el[Symbol.for("issho.locator")]!(at);
        return box && { left: box.left, top: box.top, width: box.width, height: box.height };
      },
      [id, at] as const,
    );
  }

  test("a bar is named by its category and series, and found again by them", async ({ page }) => {
    await openPage(page);
    const place = (await placeAt(page, "revenue-regions", 0.36, 0.85)) as { datum: Record<string, unknown>; x: number; y: number };
    expect(Object.keys(place.datum).sort()).toEqual(["color", "x"]);
    expect(place.x).toBeGreaterThanOrEqual(0);
    expect(place.y).toBeLessThanOrEqual(1);

    const box = await locate(page, "revenue-regions", { datum: place.datum });
    expect(box!.width).toBeGreaterThan(0);
    const again = (await page.evaluate(
      ([id, cx, cy]) => {
        const el = document.getElementById(id as string) as unknown as Record<symbol, (x: number, y: number) => unknown>;
        return el[Symbol.for("issho.point")]!(cx as number, cy as number);
      },
      ["revenue-regions", box!.left + box!.width / 2, box!.top + box!.height / 2] as const,
    )) as { datum: unknown };
    expect(again.datum).toEqual(place.datum);
  });

  test("a line chart's place is a time, across the plot", async ({ page }) => {
    await openPage(page);
    const place = (await placeAt(page, "revenue-lines", 0.6, 0.5)) as { datum: { x: string } };
    expect(Object.keys(place.datum)).toEqual(["x"]);
    expect(place.datum.x).toMatch(/^\d{4}-\d{2}-\d{2}/);
    const box = await locate(page, "revenue-lines", place);
    expect(box!.height).toBeGreaterThan(100);
  });

  test("a region is named by its code, and found by any of its names", async ({ page }) => {
    await openPage(page);
    const place = (await placeAt(page, "world", 0.36, 0.6)) as { datum: { region: string } };
    expect(place.datum.region).toBe("BRA");
    expect(await locate(page, "world", { datum: { region: "Brazil" } })).not.toBeNull();
    expect(await locate(page, "world", { datum: { region: "Atlantis" } })).toBeNull();
  });
});
