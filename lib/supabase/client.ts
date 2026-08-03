import { createBrowserClient } from "@supabase/ssr";
import { getPublicSupabaseConfig } from "@/lib/supabase/config";

export function createClient() {
	const { url, anonKey } = getPublicSupabaseConfig();
	return createBrowserClient(url, anonKey);
}
