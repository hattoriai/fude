// Helpers for the browser tests.

import { expect, type Locator, type Page } from "@playwright/test";

/** Opens a page and waits for the LiveView to connect and the charts to draw. */
export async function openPage(page: Page, path = "/"): Promise<void> {
  await page.goto(path);
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  await expect(page.locator(".fude-stage canvas").first()).toBeVisible();
  // The marks move into place on their first draw.
  await page.waitForTimeout(600);
}

/** The stage of a chart: where its marks are, and the keyboard's focus. */
export function stage(page: Page, id: string): Locator {
  return page.locator(`#${id} .fude-stage`);
}

/** Moves the pointer over a chart's stage, at a share of its width and height. */
export async function pointAt(page: Page, id: string, x: number, y: number): Promise<void> {
  await stage(page, id).scrollIntoViewIfNeeded();
  const box = await stage(page, id).boundingBox();
  if (!box) throw new Error(`no stage for ${id}`);
  await page.mouse.move(box.x + box.width * x, box.y + box.height * y);
}

/** The text of a chart's tooltip, once it shows. */
export async function tooltip(page: Page, id: string): Promise<string> {
  const tip = page.locator(`#${id} .fude-tooltip.fude-tooltip-on`);
  await expect(tip).toBeVisible();
  return (await tip.textContent()) ?? "";
}

/** Drags across a chart's stage, at half its height, from one share of its width to another. */
export async function dragAcross(page: Page, id: string, from: number, to: number): Promise<void> {
  const target = stage(page, id).first();
  await target.scrollIntoViewIfNeeded();
  const box = await target.boundingBox();
  if (!box) throw new Error(`no stage for ${id}`);
  const y = box.y + box.height * 0.5;
  await page.mouse.move(box.x + box.width * from, y);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width * ((from + to) / 2), y, { steps: 4 });
  await page.mouse.move(box.x + box.width * to, y, { steps: 4 });
  await page.mouse.up();
}
