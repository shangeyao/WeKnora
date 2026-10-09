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
#   PUSH_PROFILE   default: full | app — version upgrades (4 images) | changes — app+ui only
#   SKIP_BUILD=1   skip local image builds
#   SKIP_PULL=1    skip pulling third-party images
#   LIST_ONLY=1    print mapping and exit
#   DOCKER_PLATFORM default: linux/amd64 (target server arch; use on Apple Silicon Macs)
#
# Version upgrade (push only app/ui/docreader/sandbox):
#   WEKNORA_VERSION=v0.7.2 FRONTEND_BASE_PATH=/weknora PUSH_PROFILE=app ./scripts/push_acr_full.sh
#
# Custom code only (skip docreader/sandbox):
#   WEKNORA_VERSION=v0.7.2 FRONTEND_BASE_PATH=/weknora PUSH_PROFILE=changes ./scripts/push_acr_full.sh

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
PUSH_PROFILE="${PUSH_PROFILE:-full}"

# local_source|acr_tag|notes|build_mode (source|pull)
APP_IMAGE_MAP=(
  "weknora-app:local|app-${WEKNORA_VERSION}|app from source|source"
  "wechatopenai/weknora-ui:${WEKNORA_VERSION}|ui-${WEKNORA_VERSION}|UI from source|source"
  "wechatopenai/weknora-docreader:${WEKNORA_VERSION}|docreader-${WEKNORA_VERSION}|"
  "wechatopenai/weknora-sandbox:${WEKNORA_VERSION}|sandbox-${WEKNORA_VERSION}|"
)
INFRA_IMAGE_MAP=(
  "paradedb/paradedb:v0.22.6-pg17|paradedb-v0.22.6-pg17|"
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
IMAGE_MAP=()

CHANGES_IMAGE_MAP=(
  "weknora-app:local|app-${WEKNORA_VERSION}|app from source|source"
  "wechatopenai/weknora-ui:${WEKNORA_VERSION}|ui-${WEKNORA_VERSION}|UI from source|source"
)

select_image_map() {
  case "$PUSH_PROFILE" in
    app)
      IMAGE_MAP=("${APP_IMAGE_MAP[@]}")
      echo "[acr] PUSH_PROFILE=app — only WeKnora application images (4)"
      ;;
    changes)
      IMAGE_MAP=("${CHANGES_IMAGE_MAP[@]}")
      echo "[acr] PUSH_PROFILE=changes — app + ui only (2)"
      ;;
    full)
      IMAGE_MAP=("${APP_IMAGE_MAP[@]}" "${INFRA_IMAGE_MAP[@]}")
      ;;
    *)
      echo "ERROR: unknown PUSH_PROFILE=${PUSH_PROFILE} (use app, changes, or full)" >&2
      exit 1
      ;;
  esac
}

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

pull_hub_images() {
  if [[ "${SKIP_PULL:-}" == "1" ]]; then
    echo "[acr] SKIP_PULL=1, skipping docreader/sandbox pull"
    return
  fi
  echo "[acr] pulling docreader + sandbox for ${DOCKER_PLATFORM} ..."
  docker pull --platform "${DOCKER_PLATFORM}" "wechatopenai/weknora-docreader:${WEKNORA_VERSION}"
  docker pull --platform "${DOCKER_PLATFORM}" "wechatopenai/weknora-sandbox:${WEKNORA_VERSION}"
}

pull_third_party_image() {
  local src="$1"
  if docker pull --platform "${DOCKER_PLATFORM}" "$src"; then
    return 0
  fi
  local mirror="${DOCKER_MIRROR_PREFIX:-docker.1ms.run}"
  echo "[acr] retry via mirror: ${mirror}/${src}" >&2
  if docker pull --platform "${DOCKER_PLATFORM}" "${mirror}/${src}"; then
    docker tag "${mirror}/${src}" "$src"
    return 0
  fi
  return 1
}

build_local_images() {
  if [[ "${SKIP_BUILD:-}" == "1" ]]; then
    echo "[acr] SKIP_BUILD=1, skipping local builds"
    if [[ "${PUSH_PROFILE}" != "changes" ]]; then
      pull_hub_images
    fi
    return
  fi

  echo "[acr] building app for ${DOCKER_PLATFORM} (builder + upstream overlay) ..."
  docker pull --platform "${DOCKER_PLATFORM}" "wechatopenai/weknora-app:${WEKNORA_VERSION}"
  docker build --platform "${DOCKER_PLATFORM}" --target builder -f docker/Dockerfile.app \
    --build-arg SKIP_DUCKDB_EXTENSIONS=1 \
    -t weknora-app-builder:local .
  docker build --platform "${DOCKER_PLATFORM}" -f docker/Dockerfile.app.overlay \
    --build-arg "WEKNORA_VERSION=${WEKNORA_VERSION}" \
    -t weknora-app:local .

  echo "[acr] building ui for ${DOCKER_PLATFORM} ..."
  ./scripts/build_frontend_dist.sh
  UI_BUILD_ARGS=(--platform "${DOCKER_PLATFORM}")
  if [ -n "${FRONTEND_BASE_PATH:-}" ] && [ "${FRONTEND_BASE_PATH}" != "/" ]; then
    base="${FRONTEND_BASE_PATH%/}"
    UI_BUILD_ARGS+=(--build-arg "VITE_BASE_PATH=${base}/")
  fi
  docker build "${UI_BUILD_ARGS[@]}" \
    -t "wechatopenai/weknora-ui:${WEKNORA_VERSION}" frontend/

  pull_hub_images
}

push_all_images() {
  local entry src tag _note mode dst pushed=0 failed=0 target_arch
  target_arch="${DOCKER_PLATFORM#linux/}"
  echo "[acr] pushing ${#IMAGE_MAP[@]} images to $(to_acr_image '<tag>') ..."
  for entry in "${IMAGE_MAP[@]}"; do
    IFS='|' read -r src tag _note mode <<<"$entry"
    if [[ "${mode:-}" != "source" ]]; then
      local need_pull=1 arch=""
      if docker image inspect "$src" >/dev/null 2>&1; then
        arch="$(docker image inspect "$src" --format '{{.Architecture}}' 2>/dev/null || true)"
        if [[ "$arch" == "$target_arch" ]]; then
          need_pull=0
        fi
      fi
      if [[ "$need_pull" == "1" ]]; then
        echo "  pull (${DOCKER_PLATFORM}): $src"
        if ! pull_third_party_image "$src"; then
          echo "ERROR: pull failed for $src" >&2
          failed=$((failed + 1))
          continue
        fi
      fi
    fi
    if ! docker image inspect "$src" >/dev/null 2>&1; then
      echo "ERROR: missing local image: $src" >&2
      failed=$((failed + 1))
      continue
    fi
    dst="$(to_acr_image "$tag")"
    local arch
    arch="$(docker image inspect "$src" --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
    echo "  tag (${arch}): $src -> $dst"
    docker tag "$src" "$dst"
    echo "  push: $dst"
    if docker push "$dst"; then
      pushed=$((pushed + 1))
      docker rmi "$src" "$dst" >/dev/null 2>&1 || true
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
  select_image_map
  if [[ "${LIST_ONLY:-}" == "1" ]]; then
    list_images
    exit 0
  fi
  require_login
  build_local_images
  push_all_images
  generate_calb_ai_compose
  echo
  echo "Deploy from ACR:"
  echo "  docker login ${ACR_REGISTRY}"
  echo "  docker compose -f docker-compose.calb-ai.yml up -d"
}

main "$@"
