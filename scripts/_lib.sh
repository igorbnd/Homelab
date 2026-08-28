#!/usr/bin/env bash
# Shared helpers. Sourced by the numbered scripts.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$REPO_ROOT/results"
mkdir -p "$RESULTS_DIR"

if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
else
  echo "No .env found. Run scripts/00-preflight.sh first, or copy .env.example to .env." >&2
  exit 1
fi

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
ok()    { printf '\033[1;32m[v]\033[0m %s\n' "$*"; }
