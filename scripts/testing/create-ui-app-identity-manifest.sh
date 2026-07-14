#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EVIDENCE_TOOL="${ROOT_DIR}/scripts/perf/lib/runtime-topology-evidence.py"

usage() {
  cat <<'EOF'
Usage: ./scripts/testing/create-ui-app-identity-manifest.sh --app-path <app> --output-file <json>

Creates an immutable private identity manifest for runtime-topology pressure.
The output leaf must not already exist.
EOF
}

APP_PATH=""
OUTPUT_FILE=""
HAS_APP_PATH=false
HAS_OUTPUT_FILE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      [[ "$HAS_APP_PATH" == false && $# -ge 2 && -n "$2" ]] || { echo "--app-path requires one value and may only be specified once." >&2; exit 2; }
      APP_PATH="$2"
      HAS_APP_PATH=true
      shift 2
      ;;
    --output-file)
      [[ "$HAS_OUTPUT_FILE" == false && $# -ge 2 && -n "$2" ]] || { echo "--output-file requires one value and may only be specified once." >&2; exit 2; }
      OUTPUT_FILE="$2"
      HAS_OUTPUT_FILE=true
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$OUTPUT_FILE" ]]; then
  usage >&2
  exit 2
fi

RESOLVED_APP_PATH="$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$APP_PATH")"
RESOLVED_OUTPUT_FILE="$(/usr/bin/python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$OUTPUT_FILE")"
if [[ ! -d "$RESOLVED_APP_PATH" ]]; then
  echo "App bundle not found: $RESOLVED_APP_PATH" >&2
  exit 2
fi
if [[ -e "$RESOLVED_OUTPUT_FILE" ]]; then
  echo "Output file must not already exist: $RESOLVED_OUTPUT_FILE" >&2
  exit 2
fi

PLIST_FIELDS="$(/usr/bin/python3 "$EVIDENCE_TOOL" read-plist "$RESOLVED_APP_PATH/Contents/Info.plist")"
IFS=$'\t' read -r BUNDLE_ID EXECUTABLE_NAME <<<"$PLIST_FIELDS"
EXECUTABLE_PATH="$RESOLVED_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "App executable not found: $EXECUTABLE_PATH" >&2
  exit 2
fi

EXECUTABLE_SHA256="$(LC_ALL=C shasum -a 256 "$EXECUTABLE_PATH" | awk '{print $1}')"
DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -dr - "$RESOLVED_APP_PATH" 2>&1 | sed -n 's/^designated => //p')"
if [[ -z "$DESIGNATED_REQUIREMENT" ]]; then
  echo "Could not read the App designated requirement." >&2
  exit 2
fi
DESIGNATED_REQUIREMENT_SHA256="$(printf '%s' "$DESIGNATED_REQUIREMENT" | LC_ALL=C shasum -a 256 | awk '{print $1}')"

mkdir -p "$(dirname "$RESOLVED_OUTPUT_FILE")"
/usr/bin/python3 "$EVIDENCE_TOOL" write-manifest \
  "$RESOLVED_OUTPUT_FILE" \
  "$RESOLVED_APP_PATH" \
  "$BUNDLE_ID" \
  "$EXECUTABLE_SHA256" \
  "$DESIGNATED_REQUIREMENT_SHA256"

printf 'UI App identity manifest: %s\n' "$RESOLVED_OUTPUT_FILE"
printf 'SHA-256: %s\n' "$(LC_ALL=C shasum -a 256 "$RESOLVED_OUTPUT_FILE" | awk '{print $1}')"
