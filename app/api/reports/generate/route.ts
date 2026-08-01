import { GoogleGenerativeAI } from "@google/generative-ai";
import { NextResponse } from "next/server";
import type { z } from "zod/v4";
import { env } from "@/lib/env";
import { logger } from "@/lib/observability/logger";
import { generateReportSchema, reportStockDataResponseSchema } from "@/lib/schemas/api";
import { type AiAccessClient, checkAiAccess, getAiQuotaHeaders } from "@/lib/security/ai-access";
import { createClient } from "@/lib/supabase/server";

const genAI = new GoogleGenerativeAI(env.GEMINI_API_KEY);
type ReportStockData = z.infer<typeof reportStockDataResponseSchema>["data"];

async function fetchStockData(requestUrl: string, symbol: string): Promise<ReportStockData | null> {
	try {
		const url = new URL("/api/stock-data", requestUrl);
		url.searchParams.set("symbol", symbol);
		const response = await fetch(url);
		if (!response.ok) {
			return null;
		}

		const parsed = reportStockDataResponseSchema.safeParse(await response.json());
		return parsed.success ? parsed.data.data : null;
	} catch (error) {
		logger.warn("report.stock_data_unavailable", {
			symbol,
			errorMessage: error instanceof Error ? error.message : String(error),
		});
		return null;
	}
}

export async function POST(request: Request) {
	try {
		const body = await request.json().catch(() => null);
		const parsed = generateReportSchema.safeParse(body);

		if (!parsed.success) {
			return NextResponse.json({ error: "Symbol is required" }, { status: 400 });
		}

		const { symbol } = parsed.data;

		const supabase = await createClient();
		const access = await checkAiAccess(supabase as unknown as AiAccessClient, "generate-report");
		if (!access.allowed) {
			return NextResponse.json(
				{ error: access.error },
				{ status: access.status, headers: getAiQuotaHeaders(access) },
			);
		}

		const stockData = await fetchStockData(request.url, symbol);

		const { data: report, error: insertError } = await supabase
			.from("reports")
			.insert({
				user_id: access.userId,
				symbol: symbol.toUpperCase(),
				company_name: stockData?.longName || stockData?.shortName || symbol,
				status: "generating",
				summary: `Research report for ${symbol.toUpperCase()}`,
				report_content: "",
			})
			.select()
			.single();

		if (insertError) {
			logger.error("report.create_failed", insertError, { symbol, userId: access.userId });
			return NextResponse.json({ error: "Failed to create report" }, { status: 500 });
		}

		void generateReportContent(report.id, symbol, stockData);

		return NextResponse.json(
			{
				report,
				message: "Report generation started",
			},
			{ headers: getAiQuotaHeaders(access) },
		);
	} catch (error) {
		logger.error("report.request_failed", error);
		return NextResponse.json({ error: "Internal server error" }, { status: 500 });
	}
}

