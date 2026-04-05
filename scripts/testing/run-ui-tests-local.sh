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

ACTION="test"
ACTION_SET=false
HAS_CUSTOM_TEST_FILTER=false
declare -a EXTRA_ARGS=()

print_help() {
  cat <<'EOF'
Usage: ./scripts/testing/run-ui-tests-local.sh [test|build-for-testing|test-without-building] [xcodebuild args...]

Runs FlowTab UI automation with build caches and temp files redirected into ./.build-local/ui-tests.

Examples:
  ./scripts/testing/run-ui-tests-local.sh
  ./scripts/testing/run-ui-tests-local.sh -only-testing:FlowTabUITests/FlowTabUITests/testHomePageSelectingMockAppUpdatesWindowList
  ./scripts/testing/run-ui-tests-local.sh build-for-testing
  ./scripts/testing/run-ui-tests-local.sh test-without-building -only-testing:FlowTabUITests
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      print_help
      exit 0
      ;;
    test|build-for-testing|test-without-building)
      if [[ "${ACTION_SET}" == true ]]; then
        echo "Only one xcodebuild action may be specified." >&2
        exit 1
      fi
      ACTION="$arg"
      ACTION_SET=true
      ;;
    -only-testing:*|-skip-testing:*)
      HAS_CUSTOM_TEST_FILTER=true
      EXTRA_ARGS+=("$arg")
      ;;
    *)
      EXTRA_ARGS+=("$arg")
      ;;
  esac
done

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

if [[ "${ACTION}" != "build-for-testing" && "${HAS_CUSTOM_TEST_FILTER}" == false ]]; then
  EXTRA_ARGS=("-only-testing:FlowTabUITests" "${EXTRA_ARGS[@]}")
fi

rm -rf "${RESULT_BUNDLE_PATH}"

echo "UI test build root: ${BUILD_ROOT}"
echo "DerivedData: ${DERIVED_DATA_PATH}"
echo "TMPDIR: ${TMPDIR}"
echo "Module cache: ${MODULE_CACHE_ROOT}"
echo "Source packages: ${PACKAGE_CACHE_PATH}"
echo "Action: ${ACTION}"

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

XCODEBUILD_CMD+=("${ACTION}")
XCODEBUILD_CMD+=("${EXTRA_ARGS[@]}")

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
