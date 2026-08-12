import { afterEach, describe, expect, it, vi } from "vitest";

const STORAGE_KEY = "indus_explanations_cache_v3";

function createStorage(initial: Record<string, string> = {}) {
	const values = new Map(Object.entries(initial));
	return {
		getItem: vi.fn((key: string) => values.get(key) ?? null),
		removeItem: vi.fn((key: string) => values.delete(key)),
		setItem: vi.fn((key: string, value: string) => values.set(key, value)),
		values,
	};
}

afterEach(() => {
	vi.resetModules();
	vi.restoreAllMocks();
	vi.unstubAllGlobals();
});

describe("explanation cache", () => {
	it("requires the current metric value and enforces each entry's TTL", async () => {
		const now = 10_000_000;
		vi.spyOn(Date, "now").mockReturnValue(now);
		const storage = createStorage({
			[STORAGE_KEY]: JSON.stringify({
				entries: {
					AAPL_pe_ratio: {
						value: 33.1,
						explanation: "fresh",
						savedAt: now - 1_000,
					},
					MSFT_pe_ratio: {
						value: 40,
						explanation: "expired",
						savedAt: now - 16 * 60 * 1_000,
					},
				},
			}),
		});
		vi.stubGlobal("window", {});
		vi.stubGlobal("localStorage", storage);

		const { getCachedExplanation } = await import("@/hooks/useExplanation");

		expect(getCachedExplanation("AAPL", "pe_ratio", 33.1)).toBe("fresh");
		expect(getCachedExplanation("AAPL", "pe_ratio", 34)).toBeUndefined();
		expect(getCachedExplanation("MSFT", "pe_ratio", 40)).toBeUndefined();
	});

	it("does not refresh existing entries when another explanation is saved", async () => {
		const firstSavedAt = 9_500_000;
		vi.spyOn(Date, "now").mockReturnValue(10_000_000);
		const storage = createStorage({
			[STORAGE_KEY]: JSON.stringify({
				entries: {
					AAPL_pe_ratio: {
						value: 33.1,
						explanation: "existing",
						savedAt: firstSavedAt,
					},
				},
			}),
		});
		vi.stubGlobal("window", {});
		vi.stubGlobal("localStorage", storage);
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(
				Response.json({
					explanations: {
						MSFT_pe_ratio: "new",
					},
				}),
			),
		);

		const { batchPreload } = await import("@/hooks/useExplanation");
		await batchPreload([{ symbol: "MSFT", metric: "pe_ratio", value: 40 }]);

		const persisted = JSON.parse(storage.values.get(STORAGE_KEY) ?? "{}");
		expect(persisted.entries.AAPL_pe_ratio.savedAt).toBe(firstSavedAt);
		expect(persisted.entries.MSFT_pe_ratio).toMatchObject({
			value: 40,
			explanation: "new",
			savedAt: 10_000_000,
		});
	});
});
