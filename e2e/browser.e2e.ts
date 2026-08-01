import { expect, test } from "@playwright/test";

test("@browser landing page exposes the primary product path", async ({ page }) => {
	await page.goto("/");
	await expect(
		page.getByRole("heading", { name: /The Turning Point of Financial Intelligence/ }),
	).toBeVisible();
	await expect(page.getByRole("button", { name: "Explore Dashboard" })).toBeVisible();
	await expect(page.getByText("Comprehensive Analytics", { exact: true }).first()).toBeVisible();
});

test("@browser public pages do not overflow the viewport", async ({ page }) => {
	for (const path of ["/", "/auth"]) {
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
	await expect(page.getByText("Create Account", { exact: true })).toBeVisible();
	await expect(page.getByPlaceholder("First Name")).toBeVisible();
});
