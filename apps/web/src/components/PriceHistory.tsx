import { useQuery } from '@tanstack/react-query'
import { ChartNoAxesCombined } from 'lucide-react'
import { useAppContext } from '../app-context'
import { marketHistorySchema } from '../lib/api'

const width = 900
const height = 300
const inset = 24

export function PriceHistoryCard({ symbol }: { symbol: string }) {
  const { api } = useAppContext()
  const history = useQuery({
    queryKey: ['market-history', symbol],
    queryFn: ({ signal }) => api.get(`/v1/market/history/${encodeURIComponent(symbol)}`, marketHistorySchema, signal),
    retry: 1,
  })

  if (history.isPending) return <section className="card h-[24rem] animate-pulse" aria-label={`Loading ${symbol} price history`} />
  if (history.isError) return <section className="card"><h2 className="font-semibold">Price history</h2><p className="muted mt-3 text-sm">Historical prices are temporarily unavailable.</p><button type="button" className="ui-button ui-button-outline mt-4 rounded-full" onClick={() => history.refetch()}>Retry chart</button></section>

  const closes = history.data.points.map(point => point.close)
  const low = Math.min(...closes)
  const high = Math.max(...closes)
  const span = Math.max(high - low, 1)
  const coordinates = history.data.points.map((point, index) => ({
    x: inset + (index / Math.max(history.data.points.length - 1, 1)) * (width - inset * 2),
    y: inset + ((high - point.close) / span) * (height - inset * 2),
  }))
  const line = coordinates.map(point => `${point.x.toFixed(1)},${point.y.toFixed(1)}`).join(' ')
  const area = `${inset},${height - inset} ${line} ${width - inset},${height - inset}`
  const first = history.data.points[0]
  const last = history.data.points.at(-1)!
  const change = first.close > 0 ? ((last.close - first.close) / first.close) * 100 : 0

  return <section className="card" aria-labelledby="price-history-heading">
    <div className="flex flex-wrap items-start justify-between gap-4">
      <div><h2 id="price-history-heading" className="flex items-center gap-2 font-semibold"><ChartNoAxesCombined className="text-primary" size={18} />Price history</h2><p className="muted mt-1 text-xs">Daily closes · 1 year</p></div>
      <div className="text-right"><p className="text-xl font-semibold financial-number">{money(last.close, history.data.currency)}</p><p className={`text-xs font-semibold ${change >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>{change >= 0 ? '+' : ''}{change.toFixed(2)}%</p></div>
    </div>
    <svg className="mt-5 h-auto w-full" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${symbol} one-year closing price chart`}>
      <defs><linearGradient id={`history-fill-${symbol.replace(/\W/g, '')}`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="currentColor" stopOpacity="0.24"/><stop offset="1" stopColor="currentColor" stopOpacity="0.02"/></linearGradient></defs>
      {[0.25, 0.5, 0.75].map(value => <line key={value} x1={inset} x2={width - inset} y1={height * value} y2={height * value} className="stroke-border" strokeWidth="1" />)}
      <polygon points={area} className="fill-primary" opacity="0.12" />
      <polyline points={line} fill="none" className="stroke-primary" strokeWidth="3" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
    <div className="muted mt-2 flex justify-between text-xs"><span>{new Date(first.timestamp).toLocaleDateString()}</span><span>Low {money(low, history.data.currency)} · High {money(high, history.data.currency)}</span><span>{new Date(last.timestamp).toLocaleDateString()}</span></div>
  </section>
}

function money(value: number, currency: string) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(value)
}
