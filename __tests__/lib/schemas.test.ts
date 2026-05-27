import { describe, expect, it } from "vitest";
import {
	alpacaQuerySchema,
	batchExplainSchema,
	contextChatSchema,
	generateReportSchema,
	metricDefinitionQuerySchema,
	reportIdSchema,
	stockDataQuerySchema,
	streamParamsSchema,
} from "@/lib/schemas/api";

describe("alpacaQuerySchema", () => {
	it("accepts minimal valid input (symbol only)", () => {
		const result = alpacaQuerySchema.safeParse({ symbol: "AAPL" });
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.type).toBe("stock");
			expect(result.data.timeframe).toBe("1Min");
			expect(result.data.limit).toBe(2000);
		}
	});

	it("accepts full valid input", () => {
		const result = alpacaQuerySchema.safeParse({
			symbol: "BTC/USD",
			type: "crypto",
			timeframe: "1Hour",
			limit: "500",
			start: "1700000000",
			end: "1700100000",
		});
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.type).toBe("crypto");
			expect(result.data.limit).toBe(500);
		}
	});

	it("rejects empty symbol", () => {
		const result = alpacaQuerySchema.safeParse({ symbol: "" });
		expect(result.success).toBe(false);
	});

	it("rejects missing symbol", () => {
		const result = alpacaQuerySchema.safeParse({});
		expect(result.success).toBe(false);
	});

	it("rejects invalid type", () => {
		const result = alpacaQuerySchema.safeParse({ symbol: "AAPL", type: "forex" });
		expect(result.success).toBe(false);
	});

	it("rejects invalid timeframe", () => {
		const result = alpacaQuerySchema.safeParse({ symbol: "AAPL", timeframe: "2Min" });
		expect(result.success).toBe(false);
	});

	it("rejects limit over 10000", () => {
		const result = alpacaQuerySchema.safeParse({ symbol: "AAPL", limit: "10001" });
		expect(result.success).toBe(false);
	});

	it("rejects negative limit", () => {
		const result = alpacaQuerySchema.safeParse({ symbol: "AAPL", limit: "-1" });
		expect(result.success).toBe(false);
	});

	it("coerces string limit to number", () => {
		const result = alpacaQuerySchema.safeParse({ symbol: "AAPL", limit: "100" });
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.limit).toBe(100);
		}
	});
});

describe("streamParamsSchema", () => {
	it("accepts a stock stream symbol", () => {
		const result = streamParamsSchema.safeParse({ symbol: "AAPL" });
		expect(result.success).toBe(true);
	});

	it("accepts a crypto stream symbol", () => {
		const result = streamParamsSchema.safeParse({ symbol: "BTC/USD" });
		expect(result.success).toBe(true);
	});

	it("rejects an empty stream symbol", () => {
		const result = streamParamsSchema.safeParse({ symbol: "" });
		expect(result.success).toBe(false);
	});
});

describe("batchExplainSchema", () => {
	it("accepts valid batch items", () => {
		const result = batchExplainSchema.safeParse([
			{ symbol: "AAPL", metric: "pe_ratio", value: 28.5 },
			{ symbol: "MSFT", metric: "market_cap", value: 2800000000000 },
		]);
		expect(result.success).toBe(true);
	});

	it("rejects empty array", () => {
		const result = batchExplainSchema.safeParse([]);
		expect(result.success).toBe(false);
	});

	it("rejects item with missing symbol", () => {
		const result = batchExplainSchema.safeParse([{ metric: "pe_ratio", value: 28.5 }]);
		expect(result.success).toBe(false);
	});

	it("rejects item with non-numeric value", () => {
		const result = batchExplainSchema.safeParse([
			{ symbol: "AAPL", metric: "pe_ratio", value: "high" },
		]);
		expect(result.success).toBe(false);
	});

	it("rejects non-array input", () => {
		const result = batchExplainSchema.safeParse({
			symbol: "AAPL",
			metric: "pe_ratio",
			value: 28.5,
		});
		expect(result.success).toBe(false);
	});
});

