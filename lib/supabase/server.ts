import { type CookieOptions, createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getPublicSupabaseConfig } from "@/lib/supabase/config";

export async function createClient() {
	const cookieStore = await cookies();
	const { url, anonKey } = getPublicSupabaseConfig();

	return createServerClient(url, anonKey, {
		cookies: {
			getAll() {
				return cookieStore.getAll();
			},
			setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
				try {
					cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
				} catch {
					// The `setAll` method was called from a Server Component.
				}
			},
		},
	});
}
