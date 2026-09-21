FROM oven/bun:1.3.13-alpine AS build

WORKDIR /app
COPY apps/web/package.json apps/web/bun.lock ./
RUN bun install --frozen-lockfile
COPY apps/web/ ./
ARG VITE_API_URL
ARG VITE_MARKET_STREAM_URL
ARG VITE_COGNITO_AUTHORITY
ARG VITE_COGNITO_CLIENT_ID
RUN VITE_API_URL="${VITE_API_URL}" \
    VITE_MARKET_STREAM_URL="${VITE_MARKET_STREAM_URL}" \
    VITE_COGNITO_AUTHORITY="${VITE_COGNITO_AUTHORITY}" \
    VITE_COGNITO_CLIENT_ID="${VITE_COGNITO_CLIENT_ID}" \
    bun run build

FROM public.ecr.aws/aws-cli/aws-cli:2.36.48

RUN dnf upgrade --refresh --releasever=latest -y \
    && dnf clean all

COPY --from=build --chown=1000:1000 /app/dist /dist
COPY --chmod=0555 infra/images/web-publisher/publish.sh /usr/local/bin/publish-web

ENV HOME=/tmp
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/publish-web"]
