#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
UI_TEST_APP_LIFECYCLE_PATH="${ROOT_DIR}/scripts/testing/lib/ui-test-app-lifecycle.sh"
TEST_ROOT=""
TEST_HOME=""
MANAGED_APP_PATH=""
FORMAL_APP_PATH=""

# shellcheck source=/dev/null
source "${PATH_BOUNDARIES_PATH}"
# shellcheck source=/dev/null
source "${UI_TEST_APP_LIFECYCLE_PATH}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_exists() {
  [[ -f "$1" ]] || fail "Expected file: $1"
}

assert_path_absent() {
  [[ ! -e "$1" ]] || fail "Expected path to be absent: $1"
}

create_fake_app() {
  local app_path="$1"
  local info_plist="${app_path}/Contents/Info.plist"
  local executable_path="${app_path}/Contents/MacOS/FlowTabLifecycleFixture"

  /bin/rm -rf "${app_path}"
  /bin/mkdir -p "${app_path}/Contents/MacOS"
  /usr/bin/plutil -create xml1 "${info_plist}"
  /usr/bin/plutil -insert CFBundleIdentifier \
    -string "${FLOWTAB_UI_TEST_APP_BUNDLE_IDENTIFIER}" \
    "${info_plist}"
  /usr/bin/plutil -insert CFBundleExecutable \
    -string "FlowTabLifecycleFixture" \
    "${info_plist}"
  /usr/bin/plutil -insert CFBundlePackageType -string "APPL" "${info_plist}"
  printf '#!/usr/bin/env bash\nexit 0\n' >"${executable_path}"
  /bin/chmod 755 "${executable_path}"
  /usr/bin/codesign --force --deep --sign - "${app_path}" >/dev/null
}

cleanup() {
  if [[ -n "${MANAGED_APP_PATH}" && -n "${TEST_HOME}" ]]; then
    flowtab_ui_test_app_reset_lifecycle \
      "${ROOT_DIR}" \
      "${TEST_HOME}" \
      "${MANAGED_APP_PATH}" \
      >/dev/null 2>&1 || true
  fi
  if [[ -n "${TEST_ROOT}" && -d "${TEST_ROOT}" ]]; then
    /bin/rm -rf "${TEST_ROOT}"
  fi
}

trap cleanup EXIT

/bin/mkdir -p "${ROOT_DIR}/.build-local"
TEST_ROOT="$(/usr/bin/mktemp -d "${ROOT_DIR}/.build-local/ui-test-app-lifecycle-test.XXXXXX")"
TEST_HOME="${TEST_ROOT}/home"
/bin/mkdir -p "${TEST_HOME}/Applications"
MANAGED_APP_PATH="${TEST_HOME}/Applications/${FLOWTAB_UI_TEST_APP_BUNDLE_NAME}"
FORMAL_APP_PATH="${TEST_HOME}/Applications/Flow Tab.app"

echo "[1/8] Installer receipt is valid before a test claim"
create_fake_app "${MANAGED_APP_PATH}"
flowtab_ui_test_app_issue_receipt "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}"
flowtab_ui_test_app_describe_path "${TEST_HOME}" "${MANAGED_APP_PATH}"
flowtab_ui_test_app_lifecycle_paths "${ROOT_DIR}" "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}"
assert_file_exists "${FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH}"
flowtab_ui_test_app_validate_ready_receipt "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}"

echo "[2/8] A receipt can be claimed only once"
flowtab_ui_test_app_claim "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}"
assert_path_absent "${FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH}"
assert_file_exists "${FLOWTAB_UI_TEST_APP_CLAIM_RECEIPT_PATH}"
if flowtab_ui_test_app_claim "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}" >/dev/null 2>&1; then
  fail "A second lifecycle claim unexpectedly succeeded"
fi

echo "[3/8] Cleanup removes only the claimed dedicated test bundle"
flowtab_ui_test_app_remove_managed_bundle "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}"
assert_path_absent "${MANAGED_APP_PATH}"
assert_path_absent "${FLOWTAB_UI_TEST_APP_CLAIM_DIRECTORY}"

echo "[4/8] A changed app cannot reuse an issued receipt"
create_fake_app "${MANAGED_APP_PATH}"
flowtab_ui_test_app_issue_receipt "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}"
printf '\n# changed after installation\n' \
  >>"${MANAGED_APP_PATH}/Contents/MacOS/FlowTabLifecycleFixture"
if flowtab_ui_test_app_claim "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}" >/dev/null 2>&1; then
  fail "A receipt for a changed executable unexpectedly succeeded"
fi
flowtab_ui_test_app_remove_managed_bundle "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}"

echo "[5/8] The formal Flow Tab.app path stays outside managed cleanup"
create_fake_app "${FORMAL_APP_PATH}"
if flowtab_ui_test_app_is_dedicated_path "${TEST_HOME}" "${FORMAL_APP_PATH}"; then
  fail "The formal app path was classified as a managed UI-test app"
fi
if flowtab_ui_test_app_remove_managed_bundle \
  "${ROOT_DIR}" \
  "${TEST_HOME}" \
  "${FORMAL_APP_PATH}" \
  >/dev/null 2>&1
then
  fail "Managed cleanup unexpectedly accepted the formal app path"
fi
[[ -d "${FORMAL_APP_PATH}" ]] || fail "The formal app path was removed"

