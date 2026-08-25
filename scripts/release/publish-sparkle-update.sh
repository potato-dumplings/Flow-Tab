#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPOSITORY="potato-dumplings/Flow-Tab"
INFO_PLIST="${ROOT_DIR}/FlowTab/Resources/Info.plist"
PAGES_FEED_URL="$(
  /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${INFO_PLIST}"
)"
SPARKLE_ACCOUNT="io.github.potato-dumplings.flowtab"
SPARKLE_PUBLIC_KEY="$(
  /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${INFO_PLIST}"
)"
SPARKLE_TOOLS_DIR="${FLOWTAB_SPARKLE_TOOLS_DIR:-${ROOT_DIR}/.build-local/sparkle-tools/bin}"
GENERATE_APPCAST="${SPARKLE_TOOLS_DIR}/generate_appcast"
PACKAGE_SCRIPT="${ROOT_DIR}/scripts/release/release-dmg.sh"
GATE_SCRIPT="${ROOT_DIR}/scripts/release/run-sparkle-release-gates.sh"
APPCAST_VALIDATOR="${ROOT_DIR}/scripts/release/validate-sparkle-appcast.py"
SIGNATURE_VERIFIER_SOURCE="${ROOT_DIR}/scripts/release/verify-sparkle-signatures.swift"
PAGES_WORKTREE="${ROOT_DIR}/.build-local/gh-pages"
ASSET_READBACK_WATCHDOG_SECONDS=120
PAGES_READBACK_WATCHDOG_SECONDS=180
READBACK_CADENCE_SECONDS=2

usage() {
  cat <<'EOF'
Usage: scripts/release/publish-sparkle-update.sh \
  --version <version> \
  --notes <markdown-or-markdown-file> \
  [--baseline-dmg <previous-public-dmg>]

Creates or resumes the matching draft release, publishes its Community DMG,
then atomically advances the signed GitHub Pages appcast.
EOF
}

VERSION=""
NOTES_INPUT=""
BASELINE_DMG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 64; }
      VERSION="$2"
      shift 2
      ;;
    --notes)
      [[ $# -ge 2 ]] || { echo "Missing value for --notes" >&2; exit 64; }
      NOTES_INPUT="$2"
      shift 2
      ;;
    --baseline-dmg)
      [[ $# -ge 2 ]] || { echo "Missing value for --baseline-dmg" >&2; exit 64; }
      BASELINE_DMG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "${VERSION}" || -z "${NOTES_INPUT}" ]]; then
  usage >&2
  exit 64
fi
VERSION="${VERSION#v}"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([.-][A-Za-z0-9]+)*$ ]]; then
  echo "Unsupported release version: ${VERSION}" >&2
  exit 64
fi
TAG="v${VERSION}"
PACKAGE_BASENAME="FlowTab-${TAG}"
ASSET_NAME="${PACKAGE_BASENAME}.dmg"
CHECKSUM_NAME="${PACKAGE_BASENAME}.sha256"
DOWNLOAD_URL="https://github.com/${REPOSITORY}/releases/download/${TAG}/${ASSET_NAME}"

for command_path in \
  "${GENERATE_APPCAST}" \
  "${PACKAGE_SCRIPT}" \
  "${GATE_SCRIPT}" \
  "${APPCAST_VALIDATOR}"
do
  if [[ ! -x "${command_path}" ]]; then
    echo "Required executable is unavailable: ${command_path}" >&2
    exit 69
  fi
done
if [[ ! -f "${SIGNATURE_VERIFIER_SOURCE}" ]]; then
  echo "Sparkle signature verifier source is unavailable." >&2
  exit 69
fi
for command_name in gh git curl xcodebuild; do
  if ! command -v "${command_name}" >/dev/null; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 69
  fi
done
if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=all)" ]]; then
  echo "Sparkle publishing requires a clean worktree." >&2
  exit 1
fi
gh auth status >/dev/null

PUBLISH_PARENT="${ROOT_DIR}/.build-local/publish-sparkle"
/bin/mkdir -p "${PUBLISH_PARENT}"
PUBLISH_ROOT="$(/usr/bin/mktemp -d "${PUBLISH_PARENT%/}/${TAG}.XXXXXX")"
cleanup() {
  /bin/rm -rf "${PUBLISH_ROOT}"
}
trap cleanup EXIT

