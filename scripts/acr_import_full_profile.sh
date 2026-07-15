#!/usr/bin/env bash
# ACR overseas build rules for docker compose --profile full.
#
# All images are defined as targets in docker/Dockerfile.
#
# Usage:
#   ./scripts/acr_import_full_profile.sh          # print console checklist
#   ./scripts/acr_import_full_profile.sh --list   # table only

set -euo pipefail

ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_INSTANCE_ID="${ACR_INSTANCE_ID:-crpi-o8kn58wjl072akln}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
GITHUB_REPO="${GITHUB_REPO:-shangeyao/WeKnora}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
WEKNORA_VERSION="${WEKNORA_VERSION:-v0.6.3}"
DOCKERFILE="docker/Dockerfile"

# target|output_tag|notes
RULES=(
  "app|app-${WEKNORA_VERSION}|app from source"
  "ui|ui-${WEKNORA_VERSION}|frontend multi-stage"
  "docreader|docreader-${WEKNORA_VERSION}|from Docker Hub"
  "sandbox|sandbox-${WEKNORA_VERSION}|from Docker Hub"
  "mcp|mcp-${WEKNORA_VERSION}|mcp server"
  "paradedb|paradedb-v0.22.2-pg17|postgres + langfuse-db-init"
  "redis|redis-7.0-alpine|redis"
  "busybox|busybox-1.36|searxng-init"
  "searxng|searxng-latest|searxng"
  "minio|minio-RELEASE.2025-09-07T16-13-09Z|minio + langfuse-minio"
  "neo4j|neo4j-2025.10.1|neo4j"
  "qdrant|qdrant-v1.16.2|qdrant"
  "dex|dex-latest|dex OIDC"
  "clickhouse|clickhouse-24.8|langfuse-clickhouse"
  "langfuse|langfuse-3|langfuse-web"
  "langfuse-worker|langfuse-worker-3|langfuse-worker"
)

list_rules() {
  local entry target tag note
  printf "%-4s %-20s %-38s %s\n" "#" "Target" "输出 Tag" "说明"
  printf "%s\n" "----------------------------------------------------------------------------------------------------"
  local i=1
  for entry in "${RULES[@]}"; do
    IFS='|' read -r target tag note <<<"$entry"
    printf "%-4s %-20s %-38s %s\n" "$i" "$target" "$tag" "$note"
    i=$((i + 1))
  done
  echo
  echo "Dockerfile: ${DOCKERFILE}"
  echo "实例: ${ACR_INSTANCE_ID}"
  echo "仓库: ${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:<tag>"
  echo "共 ${#RULES[@]} 条构建规则"
}

print_guide() {
  cat <<EOF
=== ACR 海外构建：full profile 全部镜像（${#RULES[@]} 条规则）===

实例 ID: ${ACR_INSTANCE_ID}
命名空间/仓库: ${ACR_NAMESPACE}/${ACR_REPO}
代码源: GitHub ${GITHUB_REPO} Tag ${WEKNORA_VERSION}（或 Branch ${GITHUB_BRANCH}）
Dockerfile: ${DOCKERFILE}
WEKNORA_VERSION: ${WEKNORA_VERSION}

前置（只做一次）：
  1. ACR 控制台 → ${ACR_NAMESPACE}/${ACR_REPO} → 构建 → 绑定 GitHub ${GITHUB_REPO}
  2. 开启「海外机器构建」
  3. 开启「代码变更时自动构建镜像」（可选，否则手动点立即构建）

每条规则（共 ${#RULES[@]} 条）：
  1. 构建 → 添加规则
  2. 类型 Tag ${WEKNORA_VERSION} 或 Branch ${GITHUB_BRANCH}
  3. Dockerfile 路径 = ${DOCKERFILE}
     - 目录 docker/  文件名 Dockerfile
  4. 构建阶段 (target) = 下表「Target」列
     - 若控制台无 target 字段，在构建参数中添加：target=<Target>
  5. 构建参数（源码镜像建议）：WEKNORA_VERSION=${WEKNORA_VERSION}
  6. 镜像 Tag = 下表「输出 Tag」列
  7. 保存

全部规则添加后：
  - 首次：每条点「立即构建」
  - 之后：git push ${GITHUB_BRANCH} 可自动触发（需开启自动构建）

部署（服务器 amd64）：
  docker login ${ACR_REGISTRY}
  docker compose -f docker-compose.calb-ai.yml up -d

EOF
  list_rules
}

case "${1:-}" in
  --list) list_rules ;;
  *) print_guide ;;
esac
