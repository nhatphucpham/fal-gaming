#!/usr/bin/env bash
set -euo pipefail
: "${UE_ROOT:?Set UE_ROOT to your Unreal Engine 5.5 installation directory}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)" in Darwin) PLATFORM=Mac ;; Linux) PLATFORM=Linux ;; *) echo "Unsupported host" >&2; exit 1 ;; esac
exec "$UE_ROOT/Engine/Build/BatchFiles/$PLATFORM/Build.sh" FalemagEditor "$PLATFORM" Development -Project="$ROOT/Falemag.uproject" -WaitMutex -NoHotReload "$@"
