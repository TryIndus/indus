"use client";

import PriceChart from "@/components/PriceChart";

export interface CryptoChartProps {
	symbol: string;
	height?: number;
	className?: string;
	showControls?: boolean;
}

export default function CryptoChart(props: CryptoChartProps) {
	return <PriceChart {...props} type="crypto" />;
}
