#!/usr/bin/env python3
"""Create Langfuse ACR build rules and trigger overseas builds via OpenAPI."""

from __future__ import annotations

import argparse
import os
import sys
import time

RULES = [
    ("docker", "Dockerfile.langfuse", "langfuse-3"),
    ("docker", "Dockerfile.langfuse-worker", "langfuse-worker-3"),
    ("docker", "Dockerfile.clickhouse", "clickhouse-24.8"),
    ("docker", "Dockerfile.minio", "minio-RELEASE.2025-09-07T16-13-09Z"),
]


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        print(f"ERROR: set {name}", file=sys.stderr)
        sys.exit(1)
    return value


def make_client(region: str):
    from alibabacloud_cr20181201.client import Client
    from alibabacloud_tea_openapi import models as open_models

    config = open_models.Config(
        access_key_id=require_env("ALIBABA_CLOUD_ACCESS_KEY_ID"),
        access_key_secret=require_env("ALIBABA_CLOUD_ACCESS_KEY_SECRET"),
        region_id=region,
        endpoint=f"cr.{region}.aliyuncs.com",
    )
    return Client(config)


def resolve_ids(client, namespace: str, repo_name: str, instance_id: str | None):
    from alibabacloud_cr20181201 import models as cr_models

    if not instance_id:
        resp = client.list_instance(cr_models.ListInstanceRequest(page_no=1, page_size=100))
        instances = resp.body.instances or []
        if instances:
            instance_id = instances[0].instance_id
            print(f"[acr] instance: {instance_id}")
        else:
            raise RuntimeError(
                "ACR personal edition does not appear in ListInstance. "
                "Set ACR_INSTANCE_ID (e.g. crpi-o8kn58wjl072akln for new personal edition)."
            )

    page = 1
    while True:
        req = cr_models.ListRepositoryRequest(
            instance_id=instance_id,
            repo_namespace_name=namespace,
            repo_name=repo_name,
            page=page,
            page_size=30,
        )
        resp = client.list_repository(req)
        repos = resp.body.repositories or []
        for repo in repos:
            if repo.repo_namespace_name == namespace and repo.repo_name == repo_name:
                print(f"[acr] repository: {repo.repo_id} ({namespace}/{repo_name})")
                return instance_id, repo.repo_id
        if page * 30 >= int(resp.body.total_count or 0):
            break
        page += 1
    raise RuntimeError(f"repository not found: {namespace}/{repo_name}")


def enable_overseas_build(client, instance_id: str, repo_id: str, github_repo: str):
    from alibabacloud_cr20181201 import models as cr_models

    owner, name = github_repo.split("/", 1)
    req = cr_models.UpdateRepoSourceCodeRepoRequest(
        instance_id=instance_id,
        repo_id=repo_id,
        code_repo_type="GITHUB",
        code_repo_namespace_name=owner,
        code_repo_name=name,
        auto_build="false",
        oversea_build="true",
        disable_cache_build="false",
    )
    client.update_repo_source_code_repo(req)
    print("[acr] enabled overseas build on repository")


def list_existing_rules(client, instance_id: str, repo_id: str):
    from alibabacloud_cr20181201 import models as cr_models

    resp = client.list_repo_build_rule(
        cr_models.ListRepoBuildRuleRequest(instance_id=instance_id, repo_id=repo_id, page_no=1, page_size=100)
    )
    rules = {}
    for item in resp.body.build_rules or []:
        key = (item.dockerfile_location, item.dockerfile_name, item.image_tag)
        rules[key] = item.build_rule_id
    return rules


def create_or_get_rule(
    client,
    instance_id: str,
    repo_id: str,
    existing: dict,
    dockerfile_dir: str,
    dockerfile_name: str,
    image_tag: str,
    branch: str,
):
    from alibabacloud_cr20181201 import models as cr_models

    key = (dockerfile_dir if dockerfile_dir.startswith("/") else f"/{dockerfile_dir}", dockerfile_name, image_tag)
    if key in existing:
        print(f"[acr] rule exists: {image_tag} -> {existing[key]}")
        return existing[key]

    location = key[0]
    req = cr_models.CreateRepoBuildRuleRequest(
        instance_id=instance_id,
        repo_id=repo_id,
        dockerfile_location=location,
        dockerfile_name=dockerfile_name,
        push_type="GIT_BRANCH",
        push_name=branch,
        image_tag=image_tag,
        platforms=["linux/amd64"],
    )
    resp = client.create_repo_build_rule(req)
    rule_id = resp.body.build_rule_id
    print(f"[acr] created rule: {image_tag} -> {rule_id}")
    return rule_id


def trigger_build(client, instance_id: str, repo_id: str, rule_id: str, image_tag: str):
    from alibabacloud_cr20181201 import models as cr_models

    resp = client.create_build_record_by_rule(
        cr_models.CreateBuildRecordByRuleRequest(
            instance_id=instance_id,
            repo_id=repo_id,
            build_rule_id=rule_id,
        )
    )
    print(f"[acr] build triggered: {image_tag} -> {resp.body.build_record_id}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Setup Langfuse ACR build rules")
    parser.add_argument("--region", default=os.environ.get("ACR_REGION", "cn-hangzhou"))
    parser.add_argument("--namespace", default=os.environ.get("ACR_NAMESPACE", "calb_ai"))
    parser.add_argument("--repo", default=os.environ.get("ACR_REPO", "weknora"))
    parser.add_argument("--instance-id", default=os.environ.get("ACR_INSTANCE_ID", "crpi-o8kn58wjl072akln"))
    parser.add_argument("--github-repo", default=os.environ.get("GITHUB_REPO", "shangeyao/WeKnora"))
    parser.add_argument("--branch", default=os.environ.get("GITHUB_BRANCH", "main"))
    parser.add_argument("--skip-build", action="store_true", help="only create rules, do not trigger builds")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.dry_run:
        print("Would configure:")
        print(f"  region={args.region} repo={args.namespace}/{args.repo} branch={args.branch}")
        for dockerfile_dir, dockerfile_name, image_tag in RULES:
            print(f"  - {dockerfile_dir}/{dockerfile_name} -> {image_tag}")
        return

    client = make_client(args.region)
    instance_id, repo_id = resolve_ids(client, args.namespace, args.repo, args.instance_id or None)
    enable_overseas_build(client, instance_id, repo_id, args.github_repo)
    existing = list_existing_rules(client, instance_id, repo_id)

    rule_ids = []
    for dockerfile_dir, dockerfile_name, image_tag in RULES:
        rule_id = create_or_get_rule(
            client,
            instance_id,
            repo_id,
            existing,
            dockerfile_dir,
            dockerfile_name,
            image_tag,
            args.branch,
        )
        rule_ids.append((rule_id, image_tag))
        time.sleep(0.5)

    if args.skip_build:
        return

    for rule_id, image_tag in rule_ids:
        trigger_build(client, instance_id, repo_id, rule_id, image_tag)
        time.sleep(0.5)

    print("[acr] all Langfuse build jobs submitted")


if __name__ == "__main__":
    main()
