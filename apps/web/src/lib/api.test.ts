import { z } from 'zod'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { ApiError, createApiClient } from './api'

describe('Rails API client', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('adds a bearer token and validates successful responses', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ value: 42 }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)
    const result = await createApiClient('https://api.example.test', async () => 'access-token').get('/v1/value', z.object({ value: z.number() }))
    expect(result).toEqual({ value: 42 })
    expect(fetchMock).toHaveBeenCalledWith(new URL('https://api.example.test/v1/value'), expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer access-token' }) }))
  })

  it('does not send an authorization header for anonymous requests', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)
    await createApiClient('https://api.example.test', async () => null).get('/health', z.object({ ok: z.boolean() }))
    expect(fetchMock.mock.calls[0]?.[1]?.headers).toEqual({ Accept: 'application/json' })
  })

  it('exposes bounded error metadata without leaking provider payloads', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('sensitive upstream body', { status: 503, headers: { 'x-request-id': 'req-1' } })))
    const request = createApiClient('https://api.example.test', async () => null).get('/v1/value', z.unknown())
    const error = await request.catch(cause => cause)
    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ message: 'The request could not be completed.', status: 503, requestId: 'req-1' })
  })

  it('rejects responses that violate the shared schema', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ value: '42' }), { status: 200 })))
    await expect(createApiClient('https://api.example.test', async () => null).get('/v1/value', z.object({ value: z.number() }))).rejects.toBeInstanceOf(z.ZodError)
  })
})
