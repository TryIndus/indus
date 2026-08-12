import { NextResponse } from "next/server";
import { GeminiClient, getGeminiResponseStatus } from "@/lib/ai/geminiClient";
import { env } from "@/lib/env";
import { logger } from "@/lib/observability/logger";
import { finishRequestLog, getRequestHeaders, startRequestLog } from "@/lib/observability/request";
import { type Item, makeBatchPrompt } from "@/lib/prompts";
import { batchExplainSchema, valueAnalysisSchema } from "@/lib/schemas/api";
import { type AiAccessClient, checkAiAccess, getAiQuotaHeaders } from "@/lib/security/ai-access";
import { createClient } from "@/lib/supabase/server";
import { VALUE_ANALYSIS_SYSTEM_PROMPT } from "@/lib/system-prompts";

export const runtime = "nodejs";
export const maxDuration = 60;

const DEFAULT_EXPLANATION = "No explanation available.";

function explanationKey(item: Item): string {
	return `${item.symbol}_${item.metric}`;
}

function parseStructuredExplanations(
	rawText: string,
	items: Item[],
): Record<string, string> | null {
	const jsonMatch = rawText.match(/```json\s*([\s\S]*?)\s*```/) ?? rawText.match(/\{[\s\S]*\}/);
	const jsonText = jsonMatch?.[1] ?? jsonMatch?.[0] ?? rawText;

	try {
		const parsed: unknown = JSON.parse(jsonText);
		if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
			return null;
		}

		return Object.fromEntries(
			items.map((item, index) => {
				const explanation = (parsed as Record<string, unknown>)[String(index + 1)];
				const validated = valueAnalysisSchema.safeParse(explanation);
				return [
					explanationKey(item),
					validated.success ? JSON.stringify(validated.data) : DEFAULT_EXPLANATION,
				];
			}),
		);
	} catch {
		return null;
	}
}

function parseTextExplanations(rawText: string, items: Item[]): Record<string, string> {
	const numberedExplanations = rawText
		.split(/\n+/)
		.map((line) => line.trim().match(/^\d+\.\s*(.+)$/)?.[1])
		.filter((line): line is string => Boolean(line));
	const explanations =
		numberedExplanations.length > 0
			? numberedExplanations
			: rawText.split(/(?:\n\s*[-•*]\s*|\n\s*\d+\.\s*)/).filter(Boolean);

	return Object.fromEntries(
		items.map((item, index) => [explanationKey(item), explanations[index] ?? DEFAULT_EXPLANATION]),
	);
}

export async function POST(req: Request) {
	const requestLog = startRequestLog(req, "/api/batch-explain");
	try {
		const body = await req.json().catch(() => null);
		const parsed = batchExplainSchema.safeParse(body);

		if (!parsed.success) {
			finishRequestLog(requestLog, 400);
			return NextResponse.json(
				{ error: "Invalid input." },
				{ status: 400, headers: getRequestHeaders(requestLog) },
			);
		}

		const supabase = await createClient();
		const access = await checkAiAccess(supabase as unknown as AiAccessClient, "batch-explain");
		if (!access.allowed) {
			finishRequestLog(requestLog, access.status);
			return NextResponse.json(
				{ error: access.error },
				{
					status: access.status,
					headers: { ...getRequestHeaders(requestLog), ...getAiQuotaHeaders(access) },
				},
			);
		}

		const items: Item[] = parsed.data;
		const prompt = makeBatchPrompt(items);
		const geminiClient = new GeminiClient(env.GEMINI_API_KEY);
		const rawText = await geminiClient.generateContent(
			[
				{ role: "system", parts: [{ text: VALUE_ANALYSIS_SYSTEM_PROMPT }] },
				{ role: "user", parts: [{ text: prompt }] },
			],
			{ responseMimeType: "application/json", temperature: 0.2 },
			{ signal: req.signal, requestId: requestLog.requestId },
		);
		const explanations =
			parseStructuredExplanations(rawText, items) ?? parseTextExplanations(rawText, items);
		finishRequestLog(requestLog, 200, { itemCount: items.length });
		return NextResponse.json(
			{ explanations },
			{
				headers: {
					"Cache-Control": "private, no-store",
					...getRequestHeaders(requestLog),
					...getAiQuotaHeaders(access),
				},
			},
		);
	} catch (error) {
		logger.error("batch_explain.request_failed", error, { requestId: requestLog.requestId });
		const status = getGeminiResponseStatus(error);
		const message =
			status === 429
				? "The explanation service is temporarily rate limited."
				: "Unable to generate explanations.";
		finishRequestLog(requestLog, status);
		return NextResponse.json(
			{ error: message },
			{ status, headers: getRequestHeaders(requestLog) },
		);
	}
}
