import { NextResponse } from "next/server";
import { env } from "@/lib/env";
import { logger } from "@/lib/observability/logger";
import { type Item, makeBatchPrompt } from "@/lib/prompts";
import {
	batchExplainSchema,
	geminiTextResponseSchema,
	valueAnalysisSchema,
} from "@/lib/schemas/api";
import { type AiAccessClient, checkAiAccess, getAiQuotaHeaders } from "@/lib/security/ai-access";
import { createClient } from "@/lib/supabase/server";
import { VALUE_ANALYSIS_SYSTEM_PROMPT } from "@/lib/system-prompts";

const GEMINI_API_URL =
	"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";
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
	try {
		const body = await req.json().catch(() => null);
		const parsed = batchExplainSchema.safeParse(body);

		if (!parsed.success) {
			return NextResponse.json({ error: "Invalid input." }, { status: 400 });
		}

		const supabase = await createClient();
		const access = await checkAiAccess(supabase as unknown as AiAccessClient, "batch-explain");
		if (!access.allowed) {
			return NextResponse.json(
				{ error: access.error },
				{ status: access.status, headers: getAiQuotaHeaders(access) },
			);
		}

		const items: Item[] = parsed.data;
		const prompt = makeBatchPrompt(items);
		const fullPrompt = `${VALUE_ANALYSIS_SYSTEM_PROMPT}\n\n${prompt}`;
		const res = await fetch(`${GEMINI_API_URL}?key=${env.GEMINI_API_KEY}`, {
			method: "POST",
			headers: {
				"Content-Type": "application/json",
			},
			body: JSON.stringify({
				contents: [{ parts: [{ text: fullPrompt }] }],
				generationConfig: {
					responseMimeType: "application/json",
					temperature: 0.2,
				},
			}),
		});

		if (!res.ok) {
			logger.error("batch_explain.provider_failed", new Error(res.statusText), {
				status: res.status,
				itemCount: items.length,
			});

			if (res.status === 429) {
				return NextResponse.json(
					{ error: "The explanation service is temporarily rate limited." },
					{ status: 429 },
				);
			}

			return NextResponse.json({ error: "Unable to generate explanations." }, { status: 502 });
		}

		const providerResponse = geminiTextResponseSchema.safeParse(await res.json());
		if (!providerResponse.success) {
			logger.error("batch_explain.invalid_provider_response", providerResponse.error, {
				itemCount: items.length,
			});
			return NextResponse.json({ error: "Unable to generate explanations." }, { status: 502 });
		}

		const rawText = providerResponse.data.candidates[0].content.parts[0].text;
		const explanations =
			parseStructuredExplanations(rawText, items) ?? parseTextExplanations(rawText, items);
		return NextResponse.json({ explanations }, { headers: getAiQuotaHeaders(access) });
	} catch (error) {
		logger.error("batch_explain.request_failed", error);
		return NextResponse.json({ error: "Server error." }, { status: 500 });
	}
}
