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
	fail("Usage: indus deploy app staging [--replacement] | production or indus deploy infra staging | production plan | apply | tear-up | tear-down | destroy [--confirm]");
}

if (! ["staging", "production"].includes(operation)) {
	fail("Choose staging or production.");
}

const branch = operation === "staging" ? "staging" : "main";
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

if (! ["plan", "apply", "tear-up", "tear-down", "destroy"].includes(confirmation)) {
	fail("Infrastructure deployment requires plan, apply, tear-up, tear-down, or destroy.");
}

if (operation === "production" && ["tear-up", "tear-down", "destroy"].includes(confirmation)) {
	fail("Production lifecycle operations are not implemented.");
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

if (["tear-down", "destroy"].includes(confirmation)) {
	if (process.argv[6] !== "--confirm") {
		fail(`Staging ${confirmation} requires --confirm.`);
	}
	args.push("-f", `confirmation=${confirmation}-staging`);
}

run("gh", args, { stdio: "inherit" });
