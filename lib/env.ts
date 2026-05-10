import { z } from "zod/v4";
import { envSchema } from "@/lib/schemas/api";

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
