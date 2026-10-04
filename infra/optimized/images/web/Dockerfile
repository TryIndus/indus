FROM oven/bun:1.3.13-alpine AS build
WORKDIR /app
COPY apps/web/package.json apps/web/bun.lock ./
RUN bun install --frozen-lockfile
COPY apps/web/ ./
ARG VITE_API_URL
ARG VITE_MARKET_STREAM_URL
ARG VITE_COGNITO_AUTHORITY
ARG VITE_COGNITO_CLIENT_ID
RUN VITE_API_URL="${VITE_API_URL}" VITE_MARKET_STREAM_URL="${VITE_MARKET_STREAM_URL}" VITE_COGNITO_AUTHORITY="${VITE_COGNITO_AUTHORITY}" VITE_COGNITO_CLIENT_ID="${VITE_COGNITO_CLIENT_ID}" bun run build

FROM caddy:2.10.2-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d
COPY infra/optimized/runtime/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/dist /srv
