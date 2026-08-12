#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/.build-local/ui-test-app"
USER_HOME="${HOME}"
ORIGINAL_HOME="${HOME}"
ORIGINAL_CFFIXED_USER_HOME="${CFFIXED_USER_HOME:-${HOME}}"
LOCAL_SIGNING_CONFIG_PATH="${ROOT_DIR}/xcconfigs/LocalSigning.xcconfig"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
CODE_SIGNING_IDENTITY_PATH="${ROOT_DIR}/scripts/lib/code-signing-identity.sh"

CONFIGURATION="Testing"
INSTALL_PATH="${USER_HOME}/Applications/Flow Tab UITest.app"
DEVELOPMENT_TEAM="${FLOWTAB_DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY=""
RESOLVED_CODE_SIGN_IDENTITY=""
MANUAL_CODESIGN_ENABLED=0
DEVELOPMENT_TEAM_SOURCE=""
HAS_CUSTOM_BUILD_ROOT=false

# shellcheck source=/dev/null
source "${PATH_BOUNDARIES_PATH}"
# shellcheck source=/dev/null
source "${CODE_SIGNING_IDENTITY_PATH}"

if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
  DEVELOPMENT_TEAM_SOURCE="FLOWTAB_DEVELOPMENT_TEAM"
fi

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

print_help() {
  cat <<'EOF'
Usage:
  ./scripts/testing/install-ui-test-app.sh \
    [--configuration Debug|Testing|Release] \
    [--build-root /custom/build/root] \
    [--install-path /absolute/path/to/Flow Tab UITest.app] \
    [--development-team TEAMID] \
    [--code-sign-identity "Apple Development"|SHA1]

Builds FlowTab into a fixed app bundle path for UI automation so macOS permissions
can be granted to a stable bundle instead of a DerivedData product.

Defaults:
  configuration: Testing
  install path: ~/Applications/Flow Tab UITest.app

Supported install boundaries:
  ~/Applications/Flow Tab UITest.app
  ~/Applications/Flow Tab.app
  /Applications/Flow Tab UITest.app
  /Applications/Flow Tab.app

Development team:
  FLOWTAB_DEVELOPMENT_TEAM

Local signing fallback:
  When FLOWTAB_DEVELOPMENT_TEAM is not exported, the script reads it from
  xcconfigs/LocalSigning.xcconfig when present.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-root)
      if [[ "${HAS_CUSTOM_BUILD_ROOT}" == true || -z "${2-}" ]]; then
        echo "--build-root requires one non-empty value and may only be specified once." >&2
        exit 1
      fi
      BUILD_ROOT="${2}"
      HAS_CUSTOM_BUILD_ROOT=true
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2-}"
      shift 2
      ;;
    --install-path)
      INSTALL_PATH="${2-}"
      shift 2
      ;;
    --development-team)
      DEVELOPMENT_TEAM="${2-}"
      DEVELOPMENT_TEAM_SOURCE="--development-team"
      shift 2
      ;;
    --code-sign-identity)
      CODE_SIGN_IDENTITY="${2-}"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_help >&2
      exit 1
      ;;
  esac
done

INSTALL_PATH="$(flowtab_resolve_ui_test_install_path "${USER_HOME}" "${INSTALL_PATH}")"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
TMP_ROOT="${BUILD_ROOT}/tmp"
HOME_ROOT="${BUILD_ROOT}/home"
MODULE_CACHE_ROOT="${BUILD_ROOT}/module-cache"
PACKAGE_CACHE_PATH="${BUILD_ROOT}/source-packages"

if [[ "${CONFIGURATION}" != "Debug" && "${CONFIGURATION}" != "Testing" && "${CONFIGURATION}" != "Release" ]]; then
  echo "Unsupported configuration: ${CONFIGURATION}. Use Debug, Testing, or Release." >&2
  exit 1
fi

if [[ -z "${DEVELOPMENT_TEAM}" ]]; then
  DEVELOPMENT_TEAM="$(detect_local_development_team)"
  if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
    DEVELOPMENT_TEAM_SOURCE="xcconfigs/LocalSigning.xcconfig"
  fi
fi

