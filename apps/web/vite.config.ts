import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { loadEnv } from 'vite'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const streamProxyTarget = env.VITE_MARKET_STREAM_PROXY_TARGET
  return {
    plugins: [react(), tailwindcss()],
    define: { global: 'globalThis' },
    server: streamProxyTarget ? { proxy: { '/stream': { target: streamProxyTarget, changeOrigin: true } } } : undefined,
    test: {
      environment: 'jsdom',
      environmentOptions: { jsdom: { url: 'http://localhost/' } },
      setupFiles: './src/test/setup.ts',
      include: ['src/**/*.test.{ts,tsx}'],
      coverage: {
        provider: 'v8',
        reporter: ['text', 'json-summary'],
        include: ['src/**/*.{ts,tsx}'],
        exclude: ['src/test/**', 'src/main.tsx', 'src/**/*.test.{ts,tsx}'],
        thresholds: { statements: 80, branches: 65, functions: 75, lines: 85 },
      },
    },
  }
})
