import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

const email = process.env.E2E_AUTH_EMAIL;
const password = process.env.E2E_AUTH_PASSWORD;

const companyFixture = {
	symbol: "AAPL",
	longName: "Apple Inc.",
	shortName: "Apple",
	regularMarketPrice: 213.32,
	regularMarketChange: 2.7,
	regularMarketChangePercent: 1.28,
	currency: "USD",
	longBusinessSummary:
		"Apple designs, manufactures, and markets smartphones, personal computers, tablets, wearables, and services. The company serves consumer, small-business, education, enterprise, and government markets around the world.",
	website: "https://apple.com",
	sector: "Technology",
	industry: "Consumer Electronics",
	city: "Cupertino",
	country: "United States",
	marketCap: 3_190_000_000_000,
	enterpriseValue: 3_240_000_000_000,
	sharesOutstanding: 14_950_000_000,
	revenue: 391_000_000_000,
	employees: 164_000,
	peRatio: 33.1,
	forwardPE: 29.4,
	priceToBook: 48.2,
	priceToSales: 8.2,
	evToSales: 8.3,
	evToEbitda: 24.6,
	pegRatio: 2.1,
	grossMargins: 0.466,
	ebitdaMargins: 0.34,
	operatingMargins: 0.315,
	netProfitMargins: 0.243,
	returnOnAssets: 0.226,
	returnOnEquity: 1.57,
	totalCash: 65_000_000_000,
	totalDebt: 101_000_000_000,
	debtToEquity: 187,
	revenueGrowth: 0.061,
	earningsGrowth: 0.089,
	dividendYield: 0.0045,
	dividendRate: 1,
	payoutRatio: 0.149,
	beta: 1.18,
};

const cachedExplanationFixture = JSON.stringify({
	entries: {
		AAPL_pe_ratio: {
			value: 33.1,
			explanation: JSON.stringify({
				metric_display: "**P/E Ratio: 33.1**",
				insight:
					"This multiple shows how much investors pay for current earnings. Read it with growth and margins before forming a directional view.",
				evaluation: "neutral",
			}),
			savedAt: Date.now(),
		},
	},
});

async function mockCompanyResearch(page: Page) {
	const requestedTimeframes: string[] = [];
	await page.route("**/api/stock-data?**", async (route) => {
		await route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ data: companyFixture }),
		});
	});
	await page.route("**/api/alpaca?**", async (route) => {
		const url = new URL(route.request().url());
		requestedTimeframes.push(url.searchParams.get("timeframe") ?? "");
		const now = Math.floor(Date.now() / 1000);
		const data = Array.from({ length: 80 }, (_, index) => {
			const open = 192 + index * 0.25;
			return {
				time: now - (79 - index) * 60 * 30,
				open,
				high: open + 1.2,
				low: open - 0.8,
				close: open + 0.55,
				volume: 1_000_000 + index * 2_000,
			};
		});
		await route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				data,
				isEmpty: false,
				totalBars: data.length,
				earliestTimestamp: data[0].time,
			}),
		});
	});
	await page.route("**/api/stream/**", async (route) => {
		await route.fulfill({
			status: 200,
			headers: { "content-type": "text/event-stream", "cache-control": "no-cache" },
			body: "event: stream-error\ndata: {}\n\n",
		});
	});
	return requestedTimeframes;
}

test.beforeEach(async ({ page }) => {
	if (!email || !password) {
		throw new Error("Authenticated test credentials are required");
	}

	await page.goto("/auth");
	const signInForm = page.locator("form:visible");
	await signInForm.getByRole("textbox", { name: "Email", exact: true }).fill(email);
	await signInForm.getByPlaceholder("Password").fill(password);
	await signInForm.getByRole("button", { name: "Sign In", exact: true }).click();
	await expect(page).toHaveURL(/\/dashboard$/);
});

test("@authenticated dashboard loads with a verified session", async ({ page }) => {
	await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
	await expect(page.getByRole("heading", { name: "Your Favorites" })).toBeVisible();
});

test("@authenticated auth page redirects an existing session", async ({ page }) => {
	await page.goto("/auth");
	await expect(page).toHaveURL(/\/dashboard$/);
	await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
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

test("@authenticated reports API returns only the current tenant collection", async ({ page }) => {
	const response = await page.request.get("/api/reports");

	expect(response.status()).toBe(200);
	expect(await response.json()).toEqual({ reports: [] });
});

test("@authenticated settings route renders for the current tenant", async ({ page }) => {
	await page.goto("/settings");
	await expect(page).toHaveURL(/\/settings$/);
	await expect(page.getByRole("heading", { name: "Settings", exact: true })).toBeVisible();
});

test("@authenticated company research connects chart ranges to the analyst", async ({ page }) => {
	const requestedTimeframes = await mockCompanyResearch(page);
	await page.addInitScript((cachedExplanation) => {
		window.localStorage.setItem("indus_explanations_cache_v3", cachedExplanation);
	}, cachedExplanationFixture);
	await page.goto("/company/AAPL");

	await expect(page.getByText("Apple Inc.", { exact: true })).toBeVisible();
	await expect(page.getByRole("region", { name: "AAPL price chart" })).toBeVisible();
	await expect(page.getByText("Financial Metrics", { exact: true })).toBeVisible();

	await page.getByRole("button", { name: "1Y" }).click();
	await expect.poll(() => requestedTimeframes).toContain("1Day");

	await page.getByText("33.1", { exact: true }).last().hover();
	await expect(page.getByText(/Read it with growth and margins/)).toBeVisible();

	await page.getByRole("button", { name: "Ask more" }).click();
	const analyst = page.getByRole("dialog");
	await expect(analyst).toBeVisible();
	await expect(analyst.getByText("AAPL", { exact: true })).toBeVisible();
	await analyst.getByRole("button", { name: "Close chat" }).click();
	await expect(analyst).toBeHidden();
});

test("@authenticated critical product routes have no serious accessibility violations", async ({
	page,
}) => {
	for (const path of ["/dashboard", "/crypto", "/reports", "/settings"]) {
		await page.goto(path);
		await expect(page).toHaveTitle(/Indus/);
		const results = await new AxeBuilder({ page })
			.withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
			.analyze();
		const seriousViolations = results.violations.filter(({ impact }) =>
			["serious", "critical"].includes(impact ?? ""),
		);

		expect(seriousViolations, `${path} accessibility violations`).toEqual([]);
	}
});