if [[ -n "${DEVELOPMENT_TEAM}" || -n "${CODE_SIGN_IDENTITY}" ]]; then
  MANUAL_CODESIGN_ENABLED=1
  REQUESTED_CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}"

  if [[ -z "${CODE_SIGN_IDENTITY}" ]]; then
    CODE_SIGN_IDENTITY="Apple Development"
  fi

  if ! RESOLVED_CODE_SIGN_IDENTITY="$(
    flowtab_resolve_code_sign_identity \
      "${CODE_SIGN_IDENTITY}" \
      "${DEVELOPMENT_TEAM}"
  )"; then
    if [[ "${DEVELOPMENT_TEAM_SOURCE}" != "--development-team" && -z "${REQUESTED_CODE_SIGN_IDENTITY}" ]]; then
      echo "Project signing team ${DEVELOPMENT_TEAM} found, but no matching Apple Development identity is installed." >&2
      echo "Continuing with the default adhoc UI test app install." >&2
      DEVELOPMENT_TEAM=""
      CODE_SIGN_IDENTITY=""
      RESOLVED_CODE_SIGN_IDENTITY=""
      MANUAL_CODESIGN_ENABLED=0
    else
      echo "Could not resolve a local codesigning identity for install-ui-test-app.sh." >&2
      echo "Requested identity: ${CODE_SIGN_IDENTITY}" >&2
      if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
        echo "Requested team: ${DEVELOPMENT_TEAM}" >&2
      fi
      echo "Available code-signing identities:" >&2
      security find-identity -v -p codesigning >&2 || true
      exit 1
    fi
  fi
fi

if [[ "${INSTALL_PATH}" == "${USER_HOME%/}/Applications/"* ]]; then
  INSTALL_BOUNDARY="$(flowtab_prepare_direct_child_directory "${USER_HOME}" "Applications")"
else
  INSTALL_BOUNDARY="$(flowtab_prepare_direct_child_directory "/" "Applications")"
fi
INSTALL_PATH="$(flowtab_resolve_direct_child_path "${INSTALL_BOUNDARY}" "$(/usr/bin/basename "${INSTALL_PATH}")")"

mkdir -p \
  "${DERIVED_DATA_PATH}" \
  "${TMP_ROOT}" \
  "${HOME_ROOT}" \
  "${MODULE_CACHE_ROOT}/clang" \
  "${MODULE_CACHE_ROOT}/swift" \
  "${PACKAGE_CACHE_PATH}"

export TMPDIR="${TMP_ROOT}/"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}/clang"
export SWIFT_MODULECACHE_PATH="${MODULE_CACHE_ROOT}/swift"
export SWIFTPM_PACKAGECACHE="${PACKAGE_CACHE_PATH}"

if [[ "${MANUAL_CODESIGN_ENABLED}" -eq 1 ]]; then
  export HOME="${ORIGINAL_HOME}"
  export CFFIXED_USER_HOME="${ORIGINAL_CFFIXED_USER_HOME}"
else
  export HOME="${HOME_ROOT}"
  export CFFIXED_USER_HOME="${HOME_ROOT}"
fi

XCODEBUILD_CMD=(
  xcodebuild
  -project "${ROOT_DIR}/FlowTab.xcodeproj"
  -scheme FlowTab
  -configuration "${CONFIGURATION}"
  -destination "platform=macOS"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"
)

# Build unsigned first. The default install intentionally leaves an adhoc app,
# while the manual path signs the copied bundle with the resolved local identity.
XCODEBUILD_CMD+=("CODE_SIGNING_ALLOWED=NO")

XCODEBUILD_CMD+=(build)

echo "Building FlowTab for UI automation..."
"${XCODEBUILD_CMD[@]}"

BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/Flow Tab.app"
if [[ ! -d "${BUILT_APP_PATH}" ]]; then
  echo "Build output not found: ${BUILT_APP_PATH}" >&2
  exit 1
fi

rm -rf "${INSTALL_PATH}"
/usr/bin/ditto "${BUILT_APP_PATH}" "${INSTALL_PATH}"

if [[ "${MANUAL_CODESIGN_ENABLED}" -eq 1 ]]; then
  echo "Signing FlowTab UI automation app with fingerprint ${RESOLVED_CODE_SIGN_IDENTITY}..."
  /usr/bin/codesign --force --deep --sign "${RESOLVED_CODE_SIGN_IDENTITY}" "${INSTALL_PATH}"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "${INSTALL_PATH}"
fi

echo
echo "Installed UI test app:"
echo "  ${INSTALL_PATH}"
echo
echo "codesign summary:"
/usr/bin/codesign -dv --verbose=2 "${INSTALL_PATH}" 2>&1 || true

echo
echo "Next steps:"
echo "  1. Open ${INSTALL_PATH}"
echo "  2. Grant Accessibility and Screen & System Audio Recording permissions to that app"
echo "  3. Run ./scripts/testing/run-ui-tests-local.sh"
echo
echo "If the codesign summary shows Signature=adhoc, permissions may still be unstable."
echo "Provide --development-team or FLOWTAB_DEVELOPMENT_TEAM with a local Apple Development identity to install a stable signed app."
