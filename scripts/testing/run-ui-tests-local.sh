#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INVOCATION_DIRECTORY="$(pwd -P)"
DEFAULT_BUILD_ROOT="${ROOT_DIR}/.build-local/ui-tests"
DEFAULT_SPACE_FIXTURE_BUILD_ROOT="${ROOT_DIR}/.build-local/space-fixture-workflow"
BUILD_ROOT="${DEFAULT_BUILD_ROOT}"
OUTPUT_ROOT=""
USER_HOME="${HOME}"
ORIGINAL_HOME="${HOME}"
ORIGINAL_CFFIXED_USER_HOME="${CFFIXED_USER_HOME:-${HOME}}"
DEFAULT_UI_TEST_APP_PATH="${USER_HOME}/Applications/Flow Tab UITest.app"
LOCAL_SIGNING_CONFIG_PATH="${ROOT_DIR}/xcconfigs/LocalSigning.xcconfig"
CODE_SIGNING_IDENTITY_PATH="${ROOT_DIR}/scripts/lib/code-signing-identity.sh"
SPACE_FIXTURE_BUILD_SCRIPT="${ROOT_DIR}/scripts/testing/build-space-fixture-workflow.sh"
SPACE_FIXTURE_BASELINE_WORKFLOW="${ROOT_DIR}/docs/fixtures/space-fixture-home-multi-app-workflow.json"
SYSTEM_APP_MRU_FIXTURE_WORKFLOW="${ROOT_DIR}/docs/fixtures/space-fixture-system-app-mru-workflow.json"

ACTION="test"
ACTION_SET=false
HAS_CUSTOM_TEST_FILTER=false
HAS_CODE_SIGNING_OVERRIDE=false
HAS_CUSTOM_OUTPUT_ROOT=false
HAS_CUSTOM_BUILD_ROOT=false
CURRENT_STAGE="argument_parsing"
FIXTURE_STATUS="null"
FIXTURE_LOG_STATUS="null"
SIGNING_STATUS="null"
SIGNING_LOG_STATUS="null"
BUILD_FOR_TESTING_STATUS="null"
BUILD_FOR_TESTING_LOG_STATUS="null"
TEST_WITHOUT_BUILDING_STATUS="null"
TEST_WITHOUT_BUILDING_LOG_STATUS="null"
USE_STABLE_UI_TEST_APP=true
PREPARE_SPACE_FIXTURES=true
PREPARE_SYSTEM_APP_MRU_FIXTURES=false
UI_TEST_APP_PATH="${FLOWTAB_UI_TEST_APP_PATH:-${DEFAULT_UI_TEST_APP_PATH}}"
DEVELOPMENT_TEAM="${FLOWTAB_DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${FLOWTAB_CODE_SIGN_IDENTITY:-}"
RESOLVED_CODE_SIGN_IDENTITY=""
declare -a EXTRA_ARGS=()

# shellcheck source=/dev/null
source "${CODE_SIGNING_IDENTITY_PATH}"

expand_path() {
  local path="$1"
  if [[ "${path}" == "~/"* ]]; then
    printf '%s/%s' "${USER_HOME}" "${path#~/}"
    return
  fi
  printf '%s' "${path}"
}

