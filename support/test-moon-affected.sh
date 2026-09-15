#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
INSTALL_ROOT="$TEMP_ROOT/moon-runtime"
REPO="$TEMP_ROOT/repo"
RESULTS="$ROOT/moon-test-results"

cleanup() {
  rm -rf "$TEMP_ROOT"
  rm -f "$ROOT/.moon/preflight"/*.json "$ROOT/.moon/preflight"/*.log 2>/dev/null || true
}
trap cleanup EXIT

count_executions() {
  local repo="$1"
  local file="$repo/fixture/moon/.executions/count.txt"
  if [[ -f "$file" ]]; then tr -d '\r\n' < "$file"; else printf '0\n'; fi
}

assert_decision() {
  local evidence="$1" expected_affected="$2" expected_status="$3"
  grep -F "\"affected\": $expected_affected" "$evidence/decision.json" >/dev/null
  grep -F "\"status\": \"$expected_status\"" "$evidence/decision.json" >/dev/null
}

assert_task_ids() {
  local evidence="$1" expected="$2" actual
  actual="$(tr -d '\r\n' < "$evidence/affected-task-ids.json")"
  [[ "$actual" == "$expected" ]] || {
    echo "Unexpected affected task list in $evidence" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  }
}

cd "$ROOT"
git clone --quiet --no-hardlinks "$ROOT" "$REPO"
git -C "$REPO" config user.email 'moon-affected-test@example.invalid'
git -C "$REPO" config user.name 'Moon affected test'

moon_bin="$(MOON_INSTALL_ROOT="$INSTALL_ROOT" bash "$ROOT/moon-project.sh" bootstrap --install-root "$INSTALL_ROOT")"
export MOON_BIN="$moon_bin"

base_revision="$(git -C "$REPO" rev-parse HEAD)"

printf '\nREADME-only preflight fixture change.\n' >> "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit --quiet -m 'Test README-only affected decision'
docs_revision="$(git -C "$REPO" rev-parse HEAD)"

docs_evidence="$REPO/.moon/preflight/docs"
docs_result="$(bash "$ROOT/moon-affected.sh" fixture:cache.fixture --repo "$REPO" --base "$base_revision" --head "$docs_revision" --install-root "$INSTALL_ROOT" --evidence-dir "$docs_evidence")"
[[ "$docs_result" == "false" ]]
[[ "$(count_executions "$REPO")" == "0" ]]
assert_decision "$docs_evidence" false success
assert_task_ids "$docs_evidence" '[]'

aggregate_docs_evidence="$REPO/.moon/preflight/aggregate-docs"
aggregate_docs_result="$(bash "$ROOT/moon-affected.sh" fixture:cache.aggregate --repo "$REPO" --base "$base_revision" --head "$docs_revision" --install-root "$INSTALL_ROOT" --evidence-dir "$aggregate_docs_evidence")"
[[ "$aggregate_docs_result" == "false" ]]
[[ "$(count_executions "$REPO")" == "0" ]]
assert_decision "$aggregate_docs_evidence" false success
assert_task_ids "$aggregate_docs_evidence" '[]'

printf '\nrelevant committed preflight change\n' >> "$REPO/fixture/moon/input.txt"
git -C "$REPO" add fixture/moon/input.txt
git -C "$REPO" commit --quiet -m 'Test affected task input decision'
input_revision="$(git -C "$REPO" rev-parse HEAD)"

input_evidence="$REPO/.moon/preflight/input"
input_result="$(bash "$ROOT/moon-affected.sh" fixture:cache.fixture --repo "$REPO" --base "$docs_revision" --head "$input_revision" --install-root "$INSTALL_ROOT" --evidence-dir "$input_evidence")"
[[ "$input_result" == "true" ]]
[[ "$(count_executions "$REPO")" == "0" ]]
assert_decision "$input_evidence" true success
assert_task_ids "$input_evidence" '["fixture:cache.aggregate","fixture:cache.fixture"]'

aggregate_evidence="$REPO/.moon/preflight/aggregate"
aggregate_result="$(bash "$ROOT/moon-affected.sh" fixture:cache.aggregate --repo "$REPO" --base "$docs_revision" --head "$input_revision" --install-root "$INSTALL_ROOT" --evidence-dir "$aggregate_evidence")"
[[ "$aggregate_result" == "true" ]]
[[ "$(count_executions "$REPO")" == "0" ]]
assert_decision "$aggregate_evidence" true success
assert_task_ids "$aggregate_evidence" '["fixture:cache.aggregate","fixture:cache.fixture"]'
grep -F '"fixture:cache.aggregate": {' "$aggregate_evidence/affected-tasks.json" >/dev/null
grep -F '"upstream": [' "$aggregate_evidence/affected-tasks.json" >/dev/null
grep -F '"fixture:cache.fixture"' "$aggregate_evidence/affected-tasks.json" >/dev/null

printf '\none independent affected task\n' >> "$REPO/fixture/moon/independent.txt"
git -C "$REPO" add fixture/moon/independent.txt
git -C "$REPO" commit --quiet -m 'Test one affected task decision'
independent_revision="$(git -C "$REPO" rev-parse HEAD)"

independent_evidence="$REPO/.moon/preflight/independent"
independent_result="$(bash "$ROOT/moon-affected.sh" fixture:cache.independent --repo "$REPO" --base "$input_revision" --head "$independent_revision" --install-root "$INSTALL_ROOT" --evidence-dir "$independent_evidence")"
[[ "$independent_result" == "true" ]]
[[ "$(count_executions "$REPO")" == "0" ]]
assert_decision "$independent_evidence" true success
assert_task_ids "$independent_evidence" '["fixture:cache.independent"]'

conservative_evidence="$REPO/.moon/preflight/conservative"
conservative_result="$(bash "$ROOT/moon-affected.sh" fixture:cache.fixture --repo "$REPO" --base 'refs/heads/does-not-exist' --head "$independent_revision" --install-root "$INSTALL_ROOT" --evidence-dir "$conservative_evidence")"
[[ "$conservative_result" == "true" ]]
[[ "$(count_executions "$REPO")" == "0" ]]
assert_decision "$conservative_evidence" true conservative
assert_task_ids "$conservative_evidence" '[]'

mkdir -p "$RESULTS"
cat > "$RESULTS/linux-affected.json" <<EOF
{
  "platform": "linux-x86_64",
  "moon_version": "2.5.4",
  "checks": {
    "readme_only_unaffected": true,
    "zero_affected_task_list": true,
    "one_affected_task_list": true,
    "multiple_affected_task_list": true,
    "task_input_affected": true,
    "aggregate_upstream_affected": true,
    "aggregate_readme_only_unaffected": true,
    "query_does_not_execute_producer": true,
    "missing_revision_fails_conservative": true,
    "conservative_task_list_empty": true,
    "explicit_base_head": true,
    "moon_graph_propagation": true
  }
}
EOF

printf 'PASS Moon affected preflight on Linux\n'
