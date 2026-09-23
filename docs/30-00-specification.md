# Specification

## Why this tool exists

Engineering repositories need common repository mechanics regardless of whether
their actual implementation uses Java, SCAD, documentation tooling or another
domain.

`tool.git-project` centralizes those generic mechanics so domain tools and
projects do not each maintain their own bootstrap, dependency, publication and
release infrastructure.

## Typical users

The primary users are repository maintainers and domain tools.

A normal end user of a product should not need to know this tool exists.

## Why use it

Use this tool when behavior is genuinely repository-generic, for example:

- deterministic dependency bootstrap/status/update;
- managed root bootstrap/update launchers;
- generic project/dependency metadata;
- repository-safe generated-output publication;
- generic release/tag lifecycle;
- domain-neutral execution evidence;
- optional repository-level Moon orchestration.

## Non-goals

The tool does not own:

- Java/Maven lifecycle semantics;
- OpenSCAD/SCons semantics;
- documentation rendering;
- product-specific build or release behavior;
- domain-specific configuration contents;
- an alternative scheduler/hasher/cache that duplicates Moon.

The core Git path must remain Git-only.

## Public contract details

- [30-10 — Generic project configuration](30-10-project-format.md)
- [30-11 — Managed consumer launchers](30-11-managed-consumer-launchers.md)
- [30-12 — Persistent producer execution evidence](30-12-execution-evidence.md)
- [30-13 — Generated output publication](30-13-generated-output-publication.md)
- [30-14 — Generic release lifecycle](30-14-release-lifecycle.md)

Optional orchestration architecture is documented under the
[40 design family](40-00-design.md).
