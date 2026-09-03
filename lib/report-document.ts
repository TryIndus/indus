import { z } from "zod/v4";

export const reportDocumentSchema = z
	.object({
		version: z.literal(1),
		executiveSummary: z.string().trim().min(80).max(3_000),
		financialSnapshot: z
			.array(
				z
					.object({
						label: z.string().trim().min(1).max(80),
						value: z.string().trim().min(1).max(120),
						analysis: z.string().trim().min(1).max(600),
					})
					.strict(),
			)
			.min(1)
			.max(12),
		dataLimitations: z.array(z.string().trim().min(1).max(500)).min(1).max(8),
	})
	.strict();

export type ReportDocument = z.infer<typeof reportDocumentSchema>;

export const REPORT_DOCUMENT_JSON_SCHEMA = {
	type: "object",
	properties: {
		version: { type: "integer", enum: [1] },
		executiveSummary: {
			type: "string",
			description: "A concise, neutral summary based only on the supplied snapshot.",
		},
		financialSnapshot: {
			type: "array",
			items: {
				type: "object",
				properties: {
					label: { type: "string", description: "A human-readable metric name." },
					value: { type: "string", description: "The exact supplied value with its unit." },
					analysis: {
						type: "string",
						description: "What the metric measures and what follows from the supplied data.",
					},
				},
				required: ["label", "value", "analysis"],
				additionalProperties: false,
			},
		},
		dataLimitations: {
			type: "array",
			items: { type: "string" },
			description: "Material limits in the supplied data that constrain interpretation.",
		},
	},
	required: ["version", "executiveSummary", "financialSnapshot", "dataLimitations"],
	additionalProperties: false,
} as const;

export function parseReportDocumentContent(content: string): ReportDocument | null {
	try {
		return reportDocumentSchema.parse(JSON.parse(content));
	} catch {
		return null;
	}
}

export function serializeReportDocument(document: ReportDocument): string {
	return JSON.stringify(reportDocumentSchema.parse(document));
}
