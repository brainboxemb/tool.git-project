# Changelog

## Unreleased

### Changed

- Standardize repository documentation into numbered plan/manual/specification/design/verification families, retain `docs/README.md` as the GitHub directory landing page, and classify the existing project, launcher, publication, release, Moon and verification contracts under stable numbered paths.

## 0.2.12 — 2026-09-22

### Fixed

- Managed `bootstrap.*` / `update.*` launchers now enforce the committed `tools/tool.git-project` gitlink before mutating repository operations, so a stale initialized bootstrap worktree cannot silently execute an older tool revision.
- Dirty bootstrap-engine worktrees are refused rather than overwritten; read-only status reports stale/dirty/uninitialized bootstrap state without executing untrusted tool code.

### Changed

- Normal repository status includes an explicit `tool.git-project` bootstrap row with current SHA, parent gitlink, state and source-controlled version.


## 0.2.11 — 2026-09-22

### Changed

- Release test architecture is documented as stable capability contracts rather than historical issue checks, including the exact workflows required before an immutable tool release.
- GitHub Actions contract-test workflow filenames use the portfolio `test-<capability>.yml` convention so test workflows group naturally in repository listings.
- Current consumer documentation consistently names the managed root updater `update.ps1` / `update.sh`.

## 0.2.10 — 2026-09-22

### Added

- Managed root `bootstrap.*` and `update.*` launchers retain canonical source, source version and exact source revision metadata, with explicit local-patch declaration and drift warnings.
- Generic `role: tooling` dependencies may expose an optional `consumer/post-update.ps1|sh` hook so domain tools can extend repository update without replacing the generic root launcher.
- `refresh-launchers` provides the central Git-only refresh path for managed consumer launchers on Windows and POSIX.

### Changed

- Normal generic bootstrap/update checks managed launcher drift and refreshes unpatched copies from the exact pinned `tool.git-project` revision.


## 0.2.9 — 2026-09-21

### Added

- Controlled transitive traversal for owner-declared `role: external` Git submodules, including nested owner/path status through the normal update launcher on Linux and Windows.
- Owner regression coverage using independent root/nested pins of the same repository, nested tooling exclusion, dirty protection, uninitialized recovery, and unrelated-local-path preservation.

### Changed

- Consumed repositories keep their committed nested gitlinks authoritative; configured nested refs are validated without allowing an outer consumer to advance the owner's pin independently.
- `update-repo.sh` / `update-repo.ps1` now accept `status` for read-only direct plus nested closure reporting.

## 0.2.8 — 2026-09-15

### Added

- The released Moon affected action now exposes `affected-tasks`, a stable compact JSON array of fully-qualified affected Moon task IDs derived from the same single affected query as the existing boolean decision.
- Persistent `affected-task-ids.json` evidence alongside Moon's complete `affected-tasks.json` diagnostic output.
- Linux and native Windows owner coverage for zero, one and multiple affected tasks, plus conservative fallback with no falsely precise task list.

### Changed

- Preserve the existing `affected=true|false` compatibility contract while allowing domain tooling to select several coarse capabilities without rerunning Moon once per capability.
- Conservative query failures continue to return `affected=true`; the precise task list is `[]` and `decision.json.status=conservative` tells the domain layer to use its safe full scope.

## 0.2.7 — 2026-09-15

### Added

- Reusable `generated-output/publish` composite action for publishing an already prepared generated-output tree directly from the current host job on Linux or Windows.
- POSIX shell and PowerShell publisher entrypoints with the existing `dev/pr-N/<suffix>`, `prod/<suffix>`, and `rel/vX.Y.Z/<suffix>` branch contract.
- Direct same-job regression coverage for sequential publications, caller-worktree preservation, stale-source suppression, invalid/empty input rejection, Linux contract behavior, and native Windows publication.

### Changed

- The artifact-based `reusable-generated-output-publish.yml` workflow now checks out its own exact workflow revision and delegates branch materialization to the same composite publisher used by same-job callers.
- Generated-output staging now happens in a temporary Git repository rather than switching/cleaning the caller worktree, allowing multiple output families to publish sequentially in one job.
- Source freshness is still checked before staging and immediately before force-push; direct same-job callers own job-level serialization while the artifact-based wrapper retains its concurrency group.

