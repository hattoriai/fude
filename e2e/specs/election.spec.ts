import { expect, test, type Page } from "@playwright/test";
import { openPage, pointAt, stage, tooltip } from "./support";

// The election page: what a newsroom shows on the night, and the bugs it
// found in bars, columns and maps.

const exactly = (word: string) => new RegExp(`^${word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`);

async function texts(page: Page, id: string): Promise<string[]> {
  return page.locator(`#${id} svg text`).allTextContents();
}

test.describe("the election page", () => {
  test("draws every chart with no error", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await openPage(page, "/election");
    expect(errors).toEqual([]);
  });

  test("bars colored by their parties: each value once, no legend, and columns side by side", async ({ page }) => {
    await openPage(page, "/election");
    const words = await texts(page, "results");
    expect(words.filter((word) => word === "83")).toHaveLength(1);
    await expect(page.locator("#results .fude-legend")).toBeHidden();
    // Three columns: changes of seats, votes, changes of votes, none over another.
    // Each column's words end at its own edge (their x, as WebKit's boxes of
    // SVG text are not to be trusted), apart by more than a word's width.
    const edges = await Promise.all(["+25", "29.4%", "+5.6"].map(async (word) => Number(await page.locator("#results svg text", { hasText: exactly(word) }).getAttribute("x"))));
    expect(edges[1]! - edges[0]!).toBeGreaterThan(30);
    expect(edges[2]! - edges[1]!).toBeGreaterThan(30);
    // A change up is in the up color, down in the down color.
    const up = await page.locator("#results svg text", { hasText: /^\+25$/ }).getAttribute("fill");
    const down = await page.locator("#results svg text", { hasText: /^−36$/ }).getAttribute("fill");
    expect(up).not.toEqual(down);
    await expect(page.locator("#results svg text", { hasText: /^–$/ })).toHaveCount(2);
  });

  test("a stack of 100%: names in the segments, no raw values, the majority on the bar of seats", async ({ page }) => {
    await openPage(page, "/election");
    const words = await texts(page, "split");
    expect(words).toContain("Social");
    // Not the raw values as percents ("8,300%"), nor the stacks' totals ("180%").
    expect(words.some((word) => /\d,\d{3}%/.test(word) || word === "180%")).toBe(false);
    const majority = page.locator("#split svg text", { hasText: "116 for a majority" });
    await expect(majority).toHaveCount(1);
    // Its words above the bar of seats, not above the plot: by their y (the
    // baseline of the words, the middle of the bar's name).
    const seats = Number(await page.locator("#split svg text", { hasText: /^Seats$/ }).getAttribute("y"));
    const label = Number(await majority.getAttribute("y"));
    expect(label).toBeLessThan(seats);
    expect(label).toBeGreaterThan(seats - 80);
  });

  test("a parliament: its total, its majority, a party's seats in the tooltip; the keyboard goes party by party", async ({ page }) => {
    await openPage(page, "/election");
    await expect(page.locator("#chamber svg text", { hasText: /^230$/ })).toHaveCount(1);
    await expect(page.locator("#chamber svg text", { hasText: "116 for a majority" })).toHaveCount(1);
    await pointAt(page, "chamber", 0.04, 0.95);
    const tip = await tooltip(page, "chamber");
    expect(tip).toContain("Social");
    expect(tip).toContain("83 seats");
    expect(tip).toContain("33 short of a majority");
    // From the hovered party, the next one: a party is one step, not each of its seats.
    await stage(page, "chamber").focus();
    await page.keyboard.press("ArrowRight");
    await expect(page.locator("#chamber .fude-live")).toContainText("Forward!. 73 seats");
  });

  test("a map in each leader's color, shaded by the lead, with both in the tooltip and a ramp of the lead", async ({ page }) => {
    await openPage(page, "/election");
    await expect(page.locator("#leads .fude-ramp-title", { hasText: "Lead, points" })).toHaveCount(1);
    await expect(page.locator("#leads .fude-legend", { hasText: "Social" })).toHaveCount(1);
    await pointAt(page, "leads", 0.45, 0.4);
    const tip = await tooltip(page, "leads");
    expect(tip).toContain("Leader");
    expect(tip).toContain("Lead, points");
  });
});
