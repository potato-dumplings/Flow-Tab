#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/FlowTab.xcodeproj/project.pbxproj"
PACKAGE_LOCK="${ROOT_DIR}/FlowTab.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
INFO_PLIST="${ROOT_DIR}/FlowTab/Resources/Info.plist"
RELEASE_DMG="${ROOT_DIR}/scripts/release/release-dmg.sh"
COMMUNITY_DMG="${ROOT_DIR}/scripts/release/release-community-dmg.sh"
PUBLISHER="${ROOT_DIR}/scripts/release/publish-sparkle-update.sh"
VALIDATOR="${ROOT_DIR}/scripts/release/validate-sparkle-appcast.py"
SIGNATURE_VERIFIER_SOURCE="${ROOT_DIR}/scripts/release/verify-sparkle-signatures.swift"
CERTIFICATE_TEAM="${ROOT_DIR}/scripts/release/certificate-team-id.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for script_path in \
  "${RELEASE_DMG}" \
  "${COMMUNITY_DMG}" \
  "${PUBLISHER}" \
  "${ROOT_DIR}/scripts/release/run-sparkle-release-gates.sh"
do
  /bin/bash -n "${script_path}" \
    || fail "shell syntax is invalid: ${script_path}"
done
/usr/bin/python3 -c '
import ast
import pathlib
import sys
for source_path in sys.argv[1:]:
    ast.parse(pathlib.Path(source_path).read_text(encoding="utf-8"))
' "${VALIDATOR}" "${CERTIFICATE_TEAM}"

/usr/bin/grep -Fq 'repositoryURL = "https://github.com/sparkle-project/Sparkle";' \
  "${PROJECT_PATH}" || fail "Sparkle repository URL is not pinned"
/usr/bin/grep -Fq 'kind = exactVersion;' "${PROJECT_PATH}" \
  || fail "Sparkle package requirement is not exact"
/usr/bin/grep -Fq 'version = 2.9.6;' "${PROJECT_PATH}" \
  || fail "Sparkle package requirement is not 2.9.6"
/usr/bin/grep -Fq '"version" : "2.9.6"' "${PACKAGE_LOCK}" \
  || fail "Package.resolved does not contain Sparkle 2.9.6"

[[ "$(/usr/bin/grep -F -c 'INFOPLIST_FILE = FlowTab/Resources/Info.plist;' "${PROJECT_PATH}")" -eq 3 ]] \
  || fail "FlowTab app configurations do not share the processed Info.plist"
assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${INFO_PLIST}")"
  [[ "${actual}" == "${expected}" ]] \
    || fail "Info.plist ${key} is ${actual}, expected ${expected}"
}
assert_plist_value SUFeedURL \
  'https://potato-dumplings.github.io/Flow-Tab/appcast.xml'
assert_plist_value SUPublicEDKey \
  'IX+Vr0uhpQVXoBt7QNj1SAxDtCtPA6dWOX3ttXfOXYI='
assert_plist_value SUEnableAutomaticChecks true
assert_plist_value SUScheduledCheckInterval 86400
assert_plist_value SUAutomaticallyUpdate false
assert_plist_value SUAllowsAutomaticUpdates false
assert_plist_value SURequireSignedFeed true
assert_plist_value SUVerifyUpdateBeforeExtraction true
[[ "$(/usr/bin/grep -F -c 'CURRENT_PROJECT_VERSION = 5;' "${PROJECT_PATH}")" -eq 3 ]] \
  || fail "FlowTab build number is not 5 in all app configurations"
[[ "$(/usr/bin/grep -F -c 'MARKETING_VERSION = 0.1.0-alpha.05;' "${PROJECT_PATH}")" -eq 3 ]] \
  || fail "FlowTab display version is not alpha.05 in all app configurations"

/usr/bin/grep -Fq -- '--distribution community' "${PUBLISHER}" \
  || fail "publisher does not select Community distribution"
/usr/bin/grep -Fq -- '--baseline-dmg "${BASELINE_DMG}"' "${PUBLISHER}" \
  || fail "publisher does not pass the public baseline"
/usr/bin/grep -Fq -- '--channel prerelease' "${PUBLISHER}" \
  || fail "generate_appcast prerelease channel is missing"
/usr/bin/grep -Fq -- '--embed-release-notes' "${PUBLISHER}" \
  || fail "embedded release notes are missing"
/usr/bin/grep -Fq -- '--maximum-versions 3' "${PUBLISHER}" \
  || fail "appcast retention is not three versions"
/usr/bin/grep -Fq -- '--maximum-deltas 0' "${PUBLISHER}" \
  || fail "delta generation is enabled"
/usr/bin/grep -Fq 'git -C "${PAGES_WORKTREE}" rm -r --ignore-unmatch -- .' \
  "${PUBLISHER}" || fail "gh-pages is not reduced to the signed feed"
/usr/bin/grep -Fq 'RELEASE_IS_DRAFT' "${PUBLISHER}" \
  || fail "publisher does not distinguish draft and public releases"
/usr/bin/grep -Fq 'published-assets' "${PUBLISHER}" \
  || fail "publisher cannot resume from public release asset readback"
