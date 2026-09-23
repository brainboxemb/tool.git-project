# Design

## Responsibility layers

`tool.git-project` deliberately separates generic repository behavior from
domain behavior:

```text
consumer repository
        |
        +-- committed bootstrap gitlink
        |     tools/tool.git-project
        |
        +-- project.yml
        |     generic dependency/profile intent
        |
        v
tool.git-project
  Git bootstrap / status / update
  managed launchers
  generic lifecycle workflows
  optional repository orchestration
        |
        v
domain tool / project producer
  Java / SCAD / docs / product semantics
```

## Core versus optional orchestration

The Git core owns deterministic repository state and requires Git only.

Moon is an explicit optional orchestration layer. It may provide affected
selection, task invocation, runtime/cache handling and materialization evidence,
but Moon remains the scheduler/hasher/cache owner and domain tools remain
authoritative for producer semantics.

## Design details

- [40-10 — Moon repository orchestration](40-10-moon-orchestration.md)
- [40-11 — Moon affected preflight](40-11-moon-affected-preflight.md)

Public data/interface contracts are intentionally kept in the
[30 specification family](30-00-specification.md), not duplicated here.

## Safety principles

- never overwrite dirty dependency worktrees;
- never silently advance the parent bootstrap gitlink;
- keep read-only status free from mutation/network fetch;
- release reusable cross-repository interfaces before consumers adopt them;
- keep domain-specific implementation out of the generic tool.
