#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/.build-local/app-tests"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
RESULT_BUNDLE_PATH="${BUILD_ROOT}/results/FlowTabTests.xcresult"
TMP_ROOT="${BUILD_ROOT}/tmp"
HOME_ROOT="${BUILD_ROOT}/home"
MODULE_CACHE_ROOT="${BUILD_ROOT}/module-cache"
PACKAGE_CACHE_PATH="${BUILD_ROOT}/source-packages"

ACTION="test"
ACTION_SET=false
HAS_CUSTOM_TEST_FILTER=false
HAS_CODE_SIGNING_OVERRIDE=false
declare -a EXTRA_ARGS=()

print_help() {
  cat <<'EOF'
Usage: ./scripts/testing/run-flowtabtests-local.sh [test|build-for-testing|test-without-building] [xcodebuild args...]

Runs FlowTabTests with build caches, temp files, and app-test HOME redirected
into ./.build-local/app-tests. Local app-test builds disable code signing by
default because FlowTabTests do not require a permission-bearing app identity.

Examples:
  ./scripts/testing/run-flowtabtests-local.sh
  ./scripts/testing/run-flowtabtests-local.sh -only-testing:FlowTabTests/FlowTabTests/testSearchPerformanceWindowScope
  ./scripts/testing/run-flowtabtests-local.sh build-for-testing
  ./scripts/testing/run-flowtabtests-local.sh test-without-building -only-testing:FlowTabTests
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
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
  EXTRA_ARGS=("-only-testing:FlowTabTests" "${EXTRA_ARGS[@]}")
fi

rm -rf "${RESULT_BUNDLE_PATH}"

echo "FlowTabTests build root: ${BUILD_ROOT}"
echo "DerivedData: ${DERIVED_DATA_PATH}"
echo "TMPDIR: ${TMPDIR}"
echo "Module cache: ${MODULE_CACHE_ROOT}"
echo "Source packages: ${PACKAGE_CACHE_PATH}"
echo "Action: ${ACTION}"
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

if [[ "${HAS_CODE_SIGNING_OVERRIDE}" == false ]]; then
  XCODEBUILD_CMD+=("CODE_SIGNING_ALLOWED=NO")
fi

XCODEBUILD_CMD+=("${ACTION}")
XCODEBUILD_CMD+=("${EXTRA_ARGS[@]}")

if ! "${XCODEBUILD_CMD[@]}"; then
  echo >&2
  echo "FlowTabTests run failed." >&2
  echo "If the error still points at sandboxed temporary files or restricted caches," >&2
  echo "treat it as an environment blocker and rerun with elevated permissions or outside the sandbox." >&2
  exit 1
fi

if [[ -d "${RESULT_BUNDLE_PATH}" ]]; then
  echo "Result bundle: ${RESULT_BUNDLE_PATH}"
fi