/usr/bin/grep -Fq 'verify-sparkle-signatures.swift' "${PUBLISHER}" \
  || fail "publisher does not use public-key-only signature verification"
if /usr/bin/grep -Eq 'SIGN_UPDATE|sign_update[[:space:]]+--verify' "${PUBLISHER}"; then
  fail "publisher verification must not read the private key"
fi

/usr/bin/grep -Fq 'certificate-team-id.py' "${COMMUNITY_DMG}" \
  || fail "Community identity does not resolve Team ID from certificate bytes"
/usr/bin/grep -Fq -- '--authority-kind apple-development' "${COMMUNITY_DMG}" \
  || fail "Community identity audit does not require Apple Development"
/usr/bin/grep -Fq -- '--required-architectures arm64,x86_64' "${COMMUNITY_DMG}" \
  || fail "Community identity audit does not require a universal app"
/usr/bin/grep -Fq 'verify_nested_code "${STAGED_APP}"' "${COMMUNITY_DMG}" \
  || fail "nested Sparkle code is not explicitly verified"
/usr/bin/grep -Fq 'CANDIDATE_BUILD <= BASELINE_BUILD' "${COMMUNITY_DMG}" \
  || fail "build-number continuity is not enforced"

TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/flowtab-appcast-contract.XXXXXX")"
cleanup() {
  /bin/rm -rf "${TEMP_ROOT}"
}
trap cleanup EXIT
ARCHIVE="${TEMP_ROOT}/FlowTab-v0.1.0-alpha.05.dmg"
APPCAST="${TEMP_ROOT}/appcast.xml"
SIGNATURE_VERIFIER="${TEMP_ROOT}/verify-sparkle-signatures"
/usr/bin/xcrun --sdk macosx swiftc \
  -parse-as-library \
  -module-cache-path "${TEMP_ROOT}/swift-module-cache" \
  "${SIGNATURE_VERIFIER_SOURCE}" \
  -o "${SIGNATURE_VERIFIER}"
/usr/bin/printf 'flowtab-community-archive' > "${ARCHIVE}"
ARCHIVE_LENGTH="$(/usr/bin/stat -f '%z' "${ARCHIVE}")"
ARCHIVE_SHA="$(/usr/bin/shasum -a 256 "${ARCHIVE}" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s\n' \
  '<?xml version="1.0" encoding="utf-8"?>' \
  '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">' \
  '<channel><item>' \
  '<sparkle:channel>prerelease</sparkle:channel>' \
  '<sparkle:version>5</sparkle:version>' \
  '<sparkle:shortVersionString>0.1.0-alpha.05</sparkle:shortVersionString>' \
  '<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>' \
  "<enclosure url=\"https://example.invalid/FlowTab-v0.1.0-alpha.05.dmg\" length=\"${ARCHIVE_LENGTH}\" type=\"application/octet-stream\" sparkle:edSignature=\"fixture-signature\"/>" \
  '</item></channel></rss>' > "${APPCAST}"
SIGNATURE="$(
  /usr/bin/python3 "${VALIDATOR}" \
    --appcast "${APPCAST}" \
    --archive "${ARCHIVE}" \
    --display-version 0.1.0-alpha.05 \
    --build-version 5 \
    --download-url https://example.invalid/FlowTab-v0.1.0-alpha.05.dmg \
    --channel prerelease \
    --minimum-system-version 13.0 \
    --sha256 "${ARCHIVE_SHA}"
)"
[[ "${SIGNATURE}" == "fixture-signature" ]] \
  || fail "appcast validator did not return the enclosure signature"

RFC_PUBLIC_KEY='11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='
RFC_EMPTY_SIGNATURE='5VZDAMNgrHKQhuLMgG6CioSHfx645dl02HPgZSJJAVVfuIIVkKM7rMYeOXAc+bRr0lv18FlbviRlUUFDjnoQCw=='
SIGNED_EMPTY_APPCAST="${TEMP_ROOT}/signed-empty-appcast.xml"
EMPTY_ARCHIVE="${TEMP_ROOT}/empty-archive.dmg"
/usr/bin/printf '%s\n' \
  '<!-- sparkle-signatures:' \
  "edSignature: ${RFC_EMPTY_SIGNATURE}" \
  'length: 0' \
  '-->' > "${SIGNED_EMPTY_APPCAST}"
: > "${EMPTY_ARCHIVE}"
"${SIGNATURE_VERIFIER}" \
  --public-key "${RFC_PUBLIC_KEY}" \
  --appcast "${SIGNED_EMPTY_APPCAST}" \
  --archive "${EMPTY_ARCHIVE}" \
  --archive-signature "${RFC_EMPTY_SIGNATURE}" >/dev/null
/usr/bin/printf 'tampered' > "${EMPTY_ARCHIVE}"
if "${SIGNATURE_VERIFIER}" \
  --public-key "${RFC_PUBLIC_KEY}" \
  --appcast "${SIGNED_EMPTY_APPCAST}" \
  --archive "${EMPTY_ARCHIVE}" \
  --archive-signature "${RFC_EMPTY_SIGNATURE}" >/dev/null 2>&1; then
  fail "public-key verifier accepted a modified archive"
fi

echo "Sparkle release contract tests passed."
