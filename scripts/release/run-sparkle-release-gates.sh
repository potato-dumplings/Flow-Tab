#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE_PARENT="${ROOT_DIR}/.build-local/sparkle-release-gates"
/bin/mkdir -p "${GATE_PARENT}"
GATE_ROOT="$(/usr/bin/mktemp -d "${GATE_PARENT%/}/attempt.XXXXXX")"

echo "[gate 1/6] Verify package resolution and release configuration"
xcodebuild \
  -resolvePackageDependencies \
  -project "${ROOT_DIR}/FlowTab.xcodeproj" \
  -scheme FlowTab \
  -clonedSourcePackagesDirPath "${GATE_ROOT}/SourcePackages"
if ! /usr/bin/grep -Fq '"version" : "2.9.6"' \
  "${ROOT_DIR}/FlowTab.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"; then
  echo "Package.resolved does not pin Sparkle 2.9.6." >&2
  exit 1
fi

echo "[gate 2/6] Run release-script and identity contracts"
"${ROOT_DIR}/scripts/release/test-release-binary-contract.sh"
"${ROOT_DIR}/scripts/release/test-release-install-contract.sh"
"${ROOT_DIR}/scripts/release/test-release-distribution-contract.sh"
"${ROOT_DIR}/scripts/release/test-release-security-boundaries.sh"
"${ROOT_DIR}/scripts/release/test-dmg-mount-lifecycle.sh"
"${ROOT_DIR}/scripts/release/test-sparkle-release-contract.sh"
/usr/bin/python3 \
  "${ROOT_DIR}/.agents/skills/flowtab-engineering/scripts/release_identity_audit_tests.py"

echo "[gate 3/6] Run Sparkle Unit and Behavior coverage"
"${ROOT_DIR}/scripts/testing/run-flowtabtests-local.sh" \
  --output-root "${GATE_ROOT}/unit" \
  -only-testing:FlowTabTests/FlowTabTests/testUpdateChannelPolicyIncludesPrereleasesForPrereleaseBuilds \
  -only-testing:FlowTabTests/FlowTabTests/testReleaseBuildPolicyRequiresStrictlyIncreasingPositiveIntegers \
  -only-testing:FlowTabTests/FlowTabTests/testUpdatePresentationReducerPreservesAndClearsKnownUpdate \
  -only-testing:FlowTabTests/FlowTabTests/testSidebarUpdateLayoutConsumesTheExistingContentWidth \
  -only-testing:FlowTabTests/FlowTabTests/testUpdateStringsIncludeTheTargetVersionInBothLanguages \
  -only-testing:FlowTabTests/FlowTabTests/testUpdateCoordinatorStartsOnceAndPresentsOneForegroundCheck \
  -only-testing:FlowTabTests/FlowTabTests/testAllPresentationEntryPointsResolveLifecycleSingletons

echo "[gate 4/6] Install the fixed-identity UI test app"
"${ROOT_DIR}/scripts/testing/install-ui-test-app.sh"

echo "[gate 5/6] Run update UI and 20/50 ms pressure coverage"
"${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh" \
  --skip-space-fixtures \
  --output-root "${GATE_ROOT}/ui" \
  -only-testing:FlowTabUITests/FlowTabUITests/testUpdateButtonUsesCompactChineseLightLayoutAndRoutesOneAction \
  -only-testing:FlowTabUITests/FlowTabUITests/testUpdateButtonUsesCompactEnglishDarkLayout \
  -only-testing:FlowTabUITests/FlowTabUITests/testUpdateButtonIsHiddenWhenNoUpdateIsAvailable \
  -only-testing:FlowTabUITests/FlowTabUITests/testUpdateAvailabilitySurvives20MillisecondTabSwitchPressure \
  -only-testing:FlowTabUITests/FlowTabUITests/testUpdateAvailabilitySurvives50MillisecondTabSwitchPressure

echo "[gate 6/6] Run typography and repository hygiene audits"
/usr/bin/python3 \
  "${ROOT_DIR}/.agents/skills/flowtab-engineering/scripts/typography_audit.py" \
  --repository-root "${ROOT_DIR}"
git -C "${ROOT_DIR}" diff --check

echo "Sparkle release gates passed. Evidence: ${GATE_ROOT}"
