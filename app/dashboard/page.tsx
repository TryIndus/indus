import {
	ArrowRight,
	ArrowUpRight,
	Binoculars,
	BookOpenText,
	Cpu,
	Search,
	Sparkles,
} from "lucide-react";
import Link from "next/link";
import { FavoritesSection } from "@/components/FavoritesSection";
import { Button } from "@/components/ui/button";

const RESEARCH_STARTERS = [
	{ symbol: "AAPL", name: "Apple", lens: "Margins & capital return", group: "Consumer tech" },
	{ symbol: "MSFT", name: "Microsoft", lens: "Cloud growth & valuation", group: "Enterprise" },
	{
		symbol: "NVDA",
		name: "NVIDIA",
		lens: "Growth quality & expectations",
		group: "Semiconductors",
	},
	{ symbol: "AMZN", name: "Amazon", lens: "Operating leverage", group: "Commerce" },
	{ symbol: "GOOGL", name: "Alphabet", lens: "Cash generation & AI spend", group: "Platforms" },
	{ symbol: "TSLA", name: "Tesla", lens: "Margins & volatility", group: "Mobility" },
];

const THEMES = [
	{
		title: "Durable compounders",
		description: "Businesses where margins, returns, and reinvestment deserve to be read together.",
		symbols: ["MSFT", "V", "COST"],
	},
	{
		title: "AI infrastructure",
		description: "A starting set for comparing scale, valuation, and growth expectations.",
		symbols: ["NVDA", "AMD", "AVGO"],
	},
	{
		title: "Platform economics",
		description: "Study network effects through margins, growth, and capital intensity.",
		symbols: ["META", "GOOGL", "SHOP"],
	},
];

