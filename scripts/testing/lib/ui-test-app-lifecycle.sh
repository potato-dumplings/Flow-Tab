#!/usr/bin/env bash

FLOWTAB_UI_TEST_APP_LIFECYCLE_SCHEMA_VERSION=1
FLOWTAB_UI_TEST_APP_BUNDLE_IDENTIFIER="io.github.potato-dumplings.flowtab"
FLOWTAB_UI_TEST_APP_BUNDLE_NAME="Flow Tab UITest.app"

flowtab_ui_test_app_resolve_dedicated_path() {
  local user_home_boundary="${1-}"
  local path_intent="${2-}"
  local resolved_path=""

  resolved_path="$(
    flowtab_resolve_ui_test_install_path \
      "${user_home_boundary}" \
      "${path_intent}"
  )" || return
  if [[ "$(/usr/bin/basename "${resolved_path}")" != "${FLOWTAB_UI_TEST_APP_BUNDLE_NAME}" ]]; then
    echo "The managed UI-test lifecycle only accepts ${FLOWTAB_UI_TEST_APP_BUNDLE_NAME}: ${resolved_path}" >&2
    return 64
  fi
  printf '%s' "${resolved_path}"
}

flowtab_ui_test_app_is_dedicated_path() {
  flowtab_ui_test_app_resolve_dedicated_path "${1-}" "${2-}" >/dev/null 2>&1
}

flowtab_ui_test_app_describe_path() {
  local user_home_boundary="${1-}"
  local app_path="${2-}"
  local declared_app_path=""
  local applications_boundary=""
  local resolved_user_home=""
  local resolved_applications_boundary=""
  local resolved_app_path=""

  resolved_user_home="$(cd "${user_home_boundary}" && pwd -P)" || return
  declared_app_path="$(
    flowtab_ui_test_app_resolve_dedicated_path \
      "${user_home_boundary}" \
      "${app_path}"
  )" || return

  case "${declared_app_path}" in
    "${user_home_boundary%/}/Applications/${FLOWTAB_UI_TEST_APP_BUNDLE_NAME}")
      FLOWTAB_UI_TEST_APP_RESOURCE_BOUNDARY="user_home"
      applications_boundary="${user_home_boundary%/}/Applications"
      ;;
    "/Applications/${FLOWTAB_UI_TEST_APP_BUNDLE_NAME}")
      FLOWTAB_UI_TEST_APP_RESOURCE_BOUNDARY="system_root"
      applications_boundary="/Applications"
      ;;
    *)
      echo "Unsupported managed UI-test app path: ${declared_app_path}" >&2
      return 64
      ;;
  esac
  if [[ -L "${applications_boundary}" || ! -d "${applications_boundary}" ]]; then
    echo "Managed UI-test Applications boundary is unavailable: ${applications_boundary}" >&2
    return 66
  fi
  resolved_applications_boundary="$(cd "${applications_boundary}" && pwd -P)" || return
  if [[ "${FLOWTAB_UI_TEST_APP_RESOURCE_BOUNDARY}" == "user_home" \
    && "${resolved_applications_boundary}" != "${resolved_user_home%/}/Applications" ]]
  then
    echo "Managed UI-test Applications boundary resolved outside the user home: ${applications_boundary}" >&2
    return 65
  fi
  resolved_app_path="${resolved_applications_boundary%/}/${FLOWTAB_UI_TEST_APP_BUNDLE_NAME}"
  FLOWTAB_UI_TEST_APP_RELATIVE_PATH_INTENT="Applications/${FLOWTAB_UI_TEST_APP_BUNDLE_NAME}"
  FLOWTAB_UI_TEST_APP_RESOLVED_PATH="${resolved_app_path}"
}

