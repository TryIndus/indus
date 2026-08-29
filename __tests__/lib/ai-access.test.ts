import { afterEach, describe, expect, it, vi } from "vitest";
import { checkAiAccess, getAiQuotaHeaders } from "@/lib/security/ai-access";

function createClient({
	userId = "user-1",
	userError = null,
	quota = { allowed: true, remaining: 19, reset_at: "2026-08-01T20:00:00Z" },
	quotaError = null,
}: {
	userId?: string | null;
	userError?: unknown;
	quota?: { allowed: boolean; remaining: number; reset_at: string } | null;
	quotaError?: unknown;
} = {}) {
	return {
		auth: {
			getUser: async () => ({ data: { user: userId ? { id: userId } : null }, error: userError }),
		},
		rpc: async () => ({ data: quota ? [quota] : null, error: quotaError }),
	};
}

describe("checkAiAccess", () => {
	it("returns the authenticated user and quota metadata", async () => {
		await expect(checkAiAccess(createClient(), "batch-explain")).resolves.toEqual({
			allowed: true,
			userId: "user-1",
			remaining: 19,
			resetAt: "2026-08-01T20:00:00Z",
		});
	});

	it("rejects unauthenticated requests before consuming quota", async () => {
		const rpc = vi.fn();
		const client = createClient({ userId: null });
		client.rpc = rpc;
		const result = await checkAiAccess(client, "context-chat");
		expect(result).toEqual({ allowed: false, status: 401, error: "Unauthorized" });
		expect(rpc).not.toHaveBeenCalled();
	});

	it("treats an authentication error as unauthorized even when user data is present", async () => {
		const rpc = vi.fn();
		const client = createClient({ userError: new Error("token verification failed") });
		client.rpc = rpc;

		await expect(checkAiAccess(client, "batch-explain")).resolves.toEqual({
			allowed: false,
			status: 401,
			error: "Unauthorized",
		});
		expect(rpc).not.toHaveBeenCalled();
	});

	it("returns a reset time when the quota is exhausted", async () => {
		const result = await checkAiAccess(
			createClient({
				quota: { allowed: false, remaining: 0, reset_at: "2026-08-01T21:00:00Z" },
			}),
			"generate-report",
		);
		expect(result).toEqual({
			allowed: false,
			status: 429,
			error: "AI request quota exceeded",
			resetAt: "2026-08-01T21:00:00Z",
		});
	});

	it("fails closed when the quota service is unavailable", async () => {
		const result = await checkAiAccess(
			createClient({ quota: null, quotaError: new Error("database unavailable") }),
			"batch-explain",
		);
		expect(result).toEqual({
			allowed: false,
			status: 503,
			error: "AI quota service unavailable",
		});
	});

	it("fails closed when quota storage returns an empty result", async () => {
		const client = createClient();
		client.rpc = async () => ({ data: [], error: null });

		await expect(checkAiAccess(client, "context-chat")).resolves.toEqual({
			allowed: false,
			status: 503,
			error: "AI quota service unavailable",
		});
	});

	it("creates standard rate-limit headers", () => {
		expect(
			getAiQuotaHeaders({
				allowed: true,
				userId: "user-1",
				remaining: 4,
				resetAt: "2026-08-01T21:00:00Z",
			}),
		).toEqual({
			"X-RateLimit-Remaining": "4",
			"X-RateLimit-Reset": "2026-08-01T21:00:00Z",
		});
	});

	it("omits quota headers when no reset boundary is available", () => {
		expect(getAiQuotaHeaders({ allowed: false, status: 401, error: "Unauthorized" })).toEqual({});
	});

	it("creates a bounded retry header for exhausted quota", () => {
		vi.useFakeTimers();
		vi.setSystemTime(new Date("2026-08-01T20:59:58.200Z"));

		expect(
			getAiQuotaHeaders({
				allowed: false,
				status: 429,
				error: "AI request quota exceeded",
				resetAt: "2026-08-01T21:00:00.000Z",
			}),
		).toEqual({
			"Retry-After": "2",
			"X-RateLimit-Reset": "2026-08-01T21:00:00.000Z",
		});
	});
});

afterEach(() => {
	vi.useRealTimers();
});
