#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

/usr/bin/python3 \
  "${ROOT_DIR}/scripts/perf/lib/app-panel-pressure-evidence.py" \
  self-test
