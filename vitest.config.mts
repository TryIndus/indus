import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

const __dirname = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
	resolve: {
		alias: {
			"@": resolve(__dirname, "."),
		},
	},
	test: {
		environment: "node",
		include: ["__tests__/**/*.test.ts", "__tests__/**/*.test.tsx"],
		globals: true,
		coverage: {
			provider: "v8",
			include: [
				"lib/env-legacy.ts",
				"lib/realtime/alpaca-stream.ts",
				"lib/schemas/api.ts",
				"lib/security/ai-access.ts",
			],
			reporter: ["text", "html", "json-summary"],
			reportsDirectory: "coverage",
			thresholds: {
				lines: 85,
				functions: 85,
				branches: 80,
				statements: 85,
			},
		},
	},
});
