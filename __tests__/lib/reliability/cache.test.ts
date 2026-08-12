import { describe, expect, it, vi } from "vitest";
import { ResilientCache } from "@/lib/reliability/cache";

describe("ResilientCache", () => {
	it("returns fresh values without reloading", async () => {
		let now = 1_000;
		const cache = new ResilientCache<string>({
			freshForMs: 100,
			staleForMs: 500,
			now: () => now,
		});
		const loader = vi.fn().mockResolvedValue("first");

		await expect(cache.getOrLoad("key", loader)).resolves.toEqual({
			value: "first",
			status: "miss",
		});
		now += 50;
		await expect(cache.getOrLoad("key", loader)).resolves.toEqual({
			value: "first",
			status: "hit",
		});
		expect(loader).toHaveBeenCalledTimes(1);
	});

	it("serves stale data when a refresh fails inside the stale window", async () => {
		let now = 1_000;
		const cache = new ResilientCache<string>({
			freshForMs: 100,
			staleForMs: 500,
			now: () => now,
		});

		await cache.getOrLoad("key", async () => "cached");
		now += 150;
		await expect(
			cache.getOrLoad("key", async () => {
				throw new Error("provider unavailable");
			}),
		).resolves.toEqual({ value: "cached", status: "stale" });
	});

	it("deduplicates concurrent loads for the same key", async () => {
		let resolveLoad: ((value: string) => void) | undefined;
		const loader = vi.fn(
			() =>
				new Promise<string>((resolve) => {
					resolveLoad = resolve;
				}),
		);
		const cache = new ResilientCache<string>({ freshForMs: 100, staleForMs: 500 });

		const first = cache.getOrLoad("key", loader);
		const second = cache.getOrLoad("key", loader);
		resolveLoad?.("shared");

		await expect(first).resolves.toEqual({ value: "shared", status: "miss" });
		await expect(second).resolves.toEqual({ value: "shared", status: "deduplicated" });
		expect(loader).toHaveBeenCalledTimes(1);
	});

	it("serves the same stale value to callers sharing a failed refresh", async () => {
		let now = 1_000;
		let rejectRefresh: ((error: Error) => void) | undefined;
		const cache = new ResilientCache<string>({
			freshForMs: 100,
			staleForMs: 500,
			now: () => now,
		});
		await cache.getOrLoad("key", async () => "cached");
		now += 150;
		const loader = vi.fn(
			() =>
				new Promise<string>((_, reject) => {
					rejectRefresh = reject;
				}),
		);

		const first = cache.getOrLoad("key", loader);
		const second = cache.getOrLoad("key", loader);
		rejectRefresh?.(new Error("provider unavailable"));

		await expect(first).resolves.toEqual({ value: "cached", status: "stale" });
		await expect(second).resolves.toEqual({ value: "cached", status: "stale" });
		expect(loader).toHaveBeenCalledTimes(1);
	});
});
