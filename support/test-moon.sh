#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="$(mktemp -d)/moon-runtime"
FRESH_PARENT=""
FRESH=""
RESULTS="$ROOT/moon-test-results"

now_ms() {
  local value
  value="$(date +%s%3N 2>/dev/null || true)"
  if [[ "$value" =~ ^[0-9]+$ ]]; then printf '%s\n' "$value"; else printf '%s000\n' "$(date +%s)"; fi
}

count_executions() {
  local repo="$1" file="$repo/fixture/moon/.executions/count.txt"
  if [[ -f "$file" ]]; then tr -d '\r\n' < "$file"; else printf '0\n'; fi
}

cleanup() {
  rm -rf "$ROOT/fixture/moon/out" "$ROOT/fixture/moon/.executions" "$ROOT/.moon/cache" "$ROOT/.moon/invocations"
  if [[ -n "$FRESH" ]]; then git -C "$ROOT" worktree remove --force "$FRESH" >/dev/null 2>&1 || true; fi
  [[ -n "$FRESH_PARENT" ]] && rm -rf "$FRESH_PARENT"
  rm -rf "$(dirname "$INSTALL_ROOT")"
}
trap cleanup EXIT

cd "$ROOT"

# The existing repository/dependency path must remain completely independent from Moon.
bash ./git-project.sh validate --repo fixture >/dev/null

start_ms="$(now_ms)"
moon_bin="$(MOON_INSTALL_ROOT="$INSTALL_ROOT" bash ./moon-project.sh bootstrap)"
end_ms="$(now_ms)"
bootstrap_ms=$((end_ms - start_ms))
export MOON_BIN="$moon_bin"

bash ./moon-project.sh validate --repo . --install-root "$INSTALL_ROOT" >/dev/null
mapfile -t cache_paths < <(bash ./moon-project.sh cache-paths --repo .)
[[ "${cache_paths[0]}" == "$ROOT/.moon/cache/hashes" ]]
[[ "${cache_paths[1]}" == "$ROOT/.moon/cache/outputs" ]]

rm -rf fixture/moon/out fixture/moon/.executions .moon/cache .moon/invocations

bash ./moon-project.sh run fixture:cache.fixture --repo . --install-root "$INSTALL_ROOT" --evidence-dir .moon/invocations/cold >/dev/null
[[ "$(count_executions "$ROOT")" == "1" ]]
[[ -f fixture/moon/out/artifact.txt ]]
[[ -f fixture/moon/out/evidence/execution.log ]]
[[ -f .moon/invocations/cold/materialization.json ]]

bash ./moon-project.sh run fixture:cache.fixture --repo . --install-root "$INSTALL_ROOT" --evidence-dir .moon/invocations/exact >/dev/null
[[ "$(count_executions "$ROOT")" == "1" ]]

rm -rf fixture/moon/out
bash ./moon-project.sh run fixture:cache.fixture --repo . --install-root "$INSTALL_ROOT" --evidence-dir .moon/invocations/local-hydration >/dev/null
[[ "$(count_executions "$ROOT")" == "1" ]]
[[ -f fixture/moon/out/artifact.txt ]]
[[ -f fixture/moon/out/evidence/execution.log ]]

FRESH_PARENT="$(mktemp -d)"
FRESH="$FRESH_PARENT/worktree"
git -C "$ROOT" worktree add --detach "$FRESH" HEAD >/dev/null
mkdir -p "$FRESH/.moon/cache"
cp -R "$ROOT/.moon/cache/hashes" "$FRESH/.moon/cache/hashes"
cp -R "$ROOT/.moon/cache/outputs" "$FRESH/.moon/cache/outputs"

bash "$ROOT/moon-project.sh" run fixture:cache.fixture --repo "$FRESH" --install-root "$INSTALL_ROOT" --evidence-dir .moon/invocations/fresh-hydration >/dev/null
[[ "$(count_executions "$FRESH")" == "0" ]]
[[ -f "$FRESH/fixture/moon/out/artifact.txt" ]]
[[ -f "$FRESH/fixture/moon/out/evidence/execution.log" ]]

printf '\nunrelated change\n' >> "$FRESH/README.md"
bash "$ROOT/moon-project.sh" run fixture:cache.fixture --repo "$FRESH" --install-root "$INSTALL_ROOT" --evidence-dir .moon/invocations/unrelated >/dev/null
[[ "$(count_executions "$FRESH")" == "0" ]]

printf '\nrelevant change\n' >> "$FRESH/fixture/moon/input.txt"
bash "$ROOT/moon-project.sh" run fixture:cache.fixture --repo "$FRESH" --install-root "$INSTALL_ROOT" --evidence-dir .moon/invocations/relevant >/dev/null
[[ "$(count_executions "$FRESH")" == "1" ]]

mkdir -p "$RESULTS"
cat > "$RESULTS/linux.json" <<EOF
{
  "platform": "linux-x86_64",
  "moon_version": "2.5.4",
  "bootstrap_ms": $bootstrap_ms,
  "checks": {
    "git_core_without_moon": true,
    "cold_execution": true,
    "exact_rerun_skips_command": true,
    "local_hydration_skips_command": true,
    "fresh_hydration_skips_command": true,
    "unrelated_change_stays_cached": true,
    "relevant_change_executes": true
  }
}
EOF

printf 'PASS Moon production interface on Linux (bootstrap_ms=%s)\n' "$bootstrap_ms"
