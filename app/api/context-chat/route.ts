import { type NextRequest, NextResponse } from "next/server";
import { GeminiApiError, GeminiClient, type GeminiMessage } from "@/lib/ai/geminiClient";
import { GEMINI_SYSTEM_PROMPT } from "@/lib/ai/geminiSystemPrompt";
import { env } from "@/lib/env";
import { logger } from "@/lib/observability/logger";
import { contextChatSchema } from "@/lib/schemas/api";
import { type AiAccessClient, checkAiAccess, getAiQuotaHeaders } from "@/lib/security/ai-access";
import { createClient } from "@/lib/supabase/server";

const encoder = new TextEncoder();

function buildConversation(
	context: unknown,
	messages: Array<{ role: "user" | "assistant"; content: string }>,
	newMessage: string,
): GeminiMessage[] {
	return [
		{ role: "system", parts: [{ text: GEMINI_SYSTEM_PROMPT }] },
		...messages.map<GeminiMessage>((message) => ({
			role: message.role === "user" ? "user" : "model",
			parts: [{ text: message.content }],
		})),
		{
			role: "user",
			parts: [
				{
					text: `<page_context>${JSON.stringify(context)}</page_context>\n<question>${newMessage}</question>`,
				},
			],
		},
	];
}

function createStreamingResponse(
	geminiClient: GeminiClient,
	messages: GeminiMessage[],
): ReadableStream<Uint8Array> {
	return new ReadableStream({
		async start(controller) {
			try {
				const geminiStream = await geminiClient.generateStreamingContent(messages);
				const reader = geminiStream.getReader();
				const decoder = new TextDecoder();

				while (true) {
					const { done, value } = await reader.read();
					if (done) break;

					for (const line of decoder.decode(value, { stream: true }).split("\n")) {
						const text = GeminiClient.parseStreamChunk(line);
						if (text) {
							controller.enqueue(encoder.encode(`data: ${JSON.stringify({ delta: text })}\n\n`));
						}
					}
				}

				controller.enqueue(encoder.encode(`data: ${JSON.stringify({ done: true })}\n\n`));
			} catch (error) {
				logger.error("context_chat.stream_failed", error);
				controller.enqueue(
					encoder.encode(
						`data: ${JSON.stringify({ error: "Unable to complete the response" })}\n\n`,
					),
				);
			} finally {
				controller.close();
			}
		},
	});
}

export async function POST(request: NextRequest) {
	try {
		const body = await request.json().catch(() => null);
		const parsed = contextChatSchema.safeParse(body);
		if (!parsed.success) {
			return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
		}

		const supabase = await createClient();
		const access = await checkAiAccess(supabase as unknown as AiAccessClient, "context-chat");
		if (!access.allowed) {
			return NextResponse.json(
				{ error: access.error },
				{ status: access.status, headers: getAiQuotaHeaders(access) },
			);
		}

		const { context, messages, newMessage } = parsed.data;
		const geminiClient = new GeminiClient(env.GEMINI_API_KEY);
		const conversation = buildConversation(context, messages, newMessage);
		const preferStreaming = request.headers.get("accept")?.includes("text/event-stream") ?? false;

		if (preferStreaming) {
			return new Response(createStreamingResponse(geminiClient, conversation), {
				headers: {
					"Content-Type": "text/event-stream",
					"Cache-Control": "no-cache",
					Connection: "keep-alive",
					...getAiQuotaHeaders(access),
				},
			});
		}

		const response = await geminiClient.generateContent(conversation);
		return NextResponse.json({ response }, { headers: getAiQuotaHeaders(access) });
	} catch (error: unknown) {
		logger.error("context_chat.request_failed", error);

		const status = error instanceof GeminiApiError && error.status === 429 ? 429 : 502;
		return NextResponse.json({ error: "Unable to generate a response" }, { status });
	}
}
