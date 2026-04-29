#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/.build-local/ui-tests"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
RESULT_BUNDLE_PATH="${BUILD_ROOT}/results/FlowTabUITests.xcresult"
TMP_ROOT="${BUILD_ROOT}/tmp"
HOME_ROOT="${BUILD_ROOT}/home"
MODULE_CACHE_ROOT="${BUILD_ROOT}/module-cache"
PACKAGE_CACHE_PATH="${BUILD_ROOT}/source-packages"
USER_HOME="${HOME}"
DEFAULT_UI_TEST_APP_PATH="${USER_HOME}/Applications/Flow Tab UITest.app"

ACTION="test"
ACTION_SET=false
HAS_CUSTOM_TEST_FILTER=false
HAS_CODE_SIGNING_OVERRIDE=false
USE_STABLE_UI_TEST_APP=true
UI_TEST_APP_PATH="${FLOWTAB_UI_TEST_APP_PATH:-${DEFAULT_UI_TEST_APP_PATH}}"
declare -a EXTRA_ARGS=()

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
Usage: ./scripts/testing/run-ui-tests-local.sh [test|build-for-testing|test-without-building] [script args...] [xcodebuild args...]

Runs FlowTab UI automation with build caches and temp files redirected into ./.build-local/ui-tests.
When ~/Applications/Flow Tab UITest.app exists, the script also points UI tests at
that fixed app path so macOS permissions can stay attached to a stable bundle.

Examples:
  ./scripts/testing/run-ui-tests-local.sh
  ./scripts/testing/install-ui-test-app.sh
  ./scripts/testing/run-ui-tests-local.sh -only-testing:FlowTabUITests/FlowTabUITests/testHomePageSelectingMockAppUpdatesWindowList
  ./scripts/testing/run-ui-tests-local.sh --ui-test-app-path ~/Applications/Flow\ Tab\ UITest.app
  ./scripts/testing/run-ui-tests-local.sh --no-ui-test-app
  ./scripts/testing/run-ui-tests-local.sh build-for-testing
  ./scripts/testing/run-ui-tests-local.sh test-without-building -only-testing:FlowTabUITests
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    --ui-test-app-path)
      UI_TEST_APP_PATH="${2-}"
      shift 2
      ;;
    --no-ui-test-app)
      USE_STABLE_UI_TEST_APP=false
      shift
      ;;
    test|build-for-testing|test-without-building)
      if [[ "${ACTION_SET}" == true ]]; then
        echo "Only one xcodebuild action may be specified." >&2
        exit 1
      fi
      ACTION="$1"
      ACTION_SET=true
      shift
      ;;
    -only-testing:*|-skip-testing:*)
      HAS_CUSTOM_TEST_FILTER=true
      EXTRA_ARGS+=("$1")
      shift
      ;;
    CODE_SIGNING_ALLOWED=*)
      HAS_CODE_SIGNING_OVERRIDE=true
      EXTRA_ARGS+=("$1")
      shift
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

UI_TEST_APP_PATH="$(expand_path "${UI_TEST_APP_PATH}")"

mkdir -p \
  "${DERIVED_DATA_PATH}" \
  "${BUILD_ROOT}/results" \
  "${TMP_ROOT}" \
  "${HOME_ROOT}" \
  "${MODULE_CACHE_ROOT}/clang" \
  "${MODULE_CACHE_ROOT}/swift" \
  "${PACKAGE_CACHE_PATH}"

export TMPDIR="${TMP_ROOT}/"
export HOME="${HOME_ROOT}"
export CFFIXED_USER_HOME="${HOME_ROOT}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}/clang"
export SWIFT_MODULECACHE_PATH="${MODULE_CACHE_ROOT}/swift"
export SWIFTPM_PACKAGECACHE="${PACKAGE_CACHE_PATH}"

if [[ "${USE_STABLE_UI_TEST_APP}" == true && -d "${UI_TEST_APP_PATH}" ]]; then
  export FLOWTAB_UI_TEST_APP_PATH="${UI_TEST_APP_PATH}"
else
  unset FLOWTAB_UI_TEST_APP_PATH || true
fi

if [[ "${ACTION}" != "build-for-testing" && "${HAS_CUSTOM_TEST_FILTER}" == false ]]; then
  if ((${#EXTRA_ARGS[@]} > 0)); then
    EXTRA_ARGS=("-only-testing:FlowTabUITests" "${EXTRA_ARGS[@]}")
  else
    EXTRA_ARGS=("-only-testing:FlowTabUITests")
  fi
fi

rm -rf "${RESULT_BUNDLE_PATH}"

echo "UI test build root: ${BUILD_ROOT}"
echo "DerivedData: ${DERIVED_DATA_PATH}"
echo "TMPDIR: ${TMPDIR}"
echo "Module cache: ${MODULE_CACHE_ROOT}"
echo "Source packages: ${PACKAGE_CACHE_PATH}"
echo "Action: ${ACTION}"
if [[ -n "${FLOWTAB_UI_TEST_APP_PATH:-}" ]]; then
  echo "UI test app: ${FLOWTAB_UI_TEST_APP_PATH}"
else
  echo "UI test app: DerivedData build product"
fi
if [[ "${HAS_CODE_SIGNING_OVERRIDE}" == true ]]; then
  echo "Code signing for build products: caller override"
else
  echo "Code signing for build products: disabled"
fi

XCODEBUILD_CMD=(
  xcodebuild
  -project "${ROOT_DIR}/FlowTab.xcodeproj"
  -scheme FlowTab
  -destination "platform=macOS"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"
)

if [[ "${ACTION}" == "test" || "${ACTION}" == "test-without-building" ]]; then
  XCODEBUILD_CMD+=(-resultBundlePath "${RESULT_BUNDLE_PATH}")
fi

# Local UI test builds do not need signed build products, and disabling signing
# avoids coupling test execution to whichever Xcode account happens to be configured.
if [[ "${HAS_CODE_SIGNING_OVERRIDE}" == false ]]; then
  XCODEBUILD_CMD+=("CODE_SIGNING_ALLOWED=NO")
fi

XCODEBUILD_CMD+=("${ACTION}")
if ((${#EXTRA_ARGS[@]} > 0)); then
  XCODEBUILD_CMD+=("${EXTRA_ARGS[@]}")
fi

if ! "${XCODEBUILD_CMD[@]}"; then
  echo >&2
  echo "UI test run failed." >&2
  echo "If the error still points at sandboxed temporary files or restricted caches," >&2
  echo "treat it as an environment blocker and rerun with elevated permissions or outside the sandbox." >&2
  exit 1
fi

if [[ -d "${RESULT_BUNDLE_PATH}" ]]; then
  echo "Result bundle: ${RESULT_BUNDLE_PATH}"
fi
