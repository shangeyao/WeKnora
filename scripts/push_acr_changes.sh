#!/usr/bin/env bash
# Build and push customized WeKnora app + ui to ACR.
# App: compile WeKnora from repo, overlay onto upstream runtime (no full debian apt in build).
# UI: multi-stage frontend/Dockerfile from repo source.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
WEKNORA_VERSION="${WEKNORA_VERSION:-v0.8.0}"
# Upstream runtime base for overlay (Hub tag; only ships OS/deps, not your Go/Vue code).
RUNTIME_BASE_VERSION="${RUNTIME_BASE_VERSION:-v0.8.0}"
RUNTIME_BASE_IMAGE="${RUNTIME_BASE_IMAGE:-${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:app-${RUNTIME_BASE_VERSION}}"
FRONTEND_BASE_PATH="${FRONTEND_BASE_PATH:-/weknora}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
SKIP_LOGIN="${SKIP_LOGIN:-1}"
WITH_ANYDOC="${WITH_ANYDOC:-0}"

ACR_APP="${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:app-${WEKNORA_VERSION}"
ACR_UI="${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:ui-${WEKNORA_VERSION}"

log() { echo "[push-changes] $*"; }

require_login() {
  if [[ "${SKIP_LOGIN}" == "1" ]]; then
    log "SKIP_LOGIN=1, assuming existing docker login"
    return
  fi
  if [[ -z "${ACR_USERNAME:-}" || -z "${ACR_PASSWORD:-}" ]]; then
    echo "ERROR: set ACR_USERNAME and ACR_PASSWORD or SKIP_LOGIN=1 with docker login" >&2
    exit 1
  fi
  echo "${ACR_PASSWORD}" | docker login "${ACR_REGISTRY}" -u "${ACR_USERNAME}" --password-stdin
}

build_app_image() {
  log "pull runtime base for overlay: ${RUNTIME_BASE_IMAGE}"
  docker pull --platform "${DOCKER_PLATFORM}" "${RUNTIME_BASE_IMAGE}" || true
  docker tag "${RUNTIME_BASE_IMAGE}" "wechatopenai/weknora-app:${RUNTIME_BASE_VERSION}"

  log "compile WeKnora (builder stage, docker/Dockerfile.app.push-acr)"
  # shellcheck source=/dev/null
  eval "$(./scripts/get_version.sh env)"
  docker build --platform "${DOCKER_PLATFORM}" --target builder \
    -f docker/Dockerfile.app.push-acr \
    --build-arg VERSION_ARG="${VERSION}" \
    --build-arg COMMIT_ID_ARG="${COMMIT_ID}" \
    --build-arg BUILD_TIME_ARG="${BUILD_TIME}" \
    --build-arg GO_VERSION_ARG="${GO_VERSION}" \
    --build-arg GOPROXY_ARG="${GOPROXY_ARG:-https://goproxy.cn,direct}" \
    --build-arg GOSUMDB_ARG="${GOSUMDB_ARG:-off}" \
    --build-arg APK_MIRROR_ARG="${APK_MIRROR_ARG:-mirrors.aliyun.com}" \
    --build-arg WITH_ANYDOC="${WITH_ANYDOC}" \
    -t weknora-app-builder:local .

  log "overlay custom binary onto runtime -> weknora-app:local"
  docker build --platform "${DOCKER_PLATFORM}" --pull=false -f docker/Dockerfile.app.overlay \
    --build-arg "WEKNORA_VERSION=${RUNTIME_BASE_VERSION}" \
    --build-arg "RUNTIME_IMAGE=${RUNTIME_BASE_IMAGE}" \
    -t weknora-app:local .
}

build_ui_image() {
  log "build frontend dist on host (FRONTEND_BASE_PATH=${FRONTEND_BASE_PATH})"
  FRONTEND_BASE_PATH="${FRONTEND_BASE_PATH}" ./scripts/build_frontend_dist.sh

  local ui_base="${UI_BASE_IMAGE:-${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:ui-${UI_BASE_VERSION:-v0.8.0}}"
  log "assemble ui image from ACR base + local dist: ${ui_base}"
  docker pull --platform "${DOCKER_PLATFORM}" "${ui_base}"
  local cid
  cid="$(docker create --platform "${DOCKER_PLATFORM}" "${ui_base}")"
  docker cp frontend/dist/. "${cid}:/usr/share/nginx/html/"
  docker cp frontend/nginx.conf "${cid}:/etc/nginx/templates/default.conf.template"
  # Host checkout is often 644; without +x the image fails: exec permission denied.
  docker cp --chmod=755 frontend/docker-entrypoint.sh "${cid}:/docker-entrypoint.sh"
  docker cp frontend/nginx-api-proxy.conf "${cid}:/etc/nginx/api-proxy.conf"
  docker cp frontend/nginx-http.conf "${cid}:/etc/nginx/conf.d/00-weknora-http.conf"
  docker commit \
    --change "ENV FRONTEND_BASE_PATH=${FRONTEND_BASE_PATH}" \
    "${cid}" weknora-ui:local
  docker rm -f "${cid}"
}

push_images() {
  log "push app + ui to ACR (${WEKNORA_VERSION})"
  docker tag weknora-app:local "${ACR_APP}"
  docker tag weknora-ui:local "${ACR_UI}"
  docker push "${ACR_APP}"
  docker push "${ACR_UI}"
}

main() {
  require_login
  build_app_image
  build_ui_image
  push_images
  log "done: ${ACR_APP} , ${ACR_UI}"
}

main "$@"
