#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  moon-affected.sh TASK --base REV --head REV [--repo PATH] [--install-root PATH] [--evidence-dir PATH]

Prints exactly `true` or `false` to stdout. Diagnostic query output is written to the evidence directory.
The target is considered affected when Moon marks the target itself or one of its upstream dependencies affected.
The normalized complete affected task list is written to `affected-task-ids.json` in the evidence directory.
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

task_is_in_query_result() {
  local json_file="$1" project="$2" task_id="$3"
  awk -v expected_project="$project" -v expected_task="$task_id" '
    /^  "tasks": \{/ {
      in_tasks = 1
      next
    }
    in_tasks && /^  },?$/ {
      exit
    }
    in_tasks && /^    "[^"]+": \{$/ {
      line = $0
      sub(/^    "/, "", line)
      sub(/": \{$/, "", line)
      current_project = line
      next
    }
    in_tasks && current_project == expected_project && $0 == "      \"" expected_task "\": {" {
      found = 1
    }
    END {
      exit found ? 0 : 1
    }
  ' "$json_file"
}

write_affected_task_ids() {
  local json_file="$1" output_file="$2" ids_file first id escaped
  ids_file="$(mktemp "$evidence_dir/affected-task-ids.XXXXXX")"

  if ! awk '
    /^  "tasks": \{/ {
      in_tasks = 1
      next
    }
    in_tasks && /^  },?$/ {
      exit
    }
    in_tasks && /^    "[^"]+": \{$/ {
      line = $0
      sub(/^    "/, "", line)
      sub(/": \{$/, "", line)
      current_project = line
      next
    }
    in_tasks && current_project != "" && /^      "[^"]+": \{$/ {
      line = $0
      sub(/^      "/, "", line)
      sub(/": \{$/, "", line)
      print current_project ":" line
    }
  ' "$json_file" | LC_ALL=C sort -u > "$ids_file"; then
    rm -f "$ids_file"
    return 1
  fi

  {
    printf '['
    first=true
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      escaped="$(json_escape "$id")"
      if [[ "$first" == true ]]; then
        first=false
      else
        printf ','
      fi
      printf '"%s"' "$escaped"
    done < "$ids_file"
    printf ']\n'
  } > "$output_file"

  rm -f "$ids_file"
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
printf '[]\n' > "$evidence_dir/affected-task-ids.json"

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

# Moon owns both the affected decision and graph traversal. First let Moon build
# the complete affected set and propagate it to all deep downstream dependents.
# Only after Moon has resolved that graph do we normalize the complete task list
# and check exact membership of the requested target.
if ! (cd "$repo" && "$moon_bin" query tasks --affected --downstream deep < "$evidence_dir/changed-files.json") >"$evidence_dir/affected-tasks.json" 2>"$evidence_dir/affected-tasks-error.log"; then
  conservative_true "moon-affected-task-query-failed" "$moon_version"
fi

if ! write_affected_task_ids "$evidence_dir/affected-tasks.json" "$evidence_dir/affected-task-ids.json"; then
  conservative_true "moon-affected-task-result-invalid" "$moon_version"
fi

if task_is_in_query_result "$evidence_dir/affected-tasks.json" "$project" "$task_id"; then
  write_decision true success target-or-upstream-affected "$moon_version"
  printf 'true\n'
else
  write_decision false success target-and-upstream-unaffected "$moon_version"
  printf 'false\n'
fi
