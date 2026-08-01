"use client";

import type React from "react";
import {
	Table,
	TableBody,
	TableCell,
	TableHead,
	TableHeader,
	TableRow,
} from "@/components/ui/table";
import type { FinancialData } from "@/lib/types";
import { formatCurrency, formatLargeNumber, formatPercent, formatRatio } from "@/lib/utils";
import Hoverable from "./Hoverable";
import MetricNameHover from "./MetricNameHover";

interface FinancialTableProps {
	data: FinancialData;
	onChatTrigger?: (metricKey: string, metricLabel: string, value: number | string) => void;
}

const FinancialTable: React.FC<FinancialTableProps> = ({ data, onChatTrigger }) => {
	const hasValidData = (value?: number) => {
		return value !== undefined && value !== null && value !== 0;
	};

	return (
		<div className="w-full overflow-x-auto">
			<div className="grid gap-6 lg:grid-cols-3 min-w-0">
				{/* Profile Section */}
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead colSpan={2} className="text-base font-semibold">
								Company Profile
							</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Market Cap">Market Cap</MetricNameHover>
							</TableCell>
							<TableCell className="text-right font-mono">
								<Hoverable
									symbol={data.symbol}
									metric="market_cap"
									value={data.marketCap || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Market Cap"
								>
									<span>{formatCurrency(data.marketCap)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Enterprise Value">Enterprise Value</MetricNameHover>
							</TableCell>
							<TableCell className="text-right font-mono">
								<Hoverable
									symbol={data.symbol}
									metric="enterprise_value"
									value={data.enterpriseValue || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Enterprise Value"
								>
									<span>{formatCurrency(data.enterpriseValue)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Shares Outstanding">
									Shares Outstanding
								</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="shares_outstanding"
									value={data.sharesOutstanding || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Shares Outstanding"
								>
									<span>{formatLargeNumber(data.sharesOutstanding)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Revenue">Revenue (TTM)</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="revenue"
									value={data.revenue || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Revenue (TTM)"
								>
									<span>{formatCurrency(data.revenue)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Employees">Employees</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="employees"
									value={data.employees || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Employees"
								>
									<span>{formatLargeNumber(data.employees)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
					</TableBody>
				</Table>

				{/* Margins & Profitability */}
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead colSpan={2} className="text-base font-semibold">
								Margins & Profitability
							</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Gross Margin">Gross Margin</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="gross_margin"
									value={data.grossMargins || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Gross Margin"
								>
									<span>{formatPercent(data.grossMargins)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="EBITDA Margin">EBITDA Margin</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="ebitda_margin"
									value={data.ebitdaMargins || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="EBITDA Margin"
								>
									<span>{formatPercent(data.ebitdaMargins)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Operating Margin">Operating Margin</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="operating_margin"
									value={data.operatingMargins || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Operating Margin"
								>
									<span>{formatPercent(data.operatingMargins)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Net Margin">Net Margin</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="net_margin"
									value={data.netProfitMargins || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Net Margin"
								>
									<span>{formatPercent(data.netProfitMargins)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="ROA">ROA</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="roa"
									value={data.returnOnAssets || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="ROA"
								>
									<span>{formatPercent(data.returnOnAssets)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="ROE">ROE</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="roe"
									value={data.returnOnEquity || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="ROE"
								>
									<span>{formatPercent(data.returnOnEquity)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
					</TableBody>
				</Table>

				{/* Valuation Ratios */}
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead colSpan={2} className="text-base font-semibold">
								Valuation Ratios
							</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="P/E Ratio">P/E Ratio</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="pe_ratio"
									value={data.peRatio || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="P/E Ratio"
								>
									<span>{formatRatio(data.peRatio)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Forward P/E">Forward P/E</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="forward_pe"
									value={data.forwardPE || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Forward P/E"
								>
									<span>{formatRatio(data.forwardPE)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="P/B Ratio">P/B Ratio</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="price_to_book"
									value={data.priceToBook || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="P/B Ratio"
								>
									<span>{formatRatio(data.priceToBook)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						{hasValidData(data.priceToSales) && (
							<TableRow>
								<TableCell className="font-medium">
									<MetricNameHover metricName="P/S Ratio">P/S Ratio</MetricNameHover>
								</TableCell>
								<TableCell className="text-right">
									<Hoverable
										symbol={data.symbol}
										metric="price_to_sales"
										value={data.priceToSales || 0}
										onChatTrigger={onChatTrigger}
										metricLabel="P/S Ratio"
									>
										<span>{formatRatio(data.priceToSales)}</span>
									</Hoverable>
								</TableCell>
							</TableRow>
						)}
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="EV/Sales">EV/Sales</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="ev_to_sales"
									value={data.evToSales || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="EV/Sales"
								>
									<span>{formatRatio(data.evToSales)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="EV/EBITDA">EV/EBITDA</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="ev_to_ebitda"
									value={data.evToEbitda || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="EV/EBITDA"
								>
									<span>{formatRatio(data.evToEbitda)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						{hasValidData(data.pegRatio) && (
							<TableRow>
								<TableCell className="font-medium">
									<MetricNameHover metricName="PEG Ratio">PEG Ratio</MetricNameHover>
								</TableCell>
								<TableCell className="text-right">
									<Hoverable
										symbol={data.symbol}
										metric="peg_ratio"
										value={data.pegRatio || 0}
										onChatTrigger={onChatTrigger}
										metricLabel="PEG Ratio"
									>
										<span>{formatRatio(data.pegRatio)}</span>
									</Hoverable>
								</TableCell>
							</TableRow>
						)}
					</TableBody>
				</Table>

				{/* Growth Metrics */}
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead colSpan={2} className="text-base font-semibold">
								Growth Metrics
							</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{hasValidData(data.revenueGrowth) && (
							<TableRow>
								<TableCell className="font-medium">
									<MetricNameHover metricName="Revenue Growth">Revenue Growth</MetricNameHover>
								</TableCell>
								<TableCell className="text-right">
									<Hoverable
										symbol={data.symbol}
										metric="revenue_growth"
										value={data.revenueGrowth || 0}
										onChatTrigger={onChatTrigger}
										metricLabel="Revenue Growth"
									>
										<span>{formatPercent(data.revenueGrowth)}</span>
									</Hoverable>
								</TableCell>
							</TableRow>
						)}
						{hasValidData(data.earningsGrowth) && (
							<TableRow>
								<TableCell className="font-medium">
									<MetricNameHover metricName="Earnings Growth">Earnings Growth</MetricNameHover>
								</TableCell>
								<TableCell className="text-right">
									<Hoverable
										symbol={data.symbol}
										metric="earnings_growth"
										value={data.earningsGrowth || 0}
										onChatTrigger={onChatTrigger}
										metricLabel="Earnings Growth"
									>
										<span>{formatPercent(data.earningsGrowth)}</span>
									</Hoverable>
								</TableCell>
							</TableRow>
						)}
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Beta">Beta</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="beta"
									value={data.beta || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Beta"
								>
									<span>{formatRatio(data.beta)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
					</TableBody>
				</Table>

				{/* Financial Health */}
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead colSpan={2} className="text-base font-semibold">
								Financial Health
							</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Total Cash">Total Cash</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="total_cash"
									value={data.totalCash || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Total Cash"
								>
									<span>{formatCurrency(data.totalCash)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Total Debt">Total Debt</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="total_debt"
									value={data.totalDebt || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Total Debt"
								>
									<span>{formatCurrency(data.totalDebt)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
						<TableRow>
							<TableCell className="font-medium">
								<MetricNameHover metricName="Debt-to-Equity">Debt-to-Equity</MetricNameHover>
							</TableCell>
							<TableCell className="text-right">
								<Hoverable
									symbol={data.symbol}
									metric="debt_to_equity"
									value={data.debtToEquity || 0}
									onChatTrigger={onChatTrigger}
									metricLabel="Debt-to-Equity"
								>
									<span>{formatRatio(data.debtToEquity)}</span>
								</Hoverable>
							</TableCell>
						</TableRow>
					</TableBody>
				</Table>

				{/* Dividend Information */}
				{(data.dividendYield || data.dividendRate || data.payoutRatio) && (
					<Table>
						<TableHeader>
							<TableRow>
								<TableHead colSpan={2} className="text-base font-semibold">
									Dividend Information
								</TableHead>
							</TableRow>
						</TableHeader>
						<TableBody>
							<TableRow>
								<TableCell className="font-medium">
									<MetricNameHover metricName="Dividend Yield">Dividend Yield</MetricNameHover>
								</TableCell>
								<TableCell className="text-right">
									<Hoverable
										symbol={data.symbol}
										metric="dividend_yield"
										value={data.dividendYield || 0}
										onChatTrigger={onChatTrigger}
										metricLabel="Dividend Yield"
									>
										<span>{formatPercent(data.dividendYield)}</span>
									</Hoverable>
								</TableCell>
							</TableRow>
							<TableRow>
								<TableCell className="font-medium">
									<MetricNameHover metricName="Dividend Rate">Dividend Rate</MetricNameHover>
								</TableCell>
								<TableCell className="text-right">
									<span>{formatCurrency(data.dividendRate)}</span>
								</TableCell>
							</TableRow>
							<TableRow>
								<TableCell className="font-medium">
									<MetricNameHover metricName="Payout Ratio">Payout Ratio</MetricNameHover>
								</TableCell>
								<TableCell className="text-right">
									<Hoverable
										symbol={data.symbol}
										metric="payout_ratio"
										value={data.payoutRatio || 0}
										onChatTrigger={onChatTrigger}
										metricLabel="Payout Ratio"
									>
										<span>{formatPercent(data.payoutRatio)}</span>
									</Hoverable>
								</TableCell>
							</TableRow>
						</TableBody>
					</Table>
				)}
			</div>
		</div>
	);
};

export default FinancialTable;
