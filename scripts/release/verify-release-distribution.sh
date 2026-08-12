#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_SECURITY_PATH="${ROOT_DIR}/scripts/release/release-security.sh"

# shellcheck source=/dev/null
source "${RELEASE_SECURITY_PATH}"

EXPECTED_TEAM_ID=""
EXPECTED_BUNDLE_ID=""
EXPECTED_EXECUTABLE=""
EXPECTED_ENTITLEMENTS_PATH=""
EXPECTED_DMG_BUNDLES=()
POSITIONAL_ARGUMENTS=()

usage() {
  cat <<'EOF'
Usage: scripts/release/verify-release-distribution.sh \
  --expected-team-id <team-id> \
  [--expected-bundle-id <bundle-id> --expected-executable <name>] \
  [--expected-entitlements <plist>] \
  [--expected-dmg-bundle <bundle>]... \
  <app-bundle> [signed-notarized-dmg]

Pins the Developer ID Team ID for every code object. For the Flow Tab app,
also verifies bundle metadata, signing identifier, entitlements, Gatekeeper,
and byte-identical bundle contents inside the optional signed/stapled DMG.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-team-id)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--expected-team-id requires a value." >&2; exit 64; }
      EXPECTED_TEAM_ID="$2"
      shift 2
      ;;
    --expected-bundle-id)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--expected-bundle-id requires a value." >&2; exit 64; }
      EXPECTED_BUNDLE_ID="$2"
      shift 2
      ;;
    --expected-executable)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--expected-executable requires a value." >&2; exit 64; }
      EXPECTED_EXECUTABLE="$2"
      shift 2
      ;;
    --expected-entitlements)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--expected-entitlements requires a value." >&2; exit 64; }
      EXPECTED_ENTITLEMENTS_PATH="$2"
      shift 2
      ;;
    --expected-dmg-bundle)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--expected-dmg-bundle requires a value." >&2; exit 64; }
      EXPECTED_DMG_BUNDLES+=("$2")
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

if [[ -z "${EXPECTED_TEAM_ID}" ]]; then
  echo "--expected-team-id is required." >&2
  exit 64
fi
flowtab_require_team_id "${EXPECTED_TEAM_ID}" >/dev/null
if [[ "${#POSITIONAL_ARGUMENTS[@]}" -lt 1 || "${#POSITIONAL_ARGUMENTS[@]}" -gt 2 ]]; then
  usage >&2
  exit 64
fi
if [[ -n "${EXPECTED_BUNDLE_ID}" && -z "${EXPECTED_EXECUTABLE}" ]] \
  || [[ -z "${EXPECTED_BUNDLE_ID}" && -n "${EXPECTED_EXECUTABLE}" ]]; then
  echo "--expected-bundle-id and --expected-executable must be provided together." >&2
  exit 64
fi
if [[ -n "${EXPECTED_ENTITLEMENTS_PATH}" && -z "${EXPECTED_BUNDLE_ID}" ]]; then
  echo "--expected-entitlements requires the expected app bundle metadata." >&2
  exit 64
fi

APP_PATH="${POSITIONAL_ARGUMENTS[0]}"
DMG_PATH="${POSITIONAL_ARGUMENTS[1]:-}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Release app not found: ${APP_PATH}" >&2
  exit 66
fi

flowtab_require_runtime_and_timestamp() {
  local signature_details="$1"
  local label="$2"

  if ! /usr/bin/grep -E -q 'flags=.*\(.*runtime.*\)' <<< "${signature_details}"; then
    echo "${label} signature does not enable Hardened Runtime." >&2
    return 1
  fi
  if ! /usr/bin/grep -E -q '^Timestamp=.+' <<< "${signature_details}"; then
    echo "${label} signature has no secure timestamp." >&2
    return 1
  fi
}

flowtab_require_code_object_identity() {
  local code_path="$1"
  local label="$2"
  local signature_details=""

  signature_details="$(/usr/bin/codesign --display --verbose=4 "${code_path}" 2>&1)"
  flowtab_require_developer_id_signature_details \
    "${signature_details}" \
    "${EXPECTED_TEAM_ID}" \
    "${label}"
  flowtab_require_runtime_and_timestamp "${signature_details}" "${label}"
}

flowtab_require_nested_code_identities() {
  local app_path="$1"
  local candidate_path=""
  local relative_path=""

  while IFS= read -r -d '' candidate_path; do
    if /usr/bin/file -b "${candidate_path}" | /usr/bin/grep -q 'Mach-O'; then
      relative_path="${candidate_path#"${app_path}/"}"
      flowtab_require_code_object_identity \
        "${candidate_path}" \
        "Nested Mach-O ${relative_path}"
    fi
  done < <(/usr/bin/find "${app_path}/Contents" -type f -print0)

  while IFS= read -r -d '' candidate_path; do
    relative_path="${candidate_path#"${app_path}/"}"
    flowtab_require_code_object_identity \
      "${candidate_path}" \
      "Nested bundle ${relative_path}"
  done < <(
    /usr/bin/find "${app_path}/Contents" -depth -type d \
      \( -name '*.app' -o -name '*.appex' -o -name '*.bundle' -o -name '*.framework' -o -name '*.plugin' -o -name '*.xpc' \) \
      -print0
  )
}

