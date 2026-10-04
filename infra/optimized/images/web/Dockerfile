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

FROM caddy:2.11.6-alpine@sha256:c776e0c6413b544d0459665e54ec7b8b2a15000c0cbee8b254da0067b1d184ff
COPY infra/optimized/runtime/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/dist /srv
