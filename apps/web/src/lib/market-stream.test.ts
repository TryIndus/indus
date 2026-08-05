import { describe, expect, it, vi } from 'vitest'
import { createMarketStream } from './market-stream'

describe('market stream adapter', () => {
  it('uses a bearer header, parses quote ticks, and never places credentials in the URL', async () => {
    let cancel: () => void = () => undefined
    const finished = new Promise<void>(resolve => { cancel = resolve })
    const payload = JSON.stringify({
      id: 'event-1', symbol: 'BTC/USD', observed_at: '2026-08-05T12:00:00Z',
      payload: { bidPrice: '100', askPrice: '102' },
    })
    const request = vi.fn().mockResolvedValue(new Response(
      new ReadableStream({ start(controller) { controller.enqueue(new TextEncoder().encode(`id: event-1\nevent: quote\ndata: ${payload}\n\n`)) } }),
      { status: 200, headers: { 'content-type': 'text/event-stream' } },
    ))
    const stream = createMarketStream('https://stream.example', async () => 'private-token', request)
    let unsubscribe: () => void = () => undefined
    unsubscribe = stream.subscribe('btc/usd', tick => {
      expect(tick).toEqual({ symbol: 'BTC/USD', price: 101, timestamp: '2026-08-05T12:00:00Z' })
      unsubscribe()
      cancel()
    })
    await finished
    const [url, options] = request.mock.calls[0]
    expect(url).toBe('https://stream.example/v1/streams/BTC%2FUSD')
    expect(url).not.toContain('private-token')
    expect((options.headers as Headers).get('Authorization')).toBe('Bearer private-token')
  })

  it('does not open an unauthenticated stream', async () => {
    const request = vi.fn()
    const statuses: string[] = []
    createMarketStream('https://stream.example', async () => null, request)
      .subscribe('AAPL', () => undefined, status => statuses.push(status))
    await Promise.resolve()
    expect(request).not.toHaveBeenCalled()
    expect(statuses).toEqual(['unauthorized'])
  })
})
