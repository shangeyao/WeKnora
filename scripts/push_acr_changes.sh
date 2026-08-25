#!/usr/bin/env bash
# Build and push only changed WeKnora images (app + ui) to ACR.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
WEKNORA_VERSION="${WEKNORA_VERSION:-v0.8.0}"
FRONTEND_BASE_PATH="${FRONTEND_BASE_PATH:-/weknora}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
SKIP_LOGIN="${SKIP_LOGIN:-1}"
GO_SDK_VERSION="${GO_SDK_VERSION:-1.26.0}"

ACR_APP="${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:app-${WEKNORA_VERSION}"
ACR_UI="${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:ui-${WEKNORA_VERSION}"
HUB_APP="wechatopenai/weknora-app:${WEKNORA_VERSION}"
HUB_UI="wechatopenai/weknora-ui:${WEKNORA_VERSION}"

log() { echo "[push-changes] $*"; }

build_binary_in_container() {
  log "pull ACR app base if needed"
  docker pull --platform "${DOCKER_PLATFORM}" "${ACR_APP}" || true
  docker tag "${ACR_APP}" "${HUB_APP}"

  log "build Go binary inside app container (GOMAXPROCS=1)"
  docker volume create weknora-build-out >/dev/null 2>&1 || true
  docker run --rm --platform "${DOCKER_PLATFORM}" --user root --entrypoint bash \
    --memory=6g --memory-swap=8g \
    -v "${ROOT}:/src:ro" -v weknora-build-out:/out -w /src \
    -e GOMAXPROCS=1 \
    -e GOMEMLIMIT=4500MiB \
    -e GO_SDK_VERSION="${GO_SDK_VERSION}" \
    -e GO_SDK_URL="${GO_SDK_URL:-}" \
    "${HUB_APP}" -c '
      set -euo pipefail
      if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        sed -i "s|deb.debian.org|mirrors.aliyun.com|g; s|security.debian.org|mirrors.aliyun.com|g" /etc/apt/sources.list.d/debian.sources
      fi
      apt-get update -qq
      apt-get install -y -qq curl libsqlite3-dev >/dev/null
      go_tgz="go${GO_SDK_VERSION}.linux-amd64.tar.gz"
      download_go_sdk() {
        local url="$1"
        echo "[push-changes] trying Go SDK: ${url}"
        curl -fsSL --connect-timeout 15 --retry 2 "${url}" -o /tmp/go.tar.gz
      }
      if [ -n "${GO_SDK_URL}" ]; then
        download_go_sdk "${GO_SDK_URL}"
      else
        ok=0
        for url in \
          "https://golang.google.cn/dl/${go_tgz}" \
          "https://mirrors.aliyun.com/golang/${go_tgz}" \
          "https://mirrors.ustc.edu.cn/golang/${go_tgz}" \
          "https://mirrors.cloud.tencent.com/golang/${go_tgz}" \
          "https://go.dev/dl/${go_tgz}"; do
          if download_go_sdk "${url}"; then ok=1; break; fi
          echo "[push-changes] failed: ${url}" >&2
          rm -f /tmp/go.tar.gz
        done
        if [ "${ok}" != 1 ]; then
          echo "[push-changes] all Go SDK mirrors failed" >&2
          exit 1
        fi
      fi
      rm -rf /tmp/go && tar -C /tmp -xzf /tmp/go.tar.gz
      export PATH=/tmp/go/bin:$PATH
      export GOPROXY=https://goproxy.cn,direct
      export GOSUMDB=off
      export CGO_ENABLED=1
      go mod download
      VERSION=$(git -C /src describe --tags --abbrev=0 2>/dev/null || echo "${VERSION:-unknown}")
      COMMIT_ID=${COMMIT_ID:-unknown}
      BUILD_TIME=${BUILD_TIME:-unknown}
      GO_VERSION=${GO_VERSION:-unknown}
      LDFLAGS="-X github.com/Tencent/WeKnora/internal/handler.Version=${VERSION} \
        -X github.com/Tencent/WeKnora/internal/handler.Edition=standard \
        -X github.com/Tencent/WeKnora/internal/handler.CommitID=${COMMIT_ID} \
        -X github.com/Tencent/WeKnora/internal/handler.BuildTime=${BUILD_TIME} \
        -X github.com/Tencent/WeKnora/internal/handler.GoVersion=${GO_VERSION} \
        -X google.golang.org/protobuf/reflect/protoregistry.conflictPolicy=warn"
      go build -ldflags="-w -s ${LDFLAGS}" -o /out/WeKnora ./cmd/server
      cp -r /src/migrations /out/migrations
      test -f /out/WeKnora
    '
}

build_binary_on_host() {
  log "ERROR: in-container build failed; host CGO cross-compile is not supported on macOS" >&2
  return 1
}

build_app_image() {
  log "create weknora-app-builder:local"
  tmpdir="$(mktemp -d)"
  docker run --rm --platform "${DOCKER_PLATFORM}" --user root --entrypoint bash \
    -v weknora-build-out:/in:ro \
    -v "${tmpdir}:/out" \
    "${HUB_APP}" -c 'cp /in/WeKnora /out/WeKnora && cp -r /in/migrations /out/migrations'

  cat >"${tmpdir}/Dockerfile" <<EOF
FROM ${HUB_APP}
COPY WeKnora /app/WeKnora
COPY migrations /app/migrations
# gojieba dicts: overlay-built binaries look under /root/go/pkg/mod at runtime.
RUN mkdir -p /root/go/pkg/mod/github.com/yanyiwu && \\
    if [ -d /go/pkg/mod/github.com/yanyiwu ]; then \\
      cp -a /go/pkg/mod/github.com/yanyiwu/. /root/go/pkg/mod/github.com/yanyiwu/; \\
    fi
EOF
  docker build --platform "${DOCKER_PLATFORM}" -t weknora-app-builder:local "${tmpdir}"
  rm -rf "${tmpdir}"

  log "build overlay -> weknora-app:local"
  docker build --platform "${DOCKER_PLATFORM}" -f docker/Dockerfile.app.overlay \
    --build-arg "WEKNORA_VERSION=${WEKNORA_VERSION}" \
    -t weknora-app:local .
}

build_ui_image() {
  log "build frontend dist"
  FRONTEND_BASE_PATH="${FRONTEND_BASE_PATH}" ./scripts/build_frontend_dist.sh

  log "commit UI from ACR base"
  docker pull --platform "${DOCKER_PLATFORM}" "${ACR_UI}" || true
  cid="$(docker create --platform "${DOCKER_PLATFORM}" "${ACR_UI}")"
  docker cp frontend/dist/. "${cid}:/usr/share/nginx/html/"
  docker commit \
    --change "ENV FRONTEND_BASE_PATH=${FRONTEND_BASE_PATH}" \
    "${cid}" "${HUB_UI}"
  docker rm -f "${cid}"
}

push_images() {
  log "push app + ui to ACR"
  docker tag weknora-app:local "${ACR_APP}"
  docker tag "${HUB_UI}" "${ACR_UI}"
  docker push "${ACR_APP}"
  docker push "${ACR_UI}"
}

main() {
  if ! build_binary_in_container; then
    build_binary_on_host || exit 1
  fi
  build_app_image
  build_ui_image
  push_images
  log "done"
}

main "$@"
