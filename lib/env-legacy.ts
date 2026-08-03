const LEGACY_KEY_MAP: Record<string, string> = {
	ALPACA_API_KEY: "NEXT_PUBLIC_ALPACA_API_KEY",
	ALPACA_SECRET_KEY: "NEXT_PUBLIC_ALPACA_SECRET_KEY",
	ALPACA_IS_PAPER: "NEXT_PUBLIC_ALPACA_IS_PAPER",
};

// Deprecated shim: falls back to NEXT_PUBLIC_ALPACA_* if the server-only names are unset.
// The legacy names leak Alpaca credentials into the client bundle. Tracked for removal.
export function coalesceLegacyEnv(
	source: Readonly<Record<string, string | undefined>>,
): Record<string, string | undefined> {
	const next = { ...source };
	const usedLegacy: string[] = [];
	for (const [canonical, legacy] of Object.entries(LEGACY_KEY_MAP)) {
		if (!next[canonical] && source[legacy]) {
			next[canonical] = source[legacy];
			usedLegacy.push(legacy);
		}
	}
	if (usedLegacy.length > 0) {
		console.warn(
			`[env] Using deprecated ${usedLegacy.join(", ")}. ` +
				"These leak credentials into the client bundle. " +
				"Set the non-public equivalents and remove the NEXT_PUBLIC_ versions.",
		);
	}
	return next;
}
