#!/usr/bin/env python3
"""Generate a 洞鉴 (Dongjian) RSA SSO token for testing (portal uses PUBLIC key).

Usage:
  python3 scripts/generate_dongjian_sso_token.py --public-key public.pem \
    --email zhangsan@example.com --username zhangsan --name 张三

Portal link:
  http://host/weknora/api/v1/auth/dongjian/config?ssoToken=<output>
"""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate 洞鉴 (Dongjian) RSA ssoToken")
    parser.add_argument("--public-key", required=True, help="Portal RSA public key PEM path")
    parser.add_argument("--client-id", default="dongjian")
    parser.add_argument("--username", required=True)
    parser.add_argument("--email", required=True)
    parser.add_argument("--name", default="")
    args = parser.parse_args()

    pem = Path(args.public_key).read_text(encoding="utf-8")
    public_key = serialization.load_pem_public_key(pem.encode("utf-8"))
    payload = json.dumps(
        {
            "clientID": args.client_id,
            "username": args.username,
            "email": args.email.strip().lower(),
            "name": args.name,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")

    cipher = public_key.encrypt(payload, padding.PKCS1v15())
    print(base64.b64encode(cipher).decode("ascii"))


if __name__ == "__main__":
    main()
