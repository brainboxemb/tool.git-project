#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  moon-affected.sh TASK --base REV --head REV [--repo PATH] [--install-root PATH] [--evidence-dir PATH]

Prints exactly `true` or `false` to stdout. Diagnostic query output is written to the evidence directory.
The target is considered affected when Moon marks the target itself or one of its upstream dependencies affected.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

repo_absolute() {
  local repo="$1"
  [[ -d "$repo" ]] || fail "Repository directory does not exist: $repo"
  (cd "$repo" && pwd)
}

regex_escape() {
  printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

write_decision() {
  local affected="$1" status="$2" reason="$3" moon_version="$4"
  cat > "$evidence_dir/decision.json" <<EOF
{
  "schema_version": 1,
  "tool": "tool.git-project/moon-affected",
  "moon_version": "$(json_escape "$moon_version")",
  "task": "$(json_escape "$task")",
  "base": "$(json_escape "$base")",
  "head": "$(json_escape "$head")",
  "affected": $affected,
  "status": "$(json_escape "$status")",
  "reason": "$(json_escape "$reason")"
}
EOF
}

conservative_true() {
  local reason="$1" moon_version="${2:-unknown}"
  write_decision true conservative "$reason" "$moon_version"
  printf 'true\n'
  exit 0
}

task="${1:-}"
[[ -n "$task" ]] || { usage >&2; exit 2; }
shift
[[ "$task" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*:[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "Affected preflight requires a fully-qualified Moon task target: $task"

repo="."
base=""
head=""
install_root="${MOON_INSTALL_ROOT:-}"
evidence_dir=".moon/preflight"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || fail "--repo requires a value"; repo="$2"; shift 2 ;;
    --base) [[ $# -ge 2 ]] || fail "--base requires a value"; base="$2"; shift 2 ;;
    --head) [[ $# -ge 2 ]] || fail "--head requires a value"; head="$2"; shift 2 ;;
    --install-root) [[ $# -ge 2 ]] || fail "--install-root requires a value"; install_root="$2"; shift 2 ;;
    --evidence-dir) [[ $# -ge 2 ]] || fail "--evidence-dir requires a value"; evidence_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[[ -n "$base" ]] || fail "--base is required"
[[ -n "$head" ]] || fail "--head is required"

repo="$(repo_absolute "$repo")"
if [[ "$evidence_dir" != /* ]]; then evidence_dir="$repo/$evidence_dir"; fi
mkdir -p "$evidence_dir"
: > "$evidence_dir/changed-files.json"
: > "$evidence_dir/affected-tasks.json"

if ! git -C "$repo" rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  conservative_true "base-revision-not-found:$base"
fi
if ! git -C "$repo" rev-parse --verify --quiet "${head}^{commit}" >/dev/null; then
  conservative_true "head-revision-not-found:$head"
fi

bootstrap_args=(bootstrap)
[[ -n "$install_root" ]] && bootstrap_args+=(--install-root "$install_root")
if ! moon_bin="$(bash "$SCRIPT_DIR/moon-project.sh" "${bootstrap_args[@]}" 2>"$evidence_dir/bootstrap.log")"; then
  conservative_true "moon-bootstrap-failed"
fi
moon_version="$($moon_bin --version 2>&1 | tr -d '\r')"

validate_args=(validate --repo "$repo")
[[ -n "$install_root" ]] && validate_args+=(--install-root "$install_root")
if ! MOON_BIN="$moon_bin" bash "$SCRIPT_DIR/moon-project.sh" "${validate_args[@]}" >"$evidence_dir/validate.log" 2>&1; then
  conservative_true "moon-repository-validation-failed" "$moon_version"
fi

if ! (cd "$repo" && "$moon_bin" task "$task" --json) >"$evidence_dir/task.json" 2>"$evidence_dir/task-error.log"; then
  conservative_true "moon-task-not-found-or-invalid" "$moon_version"
fi

if ! (cd "$repo" && "$moon_bin" query changed-files --base "$base" --head "$head") >"$evidence_dir/changed-files.json" 2>"$evidence_dir/changed-files-error.log"; then
  conservative_true "moon-changed-files-query-failed" "$moon_version"
fi

project="${task%%:*}"
task_id="${task#*:}"
project_regex="^$(regex_escape "$project")$"
task_regex="^$(regex_escape "$task_id")$"

# Moon owns both the affected decision and graph traversal. `--downstream deep`
# propagates directly affected tasks to aggregate/dependent targets, so querying
# an aggregate answers whether executing it would traverse affected work.
if ! (cd "$repo" && "$moon_bin" query tasks --affected --downstream deep --project "$project_regex" --id "$task_regex" < "$evidence_dir/changed-files.json") >"$evidence_dir/affected-tasks.json" 2>"$evidence_dir/affected-tasks-error.log"; then
  conservative_true "moon-affected-task-query-failed" "$moon_version"
fi

if grep -Fq "\"$task_id\"" "$evidence_dir/affected-tasks.json"; then
  write_decision true success target-or-upstream-affected "$moon_version"
  printf 'true\n'
else
  write_decision false success target-and-upstream-unaffected "$moon_version"
  printf 'false\n'
fi