flowtab_ui_test_app_lifecycle_paths() {
  local repository_root="${1-}"
  local app_path="${2-}"
  local resolved_repository_root=""
  local build_local_root=""
  local lifecycle_key=""

  resolved_repository_root="$(cd "${repository_root}" && pwd -P)" || return
  build_local_root="$(
    flowtab_prepare_direct_child_directory \
      "${resolved_repository_root}" \
      ".build-local"
  )" || return
  FLOWTAB_UI_TEST_APP_LIFECYCLE_ROOT="$(
    flowtab_prepare_direct_child_directory \
      "${build_local_root}" \
      "ui-test-app-lifecycle"
  )" || return
  lifecycle_key="$(
    printf '%s' "${app_path}" \
      | LC_ALL=C /usr/bin/shasum -a 256 \
      | /usr/bin/awk '{print $1}'
  )" || return
  FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH="${FLOWTAB_UI_TEST_APP_LIFECYCLE_ROOT}/${lifecycle_key}.ready.plist"
  FLOWTAB_UI_TEST_APP_CLAIM_DIRECTORY="${FLOWTAB_UI_TEST_APP_LIFECYCLE_ROOT}/${lifecycle_key}.claim"
  FLOWTAB_UI_TEST_APP_CLAIM_RECEIPT_PATH="${FLOWTAB_UI_TEST_APP_CLAIM_DIRECTORY}/receipt.plist"
}

flowtab_ui_test_app_read_metadata() {
  local app_path="${1-}"
  local info_plist="${app_path}/Contents/Info.plist"
  local executable_name=""
  local executable_path=""
  local codesign_readback=""

  if [[ -L "${app_path}" || ! -d "${app_path}" ]]; then
    echo "Managed UI-test app is missing or is a symbolic link: ${app_path}" >&2
    return 66
  fi
  if [[ ! -f "${info_plist}" ]]; then
    echo "Managed UI-test app Info.plist is missing: ${info_plist}" >&2
    return 66
  fi

  FLOWTAB_UI_TEST_APP_ACTUAL_BUNDLE_IDENTIFIER="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}"
  )" || return
  if [[ "${FLOWTAB_UI_TEST_APP_ACTUAL_BUNDLE_IDENTIFIER}" != "${FLOWTAB_UI_TEST_APP_BUNDLE_IDENTIFIER}" ]]; then
    echo "Managed UI-test app has an unexpected bundle identifier: ${FLOWTAB_UI_TEST_APP_ACTUAL_BUNDLE_IDENTIFIER}" >&2
    return 65
  fi

  executable_name="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${info_plist}"
  )" || return
  executable_path="${app_path}/Contents/MacOS/${executable_name}"
  if [[ ! -x "${executable_path}" ]]; then
    echo "Managed UI-test app executable is missing: ${executable_path}" >&2
    return 66
  fi
  FLOWTAB_UI_TEST_APP_EXECUTABLE_SHA256="$(
    LC_ALL=C /usr/bin/shasum -a 256 "${executable_path}" \
      | /usr/bin/awk '{print $1}'
  )" || return

  /usr/bin/codesign --verify --deep --strict "${app_path}" || return
  codesign_readback="$(/usr/bin/codesign -d --verbose=4 "${app_path}" 2>&1)" || return
  FLOWTAB_UI_TEST_APP_CODE_DIRECTORY_HASH="$(
    printf '%s\n' "${codesign_readback}" \
      | /usr/bin/sed -n 's/^CDHash=//p' \
      | /usr/bin/head -n 1
  )"
  if [[ -z "${FLOWTAB_UI_TEST_APP_CODE_DIRECTORY_HASH}" ]]; then
    echo "Managed UI-test app has no Code Directory identity: ${app_path}" >&2
    return 65
  fi
}

flowtab_ui_test_app_reset_lifecycle() {
  local repository_root="${1-}"
  local user_home_boundary="${2-}"
  local app_path="${3-}"

  flowtab_ui_test_app_describe_path "${user_home_boundary}" "${app_path}" || return
  flowtab_ui_test_app_lifecycle_paths "${repository_root}" "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}" || return
  /bin/mkdir -p "${FLOWTAB_UI_TEST_APP_LIFECYCLE_ROOT}"
  /bin/rm -f "${FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH}"
  /bin/rm -rf "${FLOWTAB_UI_TEST_APP_CLAIM_DIRECTORY}"
}

