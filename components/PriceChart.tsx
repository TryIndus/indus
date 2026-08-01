"use client";

import type { CandlestickData, Time } from "lightweight-charts";
import {
	CandlestickSeries,
	createChart,
	type IChartApi,
	type ISeriesApi,
} from "lightweight-charts";
import { useCallback, useEffect, useRef, useState } from "react";

type AssetType = "stock" | "crypto";
type BarData = CandlestickData<Time> & { volume?: number };
type RealtimeStatus = "connecting" | "connected" | "reconnecting" | "disabled";

interface HistoricalDataResponse {
	data: BarData[];
	isEmpty: boolean;
	earliestTimestamp: number | null;
	totalBars: number;
	error?: string;
}

export interface PriceChartProps {
	symbol: string;
	type: AssetType;
	height?: number;
	className?: string;
	showControls?: boolean;
}

const timeframes = [
	{ value: "1Min", label: "1 Min" },
	{ value: "5Min", label: "5 Min" },
	{ value: "15Min", label: "15 Min" },
	{ value: "1Hour", label: "1 Hour" },
	{ value: "1Day", label: "1 Day" },
	{ value: "1Week", label: "1 Week" },
	{ value: "1Month", label: "1 Month" },
];

function isBarData(value: unknown): value is BarData {
	if (!value || typeof value !== "object") {
		return false;
	}

	const bar = value as Record<string, unknown>;
	return ["time", "open", "high", "low", "close"].every(
		(key) => typeof bar[key] === "number" && Number.isFinite(bar[key]),
	);
}

function parseHistoricalResponse(value: unknown): HistoricalDataResponse | null {
	if (!value || typeof value !== "object") {
		return null;
	}

	const response = value as Record<string, unknown>;
	if (
		!Array.isArray(response.data) ||
		!response.data.every(isBarData) ||
		typeof response.isEmpty !== "boolean" ||
		typeof response.totalBars !== "number" ||
		(response.earliestTimestamp !== null && typeof response.earliestTimestamp !== "number")
	) {
		return null;
	}

	return {
		data: response.data,
		isEmpty: response.isEmpty,
		earliestTimestamp: response.earliestTimestamp,
		totalBars: response.totalBars,
		error: typeof response.error === "string" ? response.error : undefined,
	};
}

function buildHistoricalUrl(
	symbol: string,
	timeframe: string,
	type: AssetType,
	end?: number,
): string {
	const params = new URLSearchParams({ symbol, timeframe });

	if (type === "crypto") {
		params.set("type", "crypto");
	}
	if (end) {
		params.set("end", String(end));
	}

	return `/api/alpaca?${params.toString()}`;
}

