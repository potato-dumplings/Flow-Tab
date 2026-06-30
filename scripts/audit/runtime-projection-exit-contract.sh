#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

failures=0

check_no_matches() {
  local label="$1"
  local pattern="$2"
  shift 2

  echo "== $label"
  if rg -n "$pattern" "$@"; then
    echo "FAIL: unexpected legacy/prohibited boundary match"
    failures=$((failures + 1))
  else
    local status=$?
    if [[ "$status" -eq 1 ]]; then
      echo "PASS: no matches"
    else
      echo "FAIL: rg failed with status $status"
      failures=$((failures + 1))
    fi
  fi
}

check_has_matches() {
  local label="$1"
  local pattern="$2"
  shift 2

  echo "== $label"
  if rg -n "$pattern" "$@"; then
    echo "PASS: required boundary evidence present"
  else
    local status=$?
    if [[ "$status" -eq 1 ]]; then
      echo "FAIL: required boundary evidence missing"
    else
      echo "FAIL: rg failed with status $status"
    fi
    failures=$((failures + 1))
  fi
}

surface_paths=(
  FlowTab/Features/Switcher
  FlowTab/Features/Home
)

production_paths=(
  FlowTab/App
  FlowTab/Features
  FlowTab/Infrastructure/Runtime
  FlowTabCore
)

activation_paths=(
  FlowTab/Infrastructure/Runtime/RuntimeActivator.swift
  FlowTab/Infrastructure/Runtime/RuntimeWindowFocusRequest.swift
  FlowTab/Infrastructure/Runtime/RuntimeProjectionService.swift
  FlowTab/Infrastructure/Runtime/RuntimeProjectionServing.swift
  FlowTab/Infrastructure/Runtime/RuntimeWindowRecordStore.swift
)

check_no_matches \
  "surface hot paths do not reference legacy snapshot, repair provider, or direct CG/AX sampling APIs" \
  "RuntimeSnapshotProvider|RuntimeSnapshot\\(|snapshotQueue|collectAXWindowData|RuntimeSystemRepairFactProvider|RuntimeProjectionRepairProvider|fullRepairEvidence|commitSearchFreshnessBarrier|readCommittedSearchIndexProjection|CGWindowListCopyWindowInfo|AXUIElementCreateApplication" \
  "${surface_paths[@]}"

check_no_matches \
  "production code has no removed Search projection-cache bridge or provider-facing full-repair payload API" \
  "commitSearchFreshnessBarrierFromProjectionCache|readCommittedSearchIndexProjection|RuntimeFullRepairProjectionPayload|fullRepairProjectionPayload" \
  "${production_paths[@]}"

check_has_matches \
  "Switcher reads projection/search APIs and sends bounded Search freshness barrier requests" \
  "readAppSwitcherProjection|readCurrentAppWindowProjection|readCommittedSearchIndexForSearch|requestSearchIndexFreshnessBarrier" \
  FlowTab/Features/Switcher FlowTab/Infrastructure/Runtime/RuntimeProjectionServing.swift

check_has_matches \
  "Home reads runtime projection APIs and signals dirty app-window scope" \
  "readHomeSummaryProjection|readHomeAppDetailProjection|readCurrentAppWindowProjection|signalAppWindowsChanged" \
  FlowTab/Features/Home FlowTab/Infrastructure/Runtime/RuntimeProjectionServing.swift

check_has_matches \
  "Search freshness commits only from main-table payload in production runtime" \
  "searchIndexPayloadFromMainTables|commitSearchFreshnessBarrierFromMainTablePayload" \
  FlowTab/Infrastructure/Runtime/RuntimeProjectionService.swift FlowTab/Infrastructure/Runtime/RuntimeReadModelStore.swift

check_no_matches \
  "production activation paths do not use direct Space setting or Window-menu shortcuts as success oracles" \
  "ManagedDisplaySetCurrentSpace|SLSSetCurrentSpace|CGSSetCurrentSpace|SetCurrentSpace|kAXMenu(Item|Bar)?Attribute|kAXPressAction" \
  "${production_paths[@]}"

check_has_matches \
  "activation verifies selected-window success through focused AX/CG or frontmost CG readback" \
  "verifyFocusAttempt|targetCGWindowHasActivationReadback|focusedAXWindowCGWindowID|frontmostVisibleCGWindowID|reportBindingReadbackMismatch" \
  FlowTab/Infrastructure/Runtime/RuntimeActivator.swift FlowTab/Infrastructure/Runtime/RuntimeWindowFocusRequest.swift

check_has_matches \
  "verified activation readback is committed into WindowRecord and runtime projection state" \
  "recordWindowFocusVerification|verifiedFocusReadback|signalWindowFocusVerified|readActivationTargetProjection" \
  "${activation_paths[@]}"

if [[ "$failures" -ne 0 ]]; then
  echo "Runtime projection exit-contract audit failed: $failures check(s)"
  exit 1
fi

echo "Runtime projection exit-contract audit passed"
