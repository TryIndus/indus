import { execFileSync } from "node:child_process";

const [command, component, operation, confirmation] = process.argv.slice(2);

function fail(message) {
	console.error(message);
	process.exit(1);
}

function run(commandName, args, options = {}) {
	const output = execFileSync(commandName, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...options });
	return typeof output === "string" ? output.trim() : "";
}

if (command !== "deploy" || !["app", "infra"].includes(component)) {
	fail("Usage: indus deploy app production [--replacement] | indus deploy infra production <plan|apply|plan-destroy-production|destroy-production> [--confirm]");
}

if (operation !== "production") {
	fail("Only production deployment is supported.");
}

const branch = "main";
const currentBranch = run("git", ["branch", "--show-current"]);
if (currentBranch !== branch) {
	fail(`Run this command from ${branch}; current branch is ${currentBranch || "detached HEAD"}.`);
}

run("gh", ["auth", "status"]);

if (component === "app") {
	if (confirmation === "--replacement") {
		run("gh", ["workflow", "run", "deploy-application.yml", "--ref", branch, "-f", "runtime=replacement"], { stdio: "inherit" });
		process.exit(0);
	}
	if (confirmation !== undefined) {
		fail("Application deployment does not accept an operation.");
	}
	run("gh", ["workflow", "run", "deploy-application.yml", "--ref", branch], { stdio: "inherit" });
	process.exit(0);
}

if (!["plan", "apply", "plan-destroy-production", "destroy-production"].includes(confirmation)) {
	fail("Infrastructure deployment requires plan, apply, plan-destroy-production, or destroy-production.");
}

const requiresConfirmation = ["plan-destroy-production", "destroy-production"].includes(confirmation);
if (requiresConfirmation && process.argv[6] !== "--confirm") {
	fail(`${confirmation} requires --confirm.`);
}
if (!requiresConfirmation && process.argv[6] !== undefined) {
	fail(`${confirmation} does not accept --confirm.`);
}

const args = [
	"workflow",
	"run",
	"deploy-infrastructure.yml",
	"--ref",
	branch,
	"-f",
	`operation=${confirmation}`,
];

if (requiresConfirmation) {
	args.push("-f", "confirmation=destroy-production");
}

run("gh", args, { stdio: "inherit" });
