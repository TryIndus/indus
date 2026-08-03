import { z } from "zod/v4";

const symbolSchema = z
	.string()
	.trim()
	.min(1)
	.max(20)
	.regex(/^[A-Za-z0-9][A-Za-z0-9./_-]*$/, "Invalid financial symbol")
	.transform((value) => value.toUpperCase());

const metricKeySchema = z
	.string()
	.trim()
	.min(1)
	.max(80)
	.regex(/^[A-Za-z0-9][A-Za-z0-9 _./%-]*$/, "Invalid metric name");

const finiteNumberSchema = z.number().finite();

const chartPointSchema = z.object({
	t: finiteNumberSchema,
	o: finiteNumberSchema,
	h: finiteNumberSchema,
	l: finiteNumberSchema,
	c: finiteNumberSchema,
	v: finiteNumberSchema.nonnegative(),
});

const optionalMetric = finiteNumberSchema.nullish();
const metricGroupsSchema = z.object({
	companyProfile: z.object({
		marketCap: optionalMetric,
		enterpriseValue: optionalMetric,
		sharesOutstanding: optionalMetric,
		revenue: optionalMetric,
		employees: optionalMetric,
	}),
	margins: z.object({
		grossMargin: optionalMetric,
		ebitdaMargin: optionalMetric,
		operatingMargin: optionalMetric,
		netMargin: optionalMetric,
		roa: optionalMetric,
		roe: optionalMetric,
	}),
	valuation: z.object({
		peRatio: optionalMetric,
		forwardPE: optionalMetric,
		pbRatio: optionalMetric,
		psRatio: optionalMetric,
		evToSales: optionalMetric,
		evToEbitda: optionalMetric,
		pegRatio: optionalMetric,
	}),
	growth: z.object({
		revenueGrowth: optionalMetric,
		earningsGrowth: optionalMetric,
		beta: optionalMetric,
	}),
	financialHealth: z.object({
		totalCash: optionalMetric,
		totalDebt: optionalMetric,
		debtToEquity: optionalMetric,
	}),
	dividends: z.object({
		dividendYield: optionalMetric,
		dividendRate: optionalMetric,
		payoutRatio: optionalMetric,
	}),
});

export const alpacaQuerySchema = z
	.object({
		symbol: symbolSchema,
		type: z.enum(["stock", "crypto"]).default("stock"),
		timeframe: z
			.enum(["1Min", "5Min", "15Min", "1Hour", "1Day", "1Week", "1Month"])
			.default("1Min"),
		limit: z.coerce.number().int().positive().max(10000).default(2000),
		start: z.coerce.number().int().nonnegative().optional(),
		end: z.coerce.number().int().nonnegative().optional(),
	})
	.refine(({ start, end }) => start === undefined || end === undefined || start < end, {
		message: "Start must be earlier than end",
		path: ["start"],
	});

export const streamParamsSchema = z.object({
	symbol: symbolSchema,
});

export const batchExplainSchema = z
	.array(
		z.object({
			symbol: symbolSchema,
			metric: metricKeySchema,
			value: finiteNumberSchema,
		}),
	)
	.min(1)
	.max(25);

export const contextChatSchema = z.object({
	context: z.object({
		symbol: symbolSchema,
		companyName: z.string().trim().min(1).max(200),
		asOf: z.iso.datetime(),
		metricGroups: metricGroupsSchema,
		chart: z
			.object({
				interval: z.string().trim().min(1).max(20),
				points: z.array(chartPointSchema).max(100),
				latestPrice: finiteNumberSchema,
				dayChangePct: finiteNumberSchema,
			})
			.optional(),
		cachedExplanations: z.record(metricKeySchema, z.string().max(500)),
		trigger: z.object({
			metricKey: metricKeySchema,
			metricLabel: z.string().trim().min(1).max(120),
			value: z.union([finiteNumberSchema, z.string().max(500)]),
		}),
	}),
	messages: z
		.array(
			z.object({
				id: z.string().min(1).max(100),
				role: z.enum(["user", "assistant"]),
				content: z.string().min(1).max(8_000),
				createdAt: z.number().int().nonnegative(),
				streaming: z.boolean().optional(),
			}),
		)
		.max(30),
	newMessage: z.string().trim().min(1).max(4_000),
});

export const metricDefinitionQuerySchema = z.object({
	metric: metricKeySchema,
});

export const stockDataQuerySchema = z.object({
	symbol: symbolSchema,
});

export const generateReportSchema = z
	.object({
		symbol: symbolSchema,
	})
	.strict();

export const reportIdSchema = z.object({
	id: z.uuid(),
});

export const geminiTextResponseSchema = z.object({
	candidates: z
		.array(
			z.object({
				content: z.object({
					parts: z.array(z.object({ text: z.string() })).min(1),
				}),
			}),
		)
		.min(1),
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
