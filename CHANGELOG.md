# Changelog

## Unreleased

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

- Domain tools now only need to produce their prepared output bundle and declare the suffix they own; generic branch materialization stays in `tool.git-project`.

## 0.1.0 — 2026-09-13

### Added

- Generic `project.yml` contract for project metadata, profile references, and Git dependencies.
- PowerShell and POSIX `validate`, `bootstrap`, `status`, and `update` commands.
- Git-submodule registration, synchronisation, pinned-ref checkout, clean-state protection, and local status reporting.
- Consumer bootstrap/update launcher templates.
- Generic fixture and Windows/Linux self-test workflow.
- Reusable PR-preview branch cleanup for generated `dev/pr-<N>/<suffix>` branches, with optional merged source-branch cleanup.
- Tagged/released workflow baseline so reusable GitHub workflows are consumed from immutable tool releases rather than moving `main`.
