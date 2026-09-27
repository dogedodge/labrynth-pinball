#!/usr/bin/env bash
# Headless import + smoke test for Labrynth Pinball.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
cd "$ROOT"

echo "==> Import"
"$GODOT" --headless --path "$ROOT" --import
echo "==> Smoke test"
"$GODOT" --headless --path "$ROOT" -- --smoke-test
echo "==> Headless run (3s)"
timeout 8 "$GODOT" --headless --path "$ROOT" --quit-after 180 || true
echo "verify.sh done"
