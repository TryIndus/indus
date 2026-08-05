import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider, createMemoryHistory } from '@tanstack/react-router'
import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { AppContextProvider } from './app-context'
import type { AppContext } from './lib/context'
import { unavailableMarketStream } from './lib/market-stream'
import { makeRouter } from './router'

function context(authenticated: boolean): AppContext {
  return {
    auth: { getUser: vi.fn(async () => authenticated ? { id: 'user-1', email: 'user@example.test' } : null), signIn: vi.fn(), signOut: vi.fn(), accessToken: vi.fn(async () => null) },
    api: { get: async (_path, schema) => schema.parse({ indices: [], watchlist: [] }) },
    queryClient: new QueryClient({ defaultOptions: { queries: { retry: false } } }),
    marketStream: unavailableMarketStream,
  }
}

async function renderPath(path: string, authenticated: boolean) {
  const value = context(authenticated)
  const router = makeRouter(value, createMemoryHistory({ initialEntries: [path] }))
  render(<AppContextProvider value={value}><QueryClientProvider client={value.queryClient}><RouterProvider router={router} /></QueryClientProvider></AppContextProvider>)
  await waitFor(() => expect(router.state.status).toBe('idle'))
  return router
}

describe('application routing', () => {
  it('redirects an anonymous user away from protected pages', async () => {
    const router = await renderPath('/reports', false)
    expect(router.state.location.pathname).toBe('/auth')
    expect(await screen.findByRole('heading', { name: 'Welcome to Indus' })).toBeVisible()
  })

  it('renders the authenticated dashboard with an empty watchlist state', async () => {
    await renderPath('/dashboard', true)
    expect(await screen.findByRole('heading', { name: 'Good morning' })).toBeVisible()
    expect(await screen.findByText('No instruments yet')).toBeVisible()
  })

  it('normalizes company symbols for display', async () => {
    await renderPath('/company/aapl', true)
    expect(await screen.findByRole('heading', { name: 'AAPL' })).toBeVisible()
    expect(screen.getByText(/Phase 3/)).toBeVisible()
  })
})