## 0.2.6 — 2026-09-14

### Fixed

- Treat a requested aggregate Moon target as affected when Moon marks one of the tasks it would execute as affected, instead of checking only the aggregate task's direct inputs.
- Use Moon's own deep downstream graph propagation for aggregate affected decisions; no parallel dependency graph or domain-specific changed-path list is introduced.
- Preserve conservative `affected=true` behavior for missing revisions or query uncertainty while keeping README-only/unrelated changes unaffected.

### Changed

- Explicit base/head affected preflight documentation now uses the qualified minimal checkout: exact shallow/blobless head plus exact shallow base, with no requirement for full repository history when no merge-base or ancestry traversal is needed.
- Linux and native Windows regressions now cover direct affected tasks, aggregate propagation, README-only aggregate skips, composite-action packaging, and producer non-execution.

## 0.2.5 — 2026-09-14

### Added

- Generic Moon 2.5.4 affected preflight for explicit VCS base/head ranges without executing producer commands.
- Linux and native Windows wrappers plus released composite action `moon/affected` for lightweight host-side CI gates before expensive domain runtimes or containers.
- Persistent preflight decision/query evidence under `.moon/preflight`, separate from producer execution and Moon materialization evidence.
- Real Git/Moon regression coverage proving README-only changes are unaffected, task-input changes are affected, missing revisions fail conservative, and preflight never executes the fixture producer.

### Changed

- Moon orchestration CI now qualifies the affected/preflight contract on Linux and Windows in addition to normal execution/cache/hydration behavior.
- Domain consumers can gate expensive jobs from Moon's declared task inputs/graph instead of maintaining duplicate changed-file rules in GitHub Actions.

## 0.2.4 — 2026-09-14

### Added

- Normative `brainboxemb.execution-evidence` JSON Schema v1 for persistent producer execution evidence.
- Positive and negative contract fixtures covering tool-owned and project-owned producers, exact revisions, status/exit-code consistency, and extensible domain-owned fields.
- `docs/execution-evidence.md` describing the standard `evidence/executions/<execution-id>/` layout and the producer-evidence versus current-materialization boundary.
- Dedicated schema/fixture CI validation using a pinned JSON Schema implementation as development tooling only.

### Changed

- Release gating now requires the execution-evidence schema test on the exact `main` release commit.
- `AGENTS.md` records the generic schema ownership boundary while keeping creation of real execution evidence with domain/project owners and keeping the Git-only core free of new runtime prerequisites.

## 0.2.3 — 2026-09-14

### Fixed

- Make Linux Moon runtime bootstrap portable to minimal containers that provide `tar` but not the external `xz` executable by falling back to Python 3 `lzma`/`tarfile` extraction.
- Preserve SHA-256 verification before extraction and report a precise prerequisite error when neither `xz` nor Python 3 with `lzma` support is available.
- Add Linux regression coverage that deliberately removes `xz` from the bootstrap `PATH`.

## 0.2.2 — 2026-09-13

### Fixed

- Accept valid single-digit pull-request numbers in generic `dev/pr-<N>/<suffix>` preview cleanup safety validation.
- Replace the ambiguous shell glob guard with an explicit branch regex after the PR number and suffix have been independently validated.
- Add owner cleanup regression coverage using PR `4` so single-digit preview deletion and protected-branch safety are both exercised.

## 0.2.1 — 2026-09-13

### Fixed

- Correctly detect committed but uninitialized dependency gitlinks instead of mistaking the parent repository for the dependency worktree.
- Initialize those dependency submodules before resolving declared release refs on Linux and native Windows.
- Report committed but uninitialized dependency gitlinks accurately in status output.
- Add Linux/native-Windows regression coverage matching a fresh consumer checkout with both the bootstrap-tool gitlink and dependency gitlink deinitialized.

## 0.2.0 — 2026-09-13

### Added

