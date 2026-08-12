export type CacheStatus = "hit" | "miss" | "stale" | "deduplicated";

export interface CacheResult<T> {
	value: T;
	status: CacheStatus;
}

interface CacheEntry<T> {
	value: T;
	freshUntil: number;
	staleUntil: number;
}

interface ResilientCacheOptions {
	freshForMs: number;
	staleForMs: number;
	maxEntries?: number;
	now?: () => number;
}

export class ResilientCache<T> {
	private readonly entries = new Map<string, CacheEntry<T>>();
	private readonly inFlight = new Map<string, Promise<T>>();
	private readonly maxEntries: number;
	private readonly now: () => number;

	constructor(private readonly options: ResilientCacheOptions) {
		this.maxEntries = Math.max(1, options.maxEntries ?? 250);
		this.now = options.now ?? Date.now;
	}

	async getOrLoad(key: string, loader: () => Promise<T>): Promise<CacheResult<T>> {
		const now = this.now();
		const cached = this.entries.get(key);

		if (cached && cached.freshUntil > now) {
			this.touch(key, cached);
			return { value: cached.value, status: "hit" };
		}

		const existingLoad = this.inFlight.get(key);
		if (existingLoad) {
			try {
				return { value: await existingLoad, status: "deduplicated" };
			} catch (error) {
				if (cached && cached.staleUntil > this.now()) {
					this.touch(key, cached);
					return { value: cached.value, status: "stale" };
				}
				throw error;
			}
		}

		const load = loader();
		this.inFlight.set(key, load);

		try {
			const value = await load;
			const loadedAt = this.now();
			this.entries.set(key, {
				value,
				freshUntil: loadedAt + this.options.freshForMs,
				staleUntil: loadedAt + this.options.freshForMs + this.options.staleForMs,
			});
			this.prune();
			return { value, status: "miss" };
		} catch (error) {
			if (cached && cached.staleUntil > this.now()) {
				this.touch(key, cached);
				return { value: cached.value, status: "stale" };
			}

			this.entries.delete(key);
			throw error;
		} finally {
			this.inFlight.delete(key);
		}
	}

	clear(): void {
		this.entries.clear();
		this.inFlight.clear();
	}

	private touch(key: string, entry: CacheEntry<T>): void {
		this.entries.delete(key);
		this.entries.set(key, entry);
	}

	private prune(): void {
		const now = this.now();
		for (const [key, entry] of this.entries) {
			if (entry.staleUntil <= now) {
				this.entries.delete(key);
			}
		}

		while (this.entries.size > this.maxEntries) {
			const oldestKey = this.entries.keys().next().value;
			if (oldestKey === undefined) {
				break;
			}
			this.entries.delete(oldestKey);
		}
	}
}
