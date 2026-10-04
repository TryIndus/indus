import { readFileSync, writeFileSync } from "node:fs";

const [manifest, ...images] = process.argv.slice(2);
if (!manifest || images.length !== 4 || images.some(image => !/@sha256:[a-f0-9]{64}$/.test(image))) {
  throw new Error("Usage: update-release-manifest.mjs <manifest> <platform-api> <research-worker> <market-data> <web>");
}
const keys = ["PLATFORM_API_IMAGE", "RESEARCH_WORKER_IMAGE", "MARKET_DATA_IMAGE", "WEB_IMAGE"];
let content = readFileSync(manifest, "utf8");
for (const [index, key] of keys.entries()) {
  const expression = new RegExp(`^${key}=.*$`, "m");
  if (!expression.test(content)) throw new Error(`missing ${key}`);
  content = content.replace(expression, `${key}=${images[index]}`);
}
writeFileSync(manifest, content);

