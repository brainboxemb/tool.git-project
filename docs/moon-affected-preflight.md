# Moon affected preflight

This work adds a generic host-side Moon preflight that determines whether a configured repository task is affected by an explicit VCS base/head range without executing producer commands.

The capability is domain-neutral. Domain tooling supplies the task to evaluate; `tool.git-project` owns Moon runtime/query mechanics only.

Implementation and qualification are tracked in issue/PR #21.
