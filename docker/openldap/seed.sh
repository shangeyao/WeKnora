#!/bin/sh
# Seed LDAP test users after OpenLDAP container starts.
set -eu
LDAP_HOST="${LDAP_HOST:-openldap}"
LDAP_PORT="${LDAP_PORT:-389}"
ADMIN_DN="${LDAP_ADMIN_DN:-cn=admin,dc=example,dc=com}"
ADMIN_PW="${LDAP_ADMIN_PASSWORD:-adminpassword}"
LDIF_PATH="${LDIF_PATH:-/ldif/50-weknora.ldif}"

echo "Waiting for LDAP at ${LDAP_HOST}:${LDAP_PORT}..."
for i in $(seq 1 30); do
  if ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -w "${ADMIN_PW}" -b "dc=example,dc=com" "(uid=testuser)" uid 2>/dev/null | grep -q "uid: testuser"; then
  echo "LDAP test user already exists, skipping seed."
  exit 0
fi

echo "Importing LDAP seed data from ${LDIF_PATH}..."
ldapadd -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -w "${ADMIN_PW}" -f "${LDIF_PATH}"
echo "LDAP seed complete."
