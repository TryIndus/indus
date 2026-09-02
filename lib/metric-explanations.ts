import type { Item } from "@/lib/prompts";
import { valueAnalysisSchema } from "@/lib/schemas/api";
import type { ValueAnalysis } from "@/lib/types";

export const DEFAULT_EXPLANATION = "No explanation available.";

const EVALUATIONS = new Set(["green", "red", "neutral", "amber"]);

function isRecord(value: unknown): value is Record<string, unknown> {
	return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function parseJson(value: string): unknown {
	try {
		return JSON.parse(value);
	} catch {
		return null;
	}
}

export function parseValueAnalysis(value: unknown): ValueAnalysis | null {
	const candidate = typeof value === "string" ? parseJson(value) : value;
	if (!isRecord(candidate)) return null;

	if (typeof candidate.metric_display === "string" && typeof candidate.insight === "string") {
		const evaluation =
			typeof candidate.evaluation === "string" && EVALUATIONS.has(candidate.evaluation)
				? candidate.evaluation
				: "neutral";
		const parsed = valueAnalysisSchema.safeParse({
			metric_display: candidate.metric_display,
			insight: candidate.insight,
			evaluation,
		});
		return parsed.success ? parsed.data : null;
	}

	for (const key of Object.keys(candidate).sort((left, right) => Number(left) - Number(right))) {
		if (!/^\d+$/.test(key)) continue;
		const nested = parseValueAnalysis(candidate[key]);
		if (nested) return nested;
	}

	return null;
}

export function normalizeMetricExplanation(value: unknown): string | null {
	const structured = parseValueAnalysis(value);
	if (structured) return JSON.stringify(structured);
	if (typeof value !== "string") return null;

	const text = value.trim();
	if (!text || text.length > 1_200 || /^[{[]/.test(text)) return null;
	return text;
}

function extractJsonText(rawText: string): string {
	const fenced = rawText.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
	if (fenced?.[1]) return fenced[1];
	const object = rawText.match(/\{[\s\S]*\}/);
	return object?.[0] ?? rawText;
}

function explanationKey(item: Item): string {
	return `${item.symbol}_${item.metric}`;
}

export function parseMetricExplanationResponse(
	rawText: string,
	items: Item[],
): Record<string, string> {
	const parsed = parseJson(extractJsonText(rawText));
	if (isRecord(parsed)) {
		return Object.fromEntries(
			items.map((item, index) => {
				const value = parsed[String(index + 1)] ?? (items.length === 1 ? parsed : null);
				return [explanationKey(item), normalizeMetricExplanation(value) ?? DEFAULT_EXPLANATION];
			}),
		);
	}

	const lines = rawText
		.split(/\n+/)
		.map((line) => line.trim().match(/^\d+[.)]\s*(.+)$/)?.[1])
		.filter((line): line is string => Boolean(line));

	return Object.fromEntries(
		items.map((item, index) => [
			explanationKey(item),
			normalizeMetricExplanation(lines[index]) ?? DEFAULT_EXPLANATION,
		]),
	);
}
