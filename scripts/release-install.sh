#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="{user-home}/Projeck-Works/Personal/FlowTabApp"
DERIVED_DATA_PATH="${PROJECT_DIR}/.build-local"
RELEASE_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/FlowTabApp.app"
INSTALL_PATH="/Applications/FlowTabApp.app"
BUNDLE_ID="com.pd.FlowTabApp"

for arg in "$@"; do
  case "${arg}" in
    -h|--help)
      cat <<'EOF'
Usage: ./scripts/release-install.sh
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      exit 1
      ;;
  esac
done

TOTAL_STEPS=6
STEP=1

reset_tcc_permission() {
  local service="$1"
  local output

  if ! output=$(/usr/bin/tccutil reset "${service}" "${BUNDLE_ID}" 2>&1); then
    echo "Failed to reset ${service} permission for ${BUNDLE_ID}" >&2
    echo "${output}" >&2
    if [[ "${output}" == *"Operation not permitted from sandbox"* ]]; then
      echo "Please run this script from macOS Terminal/iTerm (outside sandboxed environment)." >&2
    fi
    exit 1
  fi

  if [[ -n "${output}" ]]; then
    echo "${output}"
  fi
}

echo "[${STEP}/${TOTAL_STEPS}] Quit running FlowTabApp"
osascript -e 'quit app "FlowTabApp"' >/dev/null 2>&1 || true
pkill -x FlowTabApp >/dev/null 2>&1 || true
sleep 1

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Reset Accessibility and Screen Recording permissions"
reset_tcc_permission "Accessibility"
reset_tcc_permission "ScreenCapture"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Build Release"
cd "${PROJECT_DIR}"
xcodebuild \
  -project FlowTabApp.xcodeproj \
  -scheme FlowTabApp \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

if [[ ! -d "${RELEASE_APP_PATH}" ]]; then
  echo "Build output not found: ${RELEASE_APP_PATH}" >&2
  exit 1
fi

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Remove old app"
rm -rf "${INSTALL_PATH}"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Install new app"
cp -R "${RELEASE_APP_PATH}" "${INSTALL_PATH}"

STEP=$((STEP + 1))
echo "[${STEP}/${TOTAL_STEPS}] Launch app"
open "${INSTALL_PATH}"

echo "Done: ${INSTALL_PATH}"
