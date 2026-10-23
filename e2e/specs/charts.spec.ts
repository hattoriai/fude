import { expect, test } from "@playwright/test";
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
