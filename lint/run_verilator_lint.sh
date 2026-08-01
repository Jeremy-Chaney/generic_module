#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export GENERIC_MODULE_ROOT="$REPO_ROOT"

if command -v python3 >/dev/null 2>&1; then
  python3 "$REPO_ROOT/scripts/gen_register_artifacts.py"
elif command -v python >/dev/null 2>&1; then
  python "$REPO_ROOT/scripts/gen_register_artifacts.py"
else
  echo "python3/python is required to generate register artifacts" >&2
  exit 127
fi

if ! command -v verilator >/dev/null 2>&1; then
  echo "verilator is not installed or not in PATH" >&2
  echo "Install on Ubuntu/WSL with: sudo apt-get update && sudo apt-get install -y verilator" >&2
  exit 127
fi

TMP_FILELIST_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_FILELIST_DIR"
}
trap cleanup EXIT

cp "$SCRIPT_DIR"/*.f "$TMP_FILELIST_DIR"/
for filelist in "$TMP_FILELIST_DIR"/*.f; do
  sed -i "s|\${GENERIC_MODULE_ROOT}|$GENERIC_MODULE_ROOT|g; s|\$GENERIC_MODULE_ROOT|$GENERIC_MODULE_ROOT|g" "$filelist"
done

verilator \
  --lint-only \
  --Wall \
  -f "$TMP_FILELIST_DIR/verilator.f"

echo "Verilator lint passed."
