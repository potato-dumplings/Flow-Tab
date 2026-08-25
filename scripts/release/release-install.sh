#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_BUNDLE_NAME="Flow Tab.app"
APP_DISPLAY_NAME="Flow Tab"
APP_PROCESS_NAME="FlowTab"
INSTALL_PATH="/Applications/${APP_BUNDLE_NAME}"
BUNDLE_ID="io.github.potato-dumplings.flowtab"
LOCAL_SIGNING_CONFIG_PATH="${ROOT_DIR}/xcconfigs/LocalSigning.xcconfig"
RELEASE_BINARY_VERIFY_PATH="${ROOT_DIR}/scripts/release/verify-release-binary.sh"
SIGN_BUNDLE_PATH="${ROOT_DIR}/scripts/release/sign-macos-bundle.sh"
PROCESS_EXIT_OBSERVATION_PATH="${ROOT_DIR}/scripts/release/lib/process-exit-observation.sh"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
APP_ENTITLEMENTS_PATH="${ROOT_DIR}/FlowTab/Resources/FlowTab.entitlements"
DEVELOPMENT_TEAM="${FLOWTAB_DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${FLOWTAB_CODE_SIGN_IDENTITY:-Apple Development}"
RESOLVED_CODE_SIGN_IDENTITY=""
PROCESS_EXIT_WATCHDOG_SECONDS=10
PROCESS_EXIT_POLL_INTERVAL_SECONDS=0.1

# shellcheck source=scripts/release/lib/process-exit-observation.sh
source "${PROCESS_EXIT_OBSERVATION_PATH}"
# shellcheck source=scripts/lib/path-boundaries.sh
source "${PATH_BOUNDARIES_PATH}"

for arg in "$@"; do
  case "${arg}" in
    -h|--help)
      cat <<'EOF'
Usage: ./scripts/release/release-install.sh

Environment:
  FLOWTAB_DEVELOPMENT_TEAM       Optional team id; falls back to xcconfigs/LocalSigning.xcconfig.
  FLOWTAB_CODE_SIGN_IDENTITY     Optional local identity; defaults to "Apple Development".
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      exit 1
      ;;
  esac
done

TOTAL_STEPS=8
STEP=1

detect_local_development_team() {
  if [[ ! -f "${LOCAL_SIGNING_CONFIG_PATH}" ]]; then
    return 0
  fi

  awk '
    /^[[:space:]]*(#|\/\/)/ {
      next
    }
    /^[[:space:]]*FLOWTAB_DEVELOPMENT_TEAM[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=/, "", value)
      sub(/[[:space:]]*\/\/.*$/, "", value)
      sub(/[[:space:]]+$/, "", value)
      sub(/^[[:space:]]+/, "", value)
      if (value != "" && value != "YOUR_TEAM_ID") {
        print value
      }
      exit
    }
  ' "${LOCAL_SIGNING_CONFIG_PATH}"
}

resolve_code_sign_identity() {
  local requested="$1"
  local team="$2"
  local identities
  local line
  local identity

  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  while IFS= read -r line; do
    identity="${line#*\"}"
    identity="${identity%\"*}"

    if [[ "${identity}" == "${line}" ]]; then
      continue
    fi

    if [[ -n "${team}" && "${identity}" != *"(${team})" ]]; then
      continue
    fi

    if [[ -n "${requested}" && "${requested}" != "Apple Development" && "${identity}" != "${requested}" ]]; then
      continue
    fi

    if [[ "${requested}" == "Apple Development" && "${identity}" != Apple\ Development:* ]]; then
      continue
    fi

    printf '%s' "${identity}"
    return 0
  done <<< "${identities}"

  return 1
}

resolve_release_signing_identity() {
  if [[ -z "${DEVELOPMENT_TEAM}" ]]; then
    DEVELOPMENT_TEAM="$(detect_local_development_team)"
  fi

  if RESOLVED_CODE_SIGN_IDENTITY="$(resolve_code_sign_identity "${CODE_SIGN_IDENTITY}" "${DEVELOPMENT_TEAM}")"; then
    echo "Using code-signing identity: ${RESOLVED_CODE_SIGN_IDENTITY}"
    return 0
  fi

  echo "Could not resolve a local code-signing identity for release install." >&2
  echo "Requested identity: ${CODE_SIGN_IDENTITY}" >&2
  if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
    echo "Requested team: ${DEVELOPMENT_TEAM}" >&2
  fi
  echo "Available code-signing identities:" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
}

