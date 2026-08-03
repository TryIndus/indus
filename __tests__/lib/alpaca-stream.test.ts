import { describe, expect, it } from "vitest";
import {
	extractBarSymbol,
	formatSseMessage,
	getNextEventId,
	isCryptoSymbol,
	normalizeStreamSymbol,
	toCryptoCandlestickData,
	toStockCandlestickData,
} from "@/lib/realtime/alpaca-stream";

describe("alpaca stream helpers", () => {
	it("normalizes stream symbols", () => {
		expect(normalizeStreamSymbol(" aapl ")).toBe("AAPL");
		expect(normalizeStreamSymbol(" btc/usd ")).toBe("BTC/USD");
	});

	it("detects crypto symbols by pair separator", () => {
		expect(isCryptoSymbol("BTC/USD")).toBe(true);
		expect(isCryptoSymbol("AAPL")).toBe(false);
	});

	it("extracts stock and crypto symbols from stream bar payloads", () => {
		expect(extractBarSymbol({ Symbol: "AAPL" })).toBe("AAPL");
		expect(extractBarSymbol({ S: "eth/usd" })).toBe("ETH/USD");
		expect(extractBarSymbol({ Pair: "btc/usd" })).toBe("BTC/USD");
	});

	it("converts stock bars to chart candlesticks", () => {
		const result = toStockCandlestickData({
			Timestamp: "2026-05-24T15:00:00.000Z",
			OpenPrice: 100,
			HighPrice: 105,
			LowPrice: 99,
			ClosePrice: 102,
			Volume: 1000,
		});

		expect(result).toMatchObject({
			open: 100,
			high: 105,
			low: 99,
			close: 102,
			volume: 1000,
		});
		expect(result.time).toBe(Date.parse("2026-05-24T15:00:00.000Z") / 1000);
	});

	it("supports the normalized Alpaca v4 bar shape", () => {
		const result = toStockCandlestickData({
			symbol: "AAPL",
			timestamp: new Date("2026-05-24T15:00:00.000Z"),
			open: 100,
			high: 105,
			low: 99,
			close: 102,
			volume: 1000,
		});

		expect(result).toEqual({
			time: Date.parse("2026-05-24T15:00:00.000Z") / 1000,
			open: 100,
			high: 105,
			low: 99,
			close: 102,
			volume: 1000,
		});
	});

	it("converts crypto bars to chart candlesticks without hardcoding ETH/USD", () => {
		const result = toCryptoCandlestickData({
			Symbol: "BTC/USD",
			Timestamp: "2026-05-24T15:00:00.000Z",
			Open: 65_000,
			High: 66_000,
			Low: 64_500,
			Close: 65_500,
			Volume: 12.5,
		});

		expect(extractBarSymbol({ Symbol: "BTC/USD" })).toBe("BTC/USD");
		expect(result).toMatchObject({
			open: 65_000,
			high: 66_000,
			low: 64_500,
			close: 65_500,
			volume: 12.5,
		});
	});

	it("formats SSE messages with id, event, and JSON data", () => {
		expect(formatSseMessage({ id: 7, event: "bar", data: { close: 102 } })).toBe(
			'id: 7\nevent: bar\ndata: {"close":102}\n\n',
		);
	});

	it("increments Last-Event-ID values for reconnects", () => {
		expect(getNextEventId("41")).toBe(42);
		expect(getNextEventId(null)).toBe(1);
		expect(getNextEventId("not-a-number")).toBe(1);
	});
});
