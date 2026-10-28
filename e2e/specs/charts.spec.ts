import { expect, test, type Page } from "@playwright/test";
import { dragAcross, openPage, pointAt, stage, tooltip } from "./support";

test.describe("the gallery", () => {
  test("draws every chart with no error", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await openPage(page);
    await expect(page.locator("#revenue-lines .fude-axes text").first()).toBeVisible();
    await expect(page.locator("#world .fude-stage canvas")).toBeVisible();
    expect(errors).toEqual([]);
  });

  test("a chart's data stays open as the LiveView renders it again", async ({ page }) => {
    await openPage(page);
    const data = page.locator("#revenue-lines .fude-data");
    await data.locator("summary").click();
    await expect(data).toHaveAttribute("open", "");
    const before = await data.locator("tbody").textContent();

    await page.getByRole("button", { name: "Change the data" }).click();
    await expect.poll(() => data.locator("tbody").textContent()).not.toBe(before);
    await expect(data).toHaveAttribute("open", "");
  });

  test("a chart's data in its place: the table at the plot's size, kept as the LiveView renders it again", async ({ page }) => {
    await openPage(page);
    const chart = page.locator("#revenue-regions");
    const plot = chart.locator(".fude-plot");
    const table = chart.locator(".fude-data-over");
    const button = chart.getByRole("button", { name: "Data" });
    await expect(chart.locator("details.fude-data")).toHaveCount(0);
    await expect(table).toBeHidden();
    const plotBox = (await plot.boundingBox())!;

    await button.click();
    await expect(button).toHaveAttribute("aria-pressed", "true");
    await expect(table).toBeVisible();
    await expect(plot).toBeHidden();
    const tableBox = (await table.boundingBox())!;
    expect(Math.abs(tableBox.height - plotBox.height)).toBeLessThan(2);
    const before = await table.locator("tbody").textContent();

    await page.getByRole("button", { name: "Change the data" }).click();
    await expect.poll(() => table.locator("tbody").textContent()).not.toBe(before);
    await expect(table).toBeVisible();
    await expect(button).toHaveAttribute("aria-pressed", "true");

    await button.click();
    await expect(table).toBeHidden();
    await expect(plot).toBeVisible();
    await expect(button).toHaveAttribute("aria-pressed", "false");
  });

  test("a trend draws its history under it, ending on its value", async ({ page }) => {
    await openPage(page);
    const spark = page.locator("#mrr-spark .fude-spark");
    await expect(spark).toBeVisible();
    const box = (await spark.boundingBox())!;
    const last = (await spark.locator(".fude-spark-last").boundingBox())!;
    expect(Math.abs(last.x + last.width / 2 - (box.x + box.width))).toBeLessThan(2);
    expect(box.height).toBeGreaterThan(20);
  });

  test("a chart that fills its box draws again at the box's new height", async ({ page }) => {
    await openPage(page);
    const canvas = page.locator("#card-chart .fude-stage canvas");
    await expect(canvas).toBeVisible();
    const before = (await canvas.boundingBox())!.height;

    await page.locator("#card-box").evaluate((box) => (box.style.height = "420px"));
    await expect.poll(async () => (await canvas.boundingBox())!.height).toBeGreaterThan(before + 100);
    await expect(page.locator("#card-chart .fude-axes text").first()).toBeVisible();
  });

  test("a line chart's tooltip lists every series at the pointer", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "revenue-lines", 0.6, 0.5);
    const text = await tooltip(page, "revenue-lines");
    for (const series of ["Online", "Retail", "Partners"]) expect(text).toContain(series);
    expect(text).toMatch(/€[\d,]+/);
  });

  test("a chart of two units has an axis for each, and its tooltip both values", async ({ page }) => {
    await openPage(page);
    const labels = await page.locator("#orders-revenue .fude-axes text").allTextContents();
    expect(labels).toContain("Orders");
    expect(labels).toContain("Revenue");
    // The right axis's ticks: in euros on the top one only, as a graphics
    // desk writes them ("€100k", then "90k"…), in the browser's locale.
    expect(labels.filter((label) => label.includes("€")).length).toBe(1);
    expect(labels.filter((label) => /^\d+k$/i.test(label)).length).toBeGreaterThan(2);
    await pointAt(page, "orders-revenue", 0.6, 0.6);
    const text = await tooltip(page, "orders-revenue");
    expect(text).toMatch(/[\d,]+\s*Orders/);
    expect(text).toMatch(/€[\d,]+\s*Revenue/);
  });

  test("a bar's tooltip names its category and series", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "revenue-regions", 0.36, 0.85);
    const text = await tooltip(page, "revenue-regions");
    expect(text).toMatch(/North|South|East|West|Central/);
  });

  test("a click on a bar sends its category and series (select)", async ({ page }) => {
    await openPage(page);
    await stage(page, "revenue-regions").click({ position: await pointer(page, "revenue-regions", 0.36, 0.85) });
    await expect(page.locator("#selected")).toHaveText(/"id":"revenue-regions"/);
    const selected = JSON.parse((await page.locator("#selected").textContent())!);
    expect(["North", "South", "East", "West", "Central"]).toContain(selected.x);
    expect(["Online", "Retail", "Partners"]).toContain(selected.color);
    expect(typeof selected.y).toBe("number");
  });

  test("the selected bar stands out, the others faded, as the server says", async ({ page }) => {
    await openPage(page);
    const chart = page.locator("#revenue-regions");
    await expect(stage(page, "revenue-regions")).not.toHaveAttribute("data-fude-picked");
    const before = await stage(page, "revenue-regions").screenshot();
    await stage(page, "revenue-regions").click({ position: await pointer(page, "revenue-regions", 0.36, 0.85) });
    await expect(chart).toHaveAttribute("data-fude-selected", /"x":"(North|South|East|West|Central)"/);
    // One region's bars stand out: one per channel of its stack.
    await expect(stage(page, "revenue-regions")).toHaveAttribute("data-fude-picked", "3");
    await page.mouse.move(0, 0);
    await page.waitForTimeout(300);
    expect(await stage(page, "revenue-regions").screenshot()).not.toEqual(before);
  });

  test("a click on a line chart sends the time at the crosshair; Enter, the keyboard's", async ({ page }) => {
    await openPage(page);
    await stage(page, "revenue-lines").click({ position: await pointer(page, "revenue-lines", 0.6, 0.5) });
    await expect(page.locator("#selected")).toHaveText(/"x":"20\d\d-\d\d-\d\d/);
    expect(Object.keys(JSON.parse((await page.locator("#selected").textContent())!)).sort()).toEqual(["id", "x"]);

    await stage(page, "revenue-lines").focus();
    await page.keyboard.press("Home");
    await page.keyboard.press("Enter");
    await expect(page.locator("#selected")).toHaveText(/"x":"2025-01-01/);
  });

  test("the keyboard moves through the data and says each value", async ({ page }) => {
    await openPage(page);
    await stage(page, "status").focus();
    await page.keyboard.press("ArrowRight");
    await page.keyboard.press("ArrowRight");
    await expect(page.locator("#status .fude-live")).toHaveText(/Shipped\. 1,630 · 23\.8%/);
    // The fields of the tooltip after the chart's own values.
    await expect(page.locator("#status .fude-live")).toHaveText(/Days, on average: 2\.4/);
    await page.keyboard.press("Escape");
    await expect(page.locator("#status .fude-tooltip")).not.toHaveClass(/fude-tooltip-on/);
  });

  test("a funnel's labels go inside the bars that hold them, outside the others", async ({ page }) => {
    await openPage(page);
    // A color for each stage, and no legend: the axis names the stages.
    await expect(page.locator("#signups-stages .fude-legend")).toBeHidden();
    const inside = page.locator('#signups-stages svg text[text-anchor="middle"]', { hasText: "48,210" });
    await expect(inside).toHaveCount(1);
    const outside = page.locator('#signups-stages svg text[text-anchor="start"]', { hasText: "1,210" });
    await expect(outside).toHaveCount(1);
  });

  test("a dumbbell joins each category's points, writes their values and a column beside them", async ({ page }) => {
    await openPage(page);
    const svg = page.locator("#throughput svg.fude-axes:not(.fude-grid)");
    // Each point's value, in its format and suffix: the greatest above, the least below.
    // By their places in the plot (WebKit's boxes of SVG text are not theirs).
    const high = Number(await svg.locator("text", { hasText: /^618\.6\sMB\/s$/ }).getAttribute("y"));
    const low = Number(await svg.locator("text", { hasText: /^25\.6\sMB\/s$/ }).getAttribute("y"));
    expect(low).toBeGreaterThan(high + 20);
    // The ticks of the log scale are round: decimal bytes.
    await expect(svg.locator("text", { hasText: /^1\sGB\/s$/ })).toHaveCount(1);
    // The column of text: its title, and one value for each category.
    await expect(svg.locator("text", { hasText: "Speedup" })).toHaveCount(1);
    await expect(svg.locator('text[text-anchor="end"]', { hasText: /×$/ })).toHaveCount(6);
    await expect(svg.locator("text", { hasText: "24.2×" })).toHaveCount(1);
  });

  test("charts of a link show the hovered month together, the tooltip only on the hovered one", async ({ page }) => {
    await openPage(page);
    // A month of 2026, which every chart of months has.
    await pointAt(page, "revenue-lines", 0.8, 0.5);
    await tooltip(page, "revenue-lines");
    const month = await stage(page, "orders-revenue").getAttribute("data-fude-linked");
    expect(month).toMatch(/^\d+$/);
    await expect(page.locator("#orders-revenue .fude-cross line")).toHaveCount(1);
    await expect(page.locator("#orders-revenue .fude-cross text").first()).toBeVisible();
    await expect(page.locator("#orders-revenue .fude-tooltip.fude-tooltip-on")).toHaveCount(0);
    // The bar of that month.
    await expect(stage(page, "orders-months")).toHaveAttribute("data-fude-linked", "1");

    // A month of 2025: the charts of 2026 do not have it, and show nothing.
    await pointAt(page, "revenue-lines", 0.12, 0.5);
    await expect(stage(page, "orders-revenue")).not.toHaveAttribute("data-fude-linked", /.*/);
    await expect(stage(page, "orders-months")).not.toHaveAttribute("data-fude-linked", /.*/);

    // Leaving clears them all.
    await pointAt(page, "revenue-lines", 0.8, 0.5);
    await expect(stage(page, "orders-months")).toHaveAttribute("data-fude-linked", "1");
    await page.mouse.move(2, 2);
    await expect(stage(page, "orders-months")).not.toHaveAttribute("data-fude-linked", /.*/);
    await expect(page.locator("#orders-revenue .fude-cross line")).toHaveCount(0);
  });

  test("a bar of a link shows its month on the lines, and the keyboard moves it", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "orders-months", 0.5, 0.8);
    await expect(stage(page, "revenue-lines")).toHaveAttribute("data-fude-linked", /^\d+$/);

    await page.mouse.move(2, 2);
    await stage(page, "orders-revenue").focus();
    await page.keyboard.press("End");
    // December 2026: the last bar.
    await expect(stage(page, "orders-months")).toHaveAttribute("data-fude-linked", "1");
    const december = await stage(page, "revenue-lines").getAttribute("data-fude-linked");
    await page.keyboard.press("ArrowLeft");
    await expect(stage(page, "revenue-lines")).not.toHaveAttribute("data-fude-linked", december!);
  });

  test("a brush zooms the chart to the range dragged across it; the button, a double click and Escape go back", async ({ page }) => {
    await openPage(page);
    const visits = stage(page, "visits");
    const ticks = await page.locator("#visits svg.fude-axes:not(.fude-grid) text").allTextContents();
    await dragAcross(page, "visits", 0.35, 0.6);
    // Days, snapped to whole days: "28 Jul – 21 Aug 2026", by the browser's ICU.
    await expect(visits).toHaveAttribute("data-fude-zoom", /Jul.*Aug 2026/);
    await expect.poll(() => page.locator("#visits svg.fude-axes:not(.fude-grid) text").allTextContents()).not.toEqual(ticks);
    const reset = page.locator("#visits .fude-brush-reset");
    await expect(reset).toHaveText("Reset zoom");
    await reset.click();
    await expect(visits).not.toHaveAttribute("data-fude-zoom", /.*/);
    await expect(reset).toBeHidden();

    await dragAcross(page, "visits", 0.3, 0.5);
    await expect(visits).toHaveAttribute("data-fude-zoom", /.+/);
    await visits.dblclick();
    await expect(visits).not.toHaveAttribute("data-fude-zoom", /.*/);

    await dragAcross(page, "visits", 0.3, 0.5);
    await expect(visits).toHaveAttribute("data-fude-zoom", /.+/);
    await visits.focus();
    await page.keyboard.press("Escape");
    await expect(visits).not.toHaveAttribute("data-fude-zoom", /.*/);
  });

  test("a brush that selects sends the server its range, in whole months, and keeps it shaded", async ({ page }) => {
    await openPage(page);
    await dragAcross(page, "revenue-area", 0.5, 0.75);
    await expect(page.locator("#brushed")).toHaveText(/^\{"revenue-area", \{~D\[\d{4}-\d{2}-01\], ~D\[\d{4}-\d{2}-01\]\}\}$/);
    await expect(stage(page, "revenue-area")).toHaveAttribute("data-fude-brush", /2026/);
    await expect(page.locator("#revenue-area .fude-brush-reset")).toHaveText("Clear range");
    // A drag is not a click on a mark.
    await expect(page.locator("#selected")).toHaveText("");
  });

  test("Shift and the arrows choose a range from the keyboard; Enter sends it", async ({ page }) => {
    await openPage(page);
    await stage(page, "revenue-area").focus();
    await page.keyboard.press("Home");
    await page.keyboard.press("Shift+ArrowRight");
    await page.keyboard.press("Shift+ArrowRight");
    await page.keyboard.press("Enter");
    await expect(page.locator("#brushed")).toHaveText('{"revenue-area", {~D[2025-01-01], ~D[2025-03-01]}}');
  });

  test("on a touch screen, a swipe does not brush; a long press, then a drag, does", async ({ page }) => {
    await openPage(page);
    const touch = (hold: number) =>
      page.evaluate(async (hold) => {
        const stage = document.querySelector<HTMLElement>("#visits .fude-stage")!;
        stage.scrollIntoView();
        const r = stage.getBoundingClientRect();
        const y = r.top + r.height / 2;
        const send = (type: string, x: number) =>
          stage.dispatchEvent(new PointerEvent(type, { pointerId: 7, pointerType: "touch", clientX: x, clientY: y, button: 0, bubbles: true }));
        send("pointerdown", r.left + r.width * 0.3);
        await new Promise((done) => setTimeout(done, hold));
        for (let i = 1; i <= 6; i++) send("pointermove", r.left + r.width * (0.3 + i * 0.05));
        send("pointerup", r.left + r.width * 0.6);
        await new Promise((done) => setTimeout(done, 50));
        return stage.dataset.fudeZoom ?? null;
      }, hold);
    expect(await touch(50)).toBeNull();
    expect(await touch(600)).toMatch(/Aug 2026/);
  });

  test("a brush on a panel of small multiples zooms them all, with one button", async ({ page }) => {
    await openPage(page);
    await dragAcross(page, "regions-multiples-0", 0.4, 0.8);
    for (const panel of [0, 1, 2, 3]) await expect(stage(page, `regions-multiples-${panel}`)).toHaveAttribute("data-fude-zoom", /2026/);
    await expect(page.locator("#regions-multiples .fude-brush-reset:visible")).toHaveCount(1);
    await stage(page, "regions-multiples-2").dblclick();
    for (const panel of [0, 1, 2, 3]) await expect(stage(page, `regions-multiples-${panel}`)).not.toHaveAttribute("data-fude-zoom", /.*/);
  });

  test("a sparkline writes its last value at the end of its line", async ({ page }) => {
    await openPage(page);
    // Compact, as y's format says: "4.3K" or "4.3k", by the browser's ICU.
    await expect(page.locator("#visits-spark-area svg text")).toHaveText(/^[\d.,]+\s?[kK]$/);
  });

  test("the names at the ends of the lines take the legend's place, and hide a series", async ({ page }) => {
    await openPage(page);
    // The legend is the keyboard's way in only: out of sight until it has the focus.
    const legend = page.locator("#revenue-lines .fude-legend");
    await expect(legend).toHaveClass(/fude-legend-quiet/);
    const end = page.locator("#revenue-lines .fude-end-label", { hasText: /^Retail$/ });
    await end.click();
    await expect(page.locator("#revenue-lines .fude-end-label", { hasText: /^Retail$/ })).toHaveAttribute("opacity", "0.4");
    const retail = page.locator("#revenue-lines .fude-legend-item", { hasText: "Retail" });
    await expect(retail).toHaveAttribute("aria-pressed", "false");
    // The keyboard shows it again, from the legend.
    await retail.focus();
    await expect(retail).toBeVisible();
    await page.keyboard.press("Enter");
    await expect(retail).toHaveAttribute("aria-pressed", "true");
  });

  test("a legend reads in the order of the marks: a stack from its top segment down", async ({ page }) => {
    await openPage(page);
    await expect(page.locator("#revenue-regions .fude-legend-item").first()).toHaveText("Partners");
    await expect(page.locator("#revenue-regions .fude-legend")).not.toHaveClass(/fude-legend-quiet/);
  });

  test("labels on the marks: a donut's total, compact values where full ones do not fit, and bars that need no value axis", async ({ page }) => {
    await openPage(page);
    await expect(page.locator("#status svg text", { hasText: /^6,860$/ })).toHaveCount(1);
    await expect(page.locator("#status .fude-legend")).toHaveClass(/fude-legend-quiet/);
    await expect(page.locator("#profit svg text", { hasText: /^-?€\d+k$/i })).not.toHaveCount(0);
    // A value in every cell of a heatmap, or none.
    const cells = await page.locator("#activity svg text[data-key^='v:']").count();
    expect(cells).toBe(7 * 17);
    // Horizontal bars with their values: no ticks of a value axis.
    await expect(page.locator("#regions-horizontal svg text", { hasText: /^\d+k$/ })).toHaveCount(0);
  });

  test("the data moves when it changes", async ({ page }) => {
    await openPage(page);
    const before = await page.locator("#revenue-regions").getAttribute("data-fude");
    await page.click("text=Change the data");
    await expect.poll(() => page.locator("#revenue-regions").getAttribute("data-fude")).not.toBe(before);
  });

  test("a bar's tooltip adds its share of its stack, its rank and its history", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "revenue-regions", 0.36, 0.85);
    const text = await tooltip(page, "revenue-regions");
    expect(text).toMatch(/[\d.]+% of (North|South|East|West|Central)/);
    expect(text).toMatch(/#\d of 5/);
    await expect(page.locator("#revenue-regions .fude-tooltip-history")).toHaveCount(1);
  });

  test("a crosshair's tooltip adds each series' change from the point before", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "revenue-area", 0.6, 0.5);
    expect(await tooltip(page, "revenue-area")).toMatch(/[▲▼] [\d.]+% vs /);
  });

  test("the frame of a sequence of renders is written large, and changes with it", async ({ page }) => {
    await openPage(page);
    const frame = page.locator("#regions-horizontal .fude-grid text");
    await expect(frame).toHaveText("Q1");
    await page.click("text=Change the data");
    await expect(frame).toHaveText("Q2");
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

test.describe("the kinds: timeline, box plot, candlestick, treemap, radar, radial bars", () => {
  test("a timeline's bar gives its span and how long it is", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "plan", 0.45, 0.5);
    const tip = await tooltip(page, "plan");
    expect(tip).toContain("Web app");
    // Some versions of ICU put thin spaces around the dash of a range.
    expect(tip).toMatch(/28 Mar\s–\s29 Apr 2026/);
    expect(tip).toContain("32 days");
  });

  test("a box gives its median, its middle half, its whiskers and its count; the keyboard reads each", async ({ page }) => {
    await openPage(page);
    await stage(page, "deliveries").focus();
    await page.keyboard.press("ArrowRight");
    await expect(page.locator("#deliveries .fude-live")).toContainText("North. Median: 3.75");
    await pointAt(page, "deliveries", 0.68, 0.72);
    const tip = await tooltip(page, "deliveries");
    expect(tip).toMatch(/^West/);
    expect(tip).toContain("Median");
    expect(tip).toContain("Whiskers");
  });

  test("a thin candle is easy to point at, and gives its four prices", async ({ page }) => {
    await openPage(page);
    await pointAt(page, "prices", 0.5, 0.35);
    const tip = await tooltip(page, "prices");
    for (const word of ["Open", "High", "Low", "Close", "€"]) expect(tip).toContain(word);
  });

  test("a treemap names its largest tiles, and a tile gives its share", async ({ page }) => {
    await openPage(page);
    await expect(page.locator("#cities svg text", { hasText: /^Madrid$/ })).toHaveCount(1);
    await expect(page.locator("#cities svg text", { hasText: /^3\.3M$|^3\.3m$/ })).toHaveCount(1);
    await pointAt(page, "cities", 0.1, 0.3);
    expect(await tooltip(page, "cities")).toMatch(/Madrid.*%/);
  });

  test("a radar names its spokes; a ring of radial bars its category and value", async ({ page }) => {
    await openPage(page);
    for (const spoke of ["Speed", "Size", "Kinds", "Interaction", "Accessibility", "Export"]) {
      await expect(page.locator("#scores svg text", { hasText: new RegExp(`^${spoke}$`) })).toHaveCount(1);
    }
    await expect(page.locator("#goals svg text", { hasText: /^Online 86%$/ })).toHaveCount(1);
    await pointAt(page, "goals", 0.5, 0.06);
    expect(await tooltip(page, "goals")).toContain("Online");
  });
});

