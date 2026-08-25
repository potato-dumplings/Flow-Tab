#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release/verify-release-binary.sh \
  [--dsym <Flow Tab.app.dSYM>] \
  <Flow Tab.app|FlowTab binary>

Fails when a release executable contains FlowTab's testing-only launch controls
or Darwin notification control-plane names, retains ordinary local symbols, or
does not match the supplied dSYM UUIDs.
EOF
}

DSYM_PATH=""
POSITIONAL_ARGUMENTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dsym)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--dsym requires a value." >&2; exit 64; }
      DSYM_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
    *)
      POSITIONAL_ARGUMENTS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL_ARGUMENTS[@]} -ne 1 ]]; then
  usage >&2
  exit 64
fi

# Xcode keeps one Mach-O header entry in the local range after non-global stripping.
MAX_STRIPPED_LOCAL_SYMBOLS=1
INPUT_PATH="${POSITIONAL_ARGUMENTS[0]}"
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

if ! ARCHITECTURES="$(/usr/bin/lipo -archs "${BINARY_PATH}" 2>/dev/null)" \
  || [[ -z "${ARCHITECTURES}" ]]; then
  echo "Could not inspect release executable architectures: ${BINARY_PATH}" >&2
  exit 1
fi

for architecture in ${ARCHITECTURES}; do
  LOCAL_SYMBOL_COUNT="$(
    /usr/bin/otool -l -arch "${architecture}" "${BINARY_PATH}" \
      | /usr/bin/awk '
          $1 == "cmd" && $2 == "LC_DYSYMTAB" {
            in_dynamic_symbols = 1
            next
          }
          in_dynamic_symbols && $1 == "nlocalsym" {
            local_symbol_count = $2
            in_dynamic_symbols = 0
          }
          END {
            if (local_symbol_count != "") {
              print local_symbol_count
            }
          }
        '
  )"

  if [[ ! "${LOCAL_SYMBOL_COUNT}" =~ ^[0-9]+$ ]]; then
    echo "Could not inspect ${architecture} local-symbol metadata: ${BINARY_PATH}" >&2
    exit 1
  fi
  if (( LOCAL_SYMBOL_COUNT > MAX_STRIPPED_LOCAL_SYMBOLS )); then
    echo "Release executable retains ${LOCAL_SYMBOL_COUNT} ordinary local symbols for ${architecture}." >&2
    exit 1
  fi
done

normalized_uuids() {
  /usr/bin/dwarfdump --uuid "$1" 2>/dev/null \
    | /usr/bin/awk '
        /^UUID:/ {
          architecture = $3
          gsub(/[()]/, "", architecture)
          print architecture " " toupper($2)
        }
      ' \
    | /usr/bin/sort
}

if [[ -n "${DSYM_PATH}" ]]; then
  if [[ ! -d "${DSYM_PATH}" ]]; then
    echo "Release dSYM not found: ${DSYM_PATH}" >&2
    exit 66
  fi

  if ! BINARY_UUIDS="$(normalized_uuids "${BINARY_PATH}")" \
    || [[ -z "${BINARY_UUIDS}" ]]; then
    echo "Could not read release executable UUIDs: ${BINARY_PATH}" >&2
    exit 1
  fi
  if ! DSYM_UUIDS="$(normalized_uuids "${DSYM_PATH}")" \
    || [[ -z "${DSYM_UUIDS}" ]]; then
    echo "Could not read release dSYM UUIDs: ${DSYM_PATH}" >&2
    exit 1
  fi
  if [[ "${BINARY_UUIDS}" != "${DSYM_UUIDS}" ]]; then
    echo "Release executable and dSYM UUIDs do not match." >&2
    exit 1
  fi

  DSYM_DWARF_CANDIDATES=("${DSYM_PATH}/Contents/Resources/DWARF/"*)
  if [[ ${#DSYM_DWARF_CANDIDATES[@]} -ne 1 ]] \
    || [[ ! -f "${DSYM_DWARF_CANDIDATES[0]}" ]]; then
    echo "Release dSYM must contain exactly one DWARF binary: ${DSYM_PATH}" >&2
    exit 1
  fi
  DSYM_DWARF_PATH="${DSYM_DWARF_CANDIDATES[0]}"

  for architecture in ${ARCHITECTURES}; do
    DEBUG_INFO_SIZE="$(
      /usr/bin/otool -l -arch "${architecture}" "${DSYM_DWARF_PATH}" \
        | /usr/bin/awk '
            $1 == "sectname" && $2 == "__debug_info" {
              in_debug_info = 1
              next
            }
            in_debug_info && $1 == "size" {
              debug_info_size = $2
              in_debug_info = 0
            }
            END {
              if (debug_info_size != "") {
                print debug_info_size
              }
            }
          '
    )"

    if [[ ! "${DEBUG_INFO_SIZE}" =~ ^0x[0-9a-fA-F]+$ ]] \
      || (( DEBUG_INFO_SIZE == 0 )); then
      echo "Release dSYM has no DWARF debug info for ${architecture}: ${DSYM_PATH}" >&2
      exit 1
    fi
  done

  echo "Release executable is stripped, matches its supplied dSYM, and contains no testing control-plane markers."
else
  echo "Release executable is stripped and contains no testing control-plane markers."
fi
