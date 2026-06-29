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
ORIGINAL_HOME="${HOME}"
ORIGINAL_CFFIXED_USER_HOME="${CFFIXED_USER_HOME:-${HOME}}"
DEFAULT_UI_TEST_APP_PATH="${USER_HOME}/Applications/Flow Tab UITest.app"
LOCAL_SIGNING_CONFIG_PATH="${ROOT_DIR}/xcconfigs/LocalSigning.xcconfig"
SPACE_FIXTURE_BUILD_SCRIPT="${ROOT_DIR}/scripts/testing/build-space-fixture-workflow.sh"
SPACE_FIXTURE_BASELINE_WORKFLOW="${ROOT_DIR}/docs/fixtures/space-fixture-home-multi-app-workflow.json"
SPACE_FIXTURE_BASELINE_RESOLVED_PATH="${ROOT_DIR}/.build-local/space-fixture-workflow/variants/resolved-workflow.json"
UI_TEST_RUNNER_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug/FlowTabUITests-Runner.app"

ACTION="test"
ACTION_SET=false
HAS_CUSTOM_TEST_FILTER=false
HAS_CODE_SIGNING_OVERRIDE=false
USE_STABLE_UI_TEST_APP=true
PREPARE_SPACE_FIXTURES=true
UI_TEST_APP_PATH="${FLOWTAB_UI_TEST_APP_PATH:-${DEFAULT_UI_TEST_APP_PATH}}"
DEVELOPMENT_TEAM="${FLOWTAB_DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${FLOWTAB_CODE_SIGN_IDENTITY:-}"
RESOLVED_CODE_SIGN_IDENTITY=""
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

resolve_code_sign_identity() {
  local requested="$1"
  local team="$2"
  local identities
  local line
  local identity

  identities="$(
    HOME="${ORIGINAL_HOME}" \
    CFFIXED_USER_HOME="${ORIGINAL_CFFIXED_USER_HOME}" \
    security find-identity -v -p codesigning 2>/dev/null || true
  )"

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

    if [[ -z "${requested}" && "${identity}" != Apple\ Development:* ]]; then
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

  if RESOLVED_CODE_SIGN_IDENTITY="$(resolve_code_sign_identity "${CODE_SIGN_IDENTITY}" "${DEVELOPMENT_TEAM}")"; then
    echo "UI test runner signing identity: ${RESOLVED_CODE_SIGN_IDENTITY}"
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
  local check_output

  if check_output="$(/usr/bin/python3 - "${SPACE_FIXTURE_BASELINE_RESOLVED_PATH}" <<'PY'
import json
import os
import sys

resolved_path = sys.argv[1]
expected_workflow = "multi-app-home-window-counts"
expected_apps = {
    "finder": ("Finder Fixture", "com.example.fixture.finder"),
    "chrome": ("Chrome Fixture", "com.example.fixture.chrome"),
    "notes": ("Notes Fixture", "com.example.fixture.notes"),
}

def sanitized_app_bundle_name(app_name, bundle_id):
    return f"{app_name}-{bundle_id}.app".replace("/", "-").replace(":", "-")

try:
    with open(resolved_path, encoding="utf-8") as handle:
        workflow = json.load(handle)
except FileNotFoundError:
    print(f"missing {resolved_path}")
    raise SystemExit(1)
except json.JSONDecodeError as error:
    print(f"invalid JSON in {resolved_path}: {error}")
    raise SystemExit(1)

workflow_name = workflow.get("workflowName")
if workflow_name != expected_workflow:
    print(f"resolved workflow is {workflow_name!r}, expected {expected_workflow!r}")
    raise SystemExit(1)

apps = workflow.get("apps")
if not isinstance(apps, list):
    print("resolved workflow apps field is missing or invalid")
    raise SystemExit(1)

