#!/usr/bin/env bash
# Guide: import Langfuse stack images into ACR via overseas build (no local docker pull).
#
# ACR personal edition cannot sync Docker Hub directly. Use console build with
# docker/acr-import/*.Dockerfile — ACR pulls on overseas builders (amd64) and
# pushes to your repository.
#
# Usage:
#   ./scripts/acr_import_langfuse.sh          # print console steps
#   ./scripts/acr_import_langfuse.sh --list   # list build rules to create

set -euo pipefail

ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
GITHUB_REPO="${GITHUB_REPO:-shangeyao/WeKnora}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

RULES=(
  "docker/acr-import/langfuse-web.Dockerfile|langfuse-3|langfuse-web"
  "docker/acr-import/langfuse-worker.Dockerfile|langfuse-worker-3|langfuse-worker"
  "docker/acr-import/clickhouse.Dockerfile|clickhouse-24.8|langfuse-clickhouse"
  "docker/acr-import/langfuse-minio.Dockerfile|minio-RELEASE.2025-09-07T16-13-09Z|langfuse-minio"
)

list_rules() {
  local entry dockerfile tag note
  printf "%-4s %-45s %-35s %s\n" "#" "Dockerfile" "输出 Tag" "Compose 服务"
  printf "%s\n" "---------------------------------------------------------------------------------------------"
  local i=1
  for entry in "${RULES[@]}"; do
    IFS='|' read -r dockerfile tag note <<<"$entry"
    printf "%-4s %-45s %-35s %s\n" "$i" "$dockerfile" "$tag" "$note"
    i=$((i + 1))
  done
  echo
  echo "目标仓库: ${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:<tag>"
}

print_guide() {
  cat <<EOF
=== 用 ACR 海外构建导入 Langfuse（amd64）===

本地 Mac 无需 docker pull。在 ACR 控制台用海外机器拉取 Docker Hub 并推送到你的仓库。

前置：GitHub 仓库 ${GITHUB_REPO} 已绑定到 ACR 个人版实例（仓库管理 → 代码源）。

步骤（每个镜像重复一次，共 4 条构建规则）：

1. 打开 ACR 控制台 → 个人版实例 → 仓库管理 → 镜像仓库 → ${ACR_NAMESPACE}/${ACR_REPO}
2. 左侧「构建」→「添加规则」
3. 配置：
   - 代码源分支：${GITHUB_BRANCH}
   - Dockerfile 路径：见下方表格
   - 镜像版本（Tag）：见下方表格
   - 开启「海外机器构建」/「海外加速」（必须）
4. 保存后点击「立即构建」，等待成功（通常几分钟）

EOF
  list_rules
  cat <<EOF

构建完成后，在 amd64 服务器上：

  docker login ${ACR_REGISTRY}
  docker compose -f docker-compose.calb-ai.yml pull langfuse-web langfuse-worker langfuse-clickhouse langfuse-minio
  docker compose -f docker-compose.calb-ai.yml up -d langfuse-web langfuse-worker langfuse-clickhouse langfuse-minio

验证镜像架构（应为 amd64）：

  docker manifest inspect ${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:langfuse-3 | grep architecture

若尚未绑定 GitHub：先在 ACR 控制台绑定代码源，再 git push 本仓库到 ${GITHUB_BRANCH}。
EOF
}

case "${1:-}" in
  --list) list_rules ;;
  *) print_guide ;;
esac
