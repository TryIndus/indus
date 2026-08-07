import type { Item } from "@/lib/prompts";

// localStorage key for persistent cache
const STORAGE_KEY = "indus_explanations_cache_v2";
const CACHE_TTL_MS = 15 * 60 * 1000;

// Load cache from localStorage on initialization
function loadCacheFromStorage(): Map<string, string> {
	if (typeof window === "undefined") return new Map();
	try {
		const stored = localStorage.getItem(STORAGE_KEY);
		if (stored) {
			const parsed: unknown = JSON.parse(stored);
			if (
				parsed &&
				typeof parsed === "object" &&
				"savedAt" in parsed &&
				typeof parsed.savedAt === "number" &&
				Date.now() - parsed.savedAt < CACHE_TTL_MS &&
				"entries" in parsed &&
				parsed.entries &&
				typeof parsed.entries === "object"
			) {
				return new Map(
					Object.entries(parsed.entries).filter(
						(entry): entry is [string, string] => typeof entry[1] === "string",
					),
				);
			}
			localStorage.removeItem(STORAGE_KEY);
		}
	} catch (_e) {
		// Silently fail - cache will be empty
	}
	return new Map();
}

// Save cache to localStorage
function saveCacheToStorage(cache: Map<string, string>) {
	if (typeof window === "undefined") return;
	try {
		localStorage.setItem(
			STORAGE_KEY,
			JSON.stringify({ savedAt: Date.now(), entries: Object.fromEntries(cache) }),
		);
	} catch (_e) {
		// Silently fail - cache won't persist but app will continue working
	}
}

// Global cache and loading state - initialized from localStorage
const explanationCache = loadCacheFromStorage();
const loadingState = new Map<string, boolean>();
const errorState = new Map<string, string>();

// Cache update listeners - now keyed by cache key
const cacheListeners = new Map<string, Set<() => void>>();

function makeKey(symbol: string, metric: string) {
	return `${symbol}_${metric}`;
}

function notifyCacheUpdate(key: string) {
	const listeners = cacheListeners.get(key);
	if (listeners) {
		listeners.forEach((listener) => listener());
	}
}

export function getCachedExplanation(symbol: string, metric: string) {
	const key = makeKey(symbol, metric);
	return explanationCache.get(key);
}

export function isLoading(symbol: string, metric: string) {
	return !!loadingState.get(makeKey(symbol, metric));
}

export function getExplanationError(symbol: string, metric: string) {
	return errorState.get(makeKey(symbol, metric));
}

export function subscribeToCacheUpdates(symbol: string, metric: string, callback: () => void) {
	const key = makeKey(symbol, metric);
	if (!cacheListeners.has(key)) {
		cacheListeners.set(key, new Set());
	}
	cacheListeners.get(key)?.add(callback);
	return () => {
		const listeners = cacheListeners.get(key);
		if (listeners) {
			listeners.delete(callback);
			if (listeners.size === 0) {
				cacheListeners.delete(key);
			}
		}
	};
}

// Track if batch preload is in progress - use a Promise for proper deduplication
let pendingBatchRequest: Promise<void> | null = null;

export async function fetchExplanation(
	symbol: string,
	metric: string,
	value: number,
): Promise<void> {
	const key = makeKey(symbol, metric);

	if (explanationCache.has(key) || loadingState.get(key)) {
		return;
	}

	// If another metric is loading, wait and then re-check this metric instead of dropping it.
	if (pendingBatchRequest) {
		await pendingBatchRequest;
		if (explanationCache.has(key) || loadingState.get(key)) return;
	}

	// Since we removed individual API endpoint, use batch API for single items
	await batchPreload([{ symbol, metric, value }]);
}

export async function batchPreload(items: Item[]) {
	// If a batch request is already in progress, wait for it and return
	// This prevents duplicate API calls from React Strict Mode or race conditions
	if (pendingBatchRequest) {
		await pendingBatchRequest;
		return;
	}

	// Only fetch if not already cached
	const toFetch = items.filter((item) => !explanationCache.has(makeKey(item.symbol, item.metric)));

	if (toFetch.length === 0) {
		return;
	}

	for (const item of toFetch) {
		const key = makeKey(item.symbol, item.metric);
		errorState.delete(key);
		loadingState.set(key, true);
		notifyCacheUpdate(key);
	}

	// Create and store the promise BEFORE the async operation
	// This ensures any concurrent calls will see the pending request
	pendingBatchRequest = (async () => {
		try {
			const res = await fetch("/api/batch-explain", {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify(toFetch),
			});
			const data = await res.json();

			if (!res.ok) {
				const message =
					data && typeof data === "object" && typeof data.error === "string"
						? data.error
						: "This explanation is temporarily unavailable.";
				throw new Error(message);
			}

			if (data && typeof data === "object" && data.explanations) {
				for (const [key, text] of Object.entries(data.explanations)) {
					if (typeof text === "string") {
						explanationCache.set(key, text);
						notifyCacheUpdate(key);
					}
				}
				saveCacheToStorage(explanationCache);
			}
		} catch (error) {
			const message =
				error instanceof Error ? error.message : "This explanation is temporarily unavailable.";
			for (const item of toFetch) {
				const key = makeKey(item.symbol, item.metric);
				errorState.set(key, message);
				notifyCacheUpdate(key);
			}
		} finally {
			for (const item of toFetch) {
				const key = makeKey(item.symbol, item.metric);
				loadingState.delete(key);
				notifyCacheUpdate(key);
			}
			pendingBatchRequest = null;
		}
	})();

	// Wait for the request to complete
	await pendingBatchRequest;
}