apps_by_id = {str(app.get("appID", "")).strip(): app for app in apps}
for app_id, (expected_app_name, expected_bundle_id) in expected_apps.items():
    app = apps_by_id.get(app_id)
    if app is None:
        print(f"missing fixture app {app_id}")
        raise SystemExit(1)

    bundle_id = str(app.get("bundleId", "")).strip()
    if bundle_id != expected_bundle_id:
        print(f"fixture app {app_id} has bundle id {bundle_id!r}, expected {expected_bundle_id!r}")
        raise SystemExit(1)

    app_path = str(app.get("appPath", "")).strip()
    if not app_path or not os.path.isdir(app_path):
        print(f"fixture app {app_id} path is missing: {app_path}")
        raise SystemExit(1)

    expected_basename = sanitized_app_bundle_name(expected_app_name, expected_bundle_id)
    actual_basename = os.path.basename(app_path)
    if actual_basename != expected_basename:
        print(f"fixture app {app_id} path is {actual_basename!r}, expected {expected_basename!r}")
        raise SystemExit(1)

    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    try:
        import plistlib
        with open(plist_path, "rb") as handle:
            plist = plistlib.load(handle)
    except FileNotFoundError:
        print(f"fixture app {app_id} Info.plist is missing: {plist_path}")
        raise SystemExit(1)
    except Exception as error:
        print(f"fixture app {app_id} Info.plist is unreadable: {error}")
        raise SystemExit(1)

    actual_bundle_id = str(plist.get("CFBundleIdentifier", "")).strip()
    if actual_bundle_id != expected_bundle_id:
        print(
            f"fixture app {app_id} Info.plist bundle id is {actual_bundle_id!r}, "
            f"expected {expected_bundle_id!r}"
        )
        raise SystemExit(1)
PY
  )"; then
    echo "Space fixture variants: ready (${SPACE_FIXTURE_BASELINE_RESOLVED_PATH})"
    return
  fi

  echo "Space fixture variants: ${check_output}"
  echo "Space fixture variants: rebuilding shared app variants from ${SPACE_FIXTURE_BASELINE_WORKFLOW}"
  "${SPACE_FIXTURE_BUILD_SCRIPT}" --workflow-config "${SPACE_FIXTURE_BASELINE_WORKFLOW}"
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
if [[ "${ACTION}" != "build-for-testing" ]]; then
  if [[ "${PREPARE_SPACE_FIXTURES}" == true ]]; then
    echo "Space fixture preparation: enabled"
  else
    echo "Space fixture preparation: skipped"
  fi
fi

if [[ "${ACTION}" != "build-for-testing" && "${PREPARE_SPACE_FIXTURES}" == true ]]; then
  ensure_space_fixture_variants
fi

build_xcodebuild_cmd() {
  local action="$1"
  local include_result_bundle="$2"

  XCODEBUILD_CMD=(
    xcodebuild
    -project "${ROOT_DIR}/FlowTab.xcodeproj"
    -scheme FlowTab
    -destination "platform=macOS"
    -derivedDataPath "${DERIVED_DATA_PATH}"
    -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"
  )

  if [[ "${include_result_bundle}" == true ]]; then
    XCODEBUILD_CMD+=(-resultBundlePath "${RESULT_BUNDLE_PATH}")
  fi

  # Local UI test builds do not use Xcode automatic signing. The wrapper signs
  # the generated XCTest runner after build-for-testing with the local identity.
  if [[ "${HAS_CODE_SIGNING_OVERRIDE}" == false ]]; then
    XCODEBUILD_CMD+=("CODE_SIGNING_ALLOWED=NO")
  fi

  XCODEBUILD_CMD+=("${action}")
}

run_xcodebuild() {
  local action="$1"
  local include_result_bundle="$2"
  shift 2
  local action_args=("$@")

  build_xcodebuild_cmd "${action}" "${include_result_bundle}"
  if ((${#action_args[@]} > 0)); then
    XCODEBUILD_CMD+=("${action_args[@]}")
  fi

  if ! "${XCODEBUILD_CMD[@]}"; then
    echo >&2
    echo "UI test run failed." >&2
    echo "If the error still points at sandboxed temporary files, restricted caches, keychain access, signing, or automation permissions," >&2
    echo "treat it as an environment blocker and rerun with elevated permissions or outside the sandbox." >&2
    exit 1
  fi
}

case "${ACTION}" in
  test)
    run_xcodebuild "build-for-testing" false
    sign_ui_test_runner
    run_xcodebuild "test-without-building" true "${EXTRA_ARGS[@]}"
    ;;
  build-for-testing)
    run_xcodebuild "build-for-testing" false "${EXTRA_ARGS[@]}"
    sign_ui_test_runner
    ;;
  test-without-building)
    sign_ui_test_runner
    run_xcodebuild "test-without-building" true "${EXTRA_ARGS[@]}"
    ;;
esac

if [[ -d "${RESULT_BUNDLE_PATH}" ]]; then
  echo "Result bundle: ${RESULT_BUNDLE_PATH}"
fi
