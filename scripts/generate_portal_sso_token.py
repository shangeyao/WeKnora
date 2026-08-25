#!/usr/bin/env python3
"""Generate a Portal SSO token for WeKnora (AES-256-GCM, base64url).

Usage:
  PORTAL_SSO_AES_KEY='0123456789abcdef0123456789abcdef' \
    python3 scripts/generate_portal_sso_token.py --email user@corp.com --name 张三

Portal link:
  http://10.121.1.155:8081/weknora/api/v1/auth/portal/login?token=<output>
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import time

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def parse_key(raw: str) -> bytes:
    raw = raw.strip()
    if len(raw) == 32:
        return raw.encode("utf-8")
    for decoder in (base64.b64decode, lambda s: base64.urlsafe_b64decode(s + "==")):
        try:
            key = decoder(raw)
            if len(key) == 32:
                return key
        except Exception:
            pass
    raise SystemExit("PORTAL_SSO_AES_KEY must be 32 bytes or base64 of 32 bytes")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate WeKnora portal SSO token")
    parser.add_argument("--email", required=True, help="User email (unique key in WeKnora)")
    parser.add_argument("--name", default="", help="Display name")
    parser.add_argument("--ttl", type=int, default=300, help="Token lifetime seconds")
    args = parser.parse_args()

    key_raw = os.environ.get("PORTAL_SSO_AES_KEY", "")
    if not key_raw:
        raise SystemExit("Set PORTAL_SSO_AES_KEY in environment")
    key = parse_key(key_raw)

    payload = {
        "email": args.email.strip().lower(),
        "name": args.name.strip(),
        "exp": int(time.time()) + max(1, args.ttl),
    }
    plaintext = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    nonce = os.urandom(12)
    token = base64.urlsafe_b64encode(nonce + AESGCM(key).encrypt(nonce, plaintext, None)).decode("ascii").rstrip("=")
    print(token)


if __name__ == "__main__":
    main()