BUILD_SETTINGS="$(
  xcodebuild \
    -project "${ROOT_DIR}/FlowTab.xcodeproj" \
    -scheme FlowTab \
    -configuration Release \
    -derivedDataPath "${PUBLISH_ROOT}/build-settings" \
    -showBuildSettings
)"
APP_VERSION="$(
  /usr/bin/awk '/^[[:space:]]*MARKETING_VERSION = / { print $3; exit }' \
    <<< "${BUILD_SETTINGS}"
)"
APP_BUILD="$(
  /usr/bin/awk '/^[[:space:]]*CURRENT_PROJECT_VERSION = / { print $3; exit }' \
    <<< "${BUILD_SETTINGS}"
)"
if [[ "${APP_VERSION}" != "${VERSION}" ]]; then
  echo "Release version does not match MARKETING_VERSION (${APP_VERSION})." >&2
  exit 1
fi
if [[ ! "${APP_BUILD}" =~ ^[1-9][0-9]*$ ]]; then
  echo "CURRENT_PROJECT_VERSION must be a positive integer." >&2
  exit 1
fi
SIGNATURE_VERIFIER="${PUBLISH_ROOT}/verify-sparkle-signatures"
/usr/bin/xcrun --sdk macosx swiftc \
  -parse-as-library \
  -module-cache-path "${PUBLISH_ROOT}/swift-module-cache" \
  "${SIGNATURE_VERIFIER_SOURCE}" \
  -o "${SIGNATURE_VERIFIER}"

NOTES_SOURCE="${PUBLISH_ROOT}/release-notes-source.md"
if [[ -f "${NOTES_INPUT}" && ! -L "${NOTES_INPUT}" ]]; then
  /usr/bin/ditto "${NOTES_INPUT}" "${NOTES_SOURCE}"
else
  /usr/bin/printf '%s\n' "${NOTES_INPUT}" > "${NOTES_SOURCE}"
fi

if [[ -z "${BASELINE_DMG}" ]]; then
  BASELINE_TAG="$(
    gh api "repos/${REPOSITORY}/releases?per_page=100" \
      --jq ".[] | select(.draft == false and .tag_name != \"${TAG}\") | .tag_name" \
      | /usr/bin/head -n 1
  )"
  if [[ -z "${BASELINE_TAG}" ]]; then
    echo "No previous public release is available as a signing baseline." >&2
    exit 1
  fi
  BASELINE_DOWNLOAD_DIR="${PUBLISH_ROOT}/baseline"
  /bin/mkdir -p "${BASELINE_DOWNLOAD_DIR}"
  gh release download "${BASELINE_TAG}" \
    --repo "${REPOSITORY}" \
    --pattern '*.dmg' \
    --dir "${BASELINE_DOWNLOAD_DIR}"
  BASELINE_CANDIDATES=()
  while IFS= read -r candidate; do
    BASELINE_CANDIDATES+=("${candidate}")
  done < <(
    /usr/bin/find "${BASELINE_DOWNLOAD_DIR}" -maxdepth 1 -type f -name '*.dmg'
  )
  if [[ "${#BASELINE_CANDIDATES[@]}" -ne 1 ]]; then
    echo "Previous public release must contain exactly one DMG." >&2
    exit 1
  fi
  BASELINE_DMG="${BASELINE_CANDIDATES[0]}"
elif [[ ! -f "${BASELINE_DMG}" || -L "${BASELINE_DMG}" ]]; then
  echo "--baseline-dmg must reference a regular file." >&2
  exit 66
fi

RELEASE_EXISTS="false"
RELEASE_IS_DRAFT="false"
if gh release view "${TAG}" --repo "${REPOSITORY}" >/dev/null 2>&1; then
  RELEASE_EXISTS="true"
  RELEASE_IS_DRAFT="$(
    gh release view "${TAG}" \
      --repo "${REPOSITORY}" \
      --json isDraft \
      --jq '.isDraft'
  )"
  if [[ "${RELEASE_IS_DRAFT}" != "true" \
    && "${RELEASE_IS_DRAFT}" != "false" ]]; then
    echo "GitHub returned an invalid draft state for ${TAG}." >&2
    exit 1
  fi
fi

echo "[1/7] Run the local Sparkle release gates"
"${GATE_SCRIPT}"

