# Development manual

## Start here

Before changing `tool.git-project`:

1. read [../AGENTS.md](../AGENTS.md);
2. read [10-00-plan.md](10-00-plan.md);
3. identify which released capability owns the change;
4. read the relevant specification/design detail;
5. inspect the matching owner tests/workflow.

## Local ownership

The core Git path must remain usable with Git as its only external runtime
prerequisite. Python, Moon, Java, OpenSCAD and other runtimes may be used only
where the relevant optional capability or development test explicitly owns them.

Changes affecting local repository operations normally require parity between
PowerShell and POSIX shell implementations.

## Normal development loop

Use one scoped issue/branch/PR for a durable change.

Before merge:

- run the narrow owner tests for the changed capability;
- run/inspect the exact PR-head Actions suite;
- update documentation and `CHANGELOG.md` for contract-visible changes;
- keep generated/temporary test state out of source;
- merge only the qualified head revision.

After merge, verify the expected exact-main owner workflows.

## Public version points

`VERSION` is the released tool version.

Reusable workflows/actions are public cross-repository interfaces and must be
consumed from a released tag rather than moving `main`.

A release is prepared only after the complete released-capability gate described
in [50-00-verification.md](50-00-verification.md) is green on the exact current
main commit.

## Documentation and contract changes

When changing:

- project configuration → update [30-10-project-format.md](30-10-project-format.md) and its schema/tests;
- managed launchers → update [30-11-managed-consumer-launchers.md](30-11-managed-consumer-launchers.md);
- execution evidence → update [30-12-execution-evidence.md](30-12-execution-evidence.md) and schema fixtures;
- generated-output publication → update [30-13-generated-output-publication.md](30-13-generated-output-publication.md);
- generic release behavior → update [30-14-release-lifecycle.md](30-14-release-lifecycle.md);
- Moon behavior → update the matching [40 design details](40-00-design.md).

## Shared working conventions

Portfolio Git/PR/documentation conventions are owned by
[`brainboxemb.meta`](https://github.com/brainboxemb/brainboxemb.meta).
Repository-local rules here only add tool-specific constraints.
