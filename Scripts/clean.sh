#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rm -rf -- "$ROOT/Binaries" "$ROOT/Intermediate" "$ROOT/Saved" "$ROOT/DerivedDataCache"
