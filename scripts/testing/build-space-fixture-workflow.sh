#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/.build-local/space-fixture-workflow"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
TMP_ROOT="${BUILD_ROOT}/tmp"
HOME_ROOT="${BUILD_ROOT}/home"
MODULE_CACHE_ROOT="${BUILD_ROOT}/module-cache"
PACKAGE_CACHE_PATH="${BUILD_ROOT}/source-packages"

WORKFLOW_CONFIG=""
CONFIGURATION="Debug"
OUTPUT_DIR="${BUILD_ROOT}/variants"
RESOLVED_WORKFLOW_PATH=""

print_help() {
  cat <<'EOF'
Usage:
  ./scripts/testing/build-space-fixture-workflow.sh \
    --workflow-config /absolute/path/to/workflow.json \
    [--configuration Debug|Release] \
    [--output-dir /custom/output/dir] \
    [--resolved-workflow-path /custom/output/resolved-workflow.json]

Builds the FlowTabSpaceFixture template app once, then generates one fixture app
bundle variant per app declared in the workflow configuration. The script also
emits a resolved workflow JSON file with each generated app's absolute appPath.
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

sanitize_app_bundle_name() {
  local value="$1"
  printf '%s' "$value" | sed 's#[/:]#-#g'
}

set_plist_string() {
  local plist_path="$1"
  local key="$2"
  local value="$3"

  if ! /usr/bin/plutil -replace "$key" -string "$value" "$plist_path" >/dev/null 2>&1; then
    /usr/bin/plutil -insert "$key" -string "$value" "$plist_path" >/dev/null
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow-config)
      WORKFLOW_CONFIG="${2-}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2-}"
      shift 2
      ;;
    --resolved-workflow-path)
      RESOLVED_WORKFLOW_PATH="${2-}"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_help >&2
      exit 1
      ;;
  esac
done

WORKFLOW_CONFIG="$(trim "$WORKFLOW_CONFIG")"
if [[ -z "$WORKFLOW_CONFIG" ]]; then
  echo "--workflow-config is required." >&2
  print_help >&2
  exit 1
fi

if [[ ! -f "$WORKFLOW_CONFIG" ]]; then
  echo "Workflow configuration file not found: ${WORKFLOW_CONFIG}" >&2
  exit 1
fi

if [[ "$CONFIGURATION" != "Debug" && "$CONFIGURATION" != "Release" ]]; then
  echo "Unsupported configuration: ${CONFIGURATION}. Use Debug or Release." >&2
  exit 1
fi

mkdir -p \
  "${DERIVED_DATA_PATH}" \
  "${TMP_ROOT}" \
  "${HOME_ROOT}" \
  "${MODULE_CACHE_ROOT}/clang" \
  "${MODULE_CACHE_ROOT}/swift" \
  "${PACKAGE_CACHE_PATH}" \
  "${OUTPUT_DIR}"

OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"
if [[ -z "${RESOLVED_WORKFLOW_PATH}" ]]; then
  RESOLVED_WORKFLOW_PATH="${OUTPUT_DIR}/resolved-workflow.json"
fi
mkdir -p "$(dirname "${RESOLVED_WORKFLOW_PATH}")"
RESOLVED_WORKFLOW_PATH="$(cd "$(dirname "${RESOLVED_WORKFLOW_PATH}")" && pwd)/$(basename "${RESOLVED_WORKFLOW_PATH}")"

export TMPDIR="${TMP_ROOT}/"
export HOME="${HOME_ROOT}"
export CFFIXED_USER_HOME="${HOME_ROOT}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}/clang"
export SWIFT_MODULECACHE_PATH="${MODULE_CACHE_ROOT}/swift"
export SWIFTPM_PACKAGECACHE="${PACKAGE_CACHE_PATH}"

APP_RECORDS_FILE="${TMP_ROOT}/workflow-app-records.tsv"
GENERATED_APPS_FILE="${TMP_ROOT}/generated-app-records.tsv"
rm -f "${APP_RECORDS_FILE}" "${GENERATED_APPS_FILE}"

/usr/bin/python3 - "$WORKFLOW_CONFIG" "$APP_RECORDS_FILE" <<'PY'
import json
import sys

workflow_path, records_path = sys.argv[1], sys.argv[2]
with open(workflow_path, encoding="utf-8") as handle:
    workflow = json.load(handle)

