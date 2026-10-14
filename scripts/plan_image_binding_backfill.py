#!/usr/bin/env python3
"""Export unbound image candidates and a reviewed, scoped PostgreSQL repair.

Uses psql and its normal PGHOST/PGPORT/PGDATABASE/PGUSER credentials.
This command only reads production data; review the CSV and generated SQL
before running the SQL separately with psql -v ON_ERROR_STOP=1 -f repair.sql.
Chunk text is candidate evidence, not an online authorization grant.
"""

import argparse
import csv
import json
import pathlib
import subprocess
import uuid


def matches_cte(tenant_id):
    # Extract canonical handles once per chunk instead of joining every
    # resource against every chunk. A longer handle cannot match its prefix.
    return f"""
WITH image_refs AS (
    SELECT DISTINCT k.id AS knowledge_id, k.knowledge_base_id, k.title,
           k.file_name, c.tenant_id, token[1] AS handle
    FROM chunks c
    JOIN knowledges k ON k.id = c.knowledge_id AND k.tenant_id = c.tenant_id
    JOIN knowledge_bases kb ON kb.id = k.knowledge_base_id AND kb.tenant_id = k.tenant_id
    CROSS JOIN LATERAL regexp_matches(
        concat_ws(E'\\n', c.source_content, c.content, c.image_info),
        'resource://([A-Za-z0-9_-]{{22}})(?![A-Za-z0-9_-])', 'g') AS token
    WHERE c.tenant_id = {tenant_id} AND c.deleted_at IS NULL
      AND c.knowledge_base_id = k.knowledge_base_id
      AND k.deleted_at IS NULL AND kb.deleted_at IS NULL
      AND k.type = 'file' AND k.parse_status = 'completed'
), matches AS (
    SELECT r.id AS resource_id, r.handle, r.tenant_id, d.knowledge_id,
           d.knowledge_base_id, d.title, d.file_name,
           count(*) OVER (PARTITION BY r.id) AS source_documents
    FROM image_refs d
    JOIN resources r ON r.handle = d.handle AND r.tenant_id = d.tenant_id
    WHERE r.state = 'active' AND r.deleted_at IS NULL
      AND (r.kind = 'image' OR r.mime_type LIKE 'image/%')
)
"""


def read_candidates(tenant_id, kb_id):
    scope = f"AND m.knowledge_base_id = '{kb_id}'" if kb_id else ""
    query = matches_cte(tenant_id) + f"""
SELECT COALESCE(json_agg(row_to_json(candidate)), '[]'::json)
FROM (
    SELECT m.* FROM matches m
    WHERE NOT EXISTS (SELECT 1 FROM resource_bindings b WHERE b.resource_id = m.resource_id)
    {scope}
    ORDER BY m.handle, m.knowledge_id
) candidate;
"""
    result = subprocess.run(
        ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", query],
        text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout)


def repair_sql(tenant_id, rows):
    selected = [r for r in rows if int(r["source_documents"]) == 1]
    if not selected:
        return "-- No unambiguous, unbound image candidates; nothing to repair.\n"
    values = []
    for row in selected:
        resource_id = str(uuid.UUID(row["resource_id"]))
        knowledge_id = str(uuid.UUID(row["knowledge_id"]))
        kb_id = str(uuid.UUID(row["knowledge_base_id"]))
        values.append(f"('{resource_id}', '{knowledge_id}', '{kb_id}')")
    # IDs are parsed as UUIDs before interpolation; titles/content never enter
    # the executable SQL. Freeze the reviewed set instead of rescanning new
    # candidates at execution time.
    values_sql = ',\n'.join(values)
    return f"""-- Review candidates.csv against the source documents before executing.
-- Tenant {tenant_id}; {len(selected)} fixed resource/document pairs.
-- Unrelated existing bindings and ambiguous sources are never overwritten.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TEMP TABLE reviewed_image_bindings (
    resource_id text PRIMARY KEY, knowledge_id text, knowledge_base_id text
) ON COMMIT DROP;
INSERT INTO reviewed_image_bindings VALUES
{values_sql};

CREATE TEMP TABLE validated_image_bindings ON COMMIT DROP AS
{matches_cte(tenant_id)}
SELECT m.resource_id, m.handle, m.tenant_id, m.knowledge_id
FROM matches m
JOIN reviewed_image_bindings selected ON selected.resource_id = m.resource_id
    AND selected.knowledge_id = m.knowledge_id
    AND selected.knowledge_base_id = m.knowledge_base_id
WHERE m.source_documents = 1
  AND NOT EXISTS (
      SELECT 1 FROM resource_bindings b WHERE b.resource_id = m.resource_id
      AND NOT (b.tenant_id = m.tenant_id AND b.owner_type = 'knowledge'
               AND b.owner_id = m.knowledge_id AND b.relation = 'extracted_image')
  );

DO $$
BEGIN
    IF (SELECT count(*) FROM validated_image_bindings)
       <> (SELECT count(*) FROM reviewed_image_bindings) THEN
        RAISE EXCEPTION 'Source document or ownership changed; regenerate and review the plan';
    END IF;
END $$;

WITH inserted AS (
    INSERT INTO resource_bindings (id, resource_id, tenant_id, owner_type, owner_id, relation)
    SELECT md5('extracted_image:' || resource_id || ':' || knowledge_id)::uuid::text,
           resource_id, tenant_id, 'knowledge', knowledge_id, 'extracted_image'
    FROM validated_image_bindings
    ON CONFLICT (resource_id, owner_type, owner_id, relation) DO NOTHING
    RETURNING resource_id
)
SELECT count(*) AS inserted_bindings FROM inserted;
COMMIT;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tenant-id", type=int, required=True)
    parser.add_argument("--kb-id", type=uuid.UUID, help="Optional KB scope within the tenant")
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.tenant_id <= 0:
        parser.error("--tenant-id must be positive")
    output = args.output_dir
    output.mkdir(parents=True, exist_ok=True)
    csv_path, sql_path = output / "candidates.csv", output / "repair.sql"
    if csv_path.exists() or sql_path.exists():
        parser.error("Output files already exist; use a new output directory")
    try:
        rows = read_candidates(args.tenant_id, args.kb_id)
        sql = repair_sql(args.tenant_id, rows)
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError) as error:
        parser.exit(1, f"Could not generate plan: {error}\n")
    with csv_path.open("w", newline="", encoding="utf-8-sig") as file:
        writer = csv.DictWriter(file, fieldnames=[
            "status", "resource_id", "handle", "tenant_id", "knowledge_id",
            "knowledge_base_id", "title", "file_name", "source_documents",
        ])
        writer.writeheader()
        for row in rows:
            writer.writerow({"status": "review" if row["source_documents"] == 1 else "ambiguous", **row})
    sql_path.write_text(sql, encoding="utf-8")
    unique = sum(row["source_documents"] == 1 for row in rows)
    print(f"{unique} resource/document pairs to review; {len(rows) - unique} ambiguous rows excluded.")
    print(f"Review {csv_path} and {sql_path}; production data has not been changed.")
    print("Editing the CSV does not change the SQL: remove unwanted pairs from its VALUES list.")


if __name__ == "__main__":
    main()
