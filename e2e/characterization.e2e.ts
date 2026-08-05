import { expect, test } from "@playwright/test";

const validChatRequest = {
	context: {
		symbol: "AAPL",
		companyName: "Apple Inc.",
		asOf: "2025-01-01T00:00:00.000Z",
		metricGroups: {
			companyProfile: { marketCap: 3_000_000_000_000 },
			margins: { netMargin: 0.25 },
			valuation: { peRatio: 28.5 },
			growth: { revenueGrowth: 0.1 },
			financialHealth: { totalCash: 60_000_000_000 },
			dividends: { dividendYield: 0.004 },
		},
		cachedExplanations: {},
		trigger: { metricKey: "pe_ratio", metricLabel: "P/E Ratio", value: 28.5 },
	},
	messages: [],
	newMessage: "What does this P/E ratio mean?",
};

test("@integration @characterization every private product route redirects anonymous users", async ({
	page,
}) => {
	for (const path of [
		"/dashboard",
		"/company/AAPL",
		"/search",
		"/crypto",
		"/reports",
		"/settings",
	]) {
		await page.goto(path);
		await expect(page).toHaveURL(/\/auth(?:\?|$)/);
	}
});

test("@integration @characterization malformed model requests fail before authentication or providers", async ({
	request,
}) => {
	const responses = await Promise.all([
		request.post("/api/batch-explain", { data: [] }),
		request.post("/api/context-chat", { data: { newMessage: "missing context" } }),
		request.post("/api/reports/generate", { data: { symbol: "bad symbol!" } }),
	]);

	for (const response of responses) {
		expect(response.status()).toBe(400);
		await expect(response.json()).resolves.toHaveProperty("error");
	}
});

test("@integration @characterization valid model requests require an authenticated user", async ({
	request,
}) => {
	const responses = await Promise.all([
		request.post("/api/batch-explain", {
			data: [{ symbol: "AAPL", metric: "pe_ratio", value: 28.5 }],
		}),
		request.post("/api/context-chat", { data: validChatRequest }),
		request.post("/api/reports/generate", { data: { symbol: "AAPL" } }),
	]);

	for (const response of responses) {
		expect(response.status()).toBe(401);
		await expect(response.json()).resolves.toHaveProperty("error");
	}
});

test("@integration @characterization report resources validate identifiers and authentication", async ({
	request,
}) => {
	const invalidGet = await request.get("/api/reports/not-a-uuid");
	const invalidDelete = await request.delete("/api/reports/not-a-uuid");
	expect(invalidGet.status()).toBe(400);
	expect(invalidDelete.status()).toBe(400);

	const reportId = "11111111-1111-4111-8111-111111111111";
	const anonymousGet = await request.get(`/api/reports/${reportId}`);
	const anonymousDelete = await request.delete(`/api/reports/${reportId}`);
	expect(anonymousGet.status()).toBe(401);
	expect(anonymousDelete.status()).toBe(401);
});

test("@integration @characterization malformed stream symbols are rejected before connecting upstream", async ({
	request,
}) => {
	const response = await request.get("/api/stream/bad%20symbol");
	expect(response.status()).toBe(400);
	await expect(response.json()).resolves.toEqual({ error: "Invalid stream symbol" });
});