reset_tcc_permission() {
  local service="$1"
  local output

  if ! output=$(/usr/bin/tccutil reset "${service}" "${BUNDLE_ID}" 2>&1); then
    echo "Failed to reset ${service} permission for ${BUNDLE_ID}" >&2
    echo "${output}" >&2
    if [[ "${output}" == *"Operation not permitted from sandbox"* ]]; then
      echo "Please run this script from macOS Terminal/iTerm (outside sandboxed environment)." >&2
    fi
    exit 1
  fi

  if [[ -n "${output}" ]]; then
    echo "${output}"
  fi
}

request_flowtab_process_exit() {
  /usr/bin/osascript -e "quit app \"${APP_DISPLAY_NAME}\"" >/dev/null 2>&1 || true
  /usr/bin/pkill -x "${APP_PROCESS_NAME}" >/dev/null 2>&1 || true
}

BUILD_ROOT="$(flowtab_prepare_direct_child_directory "${ROOT_DIR}" ".build-local")"
RELEASE_INSTALL_PARENT="$(
  flowtab_prepare_direct_child_directory "${BUILD_ROOT}" "release-install"
)"
ATTEMPT_ROOT="$(/usr/bin/mktemp -d "${RELEASE_INSTALL_PARENT%/}/attempt.XXXXXX")"
DERIVED_DATA_PATH="${ATTEMPT_ROOT}/DerivedData"
PACKAGE_CACHE_PATH="${ATTEMPT_ROOT}/SourcePackages"
STAGING_DIR="${ATTEMPT_ROOT}/staging"
STAGED_APP_PATH="${STAGING_DIR}/${APP_BUNDLE_NAME}"
RELEASE_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_BUNDLE_NAME}"
RELEASE_DSYM_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_BUNDLE_NAME}.dSYM"

cleanup_release_install_attempt() {
  /bin/rm -rf "${ATTEMPT_ROOT}"
}
trap cleanup_release_install_attempt EXIT

/bin/mkdir -p "${DERIVED_DATA_PATH}" "${PACKAGE_CACHE_PATH}" "${STAGING_DIR}"

echo "[${STEP}/${TOTAL_STEPS}] Resolve clean Swift package dependencies"
cd "${ROOT_DIR}"
xcodebuild \
  -resolvePackageDependencies \
  -project "${ROOT_DIR}/FlowTab.xcodeproj" \
  -scheme FlowTab \
  -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Build and verify Release"
xcodebuild \
  -project "${ROOT_DIR}/FlowTab.xcodeproj" \
  -scheme FlowTab \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "${RELEASE_APP_PATH}" ]]; then
  echo "Build output not found: ${RELEASE_APP_PATH}" >&2
  exit 1
fi

"${RELEASE_BINARY_VERIFY_PATH}" \
  --dsym "${RELEASE_DSYM_PATH}" \
  "${RELEASE_APP_PATH}"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Resolve local signing identity"
resolve_release_signing_identity

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Stage and sign verified candidate"
/usr/bin/ditto "${RELEASE_APP_PATH}" "${STAGED_APP_PATH}"
"${SIGN_BUNDLE_PATH}" \
  --identity "${RESOLVED_CODE_SIGN_IDENTITY}" \
  --entitlements "${APP_ENTITLEMENTS_PATH}" \
  "${STAGED_APP_PATH}"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Quit running ${APP_DISPLAY_NAME}"
request_flowtab_process_exit
flowtab_wait_for_process_exit \
  "${APP_PROCESS_NAME}" \
  "${PROCESS_EXIT_WATCHDOG_SECONDS}" \
  "${PROCESS_EXIT_POLL_INTERVAL_SECONDS}"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Reset Accessibility and Screen Recording permissions"
reset_tcc_permission "Accessibility"
reset_tcc_permission "ScreenCapture"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Install verified app"
request_flowtab_process_exit
flowtab_wait_for_process_exit \
  "${APP_PROCESS_NAME}" \
  "${PROCESS_EXIT_WATCHDOG_SECONDS}" \
  "${PROCESS_EXIT_POLL_INTERVAL_SECONDS}"
/bin/rm -rf "${INSTALL_PATH}"
/usr/bin/ditto "${STAGED_APP_PATH}" "${INSTALL_PATH}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${INSTALL_PATH}"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Launch app"
open "${INSTALL_PATH}"

echo "Done: ${INSTALL_PATH}"
