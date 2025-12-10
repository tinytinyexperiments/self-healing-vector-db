# syntax=docker/dockerfile:1

##########
# Web build stage
##########
FROM node:20-bullseye-slim AS web-builder
WORKDIR /web

COPY web/package.json web/package-lock.json ./
RUN npm ci

COPY web .
RUN npm run build

##########
# Web runtime stage (Next.js)
##########
FROM node:20-bullseye-slim AS web-runtime
WORKDIR /web

ENV NODE_ENV=production
ENV PORT=3001

COPY --from=web-builder /web/.next ./.next
COPY --from=web-builder /web/public ./public
COPY --from=web-builder /web/package.json ./package.json
COPY --from=web-builder /web/package-lock.json ./package-lock.json
RUN npm ci --omit=dev

EXPOSE 3001
CMD ["npm", "run", "start"]

##########
# API build stage
##########
FROM rust:1.75-slim AS api-builder
ARG APP_NAME=self_healing_vector_db_server
WORKDIR /app

# Install build tooling once so that dependency layers stay cached.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy manifests first to leverage Docker layer caching for dependencies.
COPY Cargo.toml Cargo.lock ./

# Copy the full workspace and build the binary in release mode.
COPY src ./src
COPY tests ./tests
COPY web ./web
RUN cargo build --release --bin ${APP_NAME}

##########
# API runtime stage
##########
FROM debian:bookworm-slim AS api-runtime
ARG APP_NAME=self_healing_vector_db_server
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home appuser \
    && mkdir -p /app/data \
    && chown -R appuser:appuser /app

COPY --from=api-builder /app/target/release/${APP_NAME} /usr/local/bin/${APP_NAME}

USER appuser
ENV RUST_LOG=info
EXPOSE 3000

CMD ["self_healing_vector_db_server"]
