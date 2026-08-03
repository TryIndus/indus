import { getCachedExplanation } from "@/hooks/useExplanation";
import type { FinancialData, MetricGroups, PageChartData, PageContext } from "@/lib/types";

const CONTEXT_METRIC_KEYS = [
	"market_cap",
	"enterprise_value",
	"shares_outstanding",
	"revenue",
	"employees",
	"pe_ratio",
	"forward_pe",
	"price_to_book",
	"price_to_sales",
	"ev_to_sales",
	"ev_to_ebitda",
	"gross_margin",
	"ebitda_margin",
	"operating_margin",
	"net_margin",
] as const;
const MAX_EXPLANATION_LENGTH = 280;
const MAX_CONTEXT_SIZE_KB = 25;

interface BuildContextParams {
	financialData: FinancialData;
	chartData?: PageChartData;
	triggerMetric: {
		metricKey: string;
		metricLabel: string;
		value: number | string;
	};
}

export function buildPageContext({
	financialData,
	chartData,
	triggerMetric,
}: BuildContextParams): PageContext {
	const metricGroups: MetricGroups = {
		companyProfile: {
			marketCap: financialData.marketCap,
			enterpriseValue: financialData.enterpriseValue,
			sharesOutstanding: financialData.sharesOutstanding,
			revenue: financialData.revenue,
			employees: financialData.employees,
		},
		margins: {
			grossMargin: financialData.grossMargins,
			ebitdaMargin: financialData.ebitdaMargins,
			operatingMargin: financialData.operatingMargins,
			netMargin: financialData.netProfitMargins,
			roa: financialData.returnOnAssets,
			roe: financialData.returnOnEquity,
		},
		valuation: {
			peRatio: financialData.peRatio,
			forwardPE: financialData.forwardPE,
			pbRatio: financialData.priceToBook,
			psRatio: financialData.priceToSales,
			evToSales: financialData.evToSales,
			evToEbitda: financialData.evToEbitda,
			pegRatio: financialData.pegRatio,
		},
		growth: {
			revenueGrowth: financialData.revenueGrowth,
			earningsGrowth: financialData.earningsGrowth,
			beta: financialData.beta,
		},
		financialHealth: {
			totalCash: financialData.totalCash,
			totalDebt: financialData.totalDebt,
			debtToEquity: financialData.debtToEquity,
		},
		dividends: {
			dividendYield: financialData.dividendYield,
			dividendRate: financialData.dividendRate,
			payoutRatio: financialData.payoutRatio,
		},
	};

	const cachedExplanations: Record<string, string> = {};

	for (const metricKey of CONTEXT_METRIC_KEYS) {
		const cached = getCachedExplanation(financialData.symbol, metricKey);
		if (cached) {
			cachedExplanations[metricKey] =
				cached.length > MAX_EXPLANATION_LENGTH
					? `${cached.substring(0, MAX_EXPLANATION_LENGTH)}...`
					: cached;
		}
	}

	const chart = chartData?.points
		? {
				interval: chartData.interval ?? "1d",
				points: chartData.points.slice(-50).map((point) => ({
					t: point.t,
					o: point.o,
					h: point.h,
					l: point.l,
					c: point.c,
					v: point.v,
				})),
				latestPrice: chartData.latestPrice ?? financialData.regularMarketPrice ?? 0,
				dayChangePct: chartData.dayChangePct ?? financialData.regularMarketChangePercent ?? 0,
			}
		: undefined;

	return {
		symbol: financialData.symbol,
		companyName: financialData.longName ?? financialData.shortName ?? financialData.symbol,
		asOf: new Date().toISOString(),
		metricGroups,
		chart,
		cachedExplanations,
		trigger: triggerMetric,
	};
}

export function trimContextIfNeeded(context: PageContext): PageContext {
	const sizeKB = new TextEncoder().encode(JSON.stringify(context)).byteLength / 1024;

	if (sizeKB > MAX_CONTEXT_SIZE_KB) {
		const explanationEntries = Object.entries(context.cachedExplanations);
		const trimmedExplanations: Record<string, string> = {};

		for (let i = 0; i < Math.min(10, explanationEntries.length); i++) {
			const [key, value] = explanationEntries[i];
			trimmedExplanations[key] = value.length > 200 ? `${value.substring(0, 200)}...` : value;
		}

		return {
			...context,
			cachedExplanations: trimmedExplanations,
			chart: context.chart
				? {
						...context.chart,
						points: context.chart.points.slice(-30),
					}
				: undefined,
		};
	}

	return context;
}
