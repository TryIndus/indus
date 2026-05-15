import { z } from "zod/v4";

export const alpacaQuerySchema = z.object({
	symbol: z.string().min(1),
	type: z.enum(["stock", "crypto"]).default("stock"),
	timeframe: z.enum(["1Min", "5Min", "15Min", "1Hour", "1Day", "1Week", "1Month"]).default("1Min"),
	limit: z.coerce.number().int().positive().max(10000).default(2000),
	start: z.coerce.number().optional(),
	end: z.coerce.number().optional(),
});

export const batchExplainSchema = z
	.array(
		z.object({
			symbol: z.string().min(1),
			metric: z.string().min(1),
			value: z.number(),
		}),
	)
	.min(1);

export const contextChatSchema = z.object({
	context: z.object({
		symbol: z.string().min(1),
		companyName: z.string(),
		asOf: z.string(),
		metricGroups: z.record(z.string(), z.any()),
		chart: z
			.object({
				interval: z.string(),
				points: z.array(z.any()),
				latestPrice: z.number(),
				dayChangePct: z.number(),
			})
			.optional(),
		cachedExplanations: z.record(z.string(), z.string()),
		trigger: z.object({
			metricKey: z.string(),
			metricLabel: z.string(),
			value: z.union([z.number(), z.string()]),
		}),
	}),
	messages: z.array(
		z.object({
			id: z.string(),
			role: z.enum(["user", "assistant", "system"]),
			content: z.string(),
			createdAt: z.number(),
			streaming: z.boolean().optional(),
		}),
	),
	newMessage: z.string().min(1),
});

export const metricDefinitionQuerySchema = z.object({
	metric: z.string().min(1),
});

export const stockDataQuerySchema = z.object({
	symbol: z.string().min(1),
});

export const generateReportSchema = z.object({
	symbol: z.string().min(1),
});

export const reportIdSchema = z.object({
	id: z.uuid(),
});

export const envSchema = z.object({
	NEXT_PUBLIC_SUPABASE_URL: z.url(),
	NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
	ALPACA_API_KEY: z.string().min(1),
	ALPACA_SECRET_KEY: z.string().min(1),
	ALPACA_IS_PAPER: z
		.enum(["true", "false"])
		.default("true")
		.transform((v) => v === "true"),
	GEMINI_API_KEY: z.string().min(1),
	NEXT_PUBLIC_VERCEL_URL: z.string().optional(),
});
