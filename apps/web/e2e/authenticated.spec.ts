import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'

test.beforeEach(async ({ context, page }) => {
  await context.addInitScript(() => localStorage.setItem('indus:e2e-auth', 'true'))
  await page.route('**/v1/market/summary', route => route.fulfill({
    contentType: 'application/json',
    body: JSON.stringify({
      indices: [{ symbol: 'SPY', price: 542.1, changePercent: 0.62 }],
      watchlist: [{ symbol: 'AAPL', name: 'Apple Inc.', price: 228.12, changePercent: 1.08 }],
    }),
  }))
})

test('renders an authenticated dashboard using the Rails contract', async ({ page }) => {
  await page.goto('/dashboard')
  await expect(page.getByRole('heading', { name: 'Good morning' })).toBeVisible()
  await expect(page.getByRole('link', { name: /AAPL/ })).toBeVisible()
})

test('renders queryless crypto navigation', async ({ page }) => {
  await page.goto('/crypto')
  await expect(page).toHaveURL(/\/crypto$/)
  await expect(page.getByRole('heading', { name: 'Crypto markets', exact: true })).toBeVisible()
})

test('renders authenticated reports navigation', async ({ page }) => {
  await page.goto('/reports')
  await expect(page.getByRole('heading', { name: 'Reports', exact: true })).toBeVisible()
})

test('authenticated dashboard has no serious accessibility violations', async ({ page }) => {
  await page.goto('/dashboard')
  await expect(page.getByRole('heading', { name: 'Good morning' })).toBeVisible()
  const results = await new AxeBuilder({ page }).analyze()
  expect(results.violations.filter(item => ['serious', 'critical'].includes(item.impact ?? ''))).toEqual([])
})