async function generateReportContent(
	reportId: string,
	symbol: string,
	stockData: ReportStockData | null,
): Promise<void> {
	try {
		const supabase = await createClient();

		const prompt = `
Generate a comprehensive, professional research report for ${symbol.toUpperCase()}. Use proper markdown formatting for structure and readability.

${
	stockData
		? `
**Company Financial Data:**
- Company: ${stockData.longName || stockData.shortName}
- Current Price: $${stockData.regularMarketPrice}
- Price Change: ${stockData.regularMarketChange} (${stockData.regularMarketChangePercent}%)
- Market Cap: ${stockData.marketCap ? `$${(stockData.marketCap / 1e9).toFixed(2)}B` : "N/A"}
- P/E Ratio: ${stockData.peRatio || "N/A"}
- Sector: ${stockData.sector || "N/A"}
- Industry: ${stockData.industry || "N/A"}
- Beta: ${stockData.beta || "N/A"}
- 52-Week Range: $${stockData.fiftyTwoWeekLow || "N/A"} - $${stockData.fiftyTwoWeekHigh || "N/A"}
- Revenue Growth: ${stockData.revenueGrowth ? `${(stockData.revenueGrowth * 100).toFixed(2)}%` : "N/A"}
- Profit Margins: ${stockData.netProfitMargins ? `${(stockData.netProfitMargins * 100).toFixed(2)}%` : "N/A"}
- Return on Equity: ${stockData.returnOnEquity ? `${(stockData.returnOnEquity * 100).toFixed(2)}%` : "N/A"}
- Debt to Equity: ${stockData.debtToEquity || "N/A"}
`
		: "Note: Limited financial data available for analysis."
}

**FORMATTING REQUIREMENTS:**
- Use ## for main section headers (e.g., ## Executive Summary)
- Use ### for subsection headers
- Use **text** for important terms and emphasis
- Use *text* for light emphasis
- Keep paragraphs concise and readable
- Include specific numbers and percentages where relevant
- Write in professional, analytical tone

Please provide a comprehensive research report with exactly these sections:

## Executive Summary

Provide a 2-3 paragraph executive summary covering the investment thesis, key highlights, and overall recommendation for ${symbol.toUpperCase()}.

## Company Overview

### Business Model and Operations
Describe the company's core business, revenue streams, and operational structure.

### Market Position and Competitive Landscape
Analyze the company's position within its industry and key competitive advantages.

### Recent Developments
Cover any significant recent news, product launches, or strategic initiatives.

## Financial Analysis

### Revenue and Profitability Analysis
Examine recent financial performance, revenue trends, and profit margins.

### Valuation Metrics
Analyze key valuation ratios including P/E, P/B, EV/EBITDA and compare to industry averages.

### Balance Sheet Strength
Assess financial health, debt levels, cash position, and working capital.

### Growth Prospects
Evaluate revenue growth potential, expansion opportunities, and market outlook.

## Technical Analysis

### Price Performance and Trends
Analyze recent price action, trend direction, and momentum indicators.

### Support and Resistance Levels
Identify key technical levels and trading patterns.

## Risk Assessment

### Company-Specific Risks
Identify operational, competitive, and execution risks specific to the company.

### Market and Industry Risks
Evaluate broader market conditions and industry-specific challenges.

### Regulatory and Economic Risks
Assess potential regulatory changes and macroeconomic impacts.

## Investment Recommendation

### Investment Thesis
Summarize the key reasons to invest or avoid this stock.

### Price Target and Rating
Provide a specific price target with 12-month timeframe and Buy/Hold/Sell rating.

### Portfolio Considerations
Discuss appropriate position sizing and investment timeframe.

**IMPORTANT:** Write approximately 1,800-2,200 words total. Use data-driven analysis based on the provided financial metrics. Include specific numbers, percentages, and concrete examples. End with appropriate investment disclaimers.

Write the report now:`;

		const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

		const result = await model.generateContent(prompt);
		const reportContent = result.response.text();

		const lines = reportContent.split("\n");
		const execSummaryIndex = lines.findIndex((line: string) =>
			line.toLowerCase().includes("executive summary"),
		);

		let summary = `Research report for ${symbol.toUpperCase()}`;
		if (execSummaryIndex !== -1) {
			const summaryLines = lines
				.slice(execSummaryIndex + 1, execSummaryIndex + 4)
				.filter((line: string) => line.trim() && !line.includes("*"))
				.join(" ");
			if (summaryLines.length > 20) {
				summary = `${summaryLines.substring(0, 150)}...`;
			}
		}

		const { error: updateError } = await supabase
			.from("reports")
			.update({
				report_content: reportContent,
				summary: summary,
				status: "completed",
			})
			.eq("id", reportId);

		if (updateError) {
			logger.error("report.update_failed", updateError, { reportId, symbol });
			await supabase.from("reports").update({ status: "error" }).eq("id", reportId);
		}
	} catch (error) {
		logger.error("report.generation_failed", error, { reportId, symbol });
		const supabase = await createClient();
		await supabase.from("reports").update({ status: "error" }).eq("id", reportId);
	}
}
