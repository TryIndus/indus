import { z, type ZodType } from 'zod'

export class ApiError extends Error {
  readonly status: number
  readonly requestId?: string
  constructor(message: string, status: number, requestId?: string) { super(message); this.status = status; this.requestId = requestId }
}

export interface ApiClient {
  get<T>(path: string, schema: ZodType<T>, signal?: AbortSignal): Promise<T>
}

export function createApiClient(baseUrl: string, token: () => Promise<string | null>): ApiClient {
  return { async get(path, schema, signal) {
    const accessToken = await token()
    const response = await fetch(new URL(path, baseUrl), {
      signal,
      headers: { Accept: 'application/json', ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}) },
    })
    if (!response.ok) throw new ApiError('The request could not be completed.', response.status, response.headers.get('x-request-id') ?? undefined)
    return schema.parse(await response.json())
  } }
}

export const marketSummarySchema = z.object({
  indices: z.array(z.object({ symbol: z.string(), price: z.number(), changePercent: z.number() })),
  watchlist: z.array(z.object({ symbol: z.string(), name: z.string(), price: z.number(), changePercent: z.number() })),
})
export type MarketSummary = z.infer<typeof marketSummarySchema>
