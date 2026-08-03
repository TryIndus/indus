"use client";

import { useCallback, useRef, useState } from "react";
import { prepareRegeneration } from "@/lib/chat/messages";
import { buildPageContext, trimContextIfNeeded } from "@/lib/context/buildPageContext";
import type { ChatMessage, ContextChatState, FinancialData, PageChartData } from "@/lib/types";

interface UseContextChatParams {
	getFinancialData: () => FinancialData | null;
	getChartData?: () => PageChartData | undefined;
}

interface StreamPayload {
	delta?: string;
	done?: boolean;
	error?: string;
}

const RATE_LIMIT_WINDOW_MS = 30_000;
const MAX_REQUESTS_PER_WINDOW = 5;

function isAbortError(error: unknown): boolean {
	return error instanceof Error && error.name === "AbortError";
}

function parseStreamPayload(line: string): StreamPayload | null {
	if (!line.startsWith("data: ")) {
		return null;
	}

	try {
		const value: unknown = JSON.parse(line.slice(6));
		return value && typeof value === "object" ? (value as StreamPayload) : null;
	} catch {
		return null;
	}
}

function readTextResponse(value: unknown): string {
	if (value && typeof value === "object" && "response" in value) {
		const response = (value as { response?: unknown }).response;
		if (typeof response === "string") {
			return response;
		}
	}

	return "No response received.";
}

export function useContextChat({ getFinancialData, getChartData }: UseContextChatParams) {
	const [state, setState] = useState<ContextChatState>({
		open: false,
		messages: [],
		sending: false,
		error: null,
	});

	const abortControllerRef = useRef<AbortController | null>(null);

	const requestCountRef = useRef(0);
	const lastRequestWindowRef = useRef(Date.now());

	const openWithMetric = useCallback(
		(metricKey: string, metricLabel: string, value: number | string) => {
			try {
				const financialData = getFinancialData();
				const chartData = getChartData?.();

				if (!financialData) {
					setState((prev) => ({ ...prev, error: "error" }));
					return;
				}

				const initialContext = buildPageContext({
					financialData,
					chartData,
					triggerMetric: { metricKey, metricLabel, value },
				});

				const trimmedContext = trimContextIfNeeded(initialContext);

				setState((prev) => ({
					...prev,
					open: true,
					initialContext: trimmedContext,
					triggerMetric: { metricKey, label: metricLabel, value },
					error: null,
					messages: [], // Reset messages for new metric
				}));
			} catch {
				setState((prev) => ({
					...prev,
					error: "error",
				}));
			}
		},
		[getFinancialData, getChartData],
	);

	const close = useCallback(() => {
		if (abortControllerRef.current) {
			abortControllerRef.current.abort();
			abortControllerRef.current = null;
		}

		setState((prev) => ({
			...prev,
			open: false,
			sending: false,
		}));
	}, []);

	const checkRateLimit = useCallback(() => {
		const now = Date.now();

		if (now - lastRequestWindowRef.current > RATE_LIMIT_WINDOW_MS) {
			requestCountRef.current = 0;
			lastRequestWindowRef.current = now;
		}

		if (requestCountRef.current >= MAX_REQUESTS_PER_WINDOW) {
			return false;
		}

		requestCountRef.current++;
		return true;
	}, []);

	const sendMessage = useCallback(
		async (content: string, historyOverride?: ChatMessage[]) => {
			const trimmedContent = content.trim();
			if (!trimmedContent || state.sending || !state.initialContext) return;
			const conversationHistory = historyOverride ?? state.messages;

			if (!checkRateLimit()) {
				setState((prev) => ({
					...prev,
					error: "error",
				}));
				return;
			}

			const userMessage: ChatMessage = {
				id: `user-${Date.now()}`,
				role: "user",
				content: trimmedContent,
				createdAt: Date.now(),
			};

			const assistantMessageId = `assistant-${Date.now()}`;
			const assistantMessage: ChatMessage = {
				id: assistantMessageId,
				role: "assistant",
				content: "",
				createdAt: Date.now(),
				streaming: true,
			};

			setState((prev) => ({
				...prev,
				messages: [...conversationHistory, userMessage, assistantMessage],
				sending: true,
				error: null,
			}));

			try {
				abortControllerRef.current = new AbortController();

				const response = await fetch("/api/context-chat", {
					method: "POST",
					headers: {
						"Content-Type": "application/json",
						Accept: "text/event-stream",
					},
					body: JSON.stringify({
						context: state.initialContext,
						messages: conversationHistory,
						newMessage: trimmedContent,
					}),
					signal: abortControllerRef.current.signal,
				});

				if (!response.ok) {
					throw new Error(`API error: ${response.status}`);
				}

				const isStreaming = response.headers.get("content-type")?.includes("text/event-stream");

				if (isStreaming) {
					const reader = response.body?.getReader();
					if (!reader) throw new Error("No response body");

					const decoder = new TextDecoder();
					let accumulatedContent = "";
					let bufferedContent = "";

					while (true) {
						const { done, value } = await reader.read();
						if (done) break;

						bufferedContent += decoder.decode(value, { stream: true });
						const lines = bufferedContent.split("\n");
						bufferedContent = lines.pop() ?? "";

						for (const line of lines) {
							const payload = parseStreamPayload(line);
							if (payload?.error) {
								throw new Error(payload.error);
							}
							if (payload?.delta) {
								accumulatedContent += payload.delta;
								setState((prev) => ({
									...prev,
									messages: prev.messages.map((message) =>
										message.id === assistantMessageId
											? { ...message, content: accumulatedContent, streaming: true }
											: message,
									),
								}));
							}
						}
					}

					setState((prev) => ({
						...prev,
						messages: prev.messages.map((message) =>
							message.id === assistantMessageId ? { ...message, streaming: false } : message,
						),
						sending: false,
					}));
				} else {
					const data: unknown = await response.json();
					setState((prev) => ({
						...prev,
						messages: prev.messages.map((message) =>
							message.id === assistantMessageId
								? { ...message, content: readTextResponse(data), streaming: false }
								: message,
						),
						sending: false,
					}));
				}
			} catch (error: unknown) {
				if (isAbortError(error)) {
					return;
				}

				setState((prev) => ({
					...prev,
					messages: prev.messages.filter((msg) => msg.id !== assistantMessageId),
					sending: false,
					error: "error",
				}));
			} finally {
				abortControllerRef.current = null;
			}
		},
		[state.sending, state.initialContext, state.messages, checkRateLimit],
	);

	const regenerateLast = useCallback(async () => {
		if (state.messages.length < 2 || state.sending) return;
		const regeneration = prepareRegeneration(state.messages);
		if (!regeneration) return;

		await sendMessage(regeneration.content, regeneration.history);
	}, [state.messages, state.sending, sendMessage]);

	const clearError = useCallback(() => {
		setState((prev) => ({ ...prev, error: null }));
	}, []);

	return {
		...state,
		openWithMetric,
		close,
		sendMessage,
		regenerateLast,
		clearError,
	};
}
