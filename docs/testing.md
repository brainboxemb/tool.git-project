# Test architecture

`tool.git-project` is a released multi-interface repository. One release tag
publishes the generic Git core together with reusable repository workflows,
composite actions, Moon integration and the execution-evidence schema.

Tests therefore protect **released capability contracts**, not individual issues.
Historical incidents may explain why a contract exists, but durable test names,
step names and documentation describe the invariant that must remain true.

## Release qualification policy

A release is created only from the exact current `main` commit after every
released capability suite listed below has succeeded for that commit.

This is intentionally broader than the code changed by one patch. The same
immutable tag exposes all listed public interfaces, so release qualification
checks the complete released surface once before tagging.

Ordinary pull-request feedback may be optimized separately in the future. Such
optimization must not weaken exact-release qualification.

| Capability | Released surface | Contract workflow | Platform / environment | Release gate |
| --- | --- | --- | --- | --- |
| Generic Git core and managed launchers | `git-project.ps1`, `git-project.sh`, `bootstrap.*`, `update.*` | `test-self.yml` | Linux + native Windows | yes |
| PR preview cleanup | `reusable-pr-preview-cleanup.yml` | `test-pr-preview-cleanup.yml` | GitHub repository integration | yes |
| Artifact-based generated-output publication | `reusable-generated-output-publish.yml` | `test-generated-output-publish.yml` | GitHub repository integration | yes |
| Same-job generated-output publication | `generated-output/publish/action.yml` plus native publisher scripts | `test-generated-output-same-job.yml` | Linux + native Windows + GitHub integration | yes |
| Generic release lifecycle | `reusable-release.yml` | `test-release-lifecycle.yml` | GitHub Actions dry-run contract | yes |
| Moon affected/execution/cache integration | `moon/affected/action.yml`, `moon/action.yml`, native Moon wrappers | `test-moon-orchestration.yml` | Linux + native Windows | yes |
| Execution-evidence schema | `schemas/execution-evidence.schema.json` | `test-execution-evidence-schema.yml` | schema validation + positive/negative fixtures | yes |

The list above mirrors `.github/workflows/release.yml`. Adding or removing a
released capability requires reviewing both the release gate and this document.

## Core Git contract

`test-self.yml` proves the repository-maintenance contract from a consumer
checkout rather than merely invoking internal helper functions.

Stable assertions include:

- the bootstrap gitlink can restore the exact pinned `tool.git-project`;
- declared direct dependencies resolve to their configured refs;
- `bootstrap.*` and `update.*` remain Git-only entrypoints;
- repeated update is idempotent;
- status is read-only;
- dirty dependencies block destructive movement;
- managed launcher provenance drift is visible;
- a declared local launcher patch is preserved rather than overwritten;
- controlled transitive `role: external` closure is restored and reported;
- nested owner-local tooling is not recursively initialized;
- Linux and native Windows expose the same contract.

The test may contain many assertions because they belong to one user-facing
repository-maintenance capability. Assertions should not be named after the
issue that first exposed them.

## Lifecycle capability contracts

### PR preview cleanup

The cleanup suite proves that only the requested
`dev/pr-<positive-integer>/<validated-suffix>` namespace is removed and that
protected/unrelated refs remain untouched.

A particular PR number used by a fixture is test data, not the specification.

### Generated-output publication

The publication suites prove the stable branch mapping, exact-source freshness,
same-repository pull-request boundary, isolated staging, non-empty/safe input
validation and stale-writer suppression.

The artifact-based workflow and same-job composite action share publication
semantics but have different transport/job-boundary contracts, so both remain
separately qualified.

### Generic release lifecycle

The release lifecycle suite proves request parsing, exact release-SHA and
version validation, workflow-gate handling and side-effect-free dry-run
behavior. It does not manufacture domain release assets.

### Moon integration

The Moon suite protects the optional orchestration interface: pinned runtime,
affected selection, conservative fallback, cache/hydration behavior and current
materialization evidence on Linux and Windows.

It does not test Java, SCAD or documentation build semantics.

### Execution-evidence schema

The schema suite proves that the published JSON Schema accepts valid generic
producer evidence and rejects invalid contract fixtures. Python/jsonschema is
CI-only validation tooling and is not a consumer prerequisite.

## Test wording policy

Durable tests describe production invariants:

- prefer `positive PR identifier is accepted` over `single-digit bug fixed`;
- prefer `declared local patch is preserved` over an issue-specific marker;
- prefer capability names and expected behavior over issue or migration numbers.

Issue links and historical details belong in pull requests, issues and
`CHANGELOG.md`, not in the long-lived test contract.

## Fixture policy

The generic tool must not interpret domain configuration or execute domain
build logic.

Some current integration fixtures use immutable commits from existing
brainboxemb tooling/library repositories as opaque Git repositories. Those refs
are reproducible and useful for cross-repository integration evidence, but they
also create avoidable coupling.

The preferred long-term core fixture is self-contained synthetic Git repositories
created by the test suite itself. Replacing named domain repositories with
synthetic Git fixtures is a test-maintenance optimization; it must preserve the
same generic dependency and transitive-closure assertions.
