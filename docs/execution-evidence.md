# Persistent producer execution evidence

`tool.git-project` owns the domain-neutral contract for persistent producer execution evidence. Domain tools and project-owned producers remain responsible for creating evidence for their own real executions.

This contract is independent of Moon. Moon may execute or hydrate producer output, but producer evidence must remain meaningful when the same domain action is run directly.

## Standard location

A persistent generated-output snapshot stores one directory per independently useful producer/capability execution:

```text
evidence/executions/<execution-id>/
  execution.json
  execution.log
```

`<execution-id>` is a stable repository/domain identifier. It does not need to equal a Moon task name.

Graph-only aggregation tasks and publication side effects are not producer executions merely because they are visible in orchestration.

## Normative schema

The machine-readable contract is:

```text
schemas/execution-evidence.schema.json
```

Schema identity:

```text
brainboxemb.execution-evidence
schema_version = 1
```

Required fields:

- `capability` — stable repository-level capability represented by the execution;
- `owner` — repository/tool that owns the action semantics;
- `action` — stable owner action or project-owned producer action;
- `source_revision` — exact source revision used by the producer execution;
- `owner_revision` — exact Git revision providing the action semantics;
- `status` — `success` or `failure`;
- `exit_code` — `0` for success and non-zero for failure;
- `log` — relative path from `execution.json` to the retained human-readable producer log;
- `domain_evidence` — zero or more relative paths to richer retained domain evidence.

For a project-owned producer, `owner_revision` normally equals `source_revision`. For a reusable owner tool such as `tool.java-project` or `tool.scad-project`, it is the exact checked-out tool revision that supplied the action semantics.

The schema permits additional domain-owned fields. Generic consumers must not depend on those additions.

## Producer evidence versus orchestration evidence

Producer evidence and current materialization evidence describe different facts.

Producer evidence answers what actually ran and produced the retained output. It belongs inside the cacheable/hydratable producer result and must not be rewritten later.

Current Moon invocation/materialization evidence remains separate:

```text
orchestration/
  materialization.json
  moon.log
```

`materialization.json` identifies the current orchestration invocation and source revision. `moon.log` retains Moon's human-readable task-level execute/cache/hydration result.

A cached producer may therefore legitimately retain an older equivalent `source_revision` while current orchestration evidence identifies the newer revision for which that output was hydrated.

## Domain evidence remains domain-owned

The common execution envelope is an entrypoint, not a replacement for rich evidence. Examples include:

- SCAD/SCons target and cache decision reports;
- Maven Surefire XML/TXT and readable test summaries;
- engineering-document generation/validation details;
- toolchain/runtime provenance.

`domain_evidence` links the execution envelope to those retained reports without flattening their semantics into the generic schema.

## Publication rule

Publication/finalization consumes already produced or hydrated output. It may add current publication/materialization context, but it must not synthesize a successful producer execution after hydration or rewrite producer revisions to the publication revision.

## Validation and portability

The schema and fixtures are production interfaces released with `tool.git-project`.

Repository self-tests use a pinned JSON Schema implementation to prove the schema and positive/negative fixtures. This validator is CI development tooling only; ordinary Git bootstrap/update operations and consumers of the schema do **not** acquire a Python or JSON-Schema runtime prerequisite.

A future generic runtime validator/helper may be added only with an explicit dependency and portability contract. The schema itself remains the normative interface.
