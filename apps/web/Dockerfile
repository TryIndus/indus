FROM oven/bun:1.3.13-alpine AS build

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

COPY . .

ARG VITE_API_URL=http://127.0.0.1:13000
ENV VITE_API_URL=${VITE_API_URL}

RUN bun run build

FROM oven/bun:1.3.13-alpine

WORKDIR /app

COPY --chown=bun:bun --from=build /app ./

USER bun

EXPOSE 4173

CMD ["bun", "run", "preview", "--host", "0.0.0.0"]
