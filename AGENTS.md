# Agent guidance

## Purpose

`tool.git-project` contains reusable **Git repository dependency tooling**. Keep it independent from Java, SCAD, documentation generation, deployment targets, and product/domain behaviour.

## Core boundary

The tool may understand generic concepts such as:

- project metadata;
- profile references;
- dependency name/role/type/url/path/ref;
- Git submodules and gitlinks;
- clean/dirty dependency state;
- pinned commit/tag/branch resolution;
- bootstrap/status/update operations.

It must not interpret the contents of `project.java.yml`, `project.scad.yml`, or future profile-specific configuration files.

## Compatibility

- Windows PowerShell and POSIX shell are first-class local environments.
- Do not make Python, Docker, Java, Maven, OpenSCAD, or another language runtime a prerequisite for basic Git bootstrap/update operations.
- Git is the only intended external runtime prerequisite for the core tool.

## Safety

- Never discard local changes in a dependency.
- Refuse update/checkout when a dependency worktree is dirty.
- Do not silently stage or commit parent-repository gitlink changes.
- Do not follow a moving dependency merely because `main` changed; the configured `ref` controls desired state.
- Prefer full commit SHAs or stable tags for reproducible projects.

## Configuration

`project.yml` is the generic source of dependency intent. Keep the supported YAML subset deliberately simple enough that the bootstrap scripts can parse it without adding a YAML runtime dependency.

When extending the format, update:

- both PowerShell and shell implementations;
- `schemas/project.schema.json`;
- `docs/project-format.md`;
- fixture/self-tests.

## Pull requests

Use one work-item number end to end:

1. create issue `#N` to reserve the work number;
2. create `feature/pr-N-<short-slug>` from the intended target branch;
3. make the smallest initial commit on that branch;
4. convert that exact issue directly into draft PR `#N`;
5. continue implementation, self-test/evidence and review in that same PR;
6. merge only after the scoped evidence is complete.

Do not create a separate pull request with a new number for the same work item when issue conversion is available. Keep changes scoped and prove Windows and Linux behaviour where the change affects local tooling.
