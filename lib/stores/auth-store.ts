"use client";

import type { Session, User } from "@supabase/supabase-js";
import { create } from "zustand";
import { createClient } from "@/lib/supabase/client";

interface AuthState {
	user: User | null;
	session: Session | null;
	loading: boolean;
	initialize: () => () => void;
	signOut: () => Promise<void>;
}

export const useAuthStore = create<AuthState>((set) => ({
	user: null,
	session: null,
	loading: true,
	initialize: () => {
		const supabase = createClient();
		let active = true;

		void supabase.auth
			.getSession()
			.then(({ data: { session } }) => {
				if (!active) {
					return;
				}

				set({
					session,
					user: session?.user ?? null,
					loading: false,
				});
			})
			.catch(() => {
				if (active) {
					set({ session: null, user: null, loading: false });
				}
			});

		const {
			data: { subscription },
		} = supabase.auth.onAuthStateChange((_event, session) => {
			set({
				session,
				user: session?.user ?? null,
				loading: false,
			});
		});

		return () => {
			active = false;
			subscription.unsubscribe();
		};
	},
	signOut: async () => {
		const supabase = createClient();
		await supabase.auth.signOut();
		set({ session: null, user: null, loading: false });
		window.location.assign("/");
	},
}));

export function useAuth() {
	return useAuthStore();
}
