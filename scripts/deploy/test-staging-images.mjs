import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const script = fileURLToPath(new URL("./update-staging-images.mjs", import.meta.url));
const fixture = readFileSync(new URL("../../infra/gitops/environments/staging/values.yaml", import.meta.url), "utf8");
for (const scenario of ["valid", "production", "malformed", "mixed-registry", "missing-reference"]) {
	test(scenario, () => {
		const directory = mkdtempSync(join(tmpdir(), "indus-images-"));
		try {
			const target = join(directory, "infra/gitops/environments/staging/values.yaml");
			mkdirSync(join(directory, "infra/gitops/environments/staging"), { recursive: true });
			const original = scenario === "missing-reference" ? fixture.replace(/^  web: .*$/m, "") : fixture;
			writeFileSync(target, original);
			for (const repository of ["platform-api", "market-data", "research-worker", "web"]) {
				const account = scenario === "mixed-registry" && repository === "web" ? "222222222222" : "111111111111";
				const digest = scenario === "malformed" && repository === "web" ? "bad" : "a".repeat(64);
				writeFileSync(join(directory, `${repository}.image`), `${account}.dkr.ecr.us-east-1.amazonaws.com/indus/${repository}@sha256:${digest}\n`);
			}
			const result = spawnSync(process.execPath, [script], { cwd: directory, env: { ...process.env, GITHUB_REF_NAME: scenario === "production" ? "main" : "staging", GITHUB_SHA: "b".repeat(40) } });
			const updated = readFileSync(target, "utf8");
			if (scenario === "valid") {
				assert.equal(result.status, 0, result.stderr.toString());
				assert.equal((updated.match(/sha256:aaaaaaaa/g) ?? []).length, 4);
				assert.ok(updated.includes(`releaseId: "${"b".repeat(40)}"`));
				assert.equal(updated.split("images:")[0], original.split("images:")[0]);
			} else {
				assert.notEqual(result.status, 0);
				assert.equal(updated, original, "Failure must leave all image references untouched");
			}
		} finally {
			rmSync(directory, { recursive: true, force: true });
		}
	});
}
