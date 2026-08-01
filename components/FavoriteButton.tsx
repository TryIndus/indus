"use client";

import { Loader2, Star } from "lucide-react";
import type React from "react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useFavorites } from "@/lib/stores/favorites-store";
import { cn } from "@/lib/utils";

interface FavoriteButtonProps {
	symbol: string;
	companyName?: string;
	className?: string;
}

export function FavoriteButtonCompact({
	symbol,
	companyName = symbol,
	className,
}: FavoriteButtonProps) {
	const { favorites, addToFavorites, removeFromFavorites, loading } = useFavorites();
	const [isToggling, setIsToggling] = useState(false);

	const isFavorited = favorites.some((fav) => fav.symbol === symbol);

	const handleToggleFavorite = async (e: React.MouseEvent) => {
		e.stopPropagation();

		if (isToggling) return;

		try {
			setIsToggling(true);

			if (isFavorited) {
				await removeFromFavorites(symbol);
			} else {
				await addToFavorites(symbol, companyName);
			}
		} catch {
			return;
		} finally {
			setIsToggling(false);
		}
	};

	const isLoading = loading || isToggling;

	return (
		<Button
			variant="ghost"
			size="sm"
			onClick={handleToggleFavorite}
			disabled={isLoading}
			className={cn(
				"h-8 w-8 p-0 transition-all duration-200 hover:scale-110 active:scale-95",
				isFavorited && "hover:bg-yellow-100 dark:hover:bg-yellow-900/20",
				className,
			)}
		>
			{isLoading ? (
				<Loader2 className="h-4 w-4 animate-spin" />
			) : (
				<Star
					className={cn(
						"h-4 w-4 transition-all duration-200",
						isFavorited
							? "fill-yellow-400 text-yellow-400"
							: "text-muted-foreground hover:text-yellow-400",
					)}
				/>
			)}
		</Button>
	);
}
