FROM oven/bun:1.3.13-debian@sha256:e95356cb8e1de62ad69ab3bd3584ba947013d27650a226804d2fc0af4e17dac2 AS dependencies

WORKDIR /app

COPY package.json bun.lock bunfig.toml ./
RUN bun install --frozen-lockfile

FROM dependencies AS build

WORKDIR /app

# Next.js embeds public configuration in browser bundles. These values are
# publishable Supabase settings, never provider credentials.
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL
ENV NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY
ENV NEXT_TELEMETRY_DISABLED=1

COPY . .
# Route discovery imports server handlers during the build. These placeholders
# satisfy schema validation only and do not persist into the runtime stage.
RUN ALPACA_API_KEY=build-only-alpaca-key \
    ALPACA_SECRET_KEY=build-only-alpaca-secret \
    GEMINI_API_KEY=build-only-gemini-key \
    bun run build

FROM node:24.21.0-bookworm-slim@sha256:2fe369e969550cde8e867afc3fe370b260140cab4a23d467074295b42163d553 AS runtime

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

RUN apt-get update \
    && apt-get install --only-upgrade --yes libpcre2-8-0 \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx \
    && groupadd --gid 1001 indus \
    && useradd --uid 1001 --gid indus --create-home indus

WORKDIR /app

COPY --from=build --chown=indus:indus /app/public ./public
COPY --from=build --chown=indus:indus /app/.next/standalone ./
COPY --from=build --chown=indus:indus /app/.next/static ./.next/static

USER indus

EXPOSE 3000

CMD ["node", "server.js"]
