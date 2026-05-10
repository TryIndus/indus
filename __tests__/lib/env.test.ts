import { describe, expect, it } from "vitest";
import { envSchema } from "@/lib/schemas/api";

const validEnv = {
	NEXT_PUBLIC_SUPABASE_URL: "https://example.supabase.co",
	NEXT_PUBLIC_SUPABASE_ANON_KEY: "anon-key-123",
	ALPACA_API_KEY: "alpaca-key",
	ALPACA_SECRET_KEY: "alpaca-secret",
	ALPACA_IS_PAPER: "true" as const,
	GEMINI_API_KEY: "gemini-key",
};

describe("envSchema", () => {
	it("accepts valid environment variables", () => {
		const result = envSchema.safeParse(validEnv);
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.ALPACA_IS_PAPER).toBe(true);
		}
	});

	it("transforms ALPACA_IS_PAPER 'false' to boolean false", () => {
		const result = envSchema.safeParse({ ...validEnv, ALPACA_IS_PAPER: "false" });
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.ALPACA_IS_PAPER).toBe(false);
		}
	});

	it("defaults ALPACA_IS_PAPER to true when omitted", () => {
		const { ALPACA_IS_PAPER, ...envWithout } = validEnv;
		const result = envSchema.safeParse(envWithout);
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.ALPACA_IS_PAPER).toBe(true);
		}
	});

	it("rejects missing NEXT_PUBLIC_SUPABASE_URL", () => {
		const { NEXT_PUBLIC_SUPABASE_URL, ...envWithout } = validEnv;
		const result = envSchema.safeParse(envWithout);
		expect(result.success).toBe(false);
	});

	it("rejects invalid NEXT_PUBLIC_SUPABASE_URL (not a URL)", () => {
		const result = envSchema.safeParse({ ...validEnv, NEXT_PUBLIC_SUPABASE_URL: "not-a-url" });
		expect(result.success).toBe(false);
	});

	it("rejects missing ALPACA_API_KEY", () => {
		const { ALPACA_API_KEY, ...envWithout } = validEnv;
		const result = envSchema.safeParse(envWithout);
		expect(result.success).toBe(false);
	});

	it("rejects empty string for ALPACA_SECRET_KEY", () => {
		const result = envSchema.safeParse({ ...validEnv, ALPACA_SECRET_KEY: "" });
		expect(result.success).toBe(false);
	});

	it("rejects missing GEMINI_API_KEY", () => {
		const { GEMINI_API_KEY, ...envWithout } = validEnv;
		const result = envSchema.safeParse(envWithout);
		expect(result.success).toBe(false);
	});

	it("allows NEXT_PUBLIC_VERCEL_URL to be optional", () => {
		const result = envSchema.safeParse(validEnv);
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.NEXT_PUBLIC_VERCEL_URL).toBeUndefined();
		}
	});

	it("accepts NEXT_PUBLIC_VERCEL_URL when provided", () => {
		const result = envSchema.safeParse({
			...validEnv,
			NEXT_PUBLIC_VERCEL_URL: "my-app.vercel.app",
		});
		expect(result.success).toBe(true);
	});

	it("rejects invalid ALPACA_IS_PAPER value", () => {
		const result = envSchema.safeParse({ ...validEnv, ALPACA_IS_PAPER: "yes" });
		expect(result.success).toBe(false);
	});
});
