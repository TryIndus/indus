import { describe, expect, it } from "vitest";
import {
	CHART_RANGES,
	filterRangeData,
	getChartRange,
	getRangeStartTimestamp,
} from "@/lib/charts/ranges";

describe("chart ranges", () => {
	it("maps product ranges to bounded provider intervals", () => {
		expect(CHART_RANGES.map(({ value }) => value)).toEqual(["1D", "5D", "1M", "6M", "1Y", "5Y"]);
		expect(getChartRange("1M").timeframe).toBe("1Hour");
		expect(getChartRange("5Y").timeframe).toBe("1Week");
	});

	it("uses an expanded fetch window so closed-market days do not empty short ranges", () => {
		const now = Date.UTC(2026, 7, 7, 12);
		const sevenDaysInSeconds = 7 * 24 * 60 * 60;
		expect(getRangeStartTimestamp("1D", now)).toBe(Math.floor(now / 1000) - sevenDaysInSeconds);
	});

	it("shows the latest session window while preserving sparse provider results", () => {
		const day = 24 * 60 * 60;
		const data = [0, 1, 2, 3].map((offset) => ({ time: offset * day, close: offset }));
		expect(filterRangeData(data, "1D").map(({ close }) => close)).toEqual([2, 3]);
		expect(filterRangeData(data.slice(0, 1), "1D")).toEqual(data.slice(0, 1));
	});
});
