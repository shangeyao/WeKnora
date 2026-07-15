#!/usr/bin/env python3
"""Generate docker/acr-import/*.Dockerfile stubs for third-party ACR overseas builds."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docker" / "acr-import"

# filename -> FROM image
IMPORTS = {
    "paradedb.Dockerfile": "paradedb/paradedb:v0.22.2-pg17",
    "redis.Dockerfile": "redis:7.0-alpine",
    "openldap.Dockerfile": "osixia/openldap:1.5.0",
    "busybox.Dockerfile": "busybox:1.36",
    "searxng.Dockerfile": "searxng/searxng:latest",
    "minio.Dockerfile": "minio/minio:RELEASE.2025-09-07T16-13-09Z",
    "neo4j.Dockerfile": "neo4j:2025.10.1",
    "qdrant.Dockerfile": "qdrant/qdrant:v1.16.2",
    "dex.Dockerfile": "dexidp/dex:latest",
    "clickhouse.Dockerfile": "clickhouse/clickhouse-server:24.8",
    "langfuse-web.Dockerfile": "langfuse/langfuse:3",
    "langfuse-worker.Dockerfile": "langfuse/langfuse-worker:3",
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, upstream in IMPORTS.items():
        path = OUT / name
        path.write_text(
            f"# Imported by ACR overseas build (linux/amd64).\nFROM {upstream}\n",
            encoding="utf-8",
        )
        print(f"wrote {path.relative_to(ROOT)}")
    print(f"done: {len(IMPORTS)} import dockerfiles")


if __name__ == "__main__":
    main()
