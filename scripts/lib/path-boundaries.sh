#!/usr/bin/env bash

flowtab_require_release_version() {
  local version="${1-}"

  if [[ "${version}" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?([.-][A-Za-z0-9]+)*$ ]]; then
    printf '%s' "${version}"
    return 0
  fi

  echo "Unsupported release version: ${version:-<empty>}." >&2
  echo "Use a version such as v1.0, v1.2.3, or v1.2.3-beta.1." >&2
  return 64
}

flowtab_require_release_target() {
  local target="${1-}"

  case "${target}" in
    aarch64-apple-darwin|x86_64-apple-darwin|universal2-apple-darwin)
      printf '%s' "${target}"
      ;;
    *)
      echo "Unsupported release target: ${target:-<empty>}." >&2
      echo "Use aarch64-apple-darwin, x86_64-apple-darwin, or universal2-apple-darwin." >&2
      return 64
      ;;
  esac
}

flowtab_prepare_direct_child_directory() {
  local boundary="${1-}"
  local child_name="${2-}"
  local resolved_boundary=""
  local child_path=""
  local resolved_child=""

  child_path="$(flowtab_resolve_direct_child_path "${boundary}" "${child_name}")" || return
  resolved_boundary="$(cd "${boundary}" && pwd -P)"

  if [[ -L "${child_path}" ]]; then
    echo "Directory boundary must not be a symbolic link: ${child_path}" >&2
    return 1
  fi
  if [[ -e "${child_path}" && ! -d "${child_path}" ]]; then
    echo "Directory boundary is occupied by a non-directory: ${child_path}" >&2
    return 1
  fi

  /bin/mkdir -p "${child_path}"
  resolved_child="$(cd "${child_path}" && pwd -P)"
  if [[ "${resolved_child}" != "${resolved_boundary%/}/${child_name}" ]]; then
    echo "Directory resolved outside its declared resource boundary: ${child_path}" >&2
    return 1
  fi
  printf '%s' "${resolved_child}"
}

flowtab_resolve_direct_child_path() {
  local boundary="${1-}"
  local child_name="${2-}"
  local resolved_boundary=""
  local resolved_path=""

  if [[ -z "${boundary}" || -z "${child_name}" ]]; then
    echo "A non-empty resource boundary and child name are required." >&2
    return 64
  fi
  if [[ "${child_name}" == "." || "${child_name}" == ".." || "${child_name}" == */* ]]; then
    echo "Unsafe child path intent: ${child_name}" >&2
    return 64
  fi
  if [[ ! -d "${boundary}" ]]; then
    echo "Resource boundary does not exist: ${boundary}" >&2
    return 66
  fi

  resolved_boundary="$(cd "${boundary}" && pwd -P)"
  resolved_path="${resolved_boundary%/}/${child_name}"
  if [[ -L "${resolved_path}" ]]; then
    echo "Direct child path must not be a symbolic link: ${resolved_path}" >&2
    return 1
  fi
  printf '%s' "${resolved_path}"
}

flowtab_resolve_ui_test_install_path() {
  local user_home="${1-}"
  local path_intent="${2-}"
  local normalized_home=""

  if [[ -z "${user_home}" || "${user_home}" != /* || "${user_home}" == "/" ]]; then
    echo "A non-root absolute user-home boundary is required." >&2
    return 64
  fi

  normalized_home="${user_home%/}"
  if [[ "${path_intent}" == "~/"* ]]; then
    path_intent="${normalized_home}/${path_intent:2}"
  fi

  case "${path_intent}" in
    "${normalized_home}/Applications/Flow Tab UITest.app"|\
    "${normalized_home}/Applications/Flow Tab.app"|\
    "/Applications/Flow Tab UITest.app"|\
    "/Applications/Flow Tab.app")
      printf '%s' "${path_intent}"
      ;;
    *)
      echo "Unsupported UI test app install path: ${path_intent:-<empty>}." >&2
      echo "Use a Flow Tab app name directly inside the user or system Applications boundary." >&2
      return 64
      ;;
  esac
}
