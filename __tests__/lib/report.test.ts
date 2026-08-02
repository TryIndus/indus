import { describe, expect, test } from "vitest";
import { createReportMessages, extractReportSummary } from "@/lib/ai/report";

describe("createReportMessages", () => {
	test("prohibits unsupported research claims", () => {
		const messages = createReportMessages("AAPL", {
			longName: "Apple Inc.",
			regularMarketPrice: 200,
			marketCap: 3_000_000_000_000,
		});
		const systemInstruction = messages[0].parts[0].text;

		expect(systemInstruction).toContain("Use only facts present");
		expect(systemInstruction).toContain("price targets");
		expect(systemInstruction).toContain("investment recommendations");
		expect(messages[1].parts[0].text).toContain('"regularMarketPrice":200');
	});

	test("marks a missing provider snapshot as unavailable", () => {
		const messages = createReportMessages("MSFT", null);
		expect(messages[1].parts[0].text).toContain('"unavailable":true');
	});
});

describe("extractReportSummary", () => {
	test("extracts and bounds the executive summary", () => {
		const summary = extractReportSummary(
			`## Executive Summary\n${"A".repeat(180)}\n## Available Financial Snapshot\nDetails`,
			"AAPL",
		);

		expect(summary).toHaveLength(160);
		expect(summary.endsWith("...")).toBe(true);
	});
});
