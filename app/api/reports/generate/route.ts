import { NextResponse } from "next/server";
import { GeminiApiError, GeminiClient } from "@/lib/ai/geminiClient";
import { createReportMessages, extractReportSummary } from "@/lib/ai/report";
import { env } from "@/lib/env";
import { logger } from "@/lib/observability/logger";
import { generateReportSchema } from "@/lib/schemas/api";
import { type AiAccessClient, checkAiAccess, getAiQuotaHeaders } from "@/lib/security/ai-access";
import { loadReportStockData } from "@/lib/server/report-stock-data";
import { createClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
	let reportId: string | null = null;
	let reportUserId: string | null = null;
	let supabase: Awaited<ReturnType<typeof createClient>> | null = null;

	try {
		const body = await request.json().catch(() => null);
		const parsed = generateReportSchema.safeParse(body);
		if (!parsed.success) {
			return NextResponse.json({ error: "Symbol is required" }, { status: 400 });
		}

		const { symbol } = parsed.data;
		supabase = await createClient();
		const access = await checkAiAccess(supabase as unknown as AiAccessClient, "generate-report");
		if (!access.allowed) {
			return NextResponse.json(
				{ error: access.error },
				{ status: access.status, headers: getAiQuotaHeaders(access) },
			);
		}

		reportUserId = access.userId;
		const stockData = await loadReportStockData(symbol);
		const { data: report, error: insertError } = await supabase
			.from("reports")
			.insert({
				user_id: access.userId,
				symbol,
				company_name: stockData?.longName || stockData?.shortName || symbol,
				status: "generating",
				summary: `Financial snapshot for ${symbol}`,
				report_content: "",
			})
			.select()
			.single();

		if (insertError) {
			logger.error("report.create_failed", insertError, { symbol, userId: access.userId });
			return NextResponse.json({ error: "Failed to create report" }, { status: 500 });
		}

		reportId = report.id;
		const geminiClient = new GeminiClient(env.GEMINI_API_KEY);
		const reportContent = await geminiClient.generateContent(
			createReportMessages(symbol, stockData),
		);
		const summary = extractReportSummary(reportContent, symbol);

		const { data: completedReport, error: updateError } = await supabase
			.from("reports")
			.update({ report_content: reportContent, summary, status: "completed" })
			.eq("id", report.id)
			.eq("user_id", access.userId)
			.select()
			.single();

		if (updateError) {
			throw updateError;
		}

		return NextResponse.json(
			{ report: completedReport, message: "Report generation completed" },
			{ headers: getAiQuotaHeaders(access) },
		);
	} catch (error) {
		logger.error("report.generation_failed", error, { reportId });
		if (supabase && reportId && reportUserId) {
			await supabase
				.from("reports")
				.update({ status: "error" })
				.eq("id", reportId)
				.eq("user_id", reportUserId);
		}

		const status = error instanceof GeminiApiError && error.status === 429 ? 429 : 502;
		return NextResponse.json({ error: "Unable to generate report" }, { status });
	}
}
