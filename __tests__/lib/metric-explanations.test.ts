import { describe, expect, it } from "vitest";
import {
	DEFAULT_EXPLANATION,
	normalizeMetricExplanation,
	parseMetricExplanationResponse,
	parseValueAnalysis,
} from "@/lib/metric-explanations";

const item = { symbol: "AAPL", metric: "market_cap", value: 4_750_000_000_000 };

describe("metric explanations", () => {
	it("unwraps numbered provider JSON instead of exposing the wrapper", () => {
		const raw = JSON.stringify({
			1: {
				metric_display: "market capitalization: $4.75T",
				insight: "Market capitalization measures the value of outstanding shares.",
				evaluation: "neutral",
			},
		});

		const explanation = parseMetricExplanationResponse(raw, [item]).AAPL_market_cap;
		expect(parseValueAnalysis(explanation)).toMatchObject({
			metric_display: "market capitalization: $4.75T",
			insight: "Market capitalization measures the value of outstanding shares.",
		});
		expect(explanation).not.toContain('"1"');
	});

	it("accepts useful structured fields while discarding provider extras", () => {
		const explanation = normalizeMetricExplanation({
			metric_display: "P/E: 31",
			insight: "Investors pay 31 times current earnings.",
			evaluation: "neutral",
			provider_note: "do not render",
		});

		expect(parseValueAnalysis(explanation)).toEqual({
			metric_display: "P/E: 31",
			insight: "Investors pay 31 times current earnings.",
			evaluation: "neutral",
		});
	});

	it("fails closed instead of rendering malformed JSON as prose", () => {
		const result = parseMetricExplanationResponse('{"1":{"metric_display":"truncated"}}', [item]);
		expect(result.AAPL_market_cap).toBe(DEFAULT_EXPLANATION);
		expect(normalizeMetricExplanation('{"1":{"metric_display":"truncated"}}')).toBeNull();
	});
});
