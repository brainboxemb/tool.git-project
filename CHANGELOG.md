# Changelog

## Unreleased

## 0.1.0 — 2026-09-13

### Added

- Generic `project.yml` contract for project metadata, profile references, and Git dependencies.
- PowerShell and POSIX `validate`, `bootstrap`, `status`, and `update` commands.
- Git-submodule registration, synchronisation, pinned-ref checkout, clean-state protection, and local status reporting.
- Consumer bootstrap/update launcher templates.
- Generic fixture and Windows/Linux self-test workflow.
- Reusable PR-preview branch cleanup for generated `dev/pr-<N>/<suffix>` branches, with optional merged source-branch cleanup.
- Tagged/released workflow baseline so reusable GitHub workflows are consumed from immutable tool releases rather than moving `main`.
