#!/usr/bin/env bash
# ACR overseas build rules for docker compose --profile full (+ LDAP for calb-ai).
#
# Usage:
#   ./scripts/acr_import_full_profile.sh          # print console checklist
#   ./scripts/acr_import_full_profile.sh --list   # table only
#   ./scripts/generate_acr_import_dockerfiles.py  # regenerate third-party stubs

set -euo pipefail

ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_INSTANCE_ID="${ACR_INSTANCE_ID:-crpi-o8kn58wjl072akln}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
GITHUB_REPO="${GITHUB_REPO:-shangeyao/WeKnora}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

# dockerfile_path|output_tag|notes
# Paths are relative to repo root (GitHub branch checkout).
RULES=(
  # --- WeKnora images (build from source in repo) ---
  "docker/Dockerfile.app|app-latest|LDAP app from source"
  "docker/acr-import/ui.Dockerfile|ui-latest|frontend multi-stage"
  "docker/Dockerfile.docreader|docreader-latest|docreader from source"
  "docker/Dockerfile.sandbox|sandbox-latest|sandbox image for skills"
  "mcp-server/Dockerfile|mcp-latest|mcp server"
  # --- Third-party imports (FROM stubs in docker/acr-import/) ---
  "docker/acr-import/paradedb.Dockerfile|paradedb-v0.22.2-pg17|postgres + langfuse-db-init"
  "docker/acr-import/redis.Dockerfile|redis-7.0-alpine|redis"
  "docker/acr-import/openldap.Dockerfile|openldap-1.5.0|openldap + ldap-init"
  "docker/acr-import/busybox.Dockerfile|busybox-1.36|searxng-init"
  "docker/acr-import/searxng.Dockerfile|searxng-latest|searxng"
  "docker/acr-import/minio.Dockerfile|minio-RELEASE.2025-09-07T16-13-09Z|minio + langfuse-minio"
  "docker/acr-import/neo4j.Dockerfile|neo4j-2025.10.1|neo4j"
  "docker/acr-import/qdrant.Dockerfile|qdrant-v1.16.2|qdrant"
  "docker/acr-import/dex.Dockerfile|dex-latest|dex OIDC"
  "docker/acr-import/clickhouse.Dockerfile|clickhouse-24.8|langfuse-clickhouse"
  "docker/acr-import/langfuse-web.Dockerfile|langfuse-3|langfuse-web"
  "docker/acr-import/langfuse-worker.Dockerfile|langfuse-worker-3|langfuse-worker"
)

list_rules() {
  local entry path tag note
  printf "%-4s %-48s %-38s %s\n" "#" "Dockerfile" "输出 Tag" "说明"
  printf "%s\n" "------------------------------------------------------------------------------------------------------------------------------"
  local i=1
  for entry in "${RULES[@]}"; do
    IFS='|' read -r path tag note <<<"$entry"
    printf "%-4s %-48s %-38s %s\n" "$i" "$path" "$tag" "$note"
    i=$((i + 1))
  done
  echo
  echo "实例: ${ACR_INSTANCE_ID}"
  echo "仓库: ${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:<tag>"
  echo "共 ${#RULES[@]} 条构建规则"
}

print_guide() {
  cat <<EOF
=== ACR 海外构建：full profile 全部镜像（${#RULES[@]} 条规则）===

实例 ID: ${ACR_INSTANCE_ID}
命名空间/仓库: ${ACR_NAMESPACE}/${ACR_REPO}
代码源: GitHub ${GITHUB_REPO} 分支 ${GITHUB_BRANCH}

前置（只做一次）：
  1. ACR 控制台 → ${ACR_NAMESPACE}/${ACR_REPO} → 构建 → 绑定 GitHub ${GITHUB_REPO}
  2. 开启「海外机器构建」
  3. 开启「代码变更时自动构建镜像」（可选，否则手动点立即构建）

每条规则（共 ${#RULES[@]} 条）：
  1. 构建 → 添加规则
  2. 类型 Branch，分支 ${GITHUB_BRANCH}
  3. Dockerfile 路径 = 下表「Dockerfile」列（相对仓库根目录）
     - 若控制台分「目录 + 文件名」：
       例 docker/Dockerfile.app → 目录 docker/ 文件 Dockerfile.app
       例 docker/acr-import/ui.Dockerfile → 目录 docker/acr-import/ 文件 ui.Dockerfile
  4. 镜像 Tag = 下表「输出 Tag」列
  5. 保存

全部规则添加后：
  - 首次：每条点「立即构建」
  - 之后：git push ${GITHUB_BRANCH} 可自动触发（需开启自动构建）

生成第三方 FROM 桩文件：
  python3 scripts/generate_acr_import_dockerfiles.py

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
