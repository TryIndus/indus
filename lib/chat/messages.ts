import type { ChatMessage } from "@/lib/types";

export interface RegenerationRequest {
	content: string;
	history: ChatMessage[];
}

export function prepareRegeneration(messages: ChatMessage[]): RegenerationRequest | null {
	for (let index = messages.length - 1; index >= 0; index--) {
		const message = messages[index];
		if (message.role === "user") {
			return { content: message.content, history: messages.slice(0, index) };
		}
	}

	return null;
}
