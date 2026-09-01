import type { Item } from "@/lib/prompts";
import type { FinancialData } from "@/lib/types";

const EXPLANATION_METRICS = [
	["market_cap", "marketCap"],
	["enterprise_value", "enterpriseValue"],
	["shares_outstanding", "sharesOutstanding"],
	["revenue", "revenue"],
	["employees", "employees"],
	["pe_ratio", "peRatio"],
	["price_to_book", "priceToBook"],
	["ev_to_sales", "evToSales"],
	["ev_to_ebitda", "evToEbitda"],
	["forward_pe", "forwardPE"],
	["peg_ratio", "pegRatio"],
	["price_to_sales", "priceToSales"],
	["gross_margin", "grossMargins"],
	["ebitda_margin", "ebitdaMargins"],
	["operating_margin", "operatingMargins"],
	["net_margin", "netProfitMargins"],
	["roa", "returnOnAssets"],
	["roe", "returnOnEquity"],
	["total_cash", "totalCash"],
	["total_debt", "totalDebt"],
	["debt_to_equity", "debtToEquity"],
	["revenue_growth", "revenueGrowth"],
	["earnings_growth", "earningsGrowth"],
	["dividend_yield", "dividendYield"],
	["payout_ratio", "payoutRatio"],
	["beta", "beta"],
] as const satisfies ReadonlyArray<readonly [string, keyof FinancialData]>;

export function buildExplanationItems(data: FinancialData): Item[] {
	return EXPLANATION_METRICS.flatMap(([metric, field]) => {
		const value = data[field];
		return typeof value === "number" && Number.isFinite(value)
			? [{ symbol: data.symbol, metric, value }]
			: [];
	});
}
