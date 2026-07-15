#!/usr/bin/env python3
"""Generate docker-compose.calb-ai.yml for ACR-based production deploy."""

from __future__ import annotations

import copy
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
ACR = "crpi-o8kn58wjl072akln.cn-hangzhou.personal.cr.aliyuncs.com/calb_ai/weknora"
VER = "latest"

IMAGE_MAP = {
    "wechatopenai/weknora-ui:${WEKNORA_VERSION:-latest}": f"{ACR}:ui-{VER}",
    "wechatopenai/weknora-app:${WEKNORA_VERSION:-latest}": f"{ACR}:app-{VER}",
    "weknora-app:local": f"{ACR}:app-{VER}",
    "wechatopenai/weknora-docreader:${WEKNORA_VERSION:-latest}": f"{ACR}:docreader-{VER}",
    "wechatopenai/weknora-sandbox:${WEKNORA_VERSION:-latest}": f"{ACR}:sandbox-{VER}",
    "paradedb/paradedb:v0.22.2-pg17": f"{ACR}:paradedb-v0.22.2-pg17",
    "redis:7.0-alpine": f"{ACR}:redis-7.0-alpine",
    "osixia/openldap:1.5.0": f"{ACR}:openldap-1.5.0",
    "busybox:1.36": f"{ACR}:busybox-1.36",
    "searxng/searxng:latest": f"{ACR}:searxng-latest",
    "minio/minio:RELEASE.2025-09-07T16-13-09Z": f"{ACR}:minio-RELEASE.2025-09-07T16-13-09Z",
    "neo4j:2025.10.1": f"{ACR}:neo4j-2025.10.1",
    "qdrant/qdrant:v1.16.2": f"{ACR}:qdrant-v1.16.2",
    "dexidp/dex:latest": f"{ACR}:dex-latest",
    "clickhouse/clickhouse-server:24.8": f"{ACR}:clickhouse-24.8",
    "langfuse/langfuse:3": f"{ACR}:langfuse-3",
    "langfuse/langfuse-worker:3": f"{ACR}:langfuse-worker-3",
}

INCLUDE = {
    "frontend",
    "app",
    "docreader",
    "postgres",
    "redis",
    "openldap",
    "ldap-init",
    "searxng-init",
    "searxng",
    "minio",
    "neo4j",
    "qdrant",
    "dex",
    "langfuse-db-init",
    "langfuse-clickhouse",
    "langfuse-minio",
    "langfuse-worker",
    "langfuse-web",
    "mcp",
}

HEADER = f"""# WeKnora 生产部署 — 从阿里云 ACR 拉取镜像（calb_ai/weknora）
#
# 前置条件：
#   1. docker login {ACR.split('/')[0]}
#   2. 准备 .env、config/config.yaml、skills/preloaded/
#   3. 可选挂载：docker/openldap/、docker/searxng/settings.yml、misc/dex-config.yaml
#
# 启动：
#   docker compose -f docker-compose.calb-ai.yml up -d
#
# 镜像前缀可通过 .env 覆盖：
#   ACR_IMAGE_PREFIX={ACR}
#   WEKNORA_VERSION={VER}
"""


def resolve_image(img: str) -> str:
    if img in IMAGE_MAP:
        return IMAGE_MAP[img]
    for key, value in IMAGE_MAP.items():
        if key.replace("${WEKNORA_VERSION:-latest}", "latest") == img.replace(
            "${WEKNORA_VERSION:-latest}", "latest"
        ):
            return value
    if img and not img.startswith(ACR):
        raise ValueError(f"unmapped image: {img}")
    return img


def strip_build(service: dict) -> None:
    service.pop("build", None)
    service.pop("profiles", None)


def main() -> None:
    with open(ROOT / "docker-compose.yml") as handle:
        base = yaml.safe_load(handle)

    out = {
        "name": "weknora-calb-ai",
        "services": {},
        "networks": base.get("networks", {}),
        "volumes": {},
    }

    for name, service in base["services"].items():
        if name not in INCLUDE:
            continue
        item = copy.deepcopy(service)
        strip_build(item)
        if "image" in item:
            item["image"] = resolve_image(item["image"])
        elif name == "mcp":
            item["image"] = f"{ACR}:mcp-{VER}"
        out["services"][name] = item

    openldap = {
        "image": f"{ACR}:openldap-1.5.0",
        "container_name": "WeKnora-openldap",
        "environment": {
            "LDAP_ORGANISATION": "Example Inc",
            "LDAP_DOMAIN": "example.com",
            "LDAP_ADMIN_PASSWORD": "adminpassword",
            "LDAP_CONFIG_PASSWORD": "configpassword",
            "LDAP_TLS": "false",
        },
        "expose": ["389"],
        "networks": ["WeKnora-network"],
        "restart": "unless-stopped",
    }
    ldap_init = {
        "image": f"{ACR}:openldap-1.5.0",
        "container_name": "WeKnora-ldap-init",
        "depends_on": {"openldap": {"condition": "service_started"}},
        "volumes": [
            "./docker/openldap/custom:/ldif:ro",
            "./docker/openldap/seed.sh:/seed.sh:ro",
        ],
        "environment": {
            "LDAP_HOST": "openldap",
            "LDAP_ADMIN_PASSWORD": "adminpassword",
            "LDIF_PATH": "/ldif/50-weknora.ldif",
        },
        "entrypoint": ["/bin/bash", "/seed.sh"],
        "networks": ["WeKnora-network"],
        "restart": "no",
    }
    out["services"]["openldap"] = openldap
    out["services"]["ldap-init"] = ldap_init

    app = out["services"]["app"]
    deps = app.setdefault("depends_on", {})
    deps["ldap-init"] = {"condition": "service_completed_successfully"}

    env = app.setdefault("environment", [])
    sandbox_env = (
        f"WEKNORA_SANDBOX_DOCKER_IMAGE=${{ACR_IMAGE_PREFIX:-{ACR}}}:sandbox-${{WEKNORA_VERSION:-{VER}}}"
    )
    replaced = False
    new_env = []
    for item in env:
        if isinstance(item, str) and item.startswith("WEKNORA_SANDBOX_DOCKER_IMAGE="):
            new_env.append(sandbox_env)
            replaced = True
        else:
            new_env.append(item)
    if not replaced:
        new_env.append(sandbox_env)
    app["environment"] = new_env

    for service in out["services"].values():
        image = service.get("image", "")
        if image.startswith(ACR):
            tag = image.split(":", 1)[1]
            service["image"] = f"${{ACR_IMAGE_PREFIX:-{ACR}}}:{tag}"

    volume_names: set[str] = set()
    for service in out["services"].values():
        for mount in service.get("volumes", []) or []:
            if isinstance(mount, str) and not mount.startswith(("./", "/", "$")):
                volume_names.add(mount.split(":")[0])
    for name, spec in base.get("volumes", {}).items():
        if name in volume_names:
            out["volumes"][name] = spec

    output = ROOT / "docker-compose.calb-ai.yml"
    with open(output, "w") as handle:
        handle.write(HEADER)
        yaml.dump(
            out,
            handle,
            default_flow_style=False,
            sort_keys=False,
            allow_unicode=True,
            width=120,
        )

    print(f"wrote {output.name} ({len(out['services'])} services)")


if __name__ == "__main__":
    main()
