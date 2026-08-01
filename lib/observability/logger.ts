type LogLevel = "error" | "warn" | "info";
type LogContext = Record<string, boolean | number | string | null | undefined>;

function errorDetails(error: unknown): { errorName?: string; errorMessage: string } {
	if (error instanceof Error) {
		return { errorName: error.name, errorMessage: error.message };
	}

	return { errorMessage: String(error) };
}

function writeLog(level: LogLevel, event: string, context: LogContext = {}, error?: unknown): void {
	const entry = {
		timestamp: new Date().toISOString(),
		level,
		event,
		...context,
		...(error === undefined ? {} : errorDetails(error)),
	};
	const message = JSON.stringify(entry);

	if (level === "error") {
		console.error(message);
	} else if (level === "warn") {
		console.warn(message);
	} else {
		console.info(message);
	}
}

export const logger = {
	error(event: string, error: unknown, context?: LogContext) {
		writeLog("error", event, context, error);
	},
	warn(event: string, context?: LogContext) {
		writeLog("warn", event, context);
	},
	info(event: string, context?: LogContext) {
		writeLog("info", event, context);
	},
};
