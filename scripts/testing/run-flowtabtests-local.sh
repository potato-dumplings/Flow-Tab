#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DEFAULT_BUILD_ROOT="${ROOT_DIR}/.build-local/app-tests"
BUILD_ROOT="${DEFAULT_BUILD_ROOT}"
OUTPUT_ROOT=""

ACTION="test"
ACTION_SET=false
HAS_CUSTOM_TEST_FILTER=false
HAS_CODE_SIGNING_OVERRIDE=false
HAS_CUSTOM_OUTPUT_ROOT=false
HAS_CUSTOM_BUILD_ROOT=false
CURRENT_STAGE="argument_parsing"
xcodebuild_status="null"
tee_status="null"
declare -a EXTRA_ARGS=()

print_help() {
  cat <<'EOF'
Usage: ./scripts/testing/run-flowtabtests-local.sh [test|build-for-testing|test-without-building] [--build-root <dir>] [--output-root <dir>] [xcodebuild args...]

Runs FlowTabTests with build caches, temp files, and app-test HOME redirected
into ./.build-local/app-tests. Local app-test builds disable code signing by
default because FlowTabTests do not require a permission-bearing app identity.

Script options:
  --build-root <dir>   Resolve DerivedData, temp, HOME, module cache, and package
                       cache below this directory. Audit callers use a root under
                       the current project's Git-ignored ./.build-local/ tree.
  --output-root <dir>  Write this invocation's result bundle and xcodebuild log
                       below a new directory. The directory must not already
                       exist, which prevents a later attempt from overwriting it.
                       Without this option, the legacy fixed output paths remain.

Outputs below the selected root:
  results/FlowTabTests.xcresult  Test result bundle when the action runs tests
  logs/xcodebuild-<action>.log   Complete xcodebuild output
  status.json                    Action and child-process exit status

Examples:
  ./scripts/testing/run-flowtabtests-local.sh
  ./scripts/testing/run-flowtabtests-local.sh --build-root ./.build-local/test-audit/campaign-001/build/app-tests
  ./scripts/testing/run-flowtabtests-local.sh --output-root ./.build-local/test-audit/attempt-001
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
    --build-root)
      if [[ "${HAS_CUSTOM_BUILD_ROOT}" == true ]]; then
        echo "--build-root may only be specified once." >&2
        exit 1
      fi
      if [[ $# -lt 2 || -z "${2}" ]]; then
        echo "--build-root requires a non-empty directory path." >&2
        exit 1
      fi
      BUILD_ROOT="${2}"
      HAS_CUSTOM_BUILD_ROOT=true
      shift 2
      ;;
    --build-root=*)
      if [[ "${HAS_CUSTOM_BUILD_ROOT}" == true ]]; then
        echo "--build-root may only be specified once." >&2
        exit 1
      fi
      BUILD_ROOT="${1#*=}"
      if [[ -z "${BUILD_ROOT}" ]]; then
        echo "--build-root requires a non-empty directory path." >&2
        exit 1
      fi
      HAS_CUSTOM_BUILD_ROOT=true
      shift
      ;;
    --output-root)
      if [[ "${HAS_CUSTOM_OUTPUT_ROOT}" == true ]]; then
        echo "--output-root may only be specified once." >&2
        exit 1
      fi
      if [[ $# -lt 2 || -z "${2}" ]]; then
        echo "--output-root requires a non-empty directory path." >&2
        exit 1
      fi
      OUTPUT_ROOT="${2}"
      HAS_CUSTOM_OUTPUT_ROOT=true
      shift 2
      ;;
    --output-root=*)
      if [[ "${HAS_CUSTOM_OUTPUT_ROOT}" == true ]]; then
        echo "--output-root may only be specified once." >&2
        exit 1
      fi
      OUTPUT_ROOT="${1#*=}"
      if [[ -z "${OUTPUT_ROOT}" ]]; then
        echo "--output-root requires a non-empty directory path." >&2
        exit 1
      fi
      HAS_CUSTOM_OUTPUT_ROOT=true
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

DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
TMP_ROOT="${BUILD_ROOT}/tmp"
HOME_ROOT="${BUILD_ROOT}/home"
MODULE_CACHE_ROOT="${BUILD_ROOT}/module-cache"
PACKAGE_CACHE_PATH="${BUILD_ROOT}/source-packages"
if [[ "${HAS_CUSTOM_OUTPUT_ROOT}" == false ]]; then
  OUTPUT_ROOT="${BUILD_ROOT}"
fi

if [[ "${HAS_CUSTOM_OUTPUT_ROOT}" == true ]]; then
  if ! mkdir -p "$(dirname "${OUTPUT_ROOT}")"; then
    echo "Could not create output parent directory: $(dirname "${OUTPUT_ROOT}")" >&2
    exit 1
  fi
  if ! mkdir "${OUTPUT_ROOT}" 2>/dev/null; then
    if [[ -e "${OUTPUT_ROOT}" ]]; then
      echo "Output root must not already exist: ${OUTPUT_ROOT}" >&2
      echo "Use a new attempt-specific directory so prior evidence cannot be overwritten." >&2
    else
      echo "Could not create output root: ${OUTPUT_ROOT}" >&2
    fi
    exit 1
  fi
fi

RESULT_BUNDLE_PATH="${OUTPUT_ROOT}/results/FlowTabTests.xcresult"
LOG_ROOT="${OUTPUT_ROOT}/logs"
XCODEBUILD_LOG_PATH="${LOG_ROOT}/xcodebuild-${ACTION}.log"
STATUS_FILE="${OUTPUT_ROOT}/status.json"

mkdir -p \
  "${DERIVED_DATA_PATH}" \
  "${OUTPUT_ROOT}/results" \
  "${LOG_ROOT}" \
  "${TMP_ROOT}" \
  "${HOME_ROOT}" \
  "${MODULE_CACHE_ROOT}/clang" \
  "${MODULE_CACHE_ROOT}/swift" \
  "${PACKAGE_CACHE_PATH}"

write_status() {
  local final_exit_code="$1"
  local result_bundle_present="false"
  local status_temp="${STATUS_FILE}.tmp"

  if [[ -d "${RESULT_BUNDLE_PATH}" ]]; then
    result_bundle_present="true"
  fi

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "runner_kind": "flowtabtests",\n'
    printf '  "action": "%s",\n' "${ACTION}"
    printf '  "stage": "%s",\n' "${CURRENT_STAGE}"
    printf '  "final_exit_code": %s,\n' "${final_exit_code}"
    printf '  "xcodebuild_exit_code": %s,\n' "${xcodebuild_status}"
    printf '  "xcodebuild_log_exit_code": %s,\n' "${tee_status}"
    printf '  "result_bundle_present": %s\n' "${result_bundle_present}"
    printf '}\n'
  } >"${status_temp}" || return 1
  mv "${status_temp}" "${STATUS_FILE}"
}