describe("contextChatSchema", () => {
	const validInput = {
		context: {
			symbol: "AAPL",
			companyName: "Apple Inc.",
			asOf: "2025-01-01",
			metricGroups: { valuation: { pe_ratio: 28.5 } },
			cachedExplanations: {},
			trigger: {
				metricKey: "pe_ratio",
				metricLabel: "P/E Ratio",
				value: 28.5,
			},
		},
		messages: [],
		newMessage: "What does this P/E ratio mean?",
	};

	it("accepts valid input", () => {
		const result = contextChatSchema.safeParse(validInput);
		expect(result.success).toBe(true);
	});

	it("accepts input with optional chart data", () => {
		const result = contextChatSchema.safeParse({
			...validInput,
			context: {
				...validInput.context,
				chart: {
					interval: "1D",
					points: [{ time: 1700000000, close: 180 }],
					latestPrice: 180,
					dayChangePct: 1.5,
				},
			},
		});
		expect(result.success).toBe(true);
	});

	it("rejects empty newMessage", () => {
		const result = contextChatSchema.safeParse({ ...validInput, newMessage: "" });
		expect(result.success).toBe(false);
	});

	it("rejects missing context", () => {
		const { context, ...without } = validInput;
		const result = contextChatSchema.safeParse(without);
		expect(result.success).toBe(false);
	});

	it("rejects missing trigger in context", () => {
		const { trigger, ...contextWithout } = validInput.context;
		const result = contextChatSchema.safeParse({
			...validInput,
			context: contextWithout,
		});
		expect(result.success).toBe(false);
	});

	it("accepts trigger with string value", () => {
		const result = contextChatSchema.safeParse({
			...validInput,
			context: {
				...validInput.context,
				trigger: { metricKey: "sector", metricLabel: "Sector", value: "Technology" },
			},
		});
		expect(result.success).toBe(true);
	});

	it("accepts messages with valid shape", () => {
		const result = contextChatSchema.safeParse({
			...validInput,
			messages: [
				{
					id: "msg-1",
					role: "user",
					content: "Hello",
					createdAt: Date.now(),
				},
			],
		});
		expect(result.success).toBe(true);
	});
});

describe("metricDefinitionQuerySchema", () => {
	it("accepts valid metric name", () => {
		const result = metricDefinitionQuerySchema.safeParse({ metric: "pe_ratio" });
		expect(result.success).toBe(true);
	});

	it("rejects empty metric", () => {
		const result = metricDefinitionQuerySchema.safeParse({ metric: "" });
		expect(result.success).toBe(false);
	});

	it("rejects missing metric", () => {
		const result = metricDefinitionQuerySchema.safeParse({});
		expect(result.success).toBe(false);
	});
});

describe("stockDataQuerySchema", () => {
	it("accepts valid symbol", () => {
		const result = stockDataQuerySchema.safeParse({ symbol: "AAPL" });
		expect(result.success).toBe(true);
	});

	it("rejects empty symbol", () => {
		const result = stockDataQuerySchema.safeParse({ symbol: "" });
		expect(result.success).toBe(false);
	});

	it("rejects missing symbol", () => {
		const result = stockDataQuerySchema.safeParse({});
		expect(result.success).toBe(false);
	});
});

describe("generateReportSchema", () => {
	it("accepts valid symbol", () => {
		const result = generateReportSchema.safeParse({ symbol: "AAPL" });
		expect(result.success).toBe(true);
	});

	it("rejects empty symbol", () => {
		const result = generateReportSchema.safeParse({ symbol: "" });
		expect(result.success).toBe(false);
	});

	it("rejects extra fields but still passes (Zod strips)", () => {
		const result = generateReportSchema.safeParse({ symbol: "AAPL", extra: "field" });
		expect(result.success).toBe(true);
	});
});

describe("reportIdSchema", () => {
	it("accepts valid UUID", () => {
		const result = reportIdSchema.safeParse({ id: "550e8400-e29b-41d4-a716-446655440000" });
		expect(result.success).toBe(true);
	});

	it("rejects non-UUID string", () => {
		const result = reportIdSchema.safeParse({ id: "not-a-uuid" });
		expect(result.success).toBe(false);
	});

	it("rejects empty string", () => {
		const result = reportIdSchema.safeParse({ id: "" });
		expect(result.success).toBe(false);
	});

	it("rejects missing id", () => {
		const result = reportIdSchema.safeParse({});
		expect(result.success).toBe(false);
	});
});
