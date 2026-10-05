#!/usr/bin/env bash
# Build and update selected phone, watch or local Mac apps without clearing data.
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "缺少 python3，请先安装 Python 3。" >&2
  exit 1
fi
exec python3 "$repo_root/scripts/install_dev.py" "$@"