resolve_invocation_path() {
  local path="$1"
  if [[ "${path}" == /* ]]; then
    printf '%s' "${path}"
    return
  fi
  printf '%s/%s' "${INVOCATION_DIRECTORY}" "${path#./}"
}

print_help() {
  cat <<'EOF'
Usage: ./scripts/testing/run-ui-tests-local.sh [test|build-for-testing|test-without-building] [--build-root <dir>] [--output-root <dir>] [script args...] [xcodebuild args...]

Runs FlowTab UI automation with build caches and temp files redirected into ./.build-local/ui-tests.
When ~/Applications/Flow Tab UITest.app exists, the script also points UI tests at
that fixed app path so macOS permissions can stay attached to a stable bundle.

Script options:
  --build-root <dir>   Resolve DerivedData, temp, HOME, module cache, package
                       cache, and generated fixture variants below this root.
  --output-root <dir>  Write this invocation's result bundle and build/test logs
                       below a new directory. The directory must not already
                       exist, which prevents a later attempt from overwriting it.
                       Without this option, the legacy fixed output paths remain.
  --ui-test-app-path <path>
                       Use a specific fixed-path UI test app.
  --no-ui-test-app     Use the DerivedData app build product.
  --skip-space-fixtures
                       Skip shared Space fixture preparation.

Outputs below the selected root:
  results/FlowTabUITests.xcresult      UI test result bundle
  logs/xcodebuild-<action>.log         Per-action xcodebuild output
  logs/space-fixture-preparation.log   Fixture preparation output
  logs/sign-ui-test-runner.log         Runner signing output
  status.json                          Stage and child-process exit status

Examples:
  ./scripts/testing/run-ui-tests-local.sh
  ./scripts/testing/run-ui-tests-local.sh --build-root ./.build-local/test-audit/campaign-001/build/ui-tests
  ./scripts/testing/run-ui-tests-local.sh --output-root ./.build-local/test-audit/attempt-001
  ./scripts/testing/install-ui-test-app.sh
  ./scripts/testing/run-ui-tests-local.sh -only-testing:FlowTabUITests/FlowTabUITests/testHomePageSelectingMockAppUpdatesWindowList
  ./scripts/testing/run-ui-tests-local.sh --ui-test-app-path ~/Applications/Flow\ Tab\ UITest.app
  ./scripts/testing/run-ui-tests-local.sh --no-ui-test-app
  ./scripts/testing/run-ui-tests-local.sh --skip-space-fixtures
  ./scripts/testing/run-ui-tests-local.sh build-for-testing
  ./scripts/testing/run-ui-tests-local.sh test-without-building -only-testing:FlowTabUITests
EOF
}

local_signing_config_value() {
  local key="$1"

  if [[ ! -f "${LOCAL_SIGNING_CONFIG_PATH}" ]]; then
    return 0
  fi

  awk -v key="${key}" '
    /^[[:space:]]*(#|\/\/)/ {
      next
    }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
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

resolve_runner_signing_identity() {
  if [[ -n "${RESOLVED_CODE_SIGN_IDENTITY}" ]]; then
    return 0
  fi

  if [[ -z "${DEVELOPMENT_TEAM}" ]]; then
    DEVELOPMENT_TEAM="$(local_signing_config_value "FLOWTAB_DEVELOPMENT_TEAM")"
  fi

  if [[ -z "${CODE_SIGN_IDENTITY}" ]]; then
    CODE_SIGN_IDENTITY="$(local_signing_config_value "FLOWTAB_CODE_SIGN_IDENTITY")"
  fi

  if [[ -z "${CODE_SIGN_IDENTITY}" ]]; then
    CODE_SIGN_IDENTITY="Apple Development"
  fi

  if RESOLVED_CODE_SIGN_IDENTITY="$(
    HOME="${ORIGINAL_HOME}" \
    CFFIXED_USER_HOME="${ORIGINAL_CFFIXED_USER_HOME}" \
      flowtab_resolve_code_sign_identity \
        "${CODE_SIGN_IDENTITY}" \
        "${DEVELOPMENT_TEAM}"
  )"; then
    echo "UI test runner signing fingerprint: ${RESOLVED_CODE_SIGN_IDENTITY}"
    return 0
  fi

  echo "Could not resolve a local codesigning identity for FlowTabUITests-Runner.app." >&2
  echo "Requested identity: ${CODE_SIGN_IDENTITY}" >&2
  if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
    echo "Requested team: ${DEVELOPMENT_TEAM}" >&2
  else
    echo "No FLOWTAB_DEVELOPMENT_TEAM was exported and ${LOCAL_SIGNING_CONFIG_PATH} did not provide one." >&2
  fi
  echo "Configure xcconfigs/LocalSigning.xcconfig or FLOWTAB_DEVELOPMENT_TEAM, then rerun UI tests." >&2
  return 1
}

sign_ui_test_runner() {
  if [[ ! -d "${UI_TEST_RUNNER_PATH}" ]]; then
    echo "UI test runner not found: ${UI_TEST_RUNNER_PATH}" >&2
    return 1
  fi

  resolve_runner_signing_identity
  echo "Signing UI test runner: ${UI_TEST_RUNNER_PATH}"
  HOME="${ORIGINAL_HOME}" \
  CFFIXED_USER_HOME="${ORIGINAL_CFFIXED_USER_HOME}" \
    /usr/bin/codesign --force --deep --sign "${RESOLVED_CODE_SIGN_IDENTITY}" "${UI_TEST_RUNNER_PATH}"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "${UI_TEST_RUNNER_PATH}"
}

ensure_space_fixture_variants() {
  echo "Space fixture variants: rebuilding from current fixture source"
  "${SPACE_FIXTURE_BUILD_SCRIPT}" \
    --build-root "${SPACE_FIXTURE_BUILD_ROOT}" \
    --workflow-config "${SPACE_FIXTURE_BASELINE_WORKFLOW}" \
    --output-dir "${SPACE_FIXTURE_BUILD_ROOT}/variants" \
    --resolved-workflow-path "${SPACE_FIXTURE_BASELINE_RESOLVED_PATH}"
}

ensure_system_app_mru_fixture_variants() {
  echo "System app MRU fixture variants: rebuilding from current fixture source"
  "${SPACE_FIXTURE_BUILD_SCRIPT}" \
    --build-root "${SPACE_FIXTURE_BUILD_ROOT}/system-app-mru" \
    --workflow-config "${SYSTEM_APP_MRU_FIXTURE_WORKFLOW}" \
    --output-dir "${SPACE_FIXTURE_BUILD_ROOT}/system-app-mru-variants" \
    --resolved-workflow-path "${SYSTEM_APP_MRU_FIXTURE_RESOLVED_PATH}"
}

prepare_required_space_fixture_variants() {
  ensure_space_fixture_variants
  if [[ "${PREPARE_SYSTEM_APP_MRU_FIXTURES}" == true ]]; then
    ensure_system_app_mru_fixture_variants
  fi
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
    --ui-test-app-path)
      if [[ $# -lt 2 || -z "${2}" ]]; then
        echo "--ui-test-app-path requires a non-empty app path." >&2
        exit 1
      fi
      UI_TEST_APP_PATH="${2}"
      shift 2
      ;;
    --ui-test-app-path=*)
      UI_TEST_APP_PATH="${1#*=}"
      if [[ -z "${UI_TEST_APP_PATH}" ]]; then
        echo "--ui-test-app-path requires a non-empty app path." >&2
        exit 1
      fi
      shift
      ;;
    --no-ui-test-app)
      USE_STABLE_UI_TEST_APP=false
      shift
      ;;
    --skip-space-fixtures)
      PREPARE_SPACE_FIXTURES=false
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

if [[ "${PREPARE_SPACE_FIXTURES}" == true ]]; then
  if [[ "${HAS_CUSTOM_TEST_FILTER}" == false ]]; then
    PREPARE_SYSTEM_APP_MRU_FIXTURES=true
  else
    for argument in "${EXTRA_ARGS[@]}"; do
      case "${argument}" in
        -only-testing:FlowTabUITests|-only-testing:FlowTabUITests/FlowTabUITests|*testSystemAppMRU*)
          PREPARE_SYSTEM_APP_MRU_FIXTURES=true
          break
          ;;
      esac
    done
  fi
fi

UI_TEST_APP_PATH="$(expand_path "${UI_TEST_APP_PATH}")"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
TMP_ROOT="${BUILD_ROOT}/tmp"
HOME_ROOT="${BUILD_ROOT}/home"
MODULE_CACHE_ROOT="${BUILD_ROOT}/module-cache"
PACKAGE_CACHE_PATH="${BUILD_ROOT}/source-packages"
UI_TEST_RUNNER_PATH="${DERIVED_DATA_PATH}/Build/Products/Testing/FlowTabUITests-Runner.app"
UI_TEST_XCTESTRUN_PATH=""
if [[ "${HAS_CUSTOM_BUILD_ROOT}" == true ]]; then
  SPACE_FIXTURE_BUILD_ROOT="${BUILD_ROOT}/space-fixture-workflow"
else
  SPACE_FIXTURE_BUILD_ROOT="${DEFAULT_SPACE_FIXTURE_BUILD_ROOT}"
fi
SPACE_FIXTURE_BASELINE_RESOLVED_PATH="${SPACE_FIXTURE_BUILD_ROOT}/variants/resolved-workflow.json"
SYSTEM_APP_MRU_FIXTURE_RESOLVED_PATH="${SPACE_FIXTURE_BUILD_ROOT}/system-app-mru-variants/resolved-workflow.json"
SPACE_FIXTURE_BASELINE_ACCESSIBLE_PATH="$(
  resolve_invocation_path "${SPACE_FIXTURE_BASELINE_RESOLVED_PATH}"
)"
SYSTEM_APP_MRU_FIXTURE_ACCESSIBLE_PATH="$(
  resolve_invocation_path "${SYSTEM_APP_MRU_FIXTURE_RESOLVED_PATH}"
)"
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

RESULT_BUNDLE_PATH="${OUTPUT_ROOT}/results/FlowTabUITests.xcresult"
LOG_ROOT="${OUTPUT_ROOT}/logs"
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
    printf '  "runner_kind": "flowtab_ui_tests",\n'
    printf '  "action": "%s",\n' "${ACTION}"
    printf '  "stage": "%s",\n' "${CURRENT_STAGE}"
    printf '  "final_exit_code": %s,\n' "${final_exit_code}"
    printf '  "fixture_exit_code": %s,\n' "${FIXTURE_STATUS}"
    printf '  "fixture_log_exit_code": %s,\n' "${FIXTURE_LOG_STATUS}"
    printf '  "signing_exit_code": %s,\n' "${SIGNING_STATUS}"
    printf '  "signing_log_exit_code": %s,\n' "${SIGNING_LOG_STATUS}"
    printf '  "build_for_testing_exit_code": %s,\n' "${BUILD_FOR_TESTING_STATUS}"
    printf '  "build_for_testing_log_exit_code": %s,\n' "${BUILD_FOR_TESTING_LOG_STATUS}"
    printf '  "test_without_building_exit_code": %s,\n' "${TEST_WITHOUT_BUILDING_STATUS}"
    printf '  "test_without_building_log_exit_code": %s,\n' "${TEST_WITHOUT_BUILDING_LOG_STATUS}"
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
export FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH="${SPACE_FIXTURE_BASELINE_ACCESSIBLE_PATH}"
export FLOWTAB_SYSTEM_APP_MRU_FIXTURE_WORKFLOW_PATH="${SYSTEM_APP_MRU_FIXTURE_ACCESSIBLE_PATH}"

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

if [[ "${HAS_CUSTOM_OUTPUT_ROOT}" == false ]]; then
  rm -rf "${RESULT_BUNDLE_PATH}"
fi

echo "UI test build root: ${BUILD_ROOT}"
echo "Invocation output root: ${OUTPUT_ROOT}"
echo "DerivedData: ${DERIVED_DATA_PATH}"
echo "TMPDIR: ${TMPDIR}"
echo "Module cache: ${MODULE_CACHE_ROOT}"
echo "Source packages: ${PACKAGE_CACHE_PATH}"
echo "Space fixture workflow: ${FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH}"
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
if [[ "${ACTION}" != "build-for-testing" ]]; then
  if [[ "${PREPARE_SPACE_FIXTURES}" == true ]]; then
    echo "Space fixture preparation: enabled"
  else
    echo "Space fixture preparation: skipped"
  fi
fi

build_xcodebuild_cmd() {
  local action="$1"
  local include_result_bundle="$2"

  if [[ "${action}" == "test-without-building" ]]; then
    if [[ -z "${UI_TEST_XCTESTRUN_PATH}" ]]; then
      echo "The UI test .xctestrun path is not configured." >&2
      return 1
    fi
    XCODEBUILD_CMD=(
      xcodebuild
      -xctestrun "${UI_TEST_XCTESTRUN_PATH}"
      -destination "platform=macOS"
    )
  else
    XCODEBUILD_CMD=(
      xcodebuild
      -project "${ROOT_DIR}/FlowTab.xcodeproj"
      -scheme FlowTab
      -destination "platform=macOS"
      -derivedDataPath "${DERIVED_DATA_PATH}"
      -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"
    )
  fi

  if [[ "${include_result_bundle}" == true ]]; then
    XCODEBUILD_CMD+=(-resultBundlePath "${RESULT_BUNDLE_PATH}")
  fi

  # Local UI test builds do not use Xcode automatic signing. The wrapper signs
  # the generated XCTest runner after build-for-testing with the local identity.
  if [[ "${action}" != "test-without-building" && "${HAS_CODE_SIGNING_OVERRIDE}" == false ]]; then
    XCODEBUILD_CMD+=("CODE_SIGNING_ALLOWED=NO")
  fi

  XCODEBUILD_CMD+=("${action}")
}

set_xctestrun_environment_value() {
  local xctestrun_path="$1"
  local key_path="$2"
  local value="$3"

  if plutil -type "${key_path}" "${xctestrun_path}" >/dev/null 2>&1; then
    plutil -replace "${key_path}" -string "${value}" "${xctestrun_path}"
  else
    plutil -insert "${key_path}" -string "${value}" "${xctestrun_path}"
  fi
}

remove_xctestrun_environment_value() {
  local xctestrun_path="$1"
  local key_path="$2"

  if plutil -type "${key_path}" "${xctestrun_path}" >/dev/null 2>&1; then
    plutil -remove "${key_path}" "${xctestrun_path}"
  fi
}

configure_ui_test_runner_environment() {
  local products_root
  local xctestrun_path
  local -a xctestrun_paths=()

  CURRENT_STAGE="configure_ui_test_runner_environment"
  products_root="$(
    resolve_invocation_path \
      "${DERIVED_DATA_PATH}/Build/Products"
  )"
  while IFS= read -r -d '' xctestrun_path; do
    xctestrun_paths+=("${xctestrun_path}")
  done < <(
    find "${products_root}" \
      -maxdepth 1 \
      -type f \
      -name '*.xctestrun' \
      -print0
  )

  if [[ "${#xctestrun_paths[@]}" -ne 1 ]]; then
    echo "Expected one FlowTab .xctestrun file below ${products_root}; found ${#xctestrun_paths[@]}." >&2
    return 1
  fi

  UI_TEST_XCTESTRUN_PATH="${xctestrun_paths[0]}"
  if ! plutil -extract FlowTabUITests raw \
    -expect dictionary \
    -o /dev/null \
    "${UI_TEST_XCTESTRUN_PATH}" 2>/dev/null
  then
    echo "The generated .xctestrun file has no FlowTabUITests entry: ${UI_TEST_XCTESTRUN_PATH}" >&2
    return 1
  fi

  set_xctestrun_environment_value \
    "${UI_TEST_XCTESTRUN_PATH}" \
    "FlowTabUITests.EnvironmentVariables.FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH" \
    "${SPACE_FIXTURE_BASELINE_ACCESSIBLE_PATH}"
  set_xctestrun_environment_value \
    "${UI_TEST_XCTESTRUN_PATH}" \
    "FlowTabUITests.EnvironmentVariables.FLOWTAB_SYSTEM_APP_MRU_FIXTURE_WORKFLOW_PATH" \
    "${SYSTEM_APP_MRU_FIXTURE_ACCESSIBLE_PATH}"
  if [[ -n "${FLOWTAB_UI_TEST_APP_PATH:-}" ]]; then
    set_xctestrun_environment_value \
      "${UI_TEST_XCTESTRUN_PATH}" \
      "FlowTabUITests.EnvironmentVariables.FLOWTAB_UI_TEST_APP_PATH" \
      "${FLOWTAB_UI_TEST_APP_PATH}"
  else
    remove_xctestrun_environment_value \
      "${UI_TEST_XCTESTRUN_PATH}" \
      "FlowTabUITests.EnvironmentVariables.FLOWTAB_UI_TEST_APP_PATH"
  fi
  echo "Configured UI test runner environment: ${UI_TEST_XCTESTRUN_PATH}"
}

run_logged_stage() {
  local stage_name="$1"
  local log_path="$2"
  shift 2
  local command_status
  local log_status
  local -a pipeline_status

  CURRENT_STAGE="${stage_name}"
  set +e
  (set -e; "$@") 2>&1 | tee "${log_path}"
  pipeline_status=("${PIPESTATUS[@]}")
  command_status="${pipeline_status[0]}"
  log_status="${pipeline_status[1]}"
  set -e

  case "${stage_name}" in
    fixture_preparation)
      FIXTURE_STATUS="${command_status}"
      FIXTURE_LOG_STATUS="${log_status}"
      ;;
    signing)
      SIGNING_STATUS="${command_status}"
      SIGNING_LOG_STATUS="${log_status}"
      ;;
  esac

  if [[ "${log_status}" -ne 0 ]]; then
    CURRENT_STAGE="${stage_name}_log_failed"
    echo "Failed to preserve ${stage_name} log: ${log_path}" >&2
    exit 1
  fi

  if [[ "${command_status}" -ne 0 ]]; then
    CURRENT_STAGE="${stage_name}_failed"
    echo "${stage_name} failed with exit code ${command_status}. Log: ${log_path}" >&2
    exit "${command_status}"
  fi
}

run_xcodebuild() {
  local action="$1"
  local include_result_bundle="$2"
  shift 2
  local action_args=("$@")
  local log_path="${LOG_ROOT}/xcodebuild-${action}.log"
  local xcodebuild_status
  local tee_status
  local -a pipeline_status

  build_xcodebuild_cmd "${action}" "${include_result_bundle}"
  if ((${#action_args[@]} > 0)); then
    XCODEBUILD_CMD+=("${action_args[@]}")
  fi

  CURRENT_STAGE="xcodebuild_${action}"
  set +e
  "${XCODEBUILD_CMD[@]}" 2>&1 | tee "${log_path}"
  pipeline_status=("${PIPESTATUS[@]}")
  xcodebuild_status="${pipeline_status[0]}"
  tee_status="${pipeline_status[1]}"
  set -e

  case "${action}" in
    build-for-testing)
      BUILD_FOR_TESTING_STATUS="${xcodebuild_status}"
      BUILD_FOR_TESTING_LOG_STATUS="${tee_status}"
      ;;
    test-without-building)
      TEST_WITHOUT_BUILDING_STATUS="${xcodebuild_status}"
      TEST_WITHOUT_BUILDING_LOG_STATUS="${tee_status}"
      ;;
  esac

  if [[ "${tee_status}" -ne 0 ]]; then
    CURRENT_STAGE="xcodebuild_${action}_log_failed"
    echo "Failed to preserve xcodebuild log: ${log_path}" >&2
    exit 1
  fi

  if [[ "${xcodebuild_status}" -ne 0 ]]; then
    CURRENT_STAGE="xcodebuild_${action}_failed"
    echo >&2
    if grep -q "Timed out while enabling automation mode" "${log_path}"; then
      echo "UI automation initialization timed out before any test body could provide product or runtime evidence." >&2
      echo "Classification: UI automation initialization blocker." >&2
      echo "Fixed-path app: ${FLOWTAB_UI_TEST_APP_PATH:-DerivedData build product}" >&2
      echo "UI test runner: ${UI_TEST_RUNNER_PATH}" >&2
      echo "Result bundle: ${RESULT_BUNDLE_PATH}" >&2
      echo "xcodebuild log: ${log_path}" >&2
      echo "Use this as an environment/runner signal, not as a FlowTab runtime assertion failure." >&2
      echo >&2
    fi
    echo "UI test run failed." >&2
    echo "If the error still points at sandboxed temporary files, restricted caches, keychain access, signing, or automation permissions," >&2
    echo "treat it as an environment blocker and rerun with elevated permissions or outside the sandbox." >&2
    exit "${xcodebuild_status}"
  fi
}

if [[ "${ACTION}" != "build-for-testing" && "${PREPARE_SPACE_FIXTURES}" == true ]]; then
  run_logged_stage \
    "fixture_preparation" \
    "${LOG_ROOT}/space-fixture-preparation.log" \
    prepare_required_space_fixture_variants
fi

case "${ACTION}" in
  test)
    run_xcodebuild "build-for-testing" false
    configure_ui_test_runner_environment
    run_logged_stage "signing" "${LOG_ROOT}/sign-ui-test-runner.log" sign_ui_test_runner
    if ((${#EXTRA_ARGS[@]} > 0)); then
      run_xcodebuild "test-without-building" true "${EXTRA_ARGS[@]}"
    else
      run_xcodebuild "test-without-building" true
    fi
    ;;
  build-for-testing)
    if ((${#EXTRA_ARGS[@]} > 0)); then
      run_xcodebuild "build-for-testing" false "${EXTRA_ARGS[@]}"
    else
      run_xcodebuild "build-for-testing" false
    fi
    configure_ui_test_runner_environment
    run_logged_stage "signing" "${LOG_ROOT}/sign-ui-test-runner.log" sign_ui_test_runner
    ;;
  test-without-building)
    configure_ui_test_runner_environment
    run_logged_stage "signing" "${LOG_ROOT}/sign-ui-test-runner.log" sign_ui_test_runner
    if ((${#EXTRA_ARGS[@]} > 0)); then
      run_xcodebuild "test-without-building" true "${EXTRA_ARGS[@]}"
    else
      run_xcodebuild "test-without-building" true
    fi
    ;;
esac

if [[ "${ACTION}" != "build-for-testing" && ! -d "${RESULT_BUNDLE_PATH}" ]]; then
  CURRENT_STAGE="result_bundle_missing"
  echo "UI tests completed without the required result bundle: ${RESULT_BUNDLE_PATH}" >&2
  exit 1
fi

if [[ -d "${RESULT_BUNDLE_PATH}" ]]; then
  echo "Result bundle: ${RESULT_BUNDLE_PATH}"
fi
CURRENT_STAGE="completed"
