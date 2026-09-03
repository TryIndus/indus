import { describe, expect, it } from "vitest";
import { isCompleteReportContent } from "@/lib/report-content";
import {
	parseReportDocumentContent,
	reportDocumentSchema,
	serializeReportDocument,
} from "@/lib/report-document";

const document = {
	version: 1 as const,
	executiveSummary:
		"The supplied snapshot contains a current price and selected company metrics for review.",
	financialSnapshot: [
		{ label: "Market capitalization", value: "$4.75T", analysis: "The supplied company value." },
	],
	dataLimitations: ["No peer or historical comparison was supplied."],
};

describe("report document", () => {
	it("round-trips a bounded structured document", () => {
		const content = serializeReportDocument(document);
		expect(parseReportDocumentContent(content)).toEqual(document);
		expect(isCompleteReportContent(content)).toBe(true);
	});

	it("rejects missing sections, extra fields, and presentation markup objects", () => {
		expect(parseReportDocumentContent('{"version":1}')).toBeNull();
		expect(reportDocumentSchema.safeParse({ ...document, markdown: "## heading" }).success).toBe(
			false,
		);
	});

	it("keeps complete legacy reports readable during migration", () => {
		const legacy =
			"## Executive Summary\nSummary\n## Available Financial Snapshot\nData\n## Data Limitations\nLimit\nThis report is educational and is not investment advice.";
		expect(isCompleteReportContent(legacy)).toBe(true);
	});
});