flowtab_ui_test_app_issue_receipt() {
  local repository_root="${1-}"
  local user_home_boundary="${2-}"
  local app_path="${3-}"
  local source_commit=""
  local receipt_temp=""

  flowtab_ui_test_app_describe_path "${user_home_boundary}" "${app_path}" || return
  flowtab_ui_test_app_lifecycle_paths "${repository_root}" "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}" || return
  flowtab_ui_test_app_read_metadata "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}" || return
  source_commit="$(git -C "${repository_root}" rev-parse HEAD)" || return

  /bin/mkdir -p "${FLOWTAB_UI_TEST_APP_LIFECYCLE_ROOT}"
  /bin/rm -f "${FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH}"
  /bin/rm -rf "${FLOWTAB_UI_TEST_APP_CLAIM_DIRECTORY}"
  receipt_temp="$(/usr/bin/mktemp "${FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH}.tmp.XXXXXX")" || return
  if ! {
    /usr/bin/plutil -create xml1 "${receipt_temp}"
    /usr/bin/plutil -insert schema_version -integer "${FLOWTAB_UI_TEST_APP_LIFECYCLE_SCHEMA_VERSION}" "${receipt_temp}"
    /usr/bin/plutil -insert resource_boundary -string "${FLOWTAB_UI_TEST_APP_RESOURCE_BOUNDARY}" "${receipt_temp}"
    /usr/bin/plutil -insert relative_path_intent -string "${FLOWTAB_UI_TEST_APP_RELATIVE_PATH_INTENT}" "${receipt_temp}"
    /usr/bin/plutil -insert bundle_identifier -string "${FLOWTAB_UI_TEST_APP_ACTUAL_BUNDLE_IDENTIFIER}" "${receipt_temp}"
    /usr/bin/plutil -insert executable_sha256 -string "${FLOWTAB_UI_TEST_APP_EXECUTABLE_SHA256}" "${receipt_temp}"
    /usr/bin/plutil -insert code_directory_hash -string "${FLOWTAB_UI_TEST_APP_CODE_DIRECTORY_HASH}" "${receipt_temp}"
    /usr/bin/plutil -insert source_commit -string "${source_commit}" "${receipt_temp}"
    /bin/chmod 600 "${receipt_temp}"
  }; then
    /bin/rm -f "${receipt_temp}"
    return 1
  fi
  /bin/mv "${receipt_temp}" "${FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH}"
}

flowtab_ui_test_app_receipt_value() {
  local receipt_path="${1-}"
  local key="${2-}"

  /usr/bin/plutil -extract "${key}" raw -o - "${receipt_path}"
}

flowtab_ui_test_app_validate_receipt() {
  local repository_root="${1-}"
  local user_home_boundary="${2-}"
  local app_path="${3-}"
  local receipt_path="${4-}"
  local expected_source_commit=""

  if [[ ! -f "${receipt_path}" ]]; then
    echo "UI-test app lifecycle receipt is missing: ${receipt_path}" >&2
    return 66
  fi
  flowtab_ui_test_app_describe_path "${user_home_boundary}" "${app_path}" || return
  flowtab_ui_test_app_read_metadata "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}" || return
  expected_source_commit="$(git -C "${repository_root}" rev-parse HEAD)" || return

  [[ "$(flowtab_ui_test_app_receipt_value "${receipt_path}" schema_version)" == "${FLOWTAB_UI_TEST_APP_LIFECYCLE_SCHEMA_VERSION}" ]] \
    || { echo "UI-test app lifecycle receipt has an unsupported schema." >&2; return 65; }
  [[ "$(flowtab_ui_test_app_receipt_value "${receipt_path}" resource_boundary)" == "${FLOWTAB_UI_TEST_APP_RESOURCE_BOUNDARY}" ]] \
    || { echo "UI-test app lifecycle receipt has a different resource boundary." >&2; return 65; }
  [[ "$(flowtab_ui_test_app_receipt_value "${receipt_path}" relative_path_intent)" == "${FLOWTAB_UI_TEST_APP_RELATIVE_PATH_INTENT}" ]] \
    || { echo "UI-test app lifecycle receipt has a different path intent." >&2; return 65; }
  [[ "$(flowtab_ui_test_app_receipt_value "${receipt_path}" bundle_identifier)" == "${FLOWTAB_UI_TEST_APP_ACTUAL_BUNDLE_IDENTIFIER}" ]] \
    || { echo "UI-test app lifecycle receipt has a different bundle identifier." >&2; return 65; }
  [[ "$(flowtab_ui_test_app_receipt_value "${receipt_path}" executable_sha256)" == "${FLOWTAB_UI_TEST_APP_EXECUTABLE_SHA256}" ]] \
    || { echo "UI-test app lifecycle receipt does not match the installed executable." >&2; return 65; }
  [[ "$(flowtab_ui_test_app_receipt_value "${receipt_path}" code_directory_hash)" == "${FLOWTAB_UI_TEST_APP_CODE_DIRECTORY_HASH}" ]] \
    || { echo "UI-test app lifecycle receipt does not match the installed code identity." >&2; return 65; }
  [[ "$(flowtab_ui_test_app_receipt_value "${receipt_path}" source_commit)" == "${expected_source_commit}" ]] \
    || { echo "UI-test app lifecycle receipt belongs to a different source commit." >&2; return 65; }
}

