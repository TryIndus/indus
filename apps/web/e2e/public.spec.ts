import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'

test('protected routes fail closed to sign in', async ({ page }) => {
  await page.goto('/reports')
  await expect(page).toHaveURL(/\/auth(?:\?.*)?$/)
  await expect(page.getByRole('heading', { name: 'Welcome to Indus' })).toBeVisible()
})

test('sign-in surface has no serious accessibility violations', async ({ page }) => {
  await page.goto('/auth')
  const results = await new AxeBuilder({ page }).analyze()
  expect(results.violations.filter(item => ['serious', 'critical'].includes(item.impact ?? ''))).toEqual([])
})

test('sign-in shell stays within its local performance budget', async ({ page }) => {
  const started = Date.now()
  await page.goto('/auth')
  await expect(page.getByRole('button', { name: 'Sign in securely' })).toBeVisible()
  expect(Date.now() - started).toBeLessThan(3_000)
})
