import { afterEach, describe, expect, test, vi } from "vitest";
import { loadReportStockData } from "@/lib/server/report-stock-data";

afterEach(() => {
	vi.restoreAllMocks();
});

describe("loadReportStockData", () => {
	test("loads a bounded financial snapshot directly from the provider", async () => {
		const provider = {
			quote: vi.fn().mockResolvedValue({
				symbol: "AAPL",
				shortName: "Example",
				longName: "Example Corporation",
				regularMarketPrice: 125,
				regularMarketChange: 2,
				regularMarketChangePercent: 1.6,
				marketCap: 5_000,
			}),
			quoteSummary: vi.fn().mockResolvedValue({
				assetProfile: { sector: "Technology", industry: "Software" },
				defaultKeyStatistics: { beta: 1.2 },
				financialData: {
					revenueGrowth: 0.1,
					profitMargins: 0.2,
					returnOnEquity: 0.3,
					debtToEquity: 40,
				},
				summaryDetail: {
					marketCap: 6_000,
					trailingPE: 25,
					fiftyTwoWeekLow: 90,
					fiftyTwoWeekHigh: 140,
				},
			}),
		};

		await expect(loadReportStockData("AAPL", provider)).resolves.toEqual({
			shortName: "Example",
			longName: "Example Corporation",
			regularMarketPrice: 125,
			regularMarketChange: 2,
			regularMarketChangePercent: 1.6,
			marketCap: 5_000,
			peRatio: 25,
			sector: "Technology",
			industry: "Software",
			beta: 1.2,
			fiftyTwoWeekLow: 90,
			fiftyTwoWeekHigh: 140,
			revenueGrowth: 0.1,
			netProfitMargins: 0.2,
			returnOnEquity: 0.3,
			debtToEquity: 40,
		});
		expect(provider.quote).toHaveBeenCalledWith("AAPL");
		expect(provider.quoteSummary).toHaveBeenCalledWith("AAPL", {
			modules: ["defaultKeyStatistics", "financialData", "summaryDetail", "assetProfile"],
		});
	});

	test("falls back to summary market capitalization", async () => {
		const provider = {
			quote: vi.fn().mockResolvedValue({ symbol: "MSFT" }),
			quoteSummary: vi.fn().mockResolvedValue({ summaryDetail: { marketCap: 9_000 } }),
		};

		await expect(loadReportStockData("MSFT", provider)).resolves.toMatchObject({
			marketCap: 9_000,
		});
	});

	test("returns null when the provider is unavailable", async () => {
		const warning = vi.spyOn(console, "warn").mockImplementation(() => undefined);
		const provider = {
			quote: vi.fn().mockRejectedValue(new Error("provider unavailable")),
			quoteSummary: vi.fn().mockResolvedValue({}),
		};

		await expect(loadReportStockData("NVDA", provider)).resolves.toBeNull();
		expect(warning).toHaveBeenCalledWith(expect.stringContaining("report.stock_data_unavailable"));
	});

	test("returns null when summary retrieval fails", async () => {
		const warning = vi.spyOn(console, "warn").mockImplementation(() => undefined);
		const provider = {
			quote: vi.fn().mockResolvedValue({ symbol: "TSLA" }),
			quoteSummary: vi.fn().mockRejectedValue(new Error("summary unavailable")),
		};

		await expect(loadReportStockData("TSLA", provider)).resolves.toBeNull();
		expect(warning).toHaveBeenCalledWith(expect.stringContaining('"symbol":"TSLA"'));
	});
});
