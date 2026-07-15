# Unified Dockerfile for `docker compose --profile full` (ACR overseas build).
#
# Build one image:
#   docker build -f docker/Dockerfile --target <name> \
#     --build-arg WEKNORA_VERSION=v0.6.3 .
#
# Targets: app, ui, docreader, sandbox, mcp,
#   paradedb, redis, busybox, searxng, minio, neo4j, qdrant, dex,
#   clickhouse, langfuse, langfuse-worker

ARG WEKNORA_VERSION=v0.6.3

# =============================================================================
# app (from source)
# =============================================================================
FROM golang:1.26-bookworm AS app-builder

WORKDIR /app

ARG GOPRIVATE_ARG
ARG GOPROXY_ARG
ARG GOSUMDB_ARG=off
ARG APK_MIRROR_ARG

ENV GOPRIVATE=${GOPRIVATE_ARG}
ENV GOPROXY=${GOPROXY_ARG}
ENV GOSUMDB=${GOSUMDB_ARG}

RUN if [ -n "$APK_MIRROR_ARG" ]; then \
        sed -i "s@deb.debian.org@${APK_MIRROR_ARG}@g" /etc/apt/sources.list.d/debian.sources; \
    fi && \
    apt-get update && \
    apt-get install -y git build-essential libsqlite3-dev

RUN go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY cmd/download cmd/download
ARG SKIP_DUCKDB_EXTENSIONS=0
RUN if [ "$SKIP_DUCKDB_EXTENSIONS" != "1" ]; then go run cmd/download/duckdb/duckdb.go; fi
COPY . .

ARG VERSION_ARG
ARG COMMIT_ID_ARG
ARG BUILD_TIME_ARG
ARG GO_VERSION_ARG

ENV VERSION=${VERSION_ARG}
ENV COMMIT_ID=${COMMIT_ID_ARG}
ENV BUILD_TIME=${BUILD_TIME_ARG}
ENV GO_VERSION=${GO_VERSION_ARG}

RUN --mount=type=cache,target=/go/pkg/mod make build-prod
RUN --mount=type=cache,target=/go/pkg/mod cp -r /go/pkg/mod/github.com/yanyiwu/ /app/yanyiwu/

FROM debian:12.12-slim AS app

WORKDIR /app

ARG APK_MIRROR_ARG

RUN useradd -m -s /bin/bash appuser

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN if [ -n "$APK_MIRROR_ARG" ]; then \
        sed -i "s@deb.debian.org@${APK_MIRROR_ARG}@g" /etc/apt/sources.list.d/debian.sources; \
    fi && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential postgresql-client default-mysql-client tzdata sed curl bash vim wget \
        libsqlite3-0 \
        python3 python3-pip python3-dev libffi-dev libssl-dev \
        nodejs npm \
        gosu \
        ffmpeg && \
    python3 -m pip install --break-system-packages --upgrade pip setuptools wheel && \
    mkdir -p /home/appuser/.local/bin && \
    curl -LsSf https://astral.sh/uv/install.sh | CARGO_HOME=/home/appuser/.cargo UV_INSTALL_DIR=/home/appuser/.local/bin sh && \
    chown -R appuser:appuser /home/appuser && \
    ln -sf /home/appuser/.local/bin/uvx /usr/local/bin/uvx && \
    chmod +x /usr/local/bin/uvx && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data/files && \
    chown -R appuser:appuser /app /data/files

COPY --from=app-builder /go/bin/migrate /usr/local/bin/
COPY --from=app-builder /app/yanyiwu/ /go/pkg/mod/github.com/yanyiwu/
COPY --from=app-builder /app/config ./config
COPY --from=app-builder /app/scripts ./scripts
COPY --from=app-builder /app/migrations ./migrations
COPY --from=app-builder /app/dataset/samples ./dataset/samples
COPY --from=app-builder /app/skills/preloaded ./skills/preloaded
COPY --from=app-builder /app/skills/preloaded ./skills/_builtin
COPY --from=app-builder /root/.duckdb /home/appuser/.duckdb
COPY --from=app-builder /app/WeKnora .
COPY --from=app-builder /app/scripts/docker-entrypoint.sh ./scripts/docker-entrypoint.sh

RUN chmod +x ./scripts/*.sh

EXPOSE 8080
ENTRYPOINT ["./scripts/docker-entrypoint.sh"]
CMD ["./WeKnora"]

# =============================================================================
# ui (from source)
# =============================================================================
FROM node:20-alpine AS ui-builder

WORKDIR /build
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
ARG VITE_FRONTEND_COMMIT=unknown
ENV VITE_IS_DOCKER=true
ENV VITE_FRONTEND_COMMIT=${VITE_FRONTEND_COMMIT}
RUN npm run build

FROM nginx:stable-alpine AS ui

COPY --from=ui-builder /build/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/templates/default.conf.template
COPY frontend/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENV MAX_FILE_SIZE_MB=50
EXPOSE 80
ENTRYPOINT ["/docker-entrypoint.sh"]

# =============================================================================
# mcp (from source)
# =============================================================================
FROM python:3.11-slim AS mcp

WORKDIR /app
COPY mcp-server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY mcp-server/ .
RUN pip install --no-cache-dir -e .

ENV MCP_HOST=0.0.0.0
ENV MCP_PORT=8000
ENV WEKNORA_BASE_URL=http://app:8080/api/v1

EXPOSE 8000
CMD ["weknora-mcp-server", "--transport", "http", "--host", "0.0.0.0", "--port", "8000"]

# =============================================================================
# WeKnora images (import from Docker Hub)
# =============================================================================
ARG WEKNORA_VERSION=v0.6.3
FROM wechatopenai/weknora-docreader:${WEKNORA_VERSION} AS docreader
ARG WEKNORA_VERSION=v0.6.3
FROM wechatopenai/weknora-sandbox:${WEKNORA_VERSION} AS sandbox

# =============================================================================
# Third-party images (import from Docker Hub, amd64 via ACR overseas build)
# =============================================================================
FROM paradedb/paradedb:v0.22.2-pg17 AS paradedb
FROM redis:7.0-alpine AS redis
FROM busybox:1.36 AS busybox
FROM searxng/searxng:latest AS searxng
FROM minio/minio:RELEASE.2025-09-07T16-13-09Z AS minio
FROM neo4j:2025.10.1 AS neo4j
FROM qdrant/qdrant:v1.16.2 AS qdrant
FROM dexidp/dex:latest AS dex
FROM clickhouse/clickhouse-server:24.8 AS clickhouse
FROM langfuse/langfuse:3 AS langfuse
FROM langfuse/langfuse-worker:3 AS langfuse-worker
