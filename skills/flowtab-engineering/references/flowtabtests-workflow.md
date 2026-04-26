# FlowTabTests Workflow

Use this reference whenever `FlowTabTests` are required, attempted, narrowed, reported, or blocked. This workflow is the authoritative path for app unit and in-process behavior tests.

## Required Outcome

- Run `FlowTabTests` through `./scripts/testing/run-flowtabtests-local.sh`.
- Keep app-test build products, caches, temp files, and HOME under `./.build-local/app-tests`.
- Disable app-test build-product signing by default because `FlowTabTests` do not require a permission-bearing app identity.
- Treat local signing and sandbox failures as blockers, not as reasons to invent alternate commands.
- Report the exact command attempted, any allowed variation, and the outcome class.

## Fixed Workflow

1. Start from the repository root.
2. Run the canonical local wrapper from `validation-command-cookbook.md`.
   The wrapper owns the local unsigned app-test build path. Do not manually spell out an ad hoc `xcodebuild test` signing bypass in handoffs or scripts when this wrapper can be used.
3. Only these command changes are allowed:
   - Add a narrower `-only-testing:FlowTabTests/<ClassName>` or `-only-testing:FlowTabTests/<ClassName>/<testMethod>` while reproducing or iterating.
   - Use the wrapper's `build-for-testing` or `test-without-building` action when separating build and run phases.
   - Pass a caller signing override only for an explicit signing investigation, not for normal validation.
5. Do not replace this flow with a raw `.xctestrun`, Xcode GUI-only evidence, hand-written `xcodebuild` commands, or a different scheme unless the user explicitly asks for a separate experiment. Those can supplement investigation, but they do not satisfy the required `FlowTabTests` validation layer.
6. If the wrapper fails because unsigned hosted app tests are not accepted on the local Xcode/macOS combination, treat that as an app-test packaging blocker and update this workflow/script rather than falling back to one-off signing bypasses.
7. Interpret outcomes by class:
   - Test assertion failure, crash, timeout, or thrown test error: report `FlowTabTests` as failed and use the failing test as evidence.
   - Compiler or linker error: report the app unit/behavior layer as failed at build/compile.
   - Missing certificate, invalid team id, keychain identity issue, provisioning/signing identity failure, or permission to access the signing identity when a caller explicitly requested signed app-test products: report the app unit/behavior layer as blocked by local signing setup.
   - Unsigned host rejection, bundle loader identity mismatch, or test host packaging failure on the wrapper path: report the app unit/behavior layer as blocked by local app-test packaging.
   - Sandbox denial for repository-local `./.build-local` paths: report the app unit/behavior layer as blocked by local sandbox access.
8. In the handoff, include the exact command attempted, the allowed variation used if any, and the outcome class from step 7.

## Reporting Shape

- App unit/behavior: `passed`, `failed`, or `blocked`.
- Command: include the exact command attempted.
- Variation: state `none`, targeted `-only-testing`, or distinct before/after `-derivedDataPath`.
- Outcome class: use one of the classes in the fixed workflow.
- Blocker: for signing, packaging, or sandbox blockers, state what is missing or inaccessible without exposing private team ids.
