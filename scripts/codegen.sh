#!/usr/bin/env bash
# Runs code generation (riverpod, freezed, json_serializable, drift) for every workspace package.
set -euo pipefail
cd "$(dirname "$0")/.."
dart run build_runner "${1:-build}" --workspace