- Optional Moon `2.5.4` repository-orchestration companion for Linux and native Windows, with source-controlled download URLs and SHA-256 verification.
- `moon-project.sh` / `moon-project.ps1` commands for pinned runtime bootstrap, Moon configuration validation, portable cache-path discovery, and named task invocation.
- Composite `moon/action.yml` for released cross-repository consumption with separate pinned-runtime cache and portable Moon `hashes` / `outputs` cache restore/save.
- Current invocation/materialization evidence (`moon.log` + `materialization.json`) while preserving domain producer evidence inside declared task outputs.
- Compact Linux/Windows owner regression covering the production wrappers against the already-qualified cold/cache-hit/local-hydration/fresh-hydration/invalidation contract.
- `docs/moon-orchestration.md` describing the production ownership boundary and performance-first consumer contract.

### Changed

- Moon-capable GitHub jobs use blobless full-history checkout so Moon has correct VCS/affected information without eagerly downloading all repository blobs.
- The release gate now requires the Moon production-orchestration workflow on the exact `main` release commit.
- `AGENTS.md` explicitly keeps ordinary Git bootstrap/status/update Moon-free and treats faster build/release feedback as the reason for the optional orchestration layer.

### Performance intent

- Avoid unnecessary domain builds on unchanged inputs.
- Restore reusable outputs/evidence on fresh CI runners through Moon's portable cache.
- Cache the pinned Moon runtime independently so repeated CI runs avoid runtime-download overhead.
- Keep Maven, SCons and other domain engines authoritative instead of duplicating their internal lifecycle work in the repository orchestrator.

## 0.1.3 — 2026-09-13

### Fixed

- Prevent older pull-request or `main` workflow runs from force-pushing stale generated output over a newer `dev/pr-N/<suffix>` or `prod/<suffix>` publication.
- Re-check the current source revision immediately before publication and again immediately before the generated-branch force-push; stale runs now finish successfully without publishing.

### Changed

- Serialize generated-output publication per repository, source context, and output suffix with an Actions concurrency group.
- Extend generated-output self-test coverage with an explicit stale-publication case that proves stale output is not materialized.

## 0.1.2 — 2026-09-13

### Added

- Generic reusable repository release lifecycle for:
  - release-request branch parsing;
  - exact main-SHA/version/CHANGELOG validation;
  - optional successful-main-workflow gates;
  - annotated tag creation;
  - optional tagged verification dispatch/wait;
  - optional generic GitHub Release creation;
  - release-request branch cleanup.
- Side-effect-free dry-run workflow coverage so the reusable contract is exercised on pull requests and `main` without creating a tag, dispatching verification, creating a Release, or deleting refs.

### Changed

- `tool.git-project` now uses the same reusable release lifecycle for its own releases instead of maintaining a separate release implementation.
- Domain tools can keep only their domain-specific tagged verification, provenance and release assets while delegating generic repository release mechanics here.

## 0.1.1 — 2026-09-13

### Added

- Generic generated-output publication workflow for the shared repository lifecycle:
  - pull request #N -> `dev/pr-N/<suffix>`;
  - `main` -> `prod/<suffix>`;
  - release tag `vX.Y.Z` -> `rel/vX.Y.Z/<suffix>`.
- Event-context publication self-test that materializes a disposable generated branch, verifies its content, and removes it again.
- Release-gate proof that dispatches the publication test on the newly created release tag before publishing the GitHub Release.

### Changed

- Generated-output publication is now repository-generic and accepts the prepared Actions artifact plus branch suffix from the domain owner.
- Java remains responsible for preparing `bld` output; SCAD/docs can adopt the same branch-materialization primitive later without moving domain build logic into this repository.

## 0.1.0 — 2026-09-13

### Added

- Generic reusable PR-preview cleanup workflow for `dev/pr-<N>/<suffix>` branches.
- Optional same-repository merged source-branch cleanup while protecting default, `prod/*`, release and arbitrary refs.
- Source-controlled `VERSION` and guarded release workflow for reusable cross-repository interfaces.
- Linux and Windows owner self-tests plus live temporary-ref cleanup evidence.

### Fixed

- Protect dirty dependency worktrees before switching a committed gitlink during bootstrap/update on both Linux and Windows.

### Changed

- Cross-repository reusable workflows/actions are production interfaces; release/tag them before external consumption.
