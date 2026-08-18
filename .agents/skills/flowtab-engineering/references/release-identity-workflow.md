# Release Packaging And Privacy Identity Continuity

Use this workflow for release archives, upgrade-test packages, signing changes, notarization,
or any delivery expected to preserve Accessibility and Screen Recording grants.

## Contents

- [Identity Contract](#identity-contract)
- [Package Modes](#package-modes)
- [Workflow](#workflow)
- [Continuity Audit](#continuity-audit)
- [TCC-Safe Upgrade Validation](#tcc-safe-upgrade-validation)
- [Failure And Handoff Contract](#failure-and-handoff-contract)

## Identity Contract

macOS privacy authorization follows the final installed code identity. A project Team setting,
Bundle ID, archive name, tag, or successful unsigned build is not proof that the delivered App
has a reusable identity.

A permission-preserving candidate must satisfy all of these invariants:

- The final mounted `Flow Tab.app` is certificate-signed. `Signature=adhoc`,
  `TeamIdentifier=not set`, a CDHash-only designated requirement, or an unavailable Authority is
  a failed identity gate.
- The signing identifier and `CFBundleIdentifier` are both
  `io.github.potato-dumplings.flowtab`.
- The version inside the final mounted App equals the requested release version.
- The candidate and the App from the actual preceding distributed asset mutually satisfy each
  other's designated requirements.
- The intended signing class is explicit: Apple Development for a named local upgrade test, or
  Developer ID Application for public distribution.
- Packaging, copying, mounting, and ZIP extraction preserve the already-verified App bundle
  byte-for-byte.

Do not infer continuity from equal Team IDs or different CDHashes alone. Evaluate the complete
designated requirements. A sandbox result reporting zero identities or an unavailable Authority
is an environment blocker; retry the same read in an approved keychain-visible environment before
concluding that the certificate is absent.

## Package Modes

### Public Distribution

Use `scripts/release/release-dmg.sh`. Require Developer ID Application, Hardened Runtime, a secure
timestamp, Apple notarization acceptance, stapling, Gatekeeper acceptance, and the repository's
distribution verification. Missing signing or notarization credentials block delivery. Preserve
the last verified artifact and do not create an ad-hoc substitute.

### Local Upgrade Test

Apple Development is allowed only for an explicitly local artifact whose purpose is to validate
upgrade and privacy-identity continuity. Resolve the same usable certificate identity as the
baseline, sign nested code and the outer App through `scripts/release/sign-macos-bundle.sh`, and
run the continuity audit below. Label the artifact as Apple Development and keep it out of public
release uploads.

### Ad-Hoc Migration Boundary

Ad-hoc signing is not a release mode. When the actual preceding distributed App is ad-hoc, the
first stable certificate-signed candidate cannot inherit its TCC grants. Record that boundary with
`--accept-adhoc-migration`, require one user reauthorization after installing the stable App, and
use that stable App as the baseline for every later version. Do not use the migration flag again.

## Workflow

1. Resolve the requested version, tag or commit, target architectures, and package mode. Confirm
   the source tree and embedded version identify the same candidate.
2. Preserve the existing release artifact. Allocate a fresh ignored build root below
   `.build-local/`; do not overwrite the current release asset before all gates pass.
3. Obtain the actual preceding user-distributed archive. Mount or extract it through its owning
   package boundary and identify its `Flow Tab.app`. A locally rebuilt approximation is not a
   baseline.
4. Resolve the expected identity with `security find-identity -v -p codesigning` in an environment
   that can read the user's keychain. Require exactly the intended identity and pin the expected
   team independently from `xcconfigs/LocalSigning.xcconfig` or the release environment.
5. Build Release into the fresh root. An unsigned intermediate is allowed only when the final App
   is subsequently signed with the resolved stable identity.
6. Run `scripts/release/verify-release-binary.sh`, sign nested code from the inside out, and verify
   the staged App and uninstaller with `codesign --verify --deep --strict`.
7. Run the continuity audit against the baseline and staged candidate before creating the DMG.
8. Create and sign the DMG. Mount the final DMG, compare its App and uninstaller to the verified
   staged bundles, then rerun the continuity audit against the mounted App.
9. For public distribution, complete notarization, stapling, Gatekeeper, and repository
   distribution verification. For a local upgrade test, report those public-distribution checks
   as not applicable to the named local artifact.
10. Create the final archive only after every required gate passes. Verify its layout and checksum,
    publish or hand off the new path, and remove the reproducible build root.

## Continuity Audit

Run the Skill-owned deterministic audit on mounted or otherwise signature-preserving App bundles:

```bash
python3 .agents/skills/flowtab-engineering/scripts/release_identity_audit.py \
  --baseline-app <preceding-mounted-flow-tab-app> \
  --candidate-app <candidate-mounted-flow-tab-app> \
  --authority-kind developer-id \
  --expected-bundle-id io.github.potato-dumplings.flowtab \
  --expected-version <version> \
  --expected-team-id <team-id> \
  --required-architectures arm64,x86_64
```

Use `--authority-kind apple-development` for a named local upgrade test. During the one allowed
transition from a verified ad-hoc baseline, add `--accept-adhoc-migration`; the result must report
`one_time_regrant_required`. If a baseline genuinely cannot be obtained, `--candidate-only`
validates the candidate identity but leaves permission continuity unproven.

The audit fails when the candidate is ad-hoc, its identity metadata is incomplete, expected
metadata differs, a stable baseline uses another team, or either App fails the other's designated
requirement.

## TCC-Safe Upgrade Validation

- Install and launch the exact mounted candidate through `/Applications/Flow Tab.app`.
- Do not use `scripts/release/release-install.sh` for a permission-preservation check; that script
  intentionally resets `Accessibility` and `ScreenCapture` with `tccutil`.
- Do not reset, remove, or toggle TCC grants between the before and after observations unless the
  audit explicitly recorded the one-time ad-hoc migration boundary.
- Quit the preceding process and confirm the launched executable belongs to the candidate install
  path before reading permission state.
- Use the same stable signing identity, Bundle ID, and compatible designated requirement for all
  later versions. A certificate migration is a separate release boundary and cannot be described
  as permission-preserving without its own evidence.

## Failure And Handoff Contract

Stop without replacing the prior artifact when the identity, baseline, notarization, mounted
content, or continuity gate fails. Do not weaken signing, use ad-hoc fallback, or call a candidate
permission-preserving when the baseline is missing.

Report:

- requested version, source commit or tag, package mode, and architectures;
- final App signing class, TeamIdentifier, Bundle ID, and continuity audit status;
- baseline asset identity and whether mutual designated-requirement checks passed;
- any explicit one-time ad-hoc migration and required user reauthorization;
- Hardened Runtime, timestamp, notarization, stapling, Gatekeeper, mounted-content, archive-layout,
  and checksum results as applicable;
- confirmation that no TCC reset path was invoked;
- final artifact path intent, checksum, rollback artifact, and transient build-root cleanup.
