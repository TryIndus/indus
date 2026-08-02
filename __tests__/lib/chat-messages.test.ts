import { describe, expect, test } from "vitest";
import { prepareRegeneration } from "@/lib/chat/messages";
import type { ChatMessage } from "@/lib/types";

describe("prepareRegeneration", () => {
	test("removes the last user turn and every response after it", () => {
		const messages: ChatMessage[] = [
			{ id: "u1", role: "user", content: "First", createdAt: 1 },
			{ id: "a1", role: "assistant", content: "Answer", createdAt: 2 },
			{ id: "u2", role: "user", content: "Again", createdAt: 3 },
			{ id: "a2", role: "assistant", content: "Old answer", createdAt: 3 },
		];

		expect(prepareRegeneration(messages)).toEqual({
			content: "Again",
			history: messages.slice(0, 2),
		});
	});

	test("returns null when no user turn exists", () => {
		expect(
			prepareRegeneration([{ id: "a1", role: "assistant", content: "Welcome", createdAt: 1 }]),
		).toBeNull();
	});
});
