# Changelog

## Unreleased

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
- Composite `moon/action.yml` for released cross-repository consumption with separate pinned-runtime cache and portable Moon `hashes`/`outputs` cache restore/save.
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
- Side-effect-free dry-run workflow coverage so the reusable release contract is exercised on pull requests and `main` without creating tags or releases.

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

- Cross-repository reusable workflows are consumed from deliberate released tags instead of moving `main`.