echo "[6/8] Runner failure still removes the claimed dedicated test bundle"
RUNNER_BUILD_ROOT="${TEST_ROOT}/runner-build"
RUNNER_OUTPUT_ROOT="${TEST_ROOT}/runner-output"
RUNNER_CONSOLE_LOG="${TEST_ROOT}/runner-console.log"
create_fake_app "${MANAGED_APP_PATH}"
flowtab_ui_test_app_issue_receipt "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}"
if HOME="${TEST_HOME}" \
  CFFIXED_USER_HOME="${TEST_HOME}" \
  "${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh" \
    test-without-building \
    --skip-space-fixtures \
    --build-root "${RUNNER_BUILD_ROOT}" \
    --output-root "${RUNNER_OUTPUT_ROOT}" \
    >"${RUNNER_CONSOLE_LOG}" 2>&1
then
  fail "The missing build-for-testing fixture unexpectedly passed"
fi
assert_path_absent "${MANAGED_APP_PATH}"
[[ "$(/usr/bin/plutil -extract ui_test_app_lifecycle_status raw -o - "${RUNNER_OUTPUT_ROOT}/status.json")" == "claimed" ]] \
  || fail "Runner status did not preserve the claimed lifecycle"
[[ "$(/usr/bin/plutil -extract ui_test_app_cleanup_exit_code raw -o - "${RUNNER_OUTPUT_ROOT}/status.json")" == "0" ]] \
  || fail "Runner cleanup did not succeed"
[[ "$(/usr/bin/plutil -extract ui_test_app_removed raw -o - "${RUNNER_OUTPUT_ROOT}/status.json")" == "true" ]] \
  || fail "Runner status did not prove app removal"
[[ "$(/usr/bin/plutil -extract verdict raw -o - "${RUNNER_OUTPUT_ROOT}/ui-test-app-lifecycle-cleanup.json")" == "absent" ]] \
  || fail "Runner cleanup evidence did not prove exact absence"

echo "[7/8] A terminated runner still removes the claimed dedicated test bundle"
RUNNER_INTERRUPT_BUILD_ROOT="${TEST_ROOT}/runner-interrupt-build"
RUNNER_INTERRUPT_OUTPUT_ROOT="${TEST_ROOT}/runner-interrupt-output"
/bin/mkdir -p "${TEST_ROOT}/bin"
printf '#!/usr/bin/env bash\n/bin/kill -TERM "${PPID}"\nexit 143\n' \
  >"${TEST_ROOT}/bin/xcodebuild"
/bin/chmod 755 "${TEST_ROOT}/bin/xcodebuild"
create_fake_app "${MANAGED_APP_PATH}"
flowtab_ui_test_app_issue_receipt "${ROOT_DIR}" "${TEST_HOME}" "${MANAGED_APP_PATH}"
if HOME="${TEST_HOME}" \
  CFFIXED_USER_HOME="${TEST_HOME}" \
  PATH="${TEST_ROOT}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh" \
    --skip-space-fixtures \
    --build-root "${RUNNER_INTERRUPT_BUILD_ROOT}" \
    --output-root "${RUNNER_INTERRUPT_OUTPUT_ROOT}" \
    >"${TEST_ROOT}/runner-interrupt-console.log" 2>&1
then
  fail "The intentionally terminated runner unexpectedly passed"
fi
assert_path_absent "${MANAGED_APP_PATH}"
[[ "$(/usr/bin/plutil -extract final_exit_code raw -o - "${RUNNER_INTERRUPT_OUTPUT_ROOT}/status.json")" == "143" ]] \
  || fail "Runner did not preserve the TERM exit code"
[[ "$(/usr/bin/plutil -extract ui_test_app_cleanup_exit_code raw -o - "${RUNNER_INTERRUPT_OUTPUT_ROOT}/status.json")" == "0" ]] \
  || fail "Terminated-runner cleanup did not succeed"
[[ "$(/usr/bin/plutil -extract ui_test_app_removed raw -o - "${RUNNER_INTERRUPT_OUTPUT_ROOT}/status.json")" == "true" ]] \
  || fail "Terminated-runner status did not prove app removal"

echo "[8/8] A later runner cannot proceed without reinstalling"
RUNNER_REUSE_OUTPUT_ROOT="${TEST_ROOT}/runner-reuse-output"
if HOME="${TEST_HOME}" \
  CFFIXED_USER_HOME="${TEST_HOME}" \
  "${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh" \
    test-without-building \
    --skip-space-fixtures \
    --build-root "${RUNNER_BUILD_ROOT}" \
    --output-root "${RUNNER_REUSE_OUTPUT_ROOT}" \
    >"${TEST_ROOT}/runner-reuse-console.log" 2>&1
then
  fail "A runner without a fresh install receipt unexpectedly proceeded"
fi
[[ "$(/usr/bin/plutil -extract ui_test_app_lifecycle_status raw -o - "${RUNNER_REUSE_OUTPUT_ROOT}/status.json")" == "claim_failed" ]] \
  || fail "Runner did not report the missing fresh receipt"
[[ "$(/usr/bin/plutil -extract ui_test_app_cleanup_exit_code raw -o - "${RUNNER_REUSE_OUTPUT_ROOT}/status.json")" == "0" ]] \
  || fail "Missing-receipt recovery did not finish cleanup"
[[ "$(/usr/bin/plutil -extract ui_test_app_removed raw -o - "${RUNNER_REUSE_OUTPUT_ROOT}/status.json")" == "true" ]] \
  || fail "Missing-receipt recovery did not preserve app absence"

echo "PASS: UI-test app lifecycle receipt and cleanup boundaries"
