#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../vagrant"
vagrant up

echo
echo "== Forwarded port (web01) =="
vagrant port web01 || true

echo
echo "== Run healthcheck =="
../scripts/healthcheck.sh
