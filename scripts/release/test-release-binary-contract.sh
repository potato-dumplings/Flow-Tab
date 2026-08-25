#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/release/verify-release-binary.sh"
mkdir -p "${ROOT_DIR}/.build-local"
TEST_ROOT="$(/usr/bin/mktemp -d "${ROOT_DIR}/.build-local/release-binary-contract.XXXXXX")"

cleanup() {
  /bin/rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

fail() {
  echo "$1" >&2
  exit 1
}

assert_rejected_with() {
  local expected="$1"
  shift
  local output=""

  if output="$("$@" 2>&1)"; then
    fail "Command unexpectedly succeeded: $*"
  fi
  if [[ "${output}" != *"${expected}"* ]]; then
    fail "Command did not report '${expected}': $*"
  fi
}

SOURCE_PATH="${TEST_ROOT}/release-symbol-fixture.c"
UNSTRIPPED_BINARY="${TEST_ROOT}/release-symbol-fixture"
UNSTRIPPED_OBJECT="${TEST_ROOT}/release-symbol-fixture.o"
STRIPPED_BINARY="${TEST_ROOT}/release-symbol-fixture-stripped"
MATCHING_DSYM="${TEST_ROOT}/release-symbol-fixture.dSYM"
EMPTY_DSYM="${TEST_ROOT}/release-symbol-fixture-empty.dSYM"
MISMATCHED_BINARY="${TEST_ROOT}/release-symbol-fixture-mismatch"
MISMATCHED_OBJECT="${TEST_ROOT}/release-symbol-fixture-mismatch.o"
MISMATCHED_DSYM="${TEST_ROOT}/release-symbol-fixture-mismatch.dSYM"

/usr/bin/printf '%s\n' \
  '#ifndef FIXTURE_VALUE' \
  '#define FIXTURE_VALUE 42' \
  '#endif' \
  '__attribute__((noinline)) static int flowtab_local_symbol_fixture(void) {' \
  '    return FIXTURE_VALUE;' \
  '}' \
  'int main(void) {' \
  '    return flowtab_local_symbol_fixture() == FIXTURE_VALUE ? 0 : 1;' \
  '}' \
  > "${SOURCE_PATH}"

/usr/bin/clang -g -O0 -DFIXTURE_VALUE=42 -c "${SOURCE_PATH}" -o "${UNSTRIPPED_OBJECT}"
/usr/bin/clang "${UNSTRIPPED_OBJECT}" -o "${UNSTRIPPED_BINARY}"
/usr/bin/dsymutil "${UNSTRIPPED_BINARY}" -o "${MATCHING_DSYM}"

assert_rejected_with \
  "ordinary local symbols" \
  "${VERIFY_SCRIPT}" \
  "${UNSTRIPPED_BINARY}"

/usr/bin/ditto "${UNSTRIPPED_BINARY}" "${STRIPPED_BINARY}"
/usr/bin/strip -x "${STRIPPED_BINARY}"
"${VERIFY_SCRIPT}" --dsym "${MATCHING_DSYM}" "${STRIPPED_BINARY}" >/dev/null

assert_rejected_with \
  "Release dSYM not found" \
  "${VERIFY_SCRIPT}" \
  --dsym "${TEST_ROOT}/missing.dSYM" \
  "${STRIPPED_BINARY}"

/usr/bin/ditto "${MATCHING_DSYM}" "${EMPTY_DSYM}"
/bin/cp \
  "${STRIPPED_BINARY}" \
  "${EMPTY_DSYM}/Contents/Resources/DWARF/$(/usr/bin/basename "${UNSTRIPPED_BINARY}")"
assert_rejected_with \
  "Release dSYM has no DWARF debug info" \
  "${VERIFY_SCRIPT}" \
  --dsym "${EMPTY_DSYM}" \
  "${STRIPPED_BINARY}"

/usr/bin/clang -g -O0 -DFIXTURE_VALUE=7 -c "${SOURCE_PATH}" -o "${MISMATCHED_OBJECT}"
/usr/bin/clang "${MISMATCHED_OBJECT}" -o "${MISMATCHED_BINARY}"
/usr/bin/dsymutil "${MISMATCHED_BINARY}" -o "${MISMATCHED_DSYM}"
/usr/bin/strip -x "${MISMATCHED_BINARY}"

assert_rejected_with \
  "Release executable and dSYM UUIDs do not match." \
  "${VERIFY_SCRIPT}" \
  --dsym "${MISMATCHED_DSYM}" \
  "${STRIPPED_BINARY}"

echo "Release binary contract rejects local symbols and requires usable matching dSYM data."
