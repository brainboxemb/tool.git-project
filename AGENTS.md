# Agent guidance

## Purpose

`tool.git-project` contains reusable **generic repository tooling**. Its core remains Git dependency/bootstrap tooling; it may also provide optional repository-level lifecycle and Moon orchestration integration. Keep it independent from Java, SCAD, documentation-generation, deployment-target and product/domain behaviour.

## Core boundary

The Git core may understand generic concepts such as:

- project metadata;
- profile references;
- dependency name/role/type/url/path/ref;
- Git submodules and gitlinks;
- clean/dirty dependency state;
- pinned commit/tag/branch resolution;
- bootstrap/status/update operations;
- generic generated-output/release lifecycle operations.

The optional Moon integration may own only generic repository-orchestration concerns:

- the approved/pinned Moon runtime;
- validation/invocation wrappers around Moon's own configuration;
- portable Moon cache restore/save conventions;
- generic current invocation/materialization evidence.

It must not interpret the contents of `project.java.yml`, `project.scad.yml`, or future profile-specific configuration files. It must not implement a scheduler, hasher, affected-selection engine or output cache that duplicates Moon.

## Performance intent

The Moon integration exists to make build and release feedback faster. Prefer changes that reduce unnecessary domain execution, improve reusable cache/hydration on fresh runners, or reduce orchestration overhead.

Do not add orchestration complexity merely for architectural symmetry. Keep domain tasks coarse enough that Maven, SCons and other domain engines retain their own internal dependency/lifecycle logic.

## Compatibility

- Windows PowerShell and POSIX shell are first-class local environments.
- Do not make Python, Docker, Java, Maven, OpenSCAD, Moon, or another language/runtime a prerequisite for basic Git bootstrap/update operations.
- Git is the only intended external runtime prerequisite for the core Git tool.
- Moon is an explicit opt-in companion capability and must remain separately invokable/cacheable.

## Safety

- Never discard local changes in a dependency.
- Refuse update/checkout when a dependency worktree is dirty.
- Do not silently stage or commit parent-repository gitlink changes.
- Do not follow a moving dependency merely because `main` changed; the configured `ref` controls desired state.
- Prefer full commit SHAs or stable tags for reproducible projects.
- Reusable cross-repository workflows/actions are production interfaces; release/tag them before external consumption.

## Configuration

`project.yml` is the generic source of dependency intent. Keep the supported YAML subset deliberately simple enough that the bootstrap scripts can parse it without adding a YAML runtime dependency.

Moon orchestration uses Moon's own `.moon/workspace.yml` and `moon.yml` configuration. Do not invent a parallel generic task-graph format unless a concrete Moon limitation first requires one.

When extending the generic Git format, update:

- both PowerShell and shell implementations;
- `schemas/project.schema.json`;
- `docs/project-format.md`;
- fixture/self-tests.

When extending the Moon integration, preserve Linux/Windows parity and the producer-evidence versus current-materialization-evidence distinction described in `docs/moon-orchestration.md`.

## Pull requests

Use one work-item number end to end:

1. create issue `#N` to reserve the work number;
2. create `feature/pr-N-<short-slug>` from the intended target branch;
3. make the smallest initial commit on that branch;
4. convert that exact issue directly into draft PR `#N`;
5. continue implementation, self-test/evidence and review in that same PR;
6. merge only after the scoped evidence is complete.

Do not create a separate pull request with a new number for the same work item when issue conversion is available. Keep changes scoped and prove Windows and Linux behaviour where the change affects local tooling.
