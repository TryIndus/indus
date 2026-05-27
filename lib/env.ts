import { z } from "zod/v4";
import { coalesceLegacyEnv } from "@/lib/env-legacy";
import { envSchema } from "@/lib/schemas/api";

export type Env = z.infer<typeof envSchema>;

function validateEnv(): Env {
	const result = envSchema.safeParse(coalesceLegacyEnv(process.env));
	if (!result.success) {
		const formatted = z.prettifyError(result.error);
		console.error("Environment validation failed:\n", formatted);
		throw new Error("Invalid environment variables");
	}
	return result.data;
}

export const env = validateEnv();
