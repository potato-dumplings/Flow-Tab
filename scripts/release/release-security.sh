#!/usr/bin/env bash

flowtab_extract_team_id_from_identity() {
  local identity="${1-}"

  if [[ "${identity}" =~ \(([A-Z0-9]{10})\)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  echo "Could not extract a Team ID from the signing identity." >&2
  return 1
}

flowtab_require_team_id() {
  local team_id="${1-}"

  if [[ "${team_id}" =~ ^[A-Z0-9]{10}$ ]]; then
    printf '%s' "${team_id}"
    return 0
  fi

  echo "Expected Team ID must contain exactly 10 uppercase letters or digits." >&2
  return 64
}

flowtab_require_developer_id_signature_details() {
  local details="${1-}"
  local expected_team_id="${2-}"
  local label="${3:-code object}"

  flowtab_require_team_id "${expected_team_id}" >/dev/null || return
  if ! /usr/bin/grep -F -q "Authority=Developer ID Application:" <<< "${details}"; then
    echo "${label} is not signed by a Developer ID Application identity." >&2
    return 1
  fi
  if ! /usr/bin/grep -F -x -q "TeamIdentifier=${expected_team_id}" <<< "${details}"; then
    echo "${label} Team ID does not match the expected release identity." >&2
    return 1
  fi
  if ! /usr/bin/grep -F "Authority=Developer ID Application:" <<< "${details}" \
    | /usr/bin/grep -F -q "(${expected_team_id})"; then
    echo "${label} Developer ID authority does not contain the expected Team ID." >&2
    return 1
  fi
}

flowtab_require_codesign_identifier() {
  local details="${1-}"
  local expected_identifier="${2-}"
  local label="${3:-app bundle}"

  if ! /usr/bin/grep -F -x -q "Identifier=${expected_identifier}" <<< "${details}"; then
    echo "${label} signing identifier does not match ${expected_identifier}." >&2
    return 1
  fi
}

flowtab_require_bundle_identifier_format() {
  local bundle_id="${1-}"

  if [[ "${bundle_id}" =~ ^[A-Za-z0-9]+([.-][A-Za-z0-9]+)+$ ]]; then
    printf '%s' "${bundle_id}"
    return 0
  fi

  echo "Expected bundle identifier has an unsupported format." >&2
  return 64
}

flowtab_set_bundle_identifier() {
  local bundle_path="${1-}"
  local bundle_id="${2-}"
  local info_plist="${bundle_path}/Contents/Info.plist"

  flowtab_require_bundle_identifier_format "${bundle_id}" >/dev/null || return
  if [[ ! -f "${info_plist}" ]]; then
    echo "Bundle Info.plist not found: ${info_plist}" >&2
    return 66
  fi

  if /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${bundle_id}" "${info_plist}"
  else
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${bundle_id}" "${info_plist}"
  fi
}

flowtab_require_bundle_metadata() {
  local bundle_path="${1-}"
  local expected_bundle_id="${2-}"
  local expected_executable="${3-}"
  local info_plist="${bundle_path}/Contents/Info.plist"
  local actual_bundle_id=""
  local actual_executable=""

  flowtab_require_bundle_identifier_format "${expected_bundle_id}" >/dev/null || return
  if [[ -z "${expected_executable}" || "${expected_executable}" == "." \
    || "${expected_executable}" == ".." || "${expected_executable}" == */* ]]; then
    echo "Expected executable must be a direct child name." >&2
    return 64
  fi

  if [[ ! -f "${info_plist}" ]]; then
    echo "Bundle Info.plist not found: ${info_plist}" >&2
    return 66
  fi

  actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}")"
  actual_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${info_plist}")"

  if [[ "${actual_bundle_id}" != "${expected_bundle_id}" ]]; then
    echo "Bundle identifier mismatch for ${bundle_path}." >&2
    return 1
  fi
  if [[ "${actual_executable}" != "${expected_executable}" ]]; then
    echo "Bundle executable mismatch for ${bundle_path}." >&2
    return 1
  fi
  if [[ ! -f "${bundle_path}/Contents/MacOS/${expected_executable}" ]]; then
    echo "Expected bundle executable not found: ${bundle_path}/Contents/MacOS/${expected_executable}" >&2
    return 66
  fi
}

flowtab_plist_digest() {
  local plist_path="${1-}"

  /usr/bin/python3 -c '
import hashlib
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    value = plistlib.load(stream)
canonical = plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=True)
print(hashlib.sha256(canonical).hexdigest())
' "${plist_path}"
}

flowtab_require_matching_plists() {
  local expected_path="${1-}"
  local actual_path="${2-}"
  local label="${3:-property list}"

  if [[ ! -f "${expected_path}" || ! -f "${actual_path}" ]]; then
    echo "${label} comparison requires two property-list files." >&2
    return 66
  fi
  if [[ "$(flowtab_plist_digest "${expected_path}")" != "$(flowtab_plist_digest "${actual_path}")" ]]; then
    echo "${label} does not match the expected release contract." >&2
    return 1
  fi
}

flowtab_bundle_tree_digest() {
  local bundle_path="${1-}"

  /usr/bin/python3 -c '
import hashlib
import os
import stat
import sys

root = os.path.realpath(sys.argv[1])
if not os.path.isdir(root):
    raise SystemExit(f"Bundle tree not found: {sys.argv[1]}")

digest = hashlib.sha256()
for directory, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
    directory_names.sort()
    file_names.sort()
    for name in directory_names + file_names:
        path = os.path.join(directory, name)
        relative = os.path.relpath(path, root).encode("utf-8", "surrogateescape")
        metadata = os.lstat(path)
        mode = stat.S_IMODE(metadata.st_mode)
        if stat.S_ISLNK(metadata.st_mode):
            kind = b"link"
        elif stat.S_ISDIR(metadata.st_mode):
            kind = b"directory"
        elif stat.S_ISREG(metadata.st_mode):
            kind = b"file"
        else:
            raise SystemExit(f"Unsupported bundle entry: {relative!r}")
        digest.update(kind + b"\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
        if kind == b"link":
            digest.update(os.readlink(path).encode("utf-8", "surrogateescape") + b"\0")
        elif kind == b"file":
            with open(path, "rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest.update(b"\0")
print(digest.hexdigest())
' "${bundle_path}"
}

flowtab_require_distribution_layout() {
  local mount_root="${1-}"
  shift

  /usr/bin/python3 -c '
import os
import sys

root = sys.argv[1]
expected = set(sys.argv[2:]) | {"Applications"}
actual = set(os.listdir(root))
if actual != expected:
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    raise SystemExit(f"DMG layout mismatch; missing={missing}, unexpected={unexpected}")
applications = os.path.join(root, "Applications")
if not os.path.islink(applications) or os.readlink(applications) != "/Applications":
    raise SystemExit("DMG Applications entry must be a symbolic link to /Applications")
' "${mount_root}" "$@"
}
