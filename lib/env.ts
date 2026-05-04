import { z } from "zod/v4";

const envSchema = z.object({
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

export type Env = z.infer<typeof envSchema>;

function validateEnv(): Env {
	const result = envSchema.safeParse(process.env);
	if (!result.success) {
		const formatted = z.prettifyError(result.error);
		console.error("Environment validation failed:\n", formatted);
		throw new Error("Invalid environment variables");
	}
	return result.data;
}

export const env = validateEnv();
