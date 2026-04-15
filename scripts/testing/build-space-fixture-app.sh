#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/.build-local/space-fixture"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
TMP_ROOT="${BUILD_ROOT}/tmp"
HOME_ROOT="${BUILD_ROOT}/home"
MODULE_CACHE_ROOT="${BUILD_ROOT}/module-cache"
PACKAGE_CACHE_PATH="${BUILD_ROOT}/source-packages"

APP_NAME=""
BUNDLE_ID=""
CONFIGURATION="Debug"
OUTPUT_DIR="${BUILD_ROOT}/variants"

print_help() {
  cat <<'EOF'
Usage:
  ./scripts/testing/build-space-fixture-app.sh \
    --app-name "Chrome Fixture" \
    --bundle-id "com.example.chrome.fixture" \
    [--configuration Debug|Release] \
    [--output-dir /custom/output/dir]

Builds the FlowTabSpaceFixture template app, then copies it into a variant
bundle whose display name and bundle identifier match the requested values.

The generated app still accepts the normal runtime launch arguments, for example:
  --window-count 3
  --fullscreen-window-index 3
  --window-title-prefix "Fixture"
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
    --app-name)
      APP_NAME="${2-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2-}"
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

APP_NAME="$(trim "$APP_NAME")"
BUNDLE_ID="$(trim "$BUNDLE_ID")"

if [[ -z "$APP_NAME" || -z "$BUNDLE_ID" ]]; then
  echo "Both --app-name and --bundle-id are required." >&2
  print_help >&2
  exit 1
fi

if [[ "$CONFIGURATION" != "Debug" && "$CONFIGURATION" != "Release" ]]; then
  echo "Unsupported configuration: ${CONFIGURATION}. Use Debug or Release." >&2
  exit 1
fi

if [[ "$BUNDLE_ID" =~ [^A-Za-z0-9.-] || "$BUNDLE_ID" == .* || "$BUNDLE_ID" == *..* || "$BUNDLE_ID" == *- ]]; then
  echo "Invalid bundle identifier: ${BUNDLE_ID}" >&2
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

export TMPDIR="${TMP_ROOT}/"
export HOME="${HOME_ROOT}"
export CFFIXED_USER_HOME="${HOME_ROOT}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}/clang"
export SWIFT_MODULECACHE_PATH="${MODULE_CACHE_ROOT}/swift"
export SWIFTPM_PACKAGECACHE="${PACKAGE_CACHE_PATH}"

XCODEBUILD_CMD=(
  xcodebuild
  -project "${ROOT_DIR}/FlowTab.xcodeproj"
  -scheme FlowTabSpaceFixture
  -configuration "${CONFIGURATION}"
  -destination "platform=macOS"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"
  build
)

echo "Building FlowTabSpaceFixture template app..."
"${XCODEBUILD_CMD[@]}"

BASE_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/FlowTabSpaceFixture.app"
if [[ ! -d "${BASE_APP_PATH}" ]]; then
  echo "Built template app not found at ${BASE_APP_PATH}" >&2
  exit 1
fi

VARIANT_APP_NAME="$(sanitize_app_bundle_name "${APP_NAME}").app"
VARIANT_APP_PATH="${OUTPUT_DIR}/${VARIANT_APP_NAME}"
INFO_PLIST_PATH="${VARIANT_APP_PATH}/Contents/Info.plist"

rm -rf "${VARIANT_APP_PATH}"
/usr/bin/ditto "${BASE_APP_PATH}" "${VARIANT_APP_PATH}"

set_plist_string "${INFO_PLIST_PATH}" "CFBundleDisplayName" "${APP_NAME}"
set_plist_string "${INFO_PLIST_PATH}" "CFBundleName" "${APP_NAME}"
set_plist_string "${INFO_PLIST_PATH}" "CFBundleIdentifier" "${BUNDLE_ID}"

echo "Re-signing generated app bundle..."
/usr/bin/codesign --force --deep --sign - "${VARIANT_APP_PATH}" >/dev/null

echo "Generated app: ${VARIANT_APP_PATH}"
echo "Display Name: ${APP_NAME}"
echo "Bundle ID: ${BUNDLE_ID}"