apps = workflow.get("apps")
if not isinstance(apps, list) or not apps:
    raise SystemExit("Workflow configuration must define a non-empty apps array.")

with open(records_path, "w", encoding="utf-8") as handle:
    for app in apps:
        app_id = str(app.get("appID", "")).strip()
        app_name = str(app.get("appName", "")).strip()
        bundle_id = str(app.get("bundleId", "")).strip()
        if not app_id or not app_name or not bundle_id:
            raise SystemExit("Each workflow app must define appID, appName, and bundleId.")
        if any(sep in value for value in (app_id, app_name, bundle_id) for sep in ("\t", "\n")):
            raise SystemExit("Workflow app values must not contain tabs or newlines.")
        handle.write(f"{app_id}\t{app_name}\t{bundle_id}\n")
PY

XCODEBUILD_CMD=(
  xcodebuild
  -project "${ROOT_DIR}/FlowTab.xcodeproj"
  -scheme FlowTabSpaceFixture
  -configuration "${CONFIGURATION}"
  -destination "platform=macOS"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"
  CODE_SIGNING_ALLOWED=NO
  build
)

echo "Building FlowTabSpaceFixture template app..."
"${XCODEBUILD_CMD[@]}"

BASE_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/FlowTabSpaceFixture.app"
if [[ ! -d "${BASE_APP_PATH}" ]]; then
  echo "Built template app not found at ${BASE_APP_PATH}" >&2
  exit 1
fi

while IFS=$'\t' read -r APP_ID APP_NAME BUNDLE_ID; do
  if [[ "$BUNDLE_ID" =~ [^A-Za-z0-9.-] || "$BUNDLE_ID" == .* || "$BUNDLE_ID" == *..* || "$BUNDLE_ID" == *- ]]; then
    echo "Invalid bundle identifier for ${APP_ID}: ${BUNDLE_ID}" >&2
    exit 1
  fi

  VARIANT_APP_NAME="$(sanitize_app_bundle_name "${APP_NAME}-${BUNDLE_ID}").app"
  VARIANT_APP_PATH="${OUTPUT_DIR}/${VARIANT_APP_NAME}"
  INFO_PLIST_PATH="${VARIANT_APP_PATH}/Contents/Info.plist"

  rm -rf "${VARIANT_APP_PATH}"
  /usr/bin/ditto "${BASE_APP_PATH}" "${VARIANT_APP_PATH}"

  set_plist_string "${INFO_PLIST_PATH}" "CFBundleDisplayName" "${APP_NAME}"
  set_plist_string "${INFO_PLIST_PATH}" "CFBundleName" "${APP_NAME}"
  set_plist_string "${INFO_PLIST_PATH}" "CFBundleIdentifier" "${BUNDLE_ID}"

  echo "Re-signing generated app bundle for ${APP_ID}..."
  /usr/bin/codesign --force --deep --sign - "${VARIANT_APP_PATH}" >/dev/null

  printf '%s\t%s\t%s\t%s\n' \
    "${APP_ID}" \
    "${APP_NAME}" \
    "${BUNDLE_ID}" \
    "${VARIANT_APP_PATH}" >> "${GENERATED_APPS_FILE}"
done < "${APP_RECORDS_FILE}"

/usr/bin/python3 - "$WORKFLOW_CONFIG" "$GENERATED_APPS_FILE" "$RESOLVED_WORKFLOW_PATH" <<'PY'
import json
import sys

workflow_path, records_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(workflow_path, encoding="utf-8") as handle:
    workflow = json.load(handle)

generated = {}
with open(records_path, encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.rstrip("\n")
        if not line:
            continue
        app_id, app_name, bundle_id, app_path = line.split("\t")
        generated[app_id] = {
            "appName": app_name,
            "bundleId": bundle_id,
            "appPath": app_path,
        }

for app in workflow.get("apps", []):
    app_id = str(app.get("appID", "")).strip()
    if app_id not in generated:
        raise SystemExit(f"Missing generated app record for {app_id}")
    app["appName"] = generated[app_id]["appName"]
    app["bundleId"] = generated[app_id]["bundleId"]
    app["appPath"] = generated[app_id]["appPath"]

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(workflow, handle, indent=2)
    handle.write("\n")
PY

echo "Generated fixture app variants in: ${OUTPUT_DIR}"
echo "Resolved workflow: ${RESOLVED_WORKFLOW_PATH}"