export default function PriceChart({
	symbol: initialSymbol,
	type,
	height = 500,
	className = "",
	showControls = true,
}: PriceChartProps) {
	const chartContainerRef = useRef<HTMLDivElement>(null);
	const chartRef = useRef<IChartApi | null>(null);
	const candlestickSeriesRef = useRef<ISeriesApi<"Candlestick"> | null>(null);
	const eventSourceRef = useRef<EventSource | null>(null);
	const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

	const [selectedSymbol, setSelectedSymbol] = useState(initialSymbol);
	const [selectedTimeframe, setSelectedTimeframe] = useState("1Min");
	const [isLoading, setIsLoading] = useState(true);
	const [error, setError] = useState<string | null>(null);
	const [realtimeStatus, setRealtimeStatus] = useState<RealtimeStatus>("connecting");
	const [showReconnecting, setShowReconnecting] = useState(false);
	const [isLoadingMoreData, setIsLoadingMoreData] = useState(false);
	const [hasReachedDataLimit, setHasReachedDataLimit] = useState(false);
	const [dataLimitMessage, setDataLimitMessage] = useState<string | null>(null);

	const isLoadingMoreDataRef = useRef(false);
	const earliestLoadedTimestampRef = useRef<number | null>(null);
	const selectedSymbolRef = useRef(selectedSymbol);
	const selectedTimeframeRef = useRef(selectedTimeframe);
	const historicalDataRef = useRef<BarData[]>([]);
	const hasReachedDataLimitRef = useRef(false);

	const clearReconnectTimer = useCallback(() => {
		if (reconnectTimerRef.current) {
			clearTimeout(reconnectTimerRef.current);
			reconnectTimerRef.current = null;
		}
	}, []);

	const resetLoadedData = useCallback(() => {
		historicalDataRef.current = [];
		earliestLoadedTimestampRef.current = null;
		hasReachedDataLimitRef.current = false;
		setHasReachedDataLimit(false);
		setDataLimitMessage(null);

		if (candlestickSeriesRef.current) {
			candlestickSeriesRef.current.setData([]);
		}
	}, []);

	const loadHistoricalData = useCallback(
		async (symbol: string, timeframe: string) => {
			setError(null);

			try {
				const response = await fetch(buildHistoricalUrl(symbol, timeframe, type));
				const result = parseHistoricalResponse(await response.json());

				if (response.ok && result && !result.isEmpty) {
					historicalDataRef.current = result.data;
					earliestLoadedTimestampRef.current = result.earliestTimestamp;
					candlestickSeriesRef.current?.setData(result.data);
				} else {
					setError(result?.error ?? "Failed to load historical data");
				}
			} catch {
				setError("Internal server error");
			}
		},
		[type],
	);

	const loadMoreHistoricalData = useCallback(async () => {
		if (!earliestLoadedTimestampRef.current || isLoadingMoreDataRef.current) {
			return;
		}

		setIsLoadingMoreData(true);
		isLoadingMoreDataRef.current = true;

		try {
			const response = await fetch(
				buildHistoricalUrl(
					selectedSymbolRef.current,
					selectedTimeframeRef.current,
					type,
					earliestLoadedTimestampRef.current,
				),
			);
			const result = parseHistoricalResponse(await response.json());

			if (response.ok && result && !result.isEmpty) {
				const firstLoadedBar = historicalDataRef.current[0];
				const filteredNewData = firstLoadedBar
					? result.data.filter((bar: BarData) => bar.time < firstLoadedBar.time)
					: result.data;
				const combinedData = [...filteredNewData, ...historicalDataRef.current];

				historicalDataRef.current = combinedData;
				earliestLoadedTimestampRef.current = result.earliestTimestamp;
				candlestickSeriesRef.current?.setData(combinedData);
			} else {
				hasReachedDataLimitRef.current = true;
				setHasReachedDataLimit(true);

				if (earliestLoadedTimestampRef.current) {
					const earliestDate = new Date(earliestLoadedTimestampRef.current * 1000);
					const yearsBack = Math.round(
						(Date.now() - earliestDate.getTime()) / (365 * 24 * 60 * 60 * 1000),
					);
					setDataLimitMessage(
						`Reached data limit: ${earliestDate.toLocaleDateString()} (${yearsBack} years ago)`,
					);
				}
			}
		} catch {
			setDataLimitMessage("Unable to load additional historical data");
		} finally {
			setIsLoadingMoreData(false);
			isLoadingMoreDataRef.current = false;
		}
	}, [type]);

	useEffect(() => {
		if (!chartContainerRef.current) {
			return;
		}

		const chart = createChart(chartContainerRef.current, {
			width: chartContainerRef.current.clientWidth,
			height,
			layout: {
				background: { color: "transparent" },
				textColor: "#e5e7eb",
			},
			grid: {
				vertLines: { color: "#374151" },
				horzLines: { color: "#374151" },
			},
			crosshair: {
				mode: 1,
				vertLine: {
					color: "#6b7280",
					width: 1,
					style: 2,
				},
				horzLine: {
					color: "#6b7280",
					width: 1,
					style: 2,
				},
			},
			rightPriceScale: {
				borderColor: "#4b5563",
				textColor: "#e5e7eb",
			},
			timeScale: {
				borderColor: "#4b5563",
				timeVisible: true,
				secondsVisible: false,
				rightOffset: 12,
				barSpacing: 6,
				minBarSpacing: 0.5,
				maxBarSpacing: 50,
			},
		});

		const candlestickSeries = chart.addSeries(CandlestickSeries, {
			upColor: "#26a69a",
			downColor: "#ef5350",
			borderVisible: false,
			wickUpColor: "#1a7a6b",
			wickDownColor: "#c43e3a",
			priceLineVisible: false,
		});

		chartRef.current = chart;
		candlestickSeriesRef.current = candlestickSeries;

		let rangeChangeTimeout: ReturnType<typeof setTimeout> | null = null;
		chart.timeScale().subscribeVisibleLogicalRangeChange((logicalRange) => {
			if (rangeChangeTimeout) {
				clearTimeout(rangeChangeTimeout);
			}

			rangeChangeTimeout = setTimeout(() => {
				if (
					logicalRange &&
					earliestLoadedTimestampRef.current &&
					!isLoadingMoreDataRef.current &&
					!hasReachedDataLimitRef.current &&
					logicalRange.from !== null &&
					logicalRange.from <= 3 &&
					historicalDataRef.current.length > 50
				) {
					void loadMoreHistoricalData();
				}
			}, 500);
		});

		const handleResize = () => {
			if (chartContainerRef.current && chartRef.current) {
				chartRef.current.applyOptions({
					width: chartContainerRef.current.clientWidth,
				});
			}
		};

		window.addEventListener("resize", handleResize);
		setIsLoading(false);

		return () => {
			if (rangeChangeTimeout) {
				clearTimeout(rangeChangeTimeout);
			}
			window.removeEventListener("resize", handleResize);
			chart.remove();
			chartRef.current = null;
			candlestickSeriesRef.current = null;
		};
	}, [height, loadMoreHistoricalData]);

	useEffect(() => {
		selectedSymbolRef.current = selectedSymbol;
	}, [selectedSymbol]);

	useEffect(() => {
		selectedTimeframeRef.current = selectedTimeframe;
	}, [selectedTimeframe]);

	useEffect(() => {
		resetLoadedData();
		void loadHistoricalData(selectedSymbol, selectedTimeframe);
	}, [loadHistoricalData, resetLoadedData, selectedSymbol, selectedTimeframe]);

	useEffect(() => {
		setSelectedSymbol(initialSymbol);
	}, [initialSymbol]);

	useEffect(() => {
		const streamUrl = `/api/stream/${encodeURIComponent(selectedSymbol)}`;
		const eventSource = new EventSource(streamUrl);
		eventSourceRef.current = eventSource;

		setRealtimeStatus("connecting");
		setShowReconnecting(false);
		clearReconnectTimer();

		const handleOpen = () => {
			clearReconnectTimer();
			setRealtimeStatus("connected");
			setShowReconnecting(false);
		};

		const handleBar = (event: MessageEvent<string>) => {
			try {
				const data: unknown = JSON.parse(event.data);
				if (
					isBarData(data) &&
					candlestickSeriesRef.current &&
					selectedTimeframeRef.current === "1Min"
				) {
					candlestickSeriesRef.current.update(data);
				}
			} catch {
				return;
			}
		};

		const handleStreamError = () => {
			setRealtimeStatus("disabled");
			setShowReconnecting(false);
			clearReconnectTimer();
			eventSource.close();
		};

		const handleError = () => {
			if (eventSource.readyState === EventSource.CLOSED) {
				return;
			}

			setRealtimeStatus("reconnecting");
			if (!reconnectTimerRef.current) {
				reconnectTimerRef.current = setTimeout(() => {
					setShowReconnecting(true);
				}, 3000);
			}
		};

		eventSource.onopen = handleOpen;
		eventSource.onerror = handleError;
		eventSource.addEventListener("bar", handleBar as EventListener);
		eventSource.addEventListener("stream-error", handleStreamError as EventListener);

		return () => {
			clearReconnectTimer();
			eventSource.removeEventListener("bar", handleBar as EventListener);
			eventSource.removeEventListener("stream-error", handleStreamError as EventListener);
			eventSource.close();
			if (eventSourceRef.current === eventSource) {
				eventSourceRef.current = null;
			}
		};
	}, [clearReconnectTimer, selectedSymbol]);

	return (
		<div className={`bg-card rounded-lg border border-border ${className}`}>
			{showControls && (
				<div className="p-4 border-b border-border">
					<div className="flex flex-wrap items-center justify-between gap-3">
						<h3 className="text-lg font-semibold">Price Chart</h3>
						<div className="flex flex-wrap items-center gap-1 bg-muted rounded-lg p-1">
							{timeframes.map((timeframe) => (
								<button
									key={timeframe.value}
									type="button"
									onClick={() => setSelectedTimeframe(timeframe.value)}
									className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors ${
										selectedTimeframe === timeframe.value
											? "bg-primary text-primary-foreground shadow-sm"
											: "text-muted-foreground hover:text-foreground hover:bg-background"
									}`}
								>
									{timeframe.label}
								</button>
							))}
						</div>
					</div>
				</div>
			)}

			{error && (
				<div className="mx-4 mt-4 p-4 bg-destructive/10 border border-destructive/20 rounded-md">
					<p className="text-destructive font-semibold">Failed to load historical data.</p>
					<p className="text-destructive">Error: {error}</p>
				</div>
			)}

			<div className="relative p-4">
				{isLoading && (
					<div className="absolute inset-0 bg-background/90 flex items-center justify-center z-10 rounded-lg">
						<div className="flex items-center space-x-2">
							<div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary" />
							<span className="text-muted-foreground">Initializing chart...</span>
						</div>
					</div>
				)}

				{showReconnecting && realtimeStatus === "reconnecting" && (
					<div className="absolute top-8 left-1/2 z-20 -translate-x-1/2 rounded-lg border border-blue-500/30 bg-blue-500/10 px-4 py-2 text-blue-300 shadow-lg">
						<div className="flex items-center space-x-2">
							<div className="h-4 w-4 animate-spin rounded-full border-b-2 border-blue-300" />
							<span className="text-sm">Reconnecting live data...</span>
						</div>
					</div>
				)}

				{hasReachedDataLimit && dataLimitMessage && (
					<div className="absolute top-8 left-8 z-20 bg-yellow-500/10 border border-yellow-500/30 text-yellow-400 px-4 py-2 rounded-lg shadow-lg max-w-xs">
						<div className="flex items-center space-x-2">
							<div className="flex-shrink-0">
								<svg className="w-5 h-5 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
									<path
										fillRule="evenodd"
										d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
										clipRule="evenodd"
									/>
								</svg>
							</div>
							<div className="text-sm">
								<p className="font-medium">Data Limit Reached</p>
								<p className="text-xs">{dataLimitMessage}</p>
							</div>
						</div>
					</div>
				)}

				{isLoadingMoreData && (
					<div className="absolute top-8 right-8 z-20 bg-blue-500/10 border border-blue-500/30 text-blue-400 px-4 py-2 rounded-lg shadow-lg">
						<div className="flex items-center space-x-2">
							<div className="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-400" />
							<span className="text-sm">Loading more data...</span>
						</div>
					</div>
				)}

				<div
					ref={chartContainerRef}
					className="w-full max-w-full border border-border rounded-lg overflow-hidden"
					style={{ height: `${height}px` }}
				/>
			</div>
		</div>
	);
}
