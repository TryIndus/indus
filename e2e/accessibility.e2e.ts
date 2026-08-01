import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

for (const path of ["/", "/auth"]) {
	test(`@accessibility ${path} has no serious accessibility violations`, async ({ page }) => {
		await page.goto(path);
		const results = await new AxeBuilder({ page })
			.withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
			.analyze();
		const seriousViolations = results.violations.filter(({ impact }) =>
			["serious", "critical"].includes(impact ?? ""),
		);
		expect(seriousViolations).toEqual([]);
	});
}
