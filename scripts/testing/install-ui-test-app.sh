#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/.build-local/ui-test-app"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
TMP_ROOT="${BUILD_ROOT}/tmp"
HOME_ROOT="${BUILD_ROOT}/home"
MODULE_CACHE_ROOT="${BUILD_ROOT}/module-cache"
PACKAGE_CACHE_PATH="${BUILD_ROOT}/source-packages"
USER_HOME="${HOME}"

CONFIGURATION="Debug"
INSTALL_PATH="${USER_HOME}/Applications/Flow Tab UITest.app"
DEVELOPMENT_TEAM="${FLOWTAB_UI_TEST_APP_DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${FLOWTAB_UI_TEST_APP_CODE_SIGN_IDENTITY:-}"

expand_path() {
  local path="$1"
  if [[ "${path}" == "~/"* ]]; then
    printf '%s/%s' "${USER_HOME}" "${path#~/}"
    return
  fi
  printf '%s' "${path}"
}

print_help() {
  cat <<'EOF'
Usage:
  ./scripts/testing/install-ui-test-app.sh \
    [--configuration Debug|Release] \
    [--install-path /absolute/path/to/Flow Tab UITest.app] \
    [--development-team TEAMID] \
    [--code-sign-identity "Apple Development"]

Builds FlowTab into a fixed app bundle path for UI automation so macOS permissions
can be granted to a stable bundle instead of a DerivedData product.

Defaults:
  configuration: Debug
  install path: ~/Applications/Flow Tab UITest.app

Environment overrides:
  FLOWTAB_UI_TEST_APP_DEVELOPMENT_TEAM
  FLOWTAB_UI_TEST_APP_CODE_SIGN_IDENTITY
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

INSTALL_PATH="$(expand_path "${INSTALL_PATH}")"

if [[ "${CONFIGURATION}" != "Debug" && "${CONFIGURATION}" != "Release" ]]; then
  echo "Unsupported configuration: ${CONFIGURATION}. Use Debug or Release." >&2
  exit 1
fi

mkdir -p \
  "${DERIVED_DATA_PATH}" \
  "${TMP_ROOT}" \
  "${HOME_ROOT}" \
  "${MODULE_CACHE_ROOT}/clang" \
  "${MODULE_CACHE_ROOT}/swift" \
  "${PACKAGE_CACHE_PATH}" \
  "$(dirname "${INSTALL_PATH}")"

export TMPDIR="${TMP_ROOT}/"
export HOME="${HOME_ROOT}"
export CFFIXED_USER_HOME="${HOME_ROOT}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}/clang"
export SWIFT_MODULECACHE_PATH="${MODULE_CACHE_ROOT}/swift"
export SWIFTPM_PACKAGECACHE="${PACKAGE_CACHE_PATH}"

XCODEBUILD_CMD=(
  xcodebuild
  -project "${ROOT_DIR}/FlowTab.xcodeproj"
  -scheme FlowTab
  -configuration "${CONFIGURATION}"
  -destination "platform=macOS"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"
)

if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
  XCODEBUILD_CMD+=("DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}")
  XCODEBUILD_CMD+=("CODE_SIGN_STYLE=Automatic")
fi

if [[ -n "${CODE_SIGN_IDENTITY}" ]]; then
  XCODEBUILD_CMD+=("CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY}")
fi

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
echo "Provide --development-team / --code-sign-identity, or configure signing in Xcode, for a stable identity."
