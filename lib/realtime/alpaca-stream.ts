export interface StreamCandlestickData {
	time: number;
	open: number;
	high: number;
	low: number;
	close: number;
	volume: number;
}

type BarLike = Record<string, unknown>;

function asRecord(value: unknown): BarLike {
	if (value && typeof value === "object") {
		return value as BarLike;
	}
	return {};
}

function readString(source: BarLike, keys: string[]): string | null {
	for (const key of keys) {
		const value = source[key];
		if (typeof value === "string" && value.length > 0) {
			return value;
		}
	}

	return null;
}

function readNumber(source: BarLike, keys: string[]): number {
	for (const key of keys) {
		const value = source[key];
		if (typeof value === "number" && Number.isFinite(value)) {
			return value;
		}
		if (typeof value === "string" && value.trim().length > 0) {
			const parsed = Number(value);
			if (Number.isFinite(parsed)) {
				return parsed;
			}
		}
	}

	return 0;
}

function toUnixTimestamp(timestamp: string | Date | number): number {
	const date = new Date(timestamp);
	return Math.floor(date.getTime() / 1000);
}

export function normalizeStreamSymbol(symbol: string): string {
	return symbol.trim().toUpperCase();
}

export function isCryptoSymbol(symbol: string): boolean {
	return normalizeStreamSymbol(symbol).includes("/");
}

export function getNextEventId(lastEventId: string | null): number {
	if (!lastEventId) {
		return 1;
	}

	const parsed = Number.parseInt(lastEventId, 10);
	return Number.isFinite(parsed) && parsed >= 0 ? parsed + 1 : 1;
}

export function extractBarSymbol(bar: unknown): string | null {
	const source = asRecord(bar);
	const symbol = readString(source, ["Symbol", "symbol", "S", "s", "Pair", "pair"]);
	return symbol ? normalizeStreamSymbol(symbol) : null;
}

export function toStockCandlestickData(bar: unknown): StreamCandlestickData {
	const source = asRecord(bar);

	return {
		time: toUnixTimestamp((source.Timestamp ?? source.timestamp) as string | Date | number),
		open: readNumber(source, ["OpenPrice", "openPrice", "Open", "open"]),
		high: readNumber(source, ["HighPrice", "highPrice", "High", "high"]),
		low: readNumber(source, ["LowPrice", "lowPrice", "Low", "low"]),
		close: readNumber(source, ["ClosePrice", "closePrice", "Close", "close"]),
		volume: readNumber(source, ["Volume", "volume"]),
	};
}

export function toCryptoCandlestickData(bar: unknown): StreamCandlestickData {
	const source = asRecord(bar);

	return {
		time: toUnixTimestamp((source.Timestamp ?? source.timestamp) as string | Date | number),
		open: readNumber(source, ["Open", "open"]),
		high: readNumber(source, ["High", "high"]),
		low: readNumber(source, ["Low", "low"]),
		close: readNumber(source, ["Close", "close"]),
		volume: readNumber(source, ["Volume", "volume"]),
	};
}

export function formatSseMessage({
	data,
	event,
	id,
}: {
	data: unknown;
	event?: string;
	id?: number;
}): string {
	const lines: string[] = [];

	if (id !== undefined) {
		lines.push(`id: ${id}`);
	}
	if (event) {
		lines.push(`event: ${event}`);
	}

	for (const line of JSON.stringify(data).split(/\r?\n/)) {
		lines.push(`data: ${line}`);
	}

	return `${lines.join("\n")}\n\n`;
}