COMBINED_NOTES="${PUBLISH_ROOT}/release-notes.md"
if [[ "${RELEASE_EXISTS}" == "true" \
  && "${RELEASE_IS_DRAFT}" == "false" ]]; then
  echo "[2/7] Read back the already-published Community release asset"
  PUBLISHED_ASSET_DIR="${PUBLISH_ROOT}/published-assets"
  /bin/mkdir -p "${PUBLISHED_ASSET_DIR}"
  gh release download "${TAG}" \
    --repo "${REPOSITORY}" \
    --pattern "${ASSET_NAME}" \
    --dir "${PUBLISHED_ASSET_DIR}"
  gh release download "${TAG}" \
    --repo "${REPOSITORY}" \
    --pattern "${CHECKSUM_NAME}" \
    --dir "${PUBLISHED_ASSET_DIR}"
  ASSET_PATH="${PUBLISHED_ASSET_DIR}/${ASSET_NAME}"
  CHECKSUM_PATH="${PUBLISHED_ASSET_DIR}/${CHECKSUM_NAME}"
  gh release view "${TAG}" \
    --repo "${REPOSITORY}" \
    --json body \
    --jq '.body' > "${COMBINED_NOTES}"
else
  echo "[2/7] Build and audit the Community release asset"
  PACKAGE_LOG="${PUBLISH_ROOT}/community-package.log"
  "${PACKAGE_SCRIPT}" \
    --distribution community \
    --version "${VERSION}" \
    --baseline-dmg "${BASELINE_DMG}" \
    | /usr/bin/tee "${PACKAGE_LOG}"
  ASSET_PATH="${ROOT_DIR}/release/${PACKAGE_BASENAME}/${ASSET_NAME}"
  CHECKSUM_PATH="${ROOT_DIR}/release/${PACKAGE_BASENAME}/${CHECKSUM_NAME}"
  GATEKEEPER_STATUS="$(
    /usr/bin/sed -n 's/^Gatekeeper exit status: //p' "${PACKAGE_LOG}" \
      | /usr/bin/tail -n 1
  )"
  {
    /bin/cat "${NOTES_SOURCE}"
    /usr/bin/printf '\n\n## 分发信息 / Distribution\n\n'
    /usr/bin/printf '%s\n' \
      '- Community Build / 社区构建' \
      '- Apple Development signed / Apple Development 签名' \
      '- Unnotarized / 未公证' \
      '- Architectures / 架构: arm64, x86_64' \
      "- Gatekeeper assessment exit status / 检查退出状态: ${GATEKEEPER_STATUS:-unknown}"
  } > "${COMBINED_NOTES}"
fi

if [[ ! -f "${ASSET_PATH}" || ! -f "${CHECKSUM_PATH}" ]]; then
  echo "The matching release DMG and checksum are required." >&2
  exit 66