finalize_status() {
  local script_exit_code="$1"
  trap - EXIT
  if ! write_status "${script_exit_code}"; then
    echo "Failed to preserve run status: ${STATUS_FILE}" >&2
    if [[ "${script_exit_code}" -eq 0 ]]; then
      script_exit_code=1
    fi
  fi
  exit "${script_exit_code}"
}

trap 'finalize_status "$?"' EXIT

export TMPDIR="${TMP_ROOT}/"
export HOME="${HOME_ROOT}"
export CFFIXED_USER_HOME="${HOME_ROOT}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}/clang"
export SWIFT_MODULECACHE_PATH="${MODULE_CACHE_ROOT}/swift"
export SWIFTPM_PACKAGECACHE="${PACKAGE_CACHE_PATH}"

if [[ "${ACTION}" != "build-for-testing" && "${HAS_CUSTOM_TEST_FILTER}" == false ]]; then
  if ((${#EXTRA_ARGS[@]} > 0)); then
    EXTRA_ARGS=("-only-testing:FlowTabTests" "${EXTRA_ARGS[@]}")
  else
    EXTRA_ARGS=("-only-testing:FlowTabTests")
  fi
fi

if [[ "${HAS_CUSTOM_OUTPUT_ROOT}" == false ]]; then
  rm -rf "${RESULT_BUNDLE_PATH}"
fi

echo "FlowTabTests build root: ${BUILD_ROOT}"
echo "Invocation output root: ${OUTPUT_ROOT}"
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
if ((${#EXTRA_ARGS[@]} > 0)); then
  XCODEBUILD_CMD+=("${EXTRA_ARGS[@]}")
fi

CURRENT_STAGE="xcodebuild"
set +e
"${XCODEBUILD_CMD[@]}" 2>&1 | tee "${XCODEBUILD_LOG_PATH}"
pipeline_status=("${PIPESTATUS[@]}")
xcodebuild_status="${pipeline_status[0]}"
tee_status="${pipeline_status[1]}"
set -e

if [[ "${tee_status}" -ne 0 ]]; then
  CURRENT_STAGE="xcodebuild_log_failed"
  echo "Failed to preserve xcodebuild log: ${XCODEBUILD_LOG_PATH}" >&2
  exit 1
fi

if [[ "${xcodebuild_status}" -ne 0 ]]; then
  CURRENT_STAGE="xcodebuild_failed"
  echo >&2
  echo "FlowTabTests run failed." >&2
  echo "xcodebuild log: ${XCODEBUILD_LOG_PATH}" >&2
  echo "If the error still points at sandboxed temporary files or restricted caches," >&2
  echo "treat it as an environment blocker and rerun with elevated permissions or outside the sandbox." >&2
  exit "${xcodebuild_status}"
fi

if [[ "${ACTION}" != "build-for-testing" && ! -d "${RESULT_BUNDLE_PATH}" ]]; then
  CURRENT_STAGE="result_bundle_missing"
  echo "FlowTabTests completed without the required result bundle: ${RESULT_BUNDLE_PATH}" >&2
  exit 1
fi

if [[ -d "${RESULT_BUNDLE_PATH}" ]]; then
  echo "Result bundle: ${RESULT_BUNDLE_PATH}"
fi
echo "xcodebuild log: ${XCODEBUILD_LOG_PATH}"
CURRENT_STAGE="completed"
