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

FROM golang:1.27.3-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c AS caddy-build
WORKDIR /src
COPY infra/optimized/images/web/caddy/go.mod infra/optimized/images/web/caddy/go.sum ./
RUN go mod download
COPY infra/optimized/images/web/caddy/main.go ./
RUN CGO_ENABLED=0 go build -mod=readonly -trimpath -ldflags='-s -w' -o /out/caddy .

FROM caddy:2.11.7-alpine@sha256:eb4d35b7452d1ab6171fbdbe8d9275b2301dad6dad92115d91e19fb9b24d510f AS proxy-runtime
COPY --from=caddy-build /out/caddy /usr/bin/caddy
COPY infra/optimized/runtime/Caddyfile /etc/caddy/Caddyfile

FROM proxy-runtime AS runtime
COPY --from=build /app/dist /srv