fi
(
  cd "$(dirname "${CHECKSUM_PATH}")"
  /usr/bin/shasum -a 256 -c "${CHECKSUM_NAME}"
)
ASSET_SHA256="$(/usr/bin/awk '{print $1}' "${CHECKSUM_PATH}")"
if [[ ! "${ASSET_SHA256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "The release checksum does not contain a SHA-256 digest." >&2
  exit 1
fi
ASSET_LENGTH="$(/usr/bin/stat -f '%z' "${ASSET_PATH}")"
if [[ "${RELEASE_EXISTS}" != "true" \
  || "${RELEASE_IS_DRAFT}" == "true" ]]; then
  /usr/bin/printf '%s\n' \
    "- SHA-256: \`${ASSET_SHA256}\`" >> "${COMBINED_NOTES}"
fi

echo "[3/7] Create or resume the tag and draft GitHub release"
if git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  if [[ "$(git -C "${ROOT_DIR}" rev-list -n 1 "${TAG}")" \
    != "$(git -C "${ROOT_DIR}" rev-parse HEAD)" ]]; then
    echo "Existing release tag does not point at HEAD: ${TAG}" >&2
    exit 1
  fi
else
  git -C "${ROOT_DIR}" tag -a "${TAG}" -m "FlowTab ${TAG}"
fi
git -C "${ROOT_DIR}" push origin "refs/tags/${TAG}"
if [[ "${RELEASE_EXISTS}" == "true" \
  && "${RELEASE_IS_DRAFT}" == "true" ]]; then
  gh release edit "${TAG}" \
    --repo "${REPOSITORY}" \
    --title "FlowTab ${TAG} Community Build" \
    --notes-file "${COMBINED_NOTES}" \
    --prerelease
elif [[ "${RELEASE_EXISTS}" != "true" ]]; then
  gh release create "${TAG}" \
    --repo "${REPOSITORY}" \
    --draft \
    --prerelease \
    --title "FlowTab ${TAG} Community Build" \
    --notes-file "${COMBINED_NOTES}"
fi
if [[ "${RELEASE_EXISTS}" != "true" \
  || "${RELEASE_IS_DRAFT}" == "true" ]]; then
  gh release upload "${TAG}" \
    --repo "${REPOSITORY}" \
    --clobber \
    "${ASSET_PATH}" \
    "${CHECKSUM_PATH}"
fi

echo "[4/7] Generate and locally verify the signed prerelease feed"
FEED_ARCHIVES="${PUBLISH_ROOT}/feed-archives"
/bin/mkdir -p "${FEED_ARCHIVES}"
if git -C "${ROOT_DIR}" ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  git -C "${ROOT_DIR}" fetch origin gh-pages
  if [[ -e "${PAGES_WORKTREE}/.git" ]]; then
    if [[ -n "$(git -C "${PAGES_WORKTREE}" status --porcelain)" ]]; then
      echo "The gh-pages worktree contains uncommitted changes." >&2
      exit 1
    fi
    git -C "${PAGES_WORKTREE}" switch --detach origin/gh-pages
  else
    git -C "${ROOT_DIR}" worktree add --detach \
      "${PAGES_WORKTREE}" origin/gh-pages
  fi
else
  if [[ -e "${PAGES_WORKTREE}" && ! -e "${PAGES_WORKTREE}/.git" ]]; then
    echo "The configured gh-pages worktree path is occupied." >&2
    exit 1
  fi
  if [[ ! -e "${PAGES_WORKTREE}/.git" ]]; then
    git -C "${ROOT_DIR}" worktree add --detach \
      "${PAGES_WORKTREE}" HEAD
  fi
fi
if [[ -n "$(git -C "${PAGES_WORKTREE}" status --porcelain)" ]]; then
  echo "The gh-pages worktree must be clean before feed generation." >&2
  exit 1
fi
if [[ -f "${PAGES_WORKTREE}/appcast.xml" ]]; then
  /usr/bin/ditto \
    "${PAGES_WORKTREE}/appcast.xml" \
    "${FEED_ARCHIVES}/appcast.xml"
else
  /usr/bin/curl --fail --silent --show-error --location \
    "${PAGES_FEED_URL}" \
    --output "${FEED_ARCHIVES}/appcast.xml" \
    || /bin/rm -f "${FEED_ARCHIVES}/appcast.xml"
fi
/usr/bin/ditto "${ASSET_PATH}" "${FEED_ARCHIVES}/${ASSET_NAME}"
/usr/bin/ditto "${COMBINED_NOTES}" "${FEED_ARCHIVES}/${PACKAGE_BASENAME}.md"
"${GENERATE_APPCAST}" \
  --account "${SPARKLE_ACCOUNT}" \
  --channel prerelease \
  --embed-release-notes \
  --maximum-versions 3 \
  --maximum-deltas 0 \
  --download-url-prefix "https://github.com/${REPOSITORY}/releases/download/${TAG}/" \
  "${FEED_ARCHIVES}"
GENERATED_FEED="${FEED_ARCHIVES}/appcast.xml"
ENCLOSURE_SIGNATURE="$(
  /usr/bin/python3 "${APPCAST_VALIDATOR}" \
    --appcast "${GENERATED_FEED}" \
    --archive "${ASSET_PATH}" \
    --display-version "${VERSION}" \
    --build-version "${APP_BUILD}" \
    --download-url "${DOWNLOAD_URL}" \
    --channel prerelease \
    --minimum-system-version 13.0 \
    --sha256 "${ASSET_SHA256}"
)"
"${SIGNATURE_VERIFIER}" \
  --public-key "${SPARKLE_PUBLIC_KEY}" \
  --appcast "${GENERATED_FEED}" \
  --archive "${ASSET_PATH}" \
  --archive-signature "${ENCLOSURE_SIGNATURE}"
FEED_SHA256="$(/usr/bin/shasum -a 256 "${GENERATED_FEED}" | /usr/bin/awk '{print $1}')"

echo "[5/7] Publish and read back the GitHub Release assets"
if [[ "${RELEASE_EXISTS}" != "true" \
  || "${RELEASE_IS_DRAFT}" == "true" ]]; then
  gh release edit "${TAG}" \
    --repo "${REPOSITORY}" \
    --draft=false \
    --prerelease
fi
REMOTE_LENGTH="$(
  gh api "repos/${REPOSITORY}/releases/tags/${TAG}" \
    --jq ".assets[] | select(.name == \"${ASSET_NAME}\") | .size"
)"
REMOTE_DIGEST="$(
  gh api "repos/${REPOSITORY}/releases/tags/${TAG}" \
    --jq ".assets[] | select(.name == \"${ASSET_NAME}\") | (.digest // \"\")"
)"
if [[ "${REMOTE_LENGTH}" != "${ASSET_LENGTH}" ]]; then
  echo "GitHub asset length does not match the local DMG." >&2
  exit 1
