#!/usr/bin/env bash
# Langfuse-only ACR build rules (subset of full profile).
# For all --profile full images, use: ./scripts/acr_import_full_profile.sh

set -euo pipefail

ACR_REGISTRY="${ACR_REGISTRY:-crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-calb_ai}"
ACR_REPO="${ACR_REPO:-weknora}"
GITHUB_REPO="${GITHUB_REPO:-shangeyao/WeKnora}"
WEKNORA_VERSION="${WEKNORA_VERSION:-v0.6.3}"

# context_dir|dockerfile_name|image_tag|notes
RULES=(
  "/docker/|Dockerfile.langfuse|langfuse-3|langfuse-web"
  "/docker/|Dockerfile.langfuse-worker|langfuse-worker-3|langfuse-worker"
  "/docker/|Dockerfile.clickhouse|clickhouse-24.8|langfuse-clickhouse"
  "/docker/|Dockerfile.minio|minio-RELEASE.2025-09-07T16-13-09Z|langfuse-minio"
)

list_rules() {
  local entry ctx file tag note
  printf "%-4s %-12s %-28s %-35s %s\n" "#" "上下文目录" "Dockerfile文件名" "镜像版本" "Compose 服务"
  printf "%s\n" "---------------------------------------------------------------------------------------------------"
  local i=1
  for entry in "${RULES[@]}"; do
    IFS='|' read -r ctx file tag note <<<"$entry"
    printf "%-4s %-12s %-28s %-35s %s\n" "$i" "$ctx" "$file" "$tag" "$note"
    i=$((i + 1))
  done
  echo
  echo "目标仓库: ${ACR_REGISTRY}/${ACR_NAMESPACE}/${ACR_REPO}:<tag>"
}

print_guide() {
  cat <<EOF
=== Langfuse 镜像 ACR 海外构建（4 条规则）===

类型: Tag ${WEKNORA_VERSION}（或 Branch main）

每条规则：
  构建上下文目录 = 下表「上下文目录」
  Dockerfile文件名 = 下表「Dockerfile文件名」
  镜像版本 = 下表「镜像版本」
  开启「海外机器构建」

EOF
  list_rules
}

case "${1:-}" in
  --list) list_rules ;;
  *) print_guide ;;
esac
