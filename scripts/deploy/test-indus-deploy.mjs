import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const script = fileURLToPath(new URL("./indus-deploy.mjs", import.meta.url));

for (const [name, args, expected] of [
	["production application", ["deploy", "app", "production"], "workflow run deploy-application.yml --ref main"],
	["production plan", ["deploy", "infra", "production", "plan"], "workflow run deploy-infrastructure.yml --ref main -f operation=plan"],
	["production destroy plan", ["deploy", "infra", "production", "plan-destroy-production", "--confirm"], "workflow run deploy-infrastructure.yml --ref main -f operation=plan-destroy-production -f confirmation=destroy-production"],
	["production destroy", ["deploy", "infra", "production", "destroy-production", "--confirm"], "workflow run deploy-infrastructure.yml --ref main -f operation=destroy-production -f confirmation=destroy-production"],
	["staging disabled", ["deploy", "app", "staging"], null],
	["staging infrastructure disabled", ["deploy", "infra", "staging", "apply"], null],
	["destroy requires confirmation", ["deploy", "infra", "production", "destroy-production"], null],
	["ordinary plan rejects confirmation", ["deploy", "infra", "production", "plan", "--confirm"], null],
]) {
	test(name, () => {
		const directory = mkdtempSync(join(tmpdir(), "indus-deploy-"));
		const log = join(directory, "gh.log");
		try {
			const git = join(directory, "git");
			const gh = join(directory, "gh");
			writeFileSync(git, "#!/bin/sh\nprintf 'main\\n'\n");
			writeFileSync(gh, "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$INDUS_TEST_GH_LOG\"\n");
			chmodSync(git, 0o755);
			chmodSync(gh, 0o755);
			const result = spawnSync(process.execPath, [script, ...args], {
				env: { ...process.env, PATH: `${directory}:${process.env.PATH}`, INDUS_TEST_GH_LOG: log },
				encoding: "utf8",
			});
			if (expected) {
				assert.equal(result.status, 0, result.stderr);
				assert.equal(readFileSync(log, "utf8").trim().split("\n").at(-1), expected);
			} else {
				assert.notEqual(result.status, 0);
				assert.equal(result.stderr.includes("workflow run"), false);
			}
		} finally {
			rmSync(directory, { recursive: true, force: true });
		}
	});
}
