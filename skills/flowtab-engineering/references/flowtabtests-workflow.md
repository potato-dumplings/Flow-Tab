# FlowTabTests Workflow

Use this reference whenever `FlowTabTests` are required, attempted, narrowed, reported, or blocked. This workflow is the authoritative path for app unit and in-process behavior tests.

## Required Outcome

- Run `FlowTabTests` through `./scripts/testing/run-flowtabtests-local.sh`.
- Keep normal app-test build products, caches, temporary files, and HOME under `./.build-local/app-tests`.
- For audit runs, pass `--build-root <project-local-build-root>` and `--output-root <attempt-directory>`. Keep both roots inside the current project under the Git-ignored `./.build-local/` tree, and leave the output leaf absent until the wrapper creates it.
- Persist project-local locations as `{resource_boundary: repository_root, relative_path_intent: <relative-path>}`. Resolve them against the current repository root at the resource-owning boundary immediately before use.
- Keep normal non-audit wrapper calls without `--output-root` valid; they continue to use the fixed local output paths.
- Disable app-test build-product signing by default because `FlowTabTests` do not require a permission-bearing app identity.
- Treat local signing and sandbox failures as blockers, not as reasons to invent alternate commands.
- Report the attempted command, every allowed variation, and the outcome class. For audit work, keep non-secret argv and secret references in the private project-local evidence manifest, and publish only a redacted command ID/hash in Git-tracked reports.

## Fixed Workflow

1. Start from the repository root.
2. Run the canonical local wrapper from `validation-command-cookbook.md`.
   The wrapper owns the local unsigned app-test build path. Do not manually spell out an ad hoc `xcodebuild test` signing bypass in handoffs or scripts when this wrapper can be used.
3. Only these command changes are allowed:
   - Add a narrower `-only-testing:FlowTabTests/<ClassName>` or `-only-testing:FlowTabTests/<ClassName>/<testMethod>` while reproducing or iterating.
   - Use the wrapper's `build-for-testing` or `test-without-building` action when separating build and run phases.
   - For an audit attempt, add `--build-root <project-local-build-root> --output-root <not-yet-existing-attempt-directory>`. Both paths must resolve beneath the current project's ignored `./.build-local/` tree. Do not pre-create or reuse the output leaf; the wrapper creates it and rejects an existing path.
   - Pass a caller signing override only for an explicit signing investigation, not for normal validation.
4. For an audit attempt whose action runs tests, preserve `<attempt-directory>/results/FlowTabTests.xcresult`, `<attempt-directory>/logs/xcodebuild-<action>.log`, and `<attempt-directory>/status.json`. The wrapper preserves the raw xcodebuild and log-writer exit codes; evidence validation fails when a test action does not produce a result bundle. Inventory or checksum the attempt before starting another one.
   The committed-index search-pressure wrapper follows the same contract: its build and every repeated test batch receive distinct child `--output-root` leaves inside the pressure attempt, and `child-attempts.jsonl` maps those leaves to the retained child results and logs.
5. Use a raw `.xctestrun`, Xcode GUI-only evidence, hand-written `xcodebuild` command, or another scheme only when the user explicitly requests a separate experiment. Those paths can supplement an investigation, but they do not satisfy the required `FlowTabTests` validation layer.
6. If the wrapper fails because the local Xcode/macOS combination rejects unsigned hosted app tests, classify that as an app-test packaging blocker and update this workflow or wrapper instead of falling back to a one-off signing bypass.
7. Interpret outcomes by class:
   - Test assertion failure, crash, timeout, or thrown test error: report `FlowTabTests` as `failed` and use the failing test as evidence.
   - Compiler or linker error: report the app unit/behavior layer as `failed` at build/compile.
   - Missing certificate, invalid Team ID, keychain identity issue, provisioning/signing identity failure, or denied access to the signing identity when a caller explicitly requested signed app-test products: report the app unit/behavior layer as `blocked` by local signing setup.
   - Unsigned host rejection, bundle-loader identity mismatch, or test-host packaging failure on the wrapper path: report the app unit/behavior layer as `blocked` by local app-test packaging.
   - Sandbox denial for the resolved project-local build or evidence root: report the app unit/behavior layer as `blocked` by local sandbox access.
8. In a normal handoff, include the exact command attempted, the allowed variation used when applicable, and the outcome class from step 7. In an audit handoff, include the redacted command ID/hash and result while retaining non-secret argv and secret references in the private project-local evidence manifest.

## Reporting Shape

- App unit/behavior: `passed`, `failed`, or `blocked`.
- Command: include the exact command for normal work. For audit work, report the redacted command ID/hash and retain non-secret argv and secret references in the private project-local evidence manifest.
- Variation: state `none`, targeted `-only-testing`, or distinct before/after `-derivedDataPath`.
- Evidence root: for audit runs, retain the attempt-specific `--output-root`, result bundle, xcodebuild log, and `status.json` path intents in the private manifest; use a redacted archive token in tracked reports.
- Build root: retain `repository_root` as the resource boundary and the path below `./.build-local/` as the relative path intent; resolve it against the current project immediately before passing `--build-root`.
- Outcome class: use one of the classes from the fixed workflow.
- Blocker: for signing, packaging, or sandbox blockers, state what is missing or inaccessible without exposing private Team IDs.
