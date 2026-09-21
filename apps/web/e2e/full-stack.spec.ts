import AxeBuilder from '@axe-core/playwright'
import { expect, type APIRequestContext, type BrowserContext, test } from '@playwright/test'

const apiUrl = `http://127.0.0.1:${process.env.E2E_API_PORT ?? '13100'}`
const authorization = { Authorization: 'Bearer e2e-access-token' }
const secondaryAuthorization = { Authorization: 'Bearer e2e-secondary-access-token' }

async function authenticate(context: BrowserContext) {
  await context.addInitScript(() => localStorage.setItem('indus:e2e-auth', 'true'))
}

async function clearResources(request: APIRequestContext, resource: 'favorites' | 'reports', headers: Record<string, string>) {
  const response = await request.get(`${apiUrl}/v1/${resource}?page_size=100`, { headers })
  expect(response.status()).toBe(200)
  const page = await response.json() as { items: Array<{ id: string }> }
  for (const item of page.items) {
    const deleted = await request.delete(`${apiUrl}/v1/${resource}/${item.id}`, {
      headers: { ...headers, 'Idempotency-Key': crypto.randomUUID() },
    })
    expect(deleted.status()).toBe(204)
  }
}

test.describe('Chromium full-stack journeys', () => {
  test.beforeEach(async ({ request }) => {
    for (const headers of [authorization, secondaryAuthorization]) {
      await clearResources(request, 'favorites', headers)
      await clearResources(request, 'reports', headers)
    }
  })

  test('opens the product landing page and reaches embedded sign in', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByRole('heading', { name: 'Financial intelligence, in context.' })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Research a company without switching tools.' })).toBeVisible()
    await page.getByRole('link', { name: 'Start researching' }).click()
    await expect(page).toHaveURL(/\/auth$/)
    await expect(page.getByRole('heading', { name: 'Continue your research.' })).toBeVisible()
  })

  test('fails closed, signs in locally, and signs out of protected routes', async ({ page }) => {
    await page.goto('/reports')
    await expect(page).toHaveURL(/\/auth(?:\?.*)?$/)
    await expect(page.getByRole('heading', { name: 'Continue your research.' })).toBeVisible()

    const summary = page.waitForResponse(response =>
      response.url() === `${apiUrl}/v1/market/summary` && response.request().method() === 'GET')
    await page.getByLabel('Email').fill('investor@example.test')
    await page.locator('input[autocomplete="current-password"]').fill('Password123!Secure')
    await page.getByRole('button', { name: 'Sign in' }).click()

    expect((await summary).status()).toBe(200)
    await expect(page).toHaveURL(/\/dashboard$/)
    await expect(page.getByRole('heading', { name: 'Company research' })).toBeVisible()
    await expect(page.getByText('SPY', { exact: true })).toBeVisible()

    await page.getByRole('button', { name: 'Sign out' }).click()
    await expect(page).toHaveURL(/\/auth$/)
    expect(await page.evaluate(() => localStorage.getItem('indus:e2e-auth'))).toBeNull()

    await page.goto('/favorites')
    await expect(page).toHaveURL(/\/auth(?:\?.*)?$/)
  })

  test('persists a favorite and generates an evidence-backed brief through Rails', async ({ context, page }) => {
    await authenticate(context)
    await page.goto('/favorites')
    await expect(page.getByText('No favorites yet')).toBeVisible()

    const created = page.waitForResponse(response =>
      response.url() === `${apiUrl}/v1/favorites` && response.request().method() === 'POST')
    await page.getByLabel('Symbol').fill('tsla')
    await page.getByRole('button', { name: 'Add' }).click()

    const createResponse = await created
    expect(createResponse.status()).toBe(201)
    expect(createResponse.request().headers().authorization).toBe('Bearer e2e-access-token')
    expect(createResponse.request().headers()['idempotency-key']).toMatch(/^[0-9a-f-]{36}$/)
    await expect(page.getByText('TSLA', { exact: true })).toBeVisible()

    await page.reload()
    await expect(page.getByText('TSLA', { exact: true })).toBeVisible()

    await page.goto('/dashboard')
    await expect(page.getByRole('link', { name: /TSLA/ })).toBeVisible()
    await page.getByRole('link', { name: /TSLA/ }).click()
    await expect(page.getByRole('heading', { name: 'TSLA' })).toBeVisible()
    await expect(page.getByText('Market Cap')).toBeVisible()
    await expect(page.getByRole('img', { name: 'TSLA one-year closing price chart' })).toBeVisible()
    await expect(page.getByText(/TSLA Holdings is trading at/)).toBeVisible()
    const generated = page.waitForResponse(response =>
      response.url() === `${apiUrl}/v1/chat` && response.request().method() === 'POST')
    await page.getByRole('button', { name: 'Generate brief' }).click()
    const generatedResponse = await generated
    expect(generatedResponse.status()).toBe(200)
    expect(generatedResponse.request().headers()['idempotency-key']).toMatch(/^[0-9a-f-]{36}$/)
    await expect(page.getByText('TSLA has an evidence-backed research brief.')).toBeVisible()
    await expect(page.getByText(/Yahoo Finance quote \(TSLA\)/)).toBeVisible()

    await page.goto('/favorites')
    const deleted = page.waitForResponse(response =>
      response.url().startsWith(`${apiUrl}/v1/favorites/`) && response.request().method() === 'DELETE')
    await page.getByRole('button', { name: 'Remove' }).click()
    expect((await deleted).status()).toBe(204)
    await expect(page.getByText('No favorites yet')).toBeVisible()
  })

  test('persists and cancels a report through the browser, Rails, and PostgreSQL', async ({ context, page }) => {
    await authenticate(context)
    await page.goto('/reports')
    await expect(page.getByText('No reports yet')).toBeVisible()

    const created = page.waitForResponse(response =>
      response.url() === `${apiUrl}/v1/reports` && response.request().method() === 'POST')
    await page.getByLabel('Company symbol').fill('aapl')
    await page.getByRole('button', { name: 'Generate' }).click()

    const createResponse = await created
    expect(createResponse.status()).toBe(202)
    expect(createResponse.request().headers()['idempotency-key']).toMatch(/^[0-9a-f-]{36}$/)
    await expect(page.getByText('AAPL research report')).toBeVisible()
    await expect(page.getByText('queued', { exact: true })).toBeVisible()

    await page.reload()
    await expect(page.getByText('AAPL research report')).toBeVisible()
    const cancelled = page.waitForResponse(response =>
      response.url().endsWith('/cancel') && response.request().method() === 'POST')
    await page.getByRole('button', { name: 'Cancel' }).click()
    expect((await cancelled).status()).toBe(200)
    await expect(page.getByText('cancelled', { exact: true })).toBeVisible()

    await page.reload()
    await expect(page.getByText('cancelled', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Cancel' })).toHaveCount(0)
  })

  test('searches equities and slash-delimited crypto through the Rails provider boundary', async ({ context, page }) => {
    await authenticate(context)
    await page.goto('/search')
    await page.getByLabel('Search instruments').fill('apple')
    await page.getByRole('button', { name: 'Search' }).click()
    await expect(page.getByText('Apple Inc. · NASDAQ')).toBeVisible()

    await page.goto('/crypto')
    await expect(page.getByText('Bitcoin')).toBeVisible()
    const bitcoin = page.getByRole('link', { name: /BTC\/USD/ })
    await expect(bitcoin).toBeVisible()
    await bitcoin.click()
    await expect(page.getByRole('heading', { name: 'BTC/USD' })).toBeVisible()
    await expect(page.getByRole('img', { name: 'BTC/USD one-year closing price chart' })).toBeVisible()
  })

  test('keeps unauthenticated and cross-tenant Rails boundaries closed', async ({ request }) => {
    const response = await request.get(`${apiUrl}/v1/favorites`)
    expect(response.status()).toBe(401)
    await expect(response.json()).resolves.toMatchObject({
      status: 401,
      code: 'unauthorized',
      title: 'Authentication required',
    })

    const created = await request.post(`${apiUrl}/v1/favorites`, {
      headers: { ...authorization, 'Idempotency-Key': crypto.randomUUID() },
      data: { symbol: 'NVDA', instrument_type: 'equity' },
    })
    expect(created.status()).toBe(201)
    const favorite = await created.json() as { id: string }

    const secondaryPage = await request.get(`${apiUrl}/v1/favorites?page_size=100`, { headers: secondaryAuthorization })
    expect(secondaryPage.status()).toBe(200)
    await expect(secondaryPage.json()).resolves.toMatchObject({ items: [] })
    const hiddenDelete = await request.delete(`${apiUrl}/v1/favorites/${favorite.id}`, {
      headers: { ...secondaryAuthorization, 'Idempotency-Key': crypto.randomUUID() },
    })
    expect(hiddenDelete.status()).toBe(204)

    const primaryPage = await request.get(`${apiUrl}/v1/favorites?page_size=100`, { headers: authorization })
    expect(primaryPage.status()).toBe(200)
    await expect(primaryPage.json()).resolves.toMatchObject({ items: [{ id: favorite.id, symbol: 'NVDA' }] })
  })

  test('bounds an API failure and recovers through the visible retry', async ({ context, page }) => {
    await authenticate(context)
    let attempts = 0
    await page.route('**/v1/market/summary', route => {
      attempts += 1
      if (attempts <= 2) {
        return route.fulfill({ status: 503, contentType: 'text/plain', body: 'sensitive provider outage detail' })
      }
      return route.continue()
    })

    await page.goto('/dashboard')
    await expect(page.getByRole('alert')).toContainText('Data is temporarily unavailable', { timeout: 10_000 })
    await expect(page.getByText(/sensitive provider outage detail/)).toHaveCount(0)
    await page.getByRole('button', { name: 'Retry' }).click()

    await expect(page.getByText('No instruments yet')).toBeVisible()
    expect(attempts).toBe(3)
  })

  test('supports protected navigation at a mobile viewport', async ({ context, page }) => {
    await authenticate(context)
    await page.setViewportSize({ width: 390, height: 844 })
    await page.goto('/dashboard')

    await expect(page.getByRole('button', { name: 'Open navigation' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Reports' })).toBeHidden()
    await page.getByRole('button', { name: 'Open navigation' }).click()
    await page.getByRole('link', { name: 'Reports' }).click()

    await expect(page).toHaveURL(/\/reports$/)
    await expect(page.getByRole('heading', { name: 'Reports', exact: true })).toBeVisible()
    await expect(page.getByText('No reports yet')).toBeVisible()
  })

  test('has no serious accessibility violations on public and authenticated surfaces', async ({ context, page }) => {
    await page.goto('/auth')
    const publicResults = await new AxeBuilder({ page }).analyze()
    expect(publicResults.violations.filter(item => ['serious', 'critical'].includes(item.impact ?? ''))).toEqual([])

    await authenticate(context)
    await page.goto('/company/aapl')
    await expect(page.getByRole('heading', { name: 'AAPL' })).toBeVisible()
    const authenticatedResults = await new AxeBuilder({ page }).analyze()
    expect(authenticatedResults.violations.filter(item => ['serious', 'critical'].includes(item.impact ?? ''))).toEqual([])
  })

  test('keeps the compiled sign-in shell within its local load budget', async ({ page }) => {
    await page.goto('/auth')
    await expect(page.getByRole('button', { name: 'Sign in' })).toBeVisible()
    const loadTime = await page.evaluate(() => {
      const navigation = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming
      return navigation.loadEventEnd - navigation.startTime
    })
    expect(loadTime).toBeLessThan(3_000)
  })
})