fi
if [[ -n "${REMOTE_DIGEST}" \
  && "${REMOTE_DIGEST}" != "sha256:${ASSET_SHA256}" ]]; then
  echo "GitHub asset digest does not match the local DMG." >&2
  exit 1
fi
REMOTE_ASSET="${PUBLISH_ROOT}/remote-${ASSET_NAME}"
ASSET_DEADLINE=$((SECONDS + ASSET_READBACK_WATCHDOG_SECONDS))
while true; do
  /bin/rm -f "${REMOTE_ASSET}"
  if /usr/bin/curl --fail --silent --show-error --location \
      "${DOWNLOAD_URL}" --output "${REMOTE_ASSET}" \
    && [[ "$(/usr/bin/shasum -a 256 "${REMOTE_ASSET}" | /usr/bin/awk '{print $1}')" \
      == "${ASSET_SHA256}" ]]; then
    break
  fi
  if (( SECONDS >= ASSET_DEADLINE )); then
    echo "GitHub asset readback watchdog expired." >&2
    exit 1
  fi
  /bin/sleep "${READBACK_CADENCE_SECONDS}"
done

echo "[6/7] Commit the feed-only gh-pages tree"
git -C "${PAGES_WORKTREE}" rm -r --ignore-unmatch -- . >/dev/null
/usr/bin/ditto "${GENERATED_FEED}" "${PAGES_WORKTREE}/appcast.xml"
git -C "${PAGES_WORKTREE}" add appcast.xml
if ! git -C "${PAGES_WORKTREE}" diff --cached --quiet; then
  git -C "${PAGES_WORKTREE}" commit -m "Publish FlowTab ${TAG} appcast"
fi
git -C "${PAGES_WORKTREE}" push origin HEAD:gh-pages
if gh api "repos/${REPOSITORY}/pages" >/dev/null 2>&1; then
  gh api --method PUT "repos/${REPOSITORY}/pages" \
    -f 'source[branch]=gh-pages' \
    -f 'source[path]=/' >/dev/null
else
  gh api --method POST "repos/${REPOSITORY}/pages" \
    -f 'source[branch]=gh-pages' \
    -f 'source[path]=/' >/dev/null
fi

echo "[7/7] Read back and re-verify the public Pages feed"
REMOTE_FEED="${PUBLISH_ROOT}/remote-appcast.xml"
PAGES_DEADLINE=$((SECONDS + PAGES_READBACK_WATCHDOG_SECONDS))
while true; do
  /bin/rm -f "${REMOTE_FEED}"
  if /usr/bin/curl --fail --silent --show-error --location \
      "${PAGES_FEED_URL}" --output "${REMOTE_FEED}" \
    && [[ "$(/usr/bin/shasum -a 256 "${REMOTE_FEED}" | /usr/bin/awk '{print $1}')" \
      == "${FEED_SHA256}" ]]; then
    break
  fi
  if (( SECONDS >= PAGES_DEADLINE )); then
    echo "GitHub Pages feed readback watchdog expired." >&2
    exit 1
  fi
  /bin/sleep "${READBACK_CADENCE_SECONDS}"
done
"${SIGNATURE_VERIFIER}" \
  --public-key "${SPARKLE_PUBLIC_KEY}" \
  --appcast "${REMOTE_FEED}" \
  --archive "${REMOTE_ASSET}" \
  --archive-signature "${ENCLOSURE_SIGNATURE}"
/usr/bin/python3 "${APPCAST_VALIDATOR}" \
  --appcast "${REMOTE_FEED}" \
  --archive "${REMOTE_ASSET}" \
  --display-version "${VERSION}" \
  --build-version "${APP_BUILD}" \
  --download-url "${DOWNLOAD_URL}" \
  --channel prerelease \
  --minimum-system-version 13.0 \
  --sha256 "${ASSET_SHA256}" >/dev/null

cleanup
trap - EXIT
echo "Published ${TAG}: ${DOWNLOAD_URL}"
echo "Verified feed: ${PAGES_FEED_URL}"
