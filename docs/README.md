# tool.git-project documentation

This directory is the documentation entrypoint for `tool.git-project`.

The tool provides domain-neutral repository mechanics: deterministic bootstrap
and dependency management, managed root launchers, generic repository lifecycle
workflows, optional Moon orchestration and shared repository contracts.

## Who should read what?

| Need | Start here |
| --- | --- |
| Current owner work | [10 — Plan](10-00-plan.md) |
| Contribute to this tool | [20-01 — Development](20-01-development.md) |
| Use the tool in a repository | [20-02 — User manual](20-02-user.md) |
| Understand supported behavior and contracts | [30 — Specification](30-00-specification.md) |
| Understand internal ownership/architecture | [40 — Design](40-00-design.md) |
| Understand release qualification and tests | [50 — Verification](50-00-verification.md) |

The root [README](../README.md) remains the GitHub-facing orientation page.
Exact schemas stay under `schemas/`; reusable Actions/workflows stay beside
their implementation and are linked from the relevant contract documentation.

Shared BrainboxEmb repository/documentation conventions live in
[`brainboxemb.meta`](https://github.com/brainboxemb/brainboxemb.meta).
