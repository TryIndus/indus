export function getPublicSupabaseConfig() {
	const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
	const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

	if (!url || !anonKey) {
		throw new Error("Supabase public environment variables are required");
	}

	return { url, anonKey };
}
