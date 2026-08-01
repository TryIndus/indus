import Alpaca from "@alpacahq/alpaca-trade-api";
import type {
	AlpacaBar,
	CryptoBar,
} from "@alpacahq/alpaca-trade-api/dist/resources/datav2/entityv2";
import { env } from "@/lib/env";
import { logger } from "@/lib/observability/logger";
import {
	extractBarSymbol,
	formatSseMessage,
	getNextEventId,
	isCryptoSymbol,
	normalizeStreamSymbol,
	toCryptoCandlestickData,
	toStockCandlestickData,
} from "@/lib/realtime/alpaca-stream";
import { streamParamsSchema } from "@/lib/schemas/api";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

type AlpacaInstance = InstanceType<typeof Alpaca>;
type AlpacaStockStream = AlpacaInstance["data_stream_v2"];
type AlpacaCryptoStream = AlpacaInstance["crypto_stream_v1beta3"];

type AlpacaStream = AlpacaStockStream | AlpacaCryptoStream;

const encoder = new TextEncoder();

export async function GET(request: Request, { params }: { params: Promise<{ symbol: string }> }) {
	let decodedSymbol: string;

	try {
		const resolvedParams = await params;
		decodedSymbol = decodeURIComponent(resolvedParams.symbol);
	} catch {
		return Response.json({ error: "Invalid stream symbol" }, { status: 400 });
	}

	const parsed = streamParamsSchema.safeParse({ symbol: decodedSymbol });
	if (!parsed.success) {
		return Response.json({ error: "Invalid stream symbol" }, { status: 400 });
	}

	const symbol = normalizeStreamSymbol(parsed.data.symbol);
	const assetType = isCryptoSymbol(symbol) ? "crypto" : "stock";
	let cleanup: (() => void) | null = null;

	const stream = new ReadableStream<Uint8Array>({
		start(controller) {
			let alpacaStream: AlpacaStream | null = null;
			let eventId = getNextEventId(request.headers.get("last-event-id"));
			let heartbeat: ReturnType<typeof setInterval> | null = null;
			let closed = false;

			const enqueue = (chunk: string) => {
				if (!closed) {
					controller.enqueue(encoder.encode(chunk));
				}
			};

			const close = () => {
				if (closed) {
					return;
				}

				closed = true;

				if (heartbeat) {
					clearInterval(heartbeat);
					heartbeat = null;
				}

				try {
					if (assetType === "crypto") {
						(alpacaStream as AlpacaCryptoStream | null)?.unsubscribeFromBars([symbol]);
					} else {
						(alpacaStream as AlpacaStockStream | null)?.unsubscribeFromBars([symbol]);
					}
				} catch (error) {
					logger.error("market_stream.unsubscribe_failed", error, { symbol, assetType });
				}

				try {
					alpacaStream?.disconnect();
				} catch (error) {
					logger.error("market_stream.disconnect_failed", error, { symbol, assetType });
				}

				try {
					controller.close();
				} catch {
					// The browser may have already closed the connection.
				}
			};

			cleanup = close;

			const sendStreamError = () => {
				enqueue(
					formatSseMessage({
						id: eventId++,
						event: "stream-error",
						data: { message: "Live market data is temporarily unavailable" },
					}),
				);
				close();
			};

			const sendReady = () => {
				enqueue(formatSseMessage({ id: eventId++, event: "ready", data: { symbol, assetType } }));
			};

			const sendBar = (bar: unknown) => {
				const barSymbol = extractBarSymbol(bar) ?? symbol;
				if (normalizeStreamSymbol(barSymbol) !== symbol) {
					return;
				}

				const data =
					assetType === "crypto" ? toCryptoCandlestickData(bar) : toStockCandlestickData(bar);
				enqueue(formatSseMessage({ id: eventId++, event: "bar", data }));
			};

			const startAlpacaStream = () => {
				try {
					const alpaca = new Alpaca({
						keyId: env.ALPACA_API_KEY,
						secretKey: env.ALPACA_SECRET_KEY,
						paper: env.ALPACA_IS_PAPER,
					});

					heartbeat = setInterval(() => enqueue(": keep-alive\n\n"), 15_000);

					if (assetType === "crypto") {
						const cryptoStream = alpaca.crypto_stream_v1beta3;
						alpacaStream = cryptoStream;

						cryptoStream.onConnect(() => {
							sendReady();
							cryptoStream.subscribeForBars([symbol]);
						});
						cryptoStream.onCryptoBar((bar: CryptoBar) => sendBar(bar));
						cryptoStream.onDisconnect(close);
						cryptoStream.onError((error: Error) => {
							logger.error("market_stream.provider_failed", error, { symbol, assetType });
							sendStreamError();
						});
						cryptoStream.connect();
					} else {
						const stockStream = alpaca.data_stream_v2;
						alpacaStream = stockStream;

						stockStream.onConnect(() => {
							sendReady();
							stockStream.subscribeForBars([symbol]);
						});
						stockStream.onStockBar((bar: AlpacaBar) => sendBar(bar));
						stockStream.onDisconnect(close);
						stockStream.onError((error: Error) => {
							logger.error("market_stream.provider_failed", error, { symbol, assetType });
							sendStreamError();
						});
						stockStream.connect();
					}
				} catch (error) {
					logger.error("market_stream.start_failed", error, { symbol, assetType });
					sendStreamError();
				}
			};

			request.signal.addEventListener("abort", close, { once: true });
			startAlpacaStream();
		},
		cancel() {
			cleanup?.();
		},
	});

	return new Response(stream, {
		headers: {
			"Cache-Control": "no-cache, no-transform",
			Connection: "keep-alive",
			"Content-Type": "text/event-stream",
			"X-Accel-Buffering": "no",
		},
	});
}
