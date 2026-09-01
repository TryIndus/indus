import { describe, expect, it } from "vitest";
import { buildExplanationItems } from "@/lib/explanation-items";

describe("explanation items", () => {
	it("includes every available displayed metric and preserves valid zero values", () => {
		const items = buildExplanationItems({
			symbol: "AAPL",
			marketCap: 3_000_000_000_000,
			revenueGrowth: 0,
			beta: Number.NaN,
		});

		expect(items).toEqual([
			{ symbol: "AAPL", metric: "market_cap", value: 3_000_000_000_000 },
			{ symbol: "AAPL", metric: "revenue_growth", value: 0 },
		]);
	});
});
