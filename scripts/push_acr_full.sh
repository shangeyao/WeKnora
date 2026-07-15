#!/usr/bin/env bash
# Push all Docker images required by docker-compose.calb-ai.yml to Alibaba Cloud ACR.
#
# Target format (single repository, upstream version preserved in tag):
#   ${ACR_REGISTRY}/${ACR_NAMESPACE}/weknora:<component>-<upstream-version>
#
# Usage:
#   export ACR_USERNAME='your-aliyun-account'
#   export ACR_PASSWORD='your-acr-password'
#   ./scripts/push_acr_full.sh
#
# Optional:
#   ACR_REGISTRY   default: crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com
#   ACR_NAMESPACE  default: calb_ai
#   ACR_REPO       default: weknora
#   WEKNORA_VERSION default: latest  (matches upstream docker-compose.yml)
#   FRONTEND_PORT  default: 8081
#   SKIP_BUILD=1   skip local image builds
#   SKIP_PULL=1    skip pulling third-party images
#   LIST_ONLY=1    print mapping and exit
#   DOCKER_PLATFORM default: linux/amd64 (target server arch; use on Apple Silicon Macs)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
WEKNORA_VERSION="${WEKNORA_VERSION:-latest}"
FRONTEND_PORT="${FRONTEND_PORT:-8081}"
COMPOSE=(docker compose -f docker-compose.yml --profile full)

# local_source|acr_tag|notes
IMAGE_MAP=(
  "weknora-app:local|app-${WEKNORA_VERSION}|local LDAP build"
  "wechatopenai/weknora-ui:${WEKNORA_VERSION}|ui-${WEKNORA_VERSION}|local UI build"
  "wechatopenai/weknora-docreader:${WEKNORA_VERSION}|docreader-${WEKNORA_VERSION}|"
  "wechatopenai/weknora-sandbox:${WEKNORA_VERSION}|sandbox-${WEKNORA_VERSION}|"
  "weknora-mcp:local|mcp-${WEKNORA_VERSION}|local build"
  "paradedb/paradedb:v0.22.2-pg17|paradedb-v0.22.2-pg17|"
  "redis:7.0-alpine|redis-7.0-alpine|"
  "osixia/openldap:1.5.0|openldap-1.5.0|"
  "busybox:1.36|busybox-1.36|"
  "searxng/searxng:latest|searxng-latest|"
  "minio/minio:RELEASE.2025-09-07T16-13-09Z|minio-RELEASE.2025-09-07T16-13-09Z|"
  "neo4j:2025.10.1|neo4j-2025.10.1|"
  "qdrant/qdrant:v1.16.2|qdrant-v1.16.2|"
  "dexidp/dex:latest|dex-latest|"
  "clickhouse/clickhouse-server:24.8|clickhouse-24.8|"
  "langfuse/langfuse:3|langfuse-3|"
  "langfuse/langfuse-worker:3|langfuse-worker-3|"
)

to_acr_image() {
  local tag="$1"
  echo "${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:${tag}"
}

list_images() {
  local entry src tag note
  printf "%-4s %-45s %-40s %s\n" "#" "本地镜像" "ACR 地址" "备注"
  printf "%s\n" "------------------------------------------------------------------------------------------------------------------------"
  local i=1
  for entry in "${IMAGE_MAP[@]}"; do
    IFS='|' read -r src tag note <<<"$entry"
    printf "%-4s %-45s %-40s %s\n" "$i" "$src" "$(to_acr_image "$tag")" "$note"
    i=$((i + 1))
  done
}

require_login() {
  if [[ -z "${ACR_USERNAME:-}" || -z "${ACR_PASSWORD:-}" ]]; then
    echo "ERROR: set ACR_USERNAME and ACR_PASSWORD before running." >&2
    exit 1
  fi
  echo "[acr] logging in to ${ACR_REGISTRY} ..."
  echo "${ACR_PASSWORD}" | docker login "${ACR_REGISTRY}" -u "${ACR_USERNAME}" --password-stdin
}

build_local_images() {
  if [[ "${SKIP_BUILD:-}" == "1" ]]; then
    echo "[acr] SKIP_BUILD=1, skipping local builds"
    return
  fi

  echo "[acr] building frontend dist (local UI changes) ..."
  ./scripts/build_frontend_dist.sh

  echo "[acr] building local app (LDAP) for ${DOCKER_PLATFORM} ..."
  docker build --platform "${DOCKER_PLATFORM}" --target builder -f docker/Dockerfile.app -t weknora-app-builder:local .
  docker build --platform "${DOCKER_PLATFORM}" -f docker/Dockerfile.app.local -t weknora-app:local .

  echo "[acr] building local frontend image for ${DOCKER_PLATFORM} ..."
  DOCKER_DEFAULT_PLATFORM="${DOCKER_PLATFORM}" FRONTEND_PORT="${FRONTEND_PORT}" "${COMPOSE[@]}" build frontend

  echo "[acr] building mcp image for ${DOCKER_PLATFORM} ..."
  docker build --platform "${DOCKER_PLATFORM}" -t weknora-mcp:local ./mcp-server
}

pull_third_party_images() {
  if [[ "${SKIP_PULL:-}" == "1" ]]; then
    echo "[acr] SKIP_PULL=1, skipping pulls"
    return
  fi

  local entry src tag _note target_arch
  target_arch="${DOCKER_PLATFORM#linux/}"
  echo "[acr] pulling third-party images for ${DOCKER_PLATFORM} ..."
  for entry in "${IMAGE_MAP[@]}"; do
    IFS='|' read -r src tag _note <<<"$entry"
    if docker image inspect "$src" >/dev/null 2>&1; then
      local arch
      arch="$(docker image inspect "$src" --format '{{.Architecture}}')"
      if [[ "$arch" == "$target_arch" ]]; then
        echo "  skip pull (exists, ${arch}): $src"
        continue
      fi
      echo "  re-pull (${arch} -> ${target_arch}): $src"
    else
      echo "  pull (${DOCKER_PLATFORM}): $src"
    fi
    docker pull --platform "${DOCKER_PLATFORM}" "$src" || echo "WARN: pull failed for $src" >&2
  done
}

push_all_images() {
  local entry src tag _note dst pushed=0 failed=0
  echo "[acr] pushing ${#IMAGE_MAP[@]} images to $(to_acr_image '<tag>') ..."
  for entry in "${IMAGE_MAP[@]}"; do
    IFS='|' read -r src tag _note <<<"$entry"
    if ! docker image inspect "$src" >/dev/null 2>&1; then
      echo "ERROR: missing local image: $src" >&2
      failed=$((failed + 1))
      continue
    fi
    dst="$(to_acr_image "$tag")"
    local arch
    arch="$(docker image inspect "$src" --format '{{.Architecture}}')"
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

generate_calb_ai_compose() {
  echo "[acr] generating docker-compose.calb-ai.yml ..."
  python3 "${ROOT}/scripts/generate_calb_ai_compose.py"
}

main() {
  if [[ "${LIST_ONLY:-}" == "1" ]]; then
    list_images
    exit 0
  fi
  require_login
  build_local_images
  pull_third_party_images
  push_all_images
  generate_calb_ai_compose
  echo
  echo "Deploy from ACR:"
  echo "  docker login ${ACR_REGISTRY}"
  echo "  docker compose -f docker-compose.calb-ai.yml up -d"
}

main "$@"
