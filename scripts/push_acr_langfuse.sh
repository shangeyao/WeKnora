#!/usr/bin/env bash
# Push Langfuse stack images (amd64) to ACR.
#
# Prefer ACR overseas build when local Docker Hub is slow:
#   ./scripts/acr_import_langfuse.sh
#
# This script (local push) is a fallback when you already have amd64 images.
#   export ACR_USERNAME='your-aliyun-account'
#   export ACR_PASSWORD='your-acr-password'
#   ./scripts/push_acr_langfuse.sh
#
# Optional:
#   DOCKER_PLATFORM  default: linux/amd64
#   SKIP_PULL=1      use existing local images

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
TARGET_ARCH="${DOCKER_PLATFORM#linux/}"

IMAGE_MAP=(
  "langfuse/langfuse:3|langfuse-3"
  "langfuse/langfuse-worker:3|langfuse-worker-3"
  "clickhouse/clickhouse-server:24.8|clickhouse-24.8"
  "minio/minio:RELEASE.2025-09-07T16-13-09Z|minio-RELEASE.2025-09-07T16-13-09Z"
)

to_acr_image() {
  echo "${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:$1"
}

require_login() {
  if [[ -z "${ACR_USERNAME:-}" || -z "${ACR_PASSWORD:-}" ]]; then
    echo "ERROR: set ACR_USERNAME and ACR_PASSWORD before running." >&2
    exit 1
  fi
  echo "[acr] logging in to ${ACR_REGISTRY} ..."
  echo "${ACR_PASSWORD}" | docker login "${ACR_REGISTRY}" -u "${ACR_USERNAME}" --password-stdin
}

pull_images() {
  if [[ "${SKIP_PULL:-}" == "1" ]]; then
    echo "[acr] SKIP_PULL=1, skipping pulls"
    return
  fi

  local entry src tag arch
  echo "[acr] pulling Langfuse images for ${DOCKER_PLATFORM} ..."
  for entry in "${IMAGE_MAP[@]}"; do
    IFS='|' read -r src tag <<<"$entry"
    if docker image inspect "$src" >/dev/null 2>&1; then
      arch="$(docker image inspect "$src" --format '{{.Architecture}}')"
      if [[ "$arch" == "$TARGET_ARCH" ]]; then
        echo "  skip pull (exists, ${arch}): $src"
        continue
      fi
      echo "  re-pull (${arch} -> ${TARGET_ARCH}): $src"
    else
      echo "  pull (${DOCKER_PLATFORM}): $src"
    fi
    docker pull --platform "${DOCKER_PLATFORM}" "$src"
  done
}

push_images() {
  local entry src tag dst arch pushed=0 failed=0
  echo "[acr] pushing Langfuse images ..."
  for entry in "${IMAGE_MAP[@]}"; do
    IFS='|' read -r src tag <<<"$entry"
    if ! docker image inspect "$src" >/dev/null 2>&1; then
      echo "ERROR: missing local image: $src" >&2
      failed=$((failed + 1))
      continue
    fi
    arch="$(docker image inspect "$src" --format '{{.Architecture}}')"
    if [[ "$arch" != "$TARGET_ARCH" ]]; then
      echo "ERROR: $src is ${arch}, expected ${TARGET_ARCH}" >&2
      failed=$((failed + 1))
      continue
    fi
    dst="$(to_acr_image "$tag")"
    echo "  tag (${arch}): $src -> $dst"
    docker tag "$src" "$dst"
    echo "  push: $dst"
    if docker push "$dst"; then
      pushed=$((pushed + 1))
    else
      failed=$((failed + 1))
    fi
  done
  echo "[acr] done: pushed=${pushed} failed=${failed}"
  [[ "$failed" -eq 0 ]]
}

main() {
  require_login
  pull_images
  push_images
  echo
  echo "On server:"
  echo "  docker compose -f docker-compose.calb-ai.yml pull langfuse-web langfuse-worker langfuse-clickhouse langfuse-minio"
  echo "  docker compose -f docker-compose.calb-ai.yml up -d langfuse-web langfuse-worker langfuse-clickhouse langfuse-minio"
}

main "$@"
