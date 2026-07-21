#!/usr/bin/env bash

set -euo pipefail

IDENTITY=""
BUNDLE_PATH=""
ENTITLEMENTS_PATH=""
USE_SECURE_TIMESTAMP="false"

usage() {
  cat <<'EOF'
Usage: scripts/release/sign-macos-bundle.sh \
  --identity <code-signing-identity> \
  [--entitlements <plist>] \
  [--timestamp] \
  <app-bundle>

Signs nested Mach-O code and nested bundles from the inside out, then signs the
outer app bundle with Hardened Runtime enabled.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      [[ $# -ge 2 ]] || { echo "Missing value for --identity" >&2; exit 64; }
      IDENTITY="$2"
      shift 2
      ;;
    --entitlements)
      [[ $# -ge 2 ]] || { echo "Missing value for --entitlements" >&2; exit 64; }
      ENTITLEMENTS_PATH="$2"
      shift 2
      ;;
    --timestamp)
      USE_SECURE_TIMESTAMP="true"
      shift
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
      if [[ -n "${BUNDLE_PATH}" ]]; then
        echo "Only one app bundle may be signed at a time." >&2
        exit 64
      fi
      BUNDLE_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "${IDENTITY}" || -z "${BUNDLE_PATH}" ]]; then
  usage >&2
  exit 64
fi

if [[ ! -d "${BUNDLE_PATH}/Contents" ]]; then
  echo "App bundle not found: ${BUNDLE_PATH}" >&2
  exit 66
fi

if [[ -n "${ENTITLEMENTS_PATH}" && ! -f "${ENTITLEMENTS_PATH}" ]]; then
  echo "Entitlements file not found: ${ENTITLEMENTS_PATH}" >&2
  exit 66
fi

SIGN_ARGUMENTS=(--force --options runtime --sign "${IDENTITY}")
if [[ "${USE_SECURE_TIMESTAMP}" == "true" ]]; then
  SIGN_ARGUMENTS+=(--timestamp)
fi

MAIN_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${BUNDLE_PATH}/Contents/Info.plist")"
MAIN_EXECUTABLE_PATH="${BUNDLE_PATH}/Contents/MacOS/${MAIN_EXECUTABLE_NAME}"

while IFS= read -r -d '' candidate_path; do
  if [[ "${candidate_path}" == "${MAIN_EXECUTABLE_PATH}" ]]; then
    continue
  fi
  if /usr/bin/file -b "${candidate_path}" | /usr/bin/grep -q "Mach-O"; then
    /usr/bin/codesign "${SIGN_ARGUMENTS[@]}" "${candidate_path}"
  fi
done < <(/usr/bin/find "${BUNDLE_PATH}/Contents" -type f -print0)

while IFS= read -r -d '' nested_bundle_path; do
  /usr/bin/codesign "${SIGN_ARGUMENTS[@]}" "${nested_bundle_path}"
done < <(
  /usr/bin/find "${BUNDLE_PATH}/Contents" -depth -type d \
    \( -name '*.app' -o -name '*.appex' -o -name '*.bundle' -o -name '*.framework' -o -name '*.plugin' -o -name '*.xpc' \) \
    -print0
)

OUTER_SIGN_ARGUMENTS=("${SIGN_ARGUMENTS[@]}")
if [[ -n "${ENTITLEMENTS_PATH}" ]]; then
  OUTER_SIGN_ARGUMENTS+=(--entitlements "${ENTITLEMENTS_PATH}")
fi
/usr/bin/codesign "${OUTER_SIGN_ARGUMENTS[@]}" "${BUNDLE_PATH}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${BUNDLE_PATH}"
