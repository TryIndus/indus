import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const email = process.env.E2E_AUTH_EMAIL;
const password = process.env.E2E_AUTH_PASSWORD;

test.beforeEach(async ({ page }) => {
	if (!email || !password) {
		throw new Error("Authenticated test credentials are required");
	}

	await page.goto("/auth");
	await page.getByPlaceholder("Email").fill(email);
	await page.getByPlaceholder("Password").fill(password);
	await page.getByRole("button", { name: "Sign In", exact: true }).click();
	await expect(page).toHaveURL(/\/dashboard$/);
});

test("@authenticated dashboard loads with a verified session", async ({ page }) => {
	await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
	await expect(page.getByRole("heading", { name: "Your Favorites" })).toBeVisible();
});

test("@authenticated queryless crypto route renders its empty state", async ({ page }) => {
	await page.goto("/crypto");
	await expect(page).toHaveURL(/\/crypto$/);
	await expect(page.getByText("No Cryptocurrency Selected", { exact: true })).toBeVisible();
});

test("@authenticated reports route renders for the current tenant", async ({ page }) => {
	await page.goto("/reports");
	await expect(page).toHaveURL(/\/reports$/);
	await expect(page.getByRole("heading", { name: "Research Reports" })).toBeVisible();
	await expect(page.getByRole("heading", { name: "Your Reports" })).toBeVisible();
});

test("@authenticated dashboard has no serious accessibility violations", async ({ page }) => {
	await expect(page).toHaveTitle("Indus");
	const results = await new AxeBuilder({ page })
		.withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
		.analyze();
	const seriousViolations = results.violations.filter(({ impact }) =>
		["serious", "critical"].includes(impact ?? ""),
	);

	expect(seriousViolations).toEqual([]);
});
