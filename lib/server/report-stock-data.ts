import YahooFinance from "yahoo-finance2";
import { logger } from "@/lib/observability/logger";
import type { ReportStockData } from "@/lib/types";

interface ReportQuote {
	symbol: string;
	shortName?: string;
	longName?: string;
	regularMarketPrice?: number;
	regularMarketChange?: number;
	regularMarketChangePercent?: number;
	marketCap?: number;
}

interface ReportStockDataProvider {
	quote(symbol: string): Promise<ReportQuote>;
	quoteSummary(
		symbol: string,
		options: { modules: string[] },
	): Promise<{
		assetProfile?: { sector?: string; industry?: string };
		defaultKeyStatistics?: { beta?: number };
		financialData?: {
			revenueGrowth?: number;
			profitMargins?: number;
			returnOnEquity?: number;
			debtToEquity?: number;
		};
		summaryDetail?: {
			marketCap?: number;
			trailingPE?: number;
			fiftyTwoWeekLow?: number;
			fiftyTwoWeekHigh?: number;
		};
	}>;
}

const yahooFinance = new YahooFinance({ suppressNotices: ["yahooSurvey"] });
const defaultProvider: ReportStockDataProvider = {
	quote: async (symbol) => (await yahooFinance.quote(symbol)) as unknown as ReportQuote,
	quoteSummary: (symbol, options) =>
		yahooFinance.quoteSummary(symbol, {
			modules: options.modules as (
				| "assetProfile"
				| "defaultKeyStatistics"
				| "financialData"
				| "summaryDetail"
			)[],
		}),
};

export async function loadReportStockData(
	symbol: string,
	provider: ReportStockDataProvider = defaultProvider,
): Promise<ReportStockData | null> {
	try {
		const [quote, summary] = await Promise.all([
			provider.quote(symbol),
			provider.quoteSummary(symbol, {
				modules: ["defaultKeyStatistics", "financialData", "summaryDetail", "assetProfile"],
			}),
		]);

		return {
			shortName: quote.shortName,
			longName: quote.longName,
			regularMarketPrice: quote.regularMarketPrice,
			regularMarketChange: quote.regularMarketChange,
			regularMarketChangePercent: quote.regularMarketChangePercent,
			marketCap: quote.marketCap ?? summary.summaryDetail?.marketCap,
			peRatio: summary.summaryDetail?.trailingPE,
			sector: summary.assetProfile?.sector,
			industry: summary.assetProfile?.industry,
			beta: summary.defaultKeyStatistics?.beta,
			fiftyTwoWeekLow: summary.summaryDetail?.fiftyTwoWeekLow,
			fiftyTwoWeekHigh: summary.summaryDetail?.fiftyTwoWeekHigh,
			revenueGrowth: summary.financialData?.revenueGrowth,
			netProfitMargins: summary.financialData?.profitMargins,
			returnOnEquity: summary.financialData?.returnOnEquity,
			debtToEquity: summary.financialData?.debtToEquity,
		};
	} catch (error) {
		logger.warn("report.stock_data_unavailable", {
			symbol,
			errorMessage: error instanceof Error ? error.message : String(error),
		});
		return null;
	}
}
