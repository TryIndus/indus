import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
	return twMerge(clsx(inputs));
}

type NumericValue = number | null | undefined;

export function formatLargeNumber(value: NumericValue): string {
	if (value === null || value === undefined) return "—";
	if (value >= 1e12) return `${(value / 1e12).toFixed(1)}T`;
	if (value >= 1e9) return `${(value / 1e9).toFixed(1)}B`;
	if (value >= 1e6) return `${(value / 1e6).toFixed(1)}M`;
	if (value >= 1e3) return `${(value / 1e3).toFixed(1)}K`;
	return value.toFixed(0);
}

export function formatPercent(value: NumericValue, precision = 1): string {
	return value === null || value === undefined ? "—" : `${(value * 100).toFixed(precision)}%`;
}

export function formatPercentagePoints(value: NumericValue, precision = 2): string {
	return value === null || value === undefined ? "—" : `${value.toFixed(precision)}%`;
}

export function formatCurrency(value: NumericValue): string {
	if (value === null || value === undefined) return "—";
	if (value >= 1e12) return `$${(value / 1e12).toFixed(1)}T`;
	if (value >= 1e9) return `$${(value / 1e9).toFixed(1)}B`;
	if (value >= 1e6) return `$${(value / 1e6).toFixed(1)}M`;
	if (value >= 1e3) return `$${(value / 1e3).toFixed(1)}K`;
	return `$${value.toFixed(2)}`;
}

export function formatRatio(value: NumericValue, precision = 1): string {
	return value === null || value === undefined ? "—" : value.toFixed(precision);
}
