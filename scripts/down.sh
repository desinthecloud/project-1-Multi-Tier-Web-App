#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../vagrant"
vagrant halt || true
vagrant destroy -f || true
