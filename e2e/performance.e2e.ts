import { expect, test } from "@playwright/test";

test("@performance landing page stays within local performance budgets", async ({ page }) => {
	await page.goto("/");
	await page.waitForLoadState("networkidle");

	const metrics = await page.evaluate(() => {
		const navigation = performance.getEntriesByType("navigation")[0] as PerformanceNavigationTiming;
		const resources = performance.getEntriesByType("resource") as PerformanceResourceTiming[];
		const scriptBytes = resources
			.filter(({ initiatorType }) => initiatorType === "script")
			.reduce((total, resource) => total + resource.transferSize, 0);
		return {
			domContentLoadedMs: navigation.domContentLoadedEventEnd - navigation.startTime,
			loadMs: navigation.loadEventEnd - navigation.startTime,
			scriptBytes,
		};
	});

	expect(metrics.domContentLoadedMs).toBeLessThan(2_500);
	expect(metrics.loadMs).toBeLessThan(4_000);
	expect(metrics.scriptBytes).toBeLessThan(1_000_000);
});
