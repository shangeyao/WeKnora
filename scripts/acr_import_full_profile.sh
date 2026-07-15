#!/usr/bin/env bash
# ACR overseas build rules for docker compose --profile full.
#
# ACR 个人版不支持 docker build --target，每个镜像需要单独 Dockerfile + 一条规则。
# 查看完整填表说明：./scripts/acr_import_full_profile.sh
# 查看规则表格：./scripts/acr_import_full_profile.sh --list

set -euo pipefail

ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_INSTANCE_ID="${ACR_INSTANCE_ID:-crpi-o8kn58wjl072akln}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
GITHUB_REPO="${GITHUB_REPO:-shangeyao/WeKnora}"
WEKNORA_VERSION="${WEKNORA_VERSION:-v0.6.3}"

# context_dir|dockerfile_name|image_tag|build_args|notes
# 「构建上下文目录」= Dockerfile 所在目录（以仓库根为 /）
# 源码镜像必须用 /（仓库根），否则 COPY go.mod / frontend/ 会失败
RULES=(
  "/|Dockerfile.app|app-${WEKNORA_VERSION}|SKIP_DUCKDB_EXTENSIONS=1|app from source"
  "/|Dockerfile.ui|ui-${WEKNORA_VERSION}||frontend multi-stage"
  "/|Dockerfile.mcp|mcp-${WEKNORA_VERSION}||mcp server"
  "/docker/|Dockerfile.hub-docreader|docreader-${WEKNORA_VERSION}|WEKNORA_VERSION=${WEKNORA_VERSION}|from Docker Hub"
  "/docker/|Dockerfile.hub-sandbox|sandbox-${WEKNORA_VERSION}|WEKNORA_VERSION=${WEKNORA_VERSION}|from Docker Hub"
  "/docker/|Dockerfile.paradedb|paradedb-v0.22.2-pg17||postgres + langfuse-db-init"
  "/docker/|Dockerfile.redis|redis-7.0-alpine||redis"
  "/docker/|Dockerfile.busybox|busybox-1.36||searxng-init"
  "/docker/|Dockerfile.searxng|searxng-latest||searxng"
  "/docker/|Dockerfile.minio|minio-RELEASE.2025-09-07T16-13-09Z||minio + langfuse-minio"
  "/docker/|Dockerfile.neo4j|neo4j-2025.10.1||neo4j"
  "/docker/|Dockerfile.qdrant|qdrant-v1.16.2||qdrant"
  "/docker/|Dockerfile.dex|dex-latest||dex OIDC"
  "/docker/|Dockerfile.clickhouse|clickhouse-24.8||langfuse-clickhouse"
  "/docker/|Dockerfile.langfuse|langfuse-3||langfuse-web"
  "/docker/|Dockerfile.langfuse-worker|langfuse-worker-3||langfuse-worker"
)

list_rules() {
  local entry ctx file tag args note
  printf "%-4s %-12s %-28s %-38s %-28s %s\n" "#" "上下文目录" "Dockerfile文件名" "镜像版本(Tag)" "构建参数(可选)" "说明"
  printf "%s\n" "------------------------------------------------------------------------------------------------------------------------------------------------------"
  local i=1
  for entry in "${RULES[@]}"; do
    IFS='|' read -r ctx file tag args note <<<"$entry"
    printf "%-4s %-12s %-28s %-38s %-28s %s\n" "$i" "$ctx" "$file" "$tag" "$args" "$note"
    i=$((i + 1))
  done
  echo
  echo "实例: ${ACR_INSTANCE_ID}"
  echo "仓库: ${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:<tag>"
  echo "共 ${#RULES[@]} 条构建规则"
}

print_guide() {
  cat <<EOF
=== ACR 海外构建：full profile（${#RULES[@]} 条规则）===

代码源: GitHub ${GITHUB_REPO}
类型 / Branch·Tag: 建议 Tag → ${WEKNORA_VERSION}（或 Branch → main）

## 控制台每个字段怎么填

| 字段 | 填法 |
|------|------|
| 类型 | Tag（推荐）或 Branch |
| Branch/Tag | ${WEKNORA_VERSION} 或 main |
| 构建上下文目录 | 见下表「上下文目录」列（不是随意选的 docker build context） |
| Dockerfile文件名 | 见下表「Dockerfile文件名」列 |
| 镜像版本 | 见下表「镜像版本」列（不要填 latest，除非就是该组件） |
| 构建参数 | 见下表「构建参数」列（有则填，无则留空） |

重要：
  1. 「构建上下文目录」在 ACR 里表示 **Dockerfile 文件所在目录**（相对仓库根）。
     例：文件在 /docker/Dockerfile.redis → 填 /docker/
     例：文件在 /Dockerfile.app → 填 /
  2. app / ui / mcp 必须填上下文 /（仓库根），否则 COPY 找不到 cmd/、frontend/。
  3. ACR 个人版 **不支持 --target**，不能用一个多 stage Dockerfile 出 16 个镜像。
  4. 每条规则 = 一个 Dockerfile = 一个镜像 Tag。

前置（只做一次）：
  1. 绑定 GitHub ${GITHUB_REPO}
  2. 开启「海外机器构建」
  3. （可选）开启「代码变更时自动构建镜像」

EOF
  list_rules
  cat <<EOF

部署：
  docker login ${ACR_REGISTRY}
  docker compose -f docker-compose.calb-ai.yml up -d
EOF
}

case "${1:-}" in
  --list) list_rules ;;
  *) print_guide ;;
esac
