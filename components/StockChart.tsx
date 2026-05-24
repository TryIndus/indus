"use client";

import PriceChart from "@/components/PriceChart";

export interface StockChartProps {
	symbol: string;
	height?: number;
	className?: string;
	showControls?: boolean;
}

export default function StockChart(props: StockChartProps) {
	return <PriceChart {...props} type="stock" />;
}
