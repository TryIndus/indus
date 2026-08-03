import { Alpaca, TimeFrame, TimeFrameUnit, timeFrame } from "@alpacahq/alpaca-trade-api";
import { type NextRequest, NextResponse } from "next/server";
import { env } from "@/lib/env";
import { logger } from "@/lib/observability/logger";
import { alpacaQuerySchema } from "@/lib/schemas/api";

const DAY_IN_MS = 24 * 60 * 60 * 1000;
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

function getStartDate(timeframe: keyof typeof RANGE_DAYS_BY_TIMEFRAME, endDate: Date): Date {
	return new Date(endDate.getTime() - RANGE_DAYS_BY_TIMEFRAME[timeframe] * DAY_IN_MS);
}

function toAlpacaTimeframe(timeframe: keyof typeof RANGE_DAYS_BY_TIMEFRAME) {
	switch (timeframe) {
		case "1Min":
			return TimeFrame.Minute;
		case "5Min":
			return timeFrame(5, TimeFrameUnit.Minute);
		case "15Min":
			return timeFrame(15, TimeFrameUnit.Minute);
		case "1Hour":
			return TimeFrame.Hour;
		case "1Day":
			return TimeFrame.Day;
		case "1Week":
			return TimeFrame.Week;
		case "1Month":
			return TimeFrame.Month;
	}
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
			secret: env.ALPACA_SECRET_KEY,
			paper: env.ALPACA_IS_PAPER,
		});

		const endDate: Date = endParam ? new Date(endParam * 1000) : new Date();
		const startDate = startParam ? new Date(startParam * 1000) : getStartDate(timeframe, endDate);

		const historicalData: BarData[] = [];
		const request = {
			start: startDate,
			end: endDate,
			timeframe: toAlpacaTimeframe(timeframe),
			limit,
		};
		const bars =
			type === "crypto"
				? await alpaca.marketData.getCryptoBarsFor(
						symbol,
						{ ...request, loc: "us" },
						{ maxPerSymbol: limit },
					)
				: await alpaca.marketData.getStockBarsFor(
						symbol,
						{ ...request, feed: "iex", adjustment: "split" },
						{ maxPerSymbol: limit },
					);

		for (const bar of bars) {
			historicalData.push({
				time: Math.floor(bar.timestamp.getTime() / 1000),
				open: bar.open,
				high: bar.high,
				low: bar.low,
				close: bar.close,
				volume: bar.volume,
			});
		}

		const sortedData = historicalData.sort((a, b) => a.time - b.time);

		return NextResponse.json({
			data: sortedData,
			isEmpty: sortedData.length < 2,
			symbol: symbol.toUpperCase(),
			timeframe: timeframe,
			totalBars: sortedData.length,
			earliestTimestamp: sortedData.length > 0 ? sortedData[0].time : null,
			latestTimestamp: sortedData.length > 0 ? sortedData[sortedData.length - 1].time : null,
		});
	} catch (error) {
		logger.error("alpaca.history_failed", error, { symbol, timeframe, type });
		return NextResponse.json({ error: "Failed to fetch historical data" }, { status: 502 });
	}
}
