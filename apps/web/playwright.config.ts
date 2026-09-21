import { defineConfig, devices } from '@playwright/test'

const apiPort = process.env.E2E_API_PORT ?? '13100'

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    locale: 'en-CA',
    timezoneId: 'America/Toronto',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  webServer: {
    command: `VITE_E2E_AUTH=true VITE_API_URL=http://127.0.0.1:${apiPort} bun run build && bun run preview --host 127.0.0.1`,
    port: 4173,
    reuseExistingServer: false,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
})
