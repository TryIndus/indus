import { describe, expect, it } from "vitest";
import { parseReportContent } from "@/lib/report-content";

describe("report content", () => {
	it("keeps adjacent headings, paragraphs, and lists as complete blocks", () => {
		expect(
			parseReportContent(
				"# AAPL Research Report\n## Overview\nApple produces consumer devices.\nRevenue remains durable.\n- Strong margins\n- Large cash balance\n## Risks\nDemand may slow.",
			),
		).toEqual([
			{ kind: "heading", level: 1, text: "AAPL Research Report" },
			{ kind: "heading", level: 2, text: "Overview" },
			{ kind: "paragraph", text: "Apple produces consumer devices. Revenue remains durable." },
			{ kind: "list", items: ["Strong margins", "Large cash balance"] },
			{ kind: "heading", level: 2, text: "Risks" },
			{ kind: "paragraph", text: "Demand may slow." },
		]);
	});
});
