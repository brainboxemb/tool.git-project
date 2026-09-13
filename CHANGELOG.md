# Changelog

## Unreleased

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
