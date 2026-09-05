#!/usr/bin/env bash

FLOWTAB_PERF_FIXTURE_PREPARATION_STATUS="null"
FLOWTAB_PERF_FIXTURE_PREPARATION_LOG_STATUS="null"

flowtab_perf_prepare_space_fixture_workflows() {
  local build_script="$1"
  local child_ui_build_root="$2"
  local baseline_workflow_config="$3"
  local system_app_mru_workflow_config="$4"
  local test_filter="$5"
  local log_file="$6"
  local fixture_build_root="${child_ui_build_root}/space-fixture-workflow"
  local -a pipeline_status

  set +e
  (
    "$build_script" \
      --build-root "$fixture_build_root" \
      --workflow-config "$baseline_workflow_config" \
      --output-dir "${fixture_build_root}/variants" \
      --resolved-workflow-path \
        "${fixture_build_root}/variants/resolved-workflow.json" \
      || exit $?

    if [[ "$test_filter" == *testSystemAppMRU* ]]; then
      "$build_script" \
        --build-root "${fixture_build_root}/system-app-mru" \
        --workflow-config "$system_app_mru_workflow_config" \
        --output-dir \
          "${fixture_build_root}/system-app-mru-variants" \
        --resolved-workflow-path \
          "${fixture_build_root}/system-app-mru-variants/resolved-workflow.json" \
        || exit $?
    fi
  ) 2>&1 | tee "$log_file"
  pipeline_status=("${PIPESTATUS[@]}")
  set -e

  FLOWTAB_PERF_FIXTURE_PREPARATION_STATUS="${pipeline_status[0]}"
  FLOWTAB_PERF_FIXTURE_PREPARATION_LOG_STATUS="${pipeline_status[1]}"
  if [[ "$FLOWTAB_PERF_FIXTURE_PREPARATION_LOG_STATUS" -ne 0 ]]; then
    echo "Failed to preserve fixture preparation log: ${log_file}" >&2
    return 1
  fi
  if [[ "$FLOWTAB_PERF_FIXTURE_PREPARATION_STATUS" -ne 0 ]]; then
    echo "Fixture preparation failed before target launch observation." >&2
    return "$FLOWTAB_PERF_FIXTURE_PREPARATION_STATUS"
  fi
}
