#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release/verify-release-binary.sh <Flow Tab.app|FlowTab binary>

Fails when a release executable contains FlowTab's testing-only launch controls
or Darwin notification control-plane names.
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 64
fi

INPUT_PATH="$1"
if [[ "${INPUT_PATH}" == *.app ]]; then
  BINARY_PATH="${INPUT_PATH}/Contents/MacOS/FlowTab"
else
  BINARY_PATH="${INPUT_PATH}"
fi

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "Release executable not found: ${BINARY_PATH}" >&2
  exit 66
fi

STRINGS_FILE="$(mktemp -t flowtab-release-strings.XXXXXX)"
trap 'rm -f "${STRINGS_FILE}"' EXIT

/usr/bin/strings -a "${BINARY_PATH}" >"${STRINGS_FILE}"

FORBIDDEN_MARKERS=(
  "FLOWTAB_UI_TESTING"
  "XCTestBundlePath"
  "--flowtab-ui-"
  "--flowtab-tab-stress"
  "io.github.potato-dumplings.flowtab.ui-test."
)

FOUND_MARKER=0
for marker in "${FORBIDDEN_MARKERS[@]}"; do
  if /usr/bin/grep -F -q -- "${marker}" "${STRINGS_FILE}"; then
    echo "Forbidden testing marker in release executable: ${marker}" >&2
    FOUND_MARKER=1
  fi
done

if [[ ${FOUND_MARKER} -ne 0 ]]; then
  exit 1
fi

echo "Release executable contains no testing control-plane markers."