flowtab_ui_test_app_validate_ready_receipt() {
  local repository_root="${1-}"
  local user_home_boundary="${2-}"
  local app_path="${3-}"

  flowtab_ui_test_app_describe_path "${user_home_boundary}" "${app_path}" || return
  flowtab_ui_test_app_lifecycle_paths "${repository_root}" "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}" || return
  flowtab_ui_test_app_validate_receipt \
    "${repository_root}" \
    "${user_home_boundary}" \
    "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}" \
    "${FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH}"
}

flowtab_ui_test_app_claim() {
  local repository_root="${1-}"
  local user_home_boundary="${2-}"
  local app_path="${3-}"

  flowtab_ui_test_app_describe_path "${user_home_boundary}" "${app_path}" || return
  flowtab_ui_test_app_lifecycle_paths "${repository_root}" "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}" || return
  if ! /bin/mkdir "${FLOWTAB_UI_TEST_APP_CLAIM_DIRECTORY}" 2>/dev/null; then
    echo "UI-test app lifecycle is already claimed; reinstall the fixed-path app before another run." >&2
    return 73
  fi
  if ! /bin/mv "${FLOWTAB_UI_TEST_APP_READY_RECEIPT_PATH}" "${FLOWTAB_UI_TEST_APP_CLAIM_RECEIPT_PATH}" 2>/dev/null; then
    echo "A fresh UI-test app receipt is required. Run ./scripts/testing/install-ui-test-app.sh first." >&2
    return 66
  fi
  flowtab_ui_test_app_validate_receipt \
    "${repository_root}" \
    "${user_home_boundary}" \
    "${FLOWTAB_UI_TEST_APP_RESOLVED_PATH}" \
    "${FLOWTAB_UI_TEST_APP_CLAIM_RECEIPT_PATH}"
}

flowtab_ui_test_app_remove_managed_bundle() {
  local repository_root="${1-}"
  local user_home_boundary="${2-}"
  local app_path="${3-}"
  local applications_boundary=""
  local resolved_remove_path=""

  flowtab_ui_test_app_describe_path "${user_home_boundary}" "${app_path}" || return
  if [[ "${FLOWTAB_UI_TEST_APP_RESOURCE_BOUNDARY}" == "user_home" ]]; then
    applications_boundary="${user_home_boundary%/}/Applications"
  else
    applications_boundary="/Applications"
  fi
  if [[ -L "${applications_boundary}" || ! -d "${applications_boundary}" ]]; then
    echo "Managed UI-test Applications boundary is unavailable: ${applications_boundary}" >&2
    return 66
  fi
  resolved_remove_path="$(
    flowtab_resolve_direct_child_path \
      "${applications_boundary}" \
      "${FLOWTAB_UI_TEST_APP_BUNDLE_NAME}"
  )" || return
  if [[ -e "${resolved_remove_path}" ]]; then
    /bin/rm -rf "${resolved_remove_path}"
  fi
  flowtab_ui_test_app_reset_lifecycle \
    "${repository_root}" \
    "${user_home_boundary}" \
    "${resolved_remove_path}"
  [[ ! -e "${resolved_remove_path}" ]]
}