export default function Dashboard() {
	return (
		<div className="mx-auto w-full max-w-[1500px] space-y-8 px-4 pb-12 pt-2 sm:px-6 lg:px-8">
			<section className="relative overflow-hidden rounded-[1.6rem] border border-border/70 bg-card px-5 py-7 shadow-sm sm:px-8 sm:py-9">
				<div className="pointer-events-none absolute inset-y-0 right-0 hidden w-2/5 bg-[radial-gradient(circle_at_center,color-mix(in_oklab,var(--primary)_13%,transparent),transparent_68%)] md:block" />
				<div className="relative flex flex-col justify-between gap-7 md:flex-row md:items-end">
					<div>
						<p className="font-mono text-[11px] font-semibold uppercase tracking-[0.18em] text-primary">
							Dashboard
						</p>
						<h1 className="font-display mt-3 text-balance text-4xl font-medium leading-none tracking-[-0.035em] sm:text-5xl">
							Company research
						</h1>
						<p className="mt-4 max-w-xl text-sm leading-6 text-muted-foreground">
							Search a company, review its chart and fundamentals, then ask questions about the data
							on the page.
						</p>
					</div>
					<div className="flex flex-col gap-2 sm:flex-row">
						<Button asChild className="h-11 rounded-full px-5">
							<Link href="/search">
								<Search className="size-4" />
								Search companies
							</Link>
						</Button>
						<Button variant="outline" asChild className="h-11 rounded-full px-5">
							<Link href="/company/AAPL">
								Open example
								<ArrowUpRight className="size-4" />
							</Link>
						</Button>
					</div>
				</div>
			</section>

			<section aria-labelledby="workflow-heading">
				<div className="mb-4 flex items-center justify-between gap-4">
					<div>
						<div className="flex items-center gap-2 text-primary">
							<Binoculars className="size-4" />
							<p className="font-mono text-[10px] font-semibold uppercase tracking-[0.16em]">
								How it works
							</p>
						</div>
						<h2 id="workflow-heading" className="mt-1 text-xl font-semibold tracking-[-0.025em]">
							Review a company from price to fundamentals
						</h2>
					</div>
				</div>
				<div className="grid gap-3 md:grid-cols-3">
					{[
						{
							step: "01",
							icon: Search,
							title: "Discover",
							copy: "Search a listed company and open its chart, profile, and financial metrics.",
						},
						{
							step: "02",
							icon: BookOpenText,
							title: "Review",
							copy: "Compare valuation, profitability, growth, and balance-sheet metrics.",
						},
						{
							step: "03",
							icon: Cpu,
							title: "Ask",
							copy: "Ask the analyst about a metric using the company data already in view.",
						},
					].map((item) => (
						<div
							key={item.step}
							className="surface-hairline rounded-2xl border border-border/70 bg-card p-5"
						>
							<div className="flex items-center justify-between">
								<span className="flex size-9 items-center justify-center rounded-full bg-primary/10 text-primary">
									<item.icon className="size-4" />
								</span>
								<span className="font-mono text-[10px] text-muted-foreground">{item.step}</span>
							</div>
							<h3 className="mt-6 font-semibold">{item.title}</h3>
							<p className="mt-2 text-sm leading-6 text-muted-foreground">{item.copy}</p>
						</div>
					))}
				</div>
			</section>

			<FavoritesSection />

			<section aria-labelledby="starters-heading">
				<div className="mb-4 flex items-end justify-between gap-4">
					<div>
						<div className="flex items-center gap-2 text-primary">
							<Sparkles className="size-4" />
							<p className="font-mono text-[10px] font-semibold uppercase tracking-[0.16em]">
								Research starters
							</p>
						</div>
						<h2 id="starters-heading" className="mt-1 text-xl font-semibold tracking-[-0.025em]">
							Well-known names, useful questions
						</h2>
					</div>
					<Button variant="ghost" size="sm" asChild className="hidden sm:inline-flex">
						<Link href="/search">
							Search all
							<ArrowRight className="size-3.5" />
						</Link>
					</Button>
				</div>

				<div className="grid overflow-hidden rounded-2xl border border-border/70 bg-card sm:grid-cols-2 lg:grid-cols-3">
					{RESEARCH_STARTERS.map((stock) => (
						<Link
							key={stock.symbol}
							href={`/company/${stock.symbol}`}
							className="group min-w-0 border-b border-border/70 p-5 transition-colors hover:bg-accent/40 sm:odd:border-r lg:border-r lg:[&:nth-child(3n)]:border-r-0 lg:[&:nth-last-child(-n+3)]:border-b-0"
						>
							<div className="flex items-start justify-between gap-4">
								<div className="min-w-0">
									<div className="flex items-center gap-2">
										<span className="font-mono text-sm font-bold tracking-[0.08em]">
											{stock.symbol}
										</span>
										<span className="truncate text-xs text-muted-foreground">{stock.name}</span>
									</div>
									<p className="mt-6 text-sm font-medium">{stock.lens}</p>
									<p className="mt-1 text-xs text-muted-foreground">{stock.group}</p>
								</div>
								<ArrowUpRight className="size-4 text-muted-foreground transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-primary" />
							</div>
						</Link>
					))}
				</div>
			</section>

			<section aria-labelledby="themes-heading">
				<div className="mb-4">
					<p className="font-mono text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">
						Compare a theme
					</p>
					<h2 id="themes-heading" className="mt-1 text-xl font-semibold tracking-[-0.025em]">
						Build context across companies
					</h2>
				</div>
				<div className="grid gap-3 lg:grid-cols-3">
					{THEMES.map((theme) => (
						<div key={theme.title} className="rounded-2xl border border-border/70 bg-card p-5">
							<h3 className="font-semibold">{theme.title}</h3>
							<p className="mt-2 min-h-12 text-sm leading-6 text-muted-foreground">
								{theme.description}
							</p>
							<div className="mt-6 flex flex-wrap gap-2">
								{theme.symbols.map((symbol) => (
									<Link
										key={symbol}
										href={`/company/${symbol}`}
										className="rounded-full border border-border bg-background px-3 py-1.5 font-mono text-xs font-semibold transition-colors hover:border-primary/40 hover:text-primary"
									>
										{symbol}
									</Link>
								))}
							</div>
						</div>
					))}
				</div>
			</section>
		</div>
	);
}
