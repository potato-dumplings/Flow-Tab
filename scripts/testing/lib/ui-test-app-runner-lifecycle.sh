#!/usr/bin/env bash

flowtab_configure_ui_test_app_lifecycle() {
  local lifecycle_status=0

  if [[ "${USE_STABLE_UI_TEST_APP}" != true ]]; then
    unset FLOWTAB_UI_TEST_APP_PATH || true
    return 0
  fi

  if flowtab_ui_test_app_is_dedicated_path "${ORIGINAL_HOME}" "${UI_TEST_APP_PATH}"; then
    flowtab_ui_test_app_describe_path "${ORIGINAL_HOME}" "${UI_TEST_APP_PATH}"
    UI_TEST_APP_PATH="${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}"
    export FLOWTAB_UI_TEST_APP_PATH="${UI_TEST_APP_PATH}"

    if [[ "${ACTION}" == "build-for-testing" ]]; then
      CURRENT_STAGE="validate_ui_test_app_lifecycle"
      if flowtab_ui_test_app_validate_ready_receipt \
        "${ROOT_DIR}" \
        "${ORIGINAL_HOME}" \
        "${UI_TEST_APP_PATH}"
      then
        UI_TEST_APP_LIFECYCLE_STATUS="ready"
        return 0
      else
        lifecycle_status=$?
        UI_TEST_APP_LIFECYCLE_STATUS="validation_failed"
        CURRENT_STAGE="ui_test_app_lifecycle_validation_failed"
        return "${lifecycle_status}"
      fi
    fi

    UI_TEST_APP_CLEANUP_REQUIRED=true
    UI_TEST_APP_REMOVED=false
    CURRENT_STAGE="claim_ui_test_app_lifecycle"
    if flowtab_ui_test_app_claim \
      "${ROOT_DIR}" \
      "${ORIGINAL_HOME}" \
      "${UI_TEST_APP_PATH}"
    then
      UI_TEST_APP_LIFECYCLE_STATUS="claimed"
      return 0
    else
      lifecycle_status=$?
      UI_TEST_APP_LIFECYCLE_STATUS="claim_failed"
      CURRENT_STAGE="ui_test_app_lifecycle_claim_failed"
      return "${lifecycle_status}"
    fi
  fi

  if [[ ! -d "${UI_TEST_APP_PATH}" ]]; then
    echo "Fixed-path UI test app is missing: ${UI_TEST_APP_PATH}" >&2
    echo "Install it first or pass --no-ui-test-app for an explicit DerivedData run." >&2
    CURRENT_STAGE="ui_test_app_missing"
    return 66
  fi
  export FLOWTAB_UI_TEST_APP_PATH="${UI_TEST_APP_PATH}"
  UI_TEST_APP_LIFECYCLE_STATUS="unmanaged_explicit_path"
}

flowtab_cleanup_managed_ui_test_app() {
  local baseline_path="${OUTPUT_ROOT}/ui-test-app-lifecycle-baseline.json"
  local evidence_path="${OUTPUT_ROOT}/ui-test-app-lifecycle-cleanup.json"
  local cleanup_log_path="${LOG_ROOT}/ui-test-app-cleanup.log"

  if ! printf '%s\n' \
    '{"schemaVersion":1,"bundleIdentifiers":[],"capturedApplications":[]}' \
    >"${baseline_path}"
  then
    echo "Could not create the UI-test app cleanup baseline: ${baseline_path}" >&2
    return 1
  fi

  if ! /usr/bin/osascript -l JavaScript \
    "${APPLICATION_LIFECYCLE_TOOL}" \
    terminate \
    "${baseline_path}" \
    "${evidence_path}" \
    "${FLOWTAB_UI_TEST_APP_BUNDLE_IDENTIFIER}" \
    "${UI_TEST_APP_PATH}" \
    >"${cleanup_log_path}" 2>&1
  then
    echo "Could not terminate the exact UI-test application identity." >>"${cleanup_log_path}"
    return 1
  fi

  if ! /usr/bin/osascript -l JavaScript \
    "${APPLICATION_PROCESS_CLEANUP_TOOL}" \
    cleanup \
    "${evidence_path}" \
    >>"${cleanup_log_path}" 2>&1
  then
    echo "Could not verify exact UI-test application process absence." >>"${cleanup_log_path}"
    return 1
  fi

  if ! flowtab_ui_test_app_remove_managed_bundle \
    "${ROOT_DIR}" \
    "${ORIGINAL_HOME}" \
    "${UI_TEST_APP_PATH}" \
    >>"${cleanup_log_path}" 2>&1
  then
    echo "Could not remove the managed UI-test app bundle." >>"${cleanup_log_path}"
    return 1
  fi

  UI_TEST_APP_REMOVED=true
  echo "Managed UI test app removed: ${UI_TEST_APP_PATH}"
}
