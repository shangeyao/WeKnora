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
WEKNORA_VERSION="${WEKNORA_VERSION:-}"
if [[ -z "$WEKNORA_VERSION" && -f .env ]]; then
  _env_ver="$(grep -E '^WEKNORA_VERSION=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs)" || true
  if [[ -n "$_env_ver" && ! "$_env_ver" =~ ^# ]]; then
    WEKNORA_VERSION="$_env_ver"
  fi
fi
WEKNORA_VERSION="${WEKNORA_VERSION:-latest}"
export WEKNORA_VERSION

# local_source|acr_tag|notes|build_mode (source|pull)
IMAGE_MAP=(
  "weknora-app:local|app-${WEKNORA_VERSION}|app from source|source"
  "wechatopenai/weknora-ui:${WEKNORA_VERSION}|ui-${WEKNORA_VERSION}|UI from source|source"
  "wechatopenai/weknora-docreader:${WEKNORA_VERSION}|docreader-${WEKNORA_VERSION}|"
  "wechatopenai/weknora-sandbox:${WEKNORA_VERSION}|sandbox-${WEKNORA_VERSION}|"
  "paradedb/paradedb:v0.22.2-pg17|paradedb-v0.22.2-pg17|"
  "redis:7.0-alpine|redis-7.0-alpine|"
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
  if [[ "${SKIP_LOGIN:-}" == "1" ]]; then
    echo "[acr] SKIP_LOGIN=1, assuming existing docker login"
    return
  fi
  if [[ -z "${ACR_USERNAME:-}" || -z "${ACR_PASSWORD:-}" ]]; then
    if python3 -c "import json, pathlib; d=json.loads(pathlib.Path.home().joinpath('.docker/config.json').read_text()); exit(0 if '${ACR_REGISTRY}' in d.get('auths',{}) else 1)" 2>/dev/null; then
      echo "[acr] using existing docker login for ${ACR_REGISTRY}"
      return
    fi
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

  echo "[acr] building app for ${DOCKER_PLATFORM} (docker/Dockerfile --target app) ..."
  docker build --platform "${DOCKER_PLATFORM}" -f docker/Dockerfile --target app \
    --build-arg SKIP_DUCKDB_EXTENSIONS=1 \
    --build-arg "WEKNORA_VERSION=${WEKNORA_VERSION}" \
    -t weknora-app:local .

  echo "[acr] building ui for ${DOCKER_PLATFORM} (docker/Dockerfile --target ui) ..."
  docker build --platform "${DOCKER_PLATFORM}" -f docker/Dockerfile --target ui \
    --build-arg "WEKNORA_VERSION=${WEKNORA_VERSION}" \
    -t "wechatopenai/weknora-ui:${WEKNORA_VERSION}" .
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
    IFS='|' read -r src tag _note mode <<<"$entry"
    if [[ "${mode:-}" == "source" ]]; then
      echo "  skip pull (source build): $src"
      continue
    fi
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
    if ! docker pull --platform "${DOCKER_PLATFORM}" "$src"; then
      echo "ERROR: pull failed for $src" >&2
      return 1
    fi
  done
}

push_all_images() {
  local entry src tag _note dst pushed=0 failed=0
  echo "[acr] pushing ${#IMAGE_MAP[@]} images to $(to_acr_image '<tag>') ..."
  for entry in "${IMAGE_MAP[@]}"; do
    IFS='|' read -r src tag _note _mode <<<"$entry"
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
  echo "[acr] generating docker-compose.calb-ai.yml (WEKNORA_VERSION=${WEKNORA_VERSION}) ..."
  WEKNORA_VERSION="${WEKNORA_VERSION}" python3 "${ROOT}/scripts/generate_calb_ai_compose.py"
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
