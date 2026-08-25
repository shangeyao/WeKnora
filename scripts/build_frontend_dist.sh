#!/usr/bin/env bash
# Build frontend static assets for Docker / release packaging.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "${VITE_FRONTEND_COMMIT:-}" ]; then
	# shellcheck source=/dev/null
	eval "$("$PROJECT_ROOT/scripts/get_version.sh" env)"
	export VITE_FRONTEND_COMMIT="${COMMIT_ID:-unknown}"
fi

export VITE_IS_DOCKER="${VITE_IS_DOCKER:-true}"

# Subpath deploy, e.g. VITE_BASE_PATH=/weknora/ → http://host:8081/weknora/login
if [ -n "${FRONTEND_BASE_PATH:-}" ] && [ "${FRONTEND_BASE_PATH}" != "/" ]; then
	base="${FRONTEND_BASE_PATH%/}"
	export VITE_BASE_PATH="${base}/"
fi

cd "$PROJECT_ROOT/frontend"
npm ci
npm run build
# Baked into the image so nginx subpath works even if FRONTEND_BASE_PATH is unset at runtime.
base="${FRONTEND_BASE_PATH:-}"
base="${base%/}"
printf '%s' "$base" > dist/.frontend-base-path