verify_app_bundle() {
  local app_path="$1"
  local label="$2"
  local signature_details=""
  local actual_entitlements=""

  /usr/bin/codesign --verify --deep --strict --verbose=2 "${app_path}"
  signature_details="$(/usr/bin/codesign --display --verbose=4 "${app_path}" 2>&1)"
  flowtab_require_developer_id_signature_details \
    "${signature_details}" \
    "${EXPECTED_TEAM_ID}" \
    "${label}"
  flowtab_require_runtime_and_timestamp "${signature_details}" "${label}"

  if [[ -n "${EXPECTED_BUNDLE_ID}" ]]; then
    flowtab_require_bundle_metadata \
      "${app_path}" \
      "${EXPECTED_BUNDLE_ID}" \
      "${EXPECTED_EXECUTABLE}"
    flowtab_require_codesign_identifier \
      "${signature_details}" \
      "${EXPECTED_BUNDLE_ID}" \
      "${label}"
  fi

  if [[ -n "${EXPECTED_ENTITLEMENTS_PATH}" ]]; then
    actual_entitlements="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/flowtab-entitlements.XXXXXX")"
    if ! /usr/bin/codesign --display --entitlements "${actual_entitlements}" --xml "${app_path}" >/dev/null 2>&1; then
      /bin/rm -f "${actual_entitlements}"
      echo "Could not extract ${label} entitlements." >&2
      return 1
    fi
    if ! flowtab_require_matching_plists \
      "${EXPECTED_ENTITLEMENTS_PATH}" \
      "${actual_entitlements}" \
      "${label} entitlements"; then
      /bin/rm -f "${actual_entitlements}"
      return 1
    fi
    /bin/rm -f "${actual_entitlements}"
  fi

  flowtab_require_nested_code_identities "${app_path}"
}

verify_app_bundle "${APP_PATH}" "Release app"
/usr/sbin/spctl --assess --type execute --verbose=2 "${APP_PATH}"

if [[ -z "${DMG_PATH}" ]]; then
  echo "Verified expected Team ID, Developer ID, Hardened Runtime, timestamp, bundle contract, and Gatekeeper acceptance."
  exit 0
fi

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "Release DMG not found: ${DMG_PATH}" >&2
  exit 66
fi

/usr/bin/codesign --verify --strict --verbose=2 "${DMG_PATH}"
DMG_SIGNATURE_DETAILS="$(/usr/bin/codesign --display --verbose=4 "${DMG_PATH}" 2>&1)"
flowtab_require_developer_id_signature_details \
  "${DMG_SIGNATURE_DETAILS}" \
  "${EXPECTED_TEAM_ID}" \
  "Release DMG"
if ! /usr/bin/grep -E -q '^Timestamp=.+' <<< "${DMG_SIGNATURE_DETAILS}"; then
  echo "Release DMG signature has no secure timestamp." >&2
  exit 1
fi

/usr/bin/hdiutil verify "${DMG_PATH}" >/dev/null
/usr/bin/xcrun stapler validate "${DMG_PATH}"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"

MOUNT_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/flowtab-dmg-mount.XXXXXX")"
DMG_ATTACHED="false"
cleanup_mount() {
  if [[ "${DMG_ATTACHED}" == "true" ]]; then
    /usr/bin/hdiutil detach "${MOUNT_ROOT}" -quiet || true
  fi
  /bin/rm -rf "${MOUNT_ROOT}"
}
trap cleanup_mount EXIT

/usr/bin/hdiutil attach \
  -nobrowse \
  -readonly \
  -mountpoint "${MOUNT_ROOT}" \
  "${DMG_PATH}" >/dev/null
DMG_ATTACHED="true"

SOURCE_BUNDLES=("${APP_PATH}")
if [[ "${#EXPECTED_DMG_BUNDLES[@]}" -gt 0 ]]; then
  SOURCE_BUNDLES+=("${EXPECTED_DMG_BUNDLES[@]}")
fi
SOURCE_BUNDLE_NAMES=()
for source_bundle in "${SOURCE_BUNDLES[@]}"; do
  SOURCE_BUNDLE_NAMES+=("$(/usr/bin/basename "${source_bundle}")")
done
flowtab_require_distribution_layout "${MOUNT_ROOT}" "${SOURCE_BUNDLE_NAMES[@]}"

for source_bundle in "${SOURCE_BUNDLES[@]}"; do
  bundle_name="$(/usr/bin/basename "${source_bundle}")"
  mounted_bundle="${MOUNT_ROOT}/${bundle_name}"

  if [[ ! -d "${mounted_bundle}" ]]; then
    echo "Expected bundle is missing from the DMG: ${bundle_name}" >&2
    exit 1
  fi
  if [[ "$(flowtab_bundle_tree_digest "${source_bundle}")" != "$(flowtab_bundle_tree_digest "${mounted_bundle}")" ]]; then
    echo "DMG bundle content does not match the verified staged bundle: ${bundle_name}" >&2
    exit 1
  fi
done

cleanup_mount
trap - EXIT

echo "Verified pinned release identity, bundle contract, entitlements, DMG contents, notarization, and Gatekeeper acceptance."
