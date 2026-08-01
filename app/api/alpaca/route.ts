import Alpaca from "@alpacahq/alpaca-trade-api";
import { type NextRequest, NextResponse } from "next/server";
import { env } from "@/lib/env";
import { logger } from "@/lib/observability/logger";
import { alpacaQuerySchema } from "@/lib/schemas/api";

const EST_TIMEZONE_OFFSET_SECONDS = 5 * 60 * 60;
const DAY_IN_MS = 24 * 60 * 60 * 1000;
const MAX_BAR_COUNT = 1_000_000;
const RANGE_DAYS_BY_TIMEFRAME = {
	"1Min": 5,
	"5Min": 14,
	"15Min": 45,
	"1Hour": 180,
	"1Day": 4 * 365,
	"1Week": 20 * 365,
	"1Month": 20 * 365,
} as const;

interface BarData {
	time: number;
	open: number;
	high: number;
	low: number;
	close: number;
	volume: number;
}

function convertToESTTimestamp(timestamp: string | Date): number {
	const date = new Date(timestamp);
	return Math.floor((date.getTime() - EST_TIMEZONE_OFFSET_SECONDS * 1000) / 1000);
}

function convertToUTCTimestamp(estTimestamp: number): number {
	return estTimestamp + EST_TIMEZONE_OFFSET_SECONDS;
}

function getStartDate(timeframe: keyof typeof RANGE_DAYS_BY_TIMEFRAME, endDate: Date): Date {
	return new Date(endDate.getTime() - RANGE_DAYS_BY_TIMEFRAME[timeframe] * DAY_IN_MS);
}

export async function GET(request: NextRequest) {
	const { searchParams } = new URL(request.url);
	const parsed = alpacaQuerySchema.safeParse({
		symbol: searchParams.get("symbol"),
		type: searchParams.get("type") ?? undefined,
		timeframe: searchParams.get("timeframe") ?? undefined,
		limit: searchParams.get("limit") ?? undefined,
		start: searchParams.get("start") ?? undefined,
		end: searchParams.get("end") ?? undefined,
	});

	if (!parsed.success) {
		return NextResponse.json(
			{ error: "Invalid query parameters", details: parsed.error.issues },
			{ status: 400 },
		);
	}

	const { symbol, type, timeframe, limit } = parsed.data;
	const startParam = parsed.data.start;
	const endParam = parsed.data.end;

	try {
		const alpaca = new Alpaca({
			keyId: env.ALPACA_API_KEY,
			secretKey: env.ALPACA_SECRET_KEY,
			paper: env.ALPACA_IS_PAPER,
			usePolygon: false,
		});

		const endDate: Date = endParam ? new Date(endParam * 1000) : new Date();
		const startDate = startParam ? new Date(startParam * 1000) : getStartDate(timeframe, endDate);

		const historicalData: BarData[] = [];
		let pageToken: string | undefined;
		let totalFetched = 0;

		if (type === "crypto") {
			const barsResponse = await alpaca.getCryptoBars([symbol.toUpperCase()], {
				start: startDate,
				end: endDate,
				timeframe: timeframe,
				limit: limit,
			});

			for await (const [, bars] of barsResponse) {
				if (bars && Array.isArray(bars)) {
					for (const bar of bars) {
						const processedBar = {
							time: convertToESTTimestamp(bar.Timestamp),
							open: bar.Open,
							high: bar.High,
							low: bar.Low,
							close: bar.Close,
							volume: bar.Volume,
						};
						historicalData.push(processedBar);
						totalFetched++;
					}
				}
			}
		} else {
			do {
				const barsResponse = await alpaca.getBarsV2(symbol.toUpperCase(), {
					start: startDate,
					end: endDate,
					timeframe: timeframe,
					limit: limit,
					feed: "iex",
					adjustment: "split",
					page_token: pageToken,
				});

				let batchCount = 0;
				for await (const bar of barsResponse) {
					const processedBar = {
						time: convertToESTTimestamp(bar.Timestamp),
						open: bar.OpenPrice,
						high: bar.HighPrice,
						low: bar.LowPrice,
						close: bar.ClosePrice,
						volume: bar.Volume,
					};
					historicalData.push(processedBar);
					batchCount++;
				}

				totalFetched += batchCount;
				pageToken = (barsResponse as { next_page_token?: string }).next_page_token;

				if (!pageToken || batchCount === 0 || totalFetched > MAX_BAR_COUNT) {
					break;
				}
			} while (pageToken);
		}

		const sortedData = historicalData.sort((a, b) => a.time - b.time);

		return NextResponse.json({
			data: sortedData,
			isEmpty: sortedData.length < 2,
			symbol: symbol.toUpperCase(),
			timeframe: timeframe,
			totalBars: sortedData.length,
			earliestTimestamp: sortedData.length > 0 ? convertToUTCTimestamp(sortedData[0].time) : null,
			latestTimestamp:
				sortedData.length > 0
					? convertToUTCTimestamp(sortedData[sortedData.length - 1].time)
					: null,
		});
	} catch (error) {
		logger.error("alpaca.history_failed", error, { symbol, timeframe, type });
		return NextResponse.json({ error: "Failed to fetch historical data" }, { status: 502 });
	}
}
