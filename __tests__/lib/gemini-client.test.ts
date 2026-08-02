import { describe, expect, test } from "vitest";
import { createGeminiRequestBody, GeminiClient } from "@/lib/ai/geminiClient";

describe("createGeminiRequestBody", () => {
	test("keeps system instructions out of user conversation content", () => {
		const body = createGeminiRequestBody([
			{ role: "system", parts: [{ text: "Follow the supplied data." }] },
			{ role: "user", parts: [{ text: "Explain this metric." }] },
		]);

		expect(body.systemInstruction).toEqual({ parts: [{ text: "Follow the supplied data." }] });
		expect(body.contents).toEqual([
			{ role: "user", parts: [{ text: "Explain this metric." }] },
		]);
	});
});

describe("GeminiClient.parseSseBuffer", () => {
	test("preserves an incomplete event for the next transport chunk", () => {
		const first = GeminiClient.parseSseBuffer('data: {"candidates":[{"content":{"parts":[{"text":"Hel');
		expect(first.texts).toEqual([]);

		const second = GeminiClient.parseSseBuffer(`${first.remainder}lo"}]}}]}\n\n`);
		expect(second.texts).toEqual(["Hello"]);
		expect(second.remainder).toBe("");
	});

	test("parses multiple complete SSE events", () => {
		const event = (text: string) =>
			`data: ${JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] })}\n\n`;
		const parsed = GeminiClient.parseSseBuffer(`${event("one")}${event("two")}`);

		expect(parsed.texts).toEqual(["one", "two"]);
	});
});
