"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type React from "react";
import { useEffect, useState } from "react";
import { ThemeProvider } from "@/components/ThemeProvider";
import { useAuthStore } from "@/lib/stores/auth-store";

function AuthSessionManager() {
	const initialize = useAuthStore((state) => state.initialize);

	useEffect(() => {
		return initialize();
	}, [initialize]);

	return null;
}

export function AppProviders({ children }: { children: React.ReactNode }) {
	const [queryClient] = useState(
		() =>
			new QueryClient({
				defaultOptions: {
					queries: {
						refetchOnWindowFocus: false,
						staleTime: 30_000,
					},
				},
			}),
	);

	return (
		<QueryClientProvider client={queryClient}>
			<ThemeProvider>
				<AuthSessionManager />
				{children}
			</ThemeProvider>
		</QueryClientProvider>
	);
}
