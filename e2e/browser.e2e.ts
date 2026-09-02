import { expect, test } from "@playwright/test";

test("@browser landing page exposes the primary product path", async ({ page }) => {
	await page.goto("/");
	await expect(
		page.getByRole("heading", { name: /Financial intelligence, in context/ }),
	).toBeVisible();
	for (const name of [
		"Sign in",
		"Open Indus",
		"Start researching",
		"Explore an example",
		"Open your workspace",
	]) {
		await expect(page.getByRole("link", { name })).toHaveAttribute("href", "/auth");
	}
	await expect(
		page.getByText("Research a company without switching tools.", { exact: true }).first(),
	).toBeVisible();
	await expect(
		page.getByText("Know what the product is showing.", { exact: true }).first(),
	).toBeVisible();
});

test("@browser public pages do not overflow the viewport", async ({ page }) => {
	for (const path of ["/", "/auth", "/help"]) {
		await page.goto(path);
		const dimensions = await page.evaluate(() => ({
			scrollWidth: document.documentElement.scrollWidth,
			clientWidth: document.documentElement.clientWidth,
		}));
		expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
	}
});

test("@browser authentication mode can be changed without a reload", async ({ page }) => {
	await page.goto("/auth");
	await page.getByRole("button", { name: "Don't have an account? Sign up" }).click();
	await expect(page.getByRole("heading", { name: "Start your research." })).toBeVisible();
	await expect(page.getByPlaceholder("First Name")).toBeVisible();
});
