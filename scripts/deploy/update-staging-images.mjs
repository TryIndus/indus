import { readFileSync, writeFileSync } from "node:fs";

if (process.env.GITHUB_REF_NAME !== "staging") {
	throw new Error("Replacement image updates require staging.");
}
const revision = process.env.GITHUB_SHA;
if (!/^[a-f0-9]{40}$/.test(revision ?? "")) {
	throw new Error("A full source revision is required.");
}
const file = "infra/gitops/environments/staging/values.yaml";
let values = readFileSync(file, "utf8");
let registry;
for (const [key, repository] of Object.entries({
	platformApi: "platform-api",
	marketData: "market-data",
	researchWorker: "research-worker",
	web: "web",
})) {
	const image = readFileSync(`${repository}.image`, "utf8").trim();
	const match = image.match(new RegExp(`^(\\d{12}\\.dkr\\.ecr\\.us-east-1\\.amazonaws\\.com)/indus/${repository}@sha256:[a-f0-9]{64}$`));
	if (!match || (registry && registry !== match[1])) {
		throw new Error(`Invalid or inconsistent registry for ${repository}.`);
	}
	registry = match[1];
	const pattern = new RegExp(`^  ${key}: [^\\n]+/indus/${repository}@sha256:[a-f0-9]{64}$`, "gm");
	if ([...values.matchAll(pattern)].length !== 1) {
		throw new Error(`Expected exactly one ${key} image reference.`);
	}
	values = values.replace(pattern, `  ${key}: ${image}`);
}
const release = /^webPublisher: \{ releaseId: "[a-f0-9]{40}" \}$/gm;
if ([...values.matchAll(release)].length !== 1) {
	throw new Error("Expected exactly one web release reference.");
}
values = values.replace(release, `webPublisher: { releaseId: "${revision}" }`);
writeFileSync(file, values);