test.describe("the newsroom", () => {
  test("draws every kind as a newsroom would publish it, with no error", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await openPage(page, "/newsroom");
    // A highlight: the series that matters named in bold, the others gray.
    await expect(page.locator("#news-online .fude-end-label", { hasText: "Online" }).locator("text")).toHaveAttribute("font-weight", "600");
    await expect(page.locator("#news-online .fude-end-label", { hasText: "Retail" }).locator("text")).not.toHaveAttribute("font-weight", /.*/);
    // A stack's total, and a callout.
    await expect(page.locator("#news-stacked svg text", { hasText: /^€136,306$/ })).toHaveCount(1);
    await expect(page.locator("#news-online svg text", { hasText: "Record month" })).toHaveCount(1);
    // The table is the hook's: written when it is opened.
    const data = page.locator("#news-regions details.fude-data");
    await expect(data.locator("tbody tr")).toHaveCount(0);
    await data.locator("summary").click();
    await expect(data.locator("tbody tr")).toHaveCount(5);
    expect(errors).toEqual([]);
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

// A place in a chart's stage, as fractions of its size, for a click.
async function pointer(page: Page, id: string, fx: number, fy: number) {
  const box = (await stage(page, id).boundingBox())!;
  return { x: box.width * fx, y: box.height * fy };
}
