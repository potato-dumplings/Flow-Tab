#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET_PATH="${ROOT_DIR}/scripts/perf/lib/runtime-topology-target.sh"
RUNNER_PATH="${ROOT_DIR}/scripts/perf/runtime-topology-pressure.sh"
START_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
START_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

source "$TARGET_PATH"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test_preexisting_identity_filter_is_exact() (
  PREEXISTING_TARGET_IDENTITIES="42:${START_A}:100"
  read_matching_identity_rows() {
    TARGET_MATCHING_IDENTITY_ROWS=(
      "42:${START_A}:100"
      "43:${START_B}:101"
    )
    TARGET_LAUNCH_READBACK_ERROR=""
    TARGET_LAUNCH_LAST_OBSERVATION="matchingIdentityCount=2"
  }
  local rows

  rows="$(post_request_identity_rows)"

  [[ "$rows" == "43:${START_B}:101" ]] \
    || fail "pre-request baseline filtering was not exact: $rows"
)

test_caller_uses_named_monotonic_contract() {
  local await_body
  local caller_body
  local contract_step
  local remainder

  /usr/bin/grep -F -q 'TARGET_LAUNCH_WATCHDOG_MILLISECONDS=45000' "$TARGET_PATH" \
    || fail "target-launch watchdog is not named"
  /usr/bin/grep -F -q 'TARGET_LAUNCH_POLL_INTERVAL_SECONDS=0.1' "$TARGET_PATH" \
    || fail "target-launch cadence is not named"
  await_body="$(
    /usr/bin/sed -n '/^await_target_launch()/,/^record_identity_binding()/p' "$TARGET_PATH" \
      | /usr/bin/sed '$d'
  )"
  if /usr/bin/grep -E -q \
    'attempt|450|^[[:space:]]*sleep[[:space:]]+0[.]1([[:space:]]|$)' \
    <<<"$await_body"; then
    fail "target launch still depends on attempts or an unnamed sleep"
  fi
  for contract_step in \
    'read_post_request_target_identities' \
    'target_launch_read_clock' \
    'TARGET_LAUNCH_WATCHDOG_MILLISECONDS' \
    'TARGET_STABILITY_WINDOW_MILLISECONDS' \
    'target_launch_sleep' \
    'publish_launch_receipt'; do
    [[ "$await_body" == *"$contract_step"* ]] \
      || fail "target-launch owner is missing: $contract_step"
  done

  caller_body="$(
    /usr/bin/sed -n \
      '/^capture_preexisting_target_identities$/,/^if ! await_target_launch/p' \
      "$RUNNER_PATH"
  )"
  remainder="$caller_body"
  for contract_step in \
    'capture_preexisting_target_identities' \
    'LAUNCH_REQUEST_MONOTONIC_NS="$(monotonic_ns)"' \
    'run_ui_test &' \
    'await_target_launch'; do
    [[ "$remainder" == *"$contract_step"* ]] \
      || fail "target-launch caller is missing or reorders: $contract_step"
    remainder="${remainder#*"$contract_step"}"
  done
}

test_preexisting_identity_filter_is_exact
test_caller_uses_named_monotonic_contract

echo "Runtime-topology target launch checks exact baseline and named caller evidence."
