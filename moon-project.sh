#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_MANIFEST="$SCRIPT_DIR/moon/runtime.env"

if [[ ! -f "$RUNTIME_MANIFEST" ]]; then
  echo "Moon runtime manifest not found: $RUNTIME_MANIFEST" >&2
  exit 2
fi

# The manifest is source-controlled and contains only fixed KEY=value runtime metadata.
# shellcheck disable=SC1090
source "$RUNTIME_MANIFEST"

usage() {
  cat <<'EOF'
Usage:
  moon-project.sh bootstrap [--install-root PATH]
  moon-project.sh validate [--repo PATH] [--install-root PATH]
  moon-project.sh cache-paths [--repo PATH]
  moon-project.sh run TASK [--repo PATH] [--install-root PATH] [--evidence-dir PATH]

Moon is optional repository orchestration. The existing git-project commands remain Git-only.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

now_ms() {
  local value
  value="$(date +%s%3N 2>/dev/null || true)"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
  else
    printf '%s000\n' "$(date +%s)"
  fi
}

default_install_root() {
  if [[ -n "${MOON_INSTALL_ROOT:-}" ]]; then
    printf '%s\n' "$MOON_INSTALL_ROOT"
  elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    printf '%s\n' "$XDG_CACHE_HOME/brainboxemb/tool.git-project/moon"
  elif [[ -n "${HOME:-}" ]]; then
    printf '%s\n' "$HOME/.cache/brainboxemb/tool.git-project/moon"
  else
    fail "Cannot determine Moon install root; set MOON_INSTALL_ROOT."
  fi
}

moon_version_ok() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  local output
  output="$("$candidate" --version 2>&1 || true)"
  [[ "$output" == *"$MOON_VERSION"* ]]
}

extract_moon_archive() {
  local archive="$1"
  local destination="$2"

  if command -v xz >/dev/null 2>&1; then
    tar -xJf "$archive" -C "$destination"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1 && python3 -c 'import lzma, tarfile' >/dev/null 2>&1; then
    if ! python3 - "$archive" "$destination" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], mode="r:xz") as bundle:
    bundle.extractall(sys.argv[2])
PY
    then
      fail "Python fallback could not extract the pinned Moon .tar.xz archive."
    fi
    return 0
  fi

  fail "Moon Linux bootstrap requires either xz or Python 3 with lzma support to extract the pinned .tar.xz runtime."
}

bootstrap_moon() {
  local install_root="$1"
  local install_dir="$install_root/$MOON_VERSION/linux-x86_64"
  local target="$install_dir/moon"

  if moon_version_ok "$target"; then
    printf '%s\n' "$target"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || fail "curl is required to bootstrap pinned Moon."
  command -v tar >/dev/null 2>&1 || fail "tar is required to bootstrap pinned Moon."

  local temp_dir archive actual found
  temp_dir="$(mktemp -d)"
  archive="$temp_dir/moon.tar.xz"
  mkdir -p "$temp_dir/extract"

  curl --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 --retry-all-errors -fsSL \
    "$MOON_LINUX_X86_64_URL" -o "$archive"

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$archive" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  else
    rm -rf "$temp_dir"
    fail "sha256sum or shasum is required to verify pinned Moon."
  fi

  if [[ "$actual" != "$MOON_LINUX_X86_64_SHA256" ]]; then
    rm -rf "$temp_dir"
    fail "Moon archive digest mismatch: $actual"
  fi

  extract_moon_archive "$archive" "$temp_dir/extract"
  found="$(find "$temp_dir/extract" -type f -name moon -print -quit)"
  [[ -n "$found" ]] || { rm -rf "$temp_dir"; fail "moon binary not found after extraction."; }

  mkdir -p "$install_dir"
  cp "$found" "$target"
  chmod +x "$target"
  rm -rf "$temp_dir"

  moon_version_ok "$target" || fail "Bootstrapped Moon does not report expected version $MOON_VERSION."
  printf '%s\n' "$target"
}

resolve_moon() {
  local install_root="$1"
  if [[ -n "${MOON_BIN:-}" ]]; then
    moon_version_ok "$MOON_BIN" || fail "MOON_BIN does not point to Moon $MOON_VERSION: $MOON_BIN"
    printf '%s\n' "$MOON_BIN"
    return 0
  fi

  local discovered
  discovered="$(command -v moon 2>/dev/null || true)"
  if [[ -n "$discovered" ]] && moon_version_ok "$discovered"; then
    printf '%s\n' "$discovered"
    return 0
  fi

  bootstrap_moon "$install_root"
}

repo_absolute() {
  local repo="$1"
  [[ -d "$repo" ]] || fail "Repository directory does not exist: $repo"
  (cd "$repo" && pwd)
}

validate_repo_layout() {
  local repo="$1" install_root="$2"
  [[ -f "$repo/.moon/workspace.yml" ]] || fail "Missing Moon workspace configuration: $repo/.moon/workspace.yml"
  [[ -f "$repo/moon.yml" ]] || fail "Missing Moon task configuration: $repo/moon.yml"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not a Git worktree: $repo"
  local moon_bin
  moon_bin="$(resolve_moon "$install_root")"
  moon_version_ok "$moon_bin" || fail "Resolved Moon runtime is not version $MOON_VERSION."
}

command_name="${1:-}"
[[ -n "$command_name" ]] || { usage; exit 2; }
shift

case "$command_name" in
  bootstrap)
    install_root="$(default_install_root)"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --install-root) [[ $# -ge 2 ]] || fail "--install-root requires a value"; install_root="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown bootstrap option: $1" ;;
      esac
    done
    bootstrap_moon "$install_root"
    ;;

  validate)
    repo="."
    install_root="$(default_install_root)"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) [[ $# -ge 2 ]] || fail "--repo requires a value"; repo="$2"; shift 2 ;;
        --install-root) [[ $# -ge 2 ]] || fail "--install-root requires a value"; install_root="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown validate option: $1" ;;
      esac
    done
    repo="$(repo_absolute "$repo")"
    validate_repo_layout "$repo" "$install_root"
    moon_bin="$(resolve_moon "$install_root")"
    (cd "$repo" && "$moon_bin" query projects >/dev/null) || fail "Moon rejected repository configuration in $repo"
    printf 'OK moon repository: version=%s repo=%s\n' "$MOON_VERSION" "$repo"
    ;;

  cache-paths)
    repo="."
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) [[ $# -ge 2 ]] || fail "--repo requires a value"; repo="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown cache-paths option: $1" ;;
      esac
    done
    repo="$(repo_absolute "$repo")"
    printf '%s\n' "$repo/$MOON_CACHE_HASHES" "$repo/$MOON_CACHE_OUTPUTS"
    ;;

  run)
    task="${1:-}"
    [[ -n "$task" ]] || fail "run requires a Moon task name"
    shift
    [[ "$task" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || fail "Unsafe Moon task name: $task"

    repo="."
    install_root="$(default_install_root)"
    evidence_dir=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) [[ $# -ge 2 ]] || fail "--repo requires a value"; repo="$2"; shift 2 ;;
        --install-root) [[ $# -ge 2 ]] || fail "--install-root requires a value"; install_root="$2"; shift 2 ;;
        --evidence-dir) [[ $# -ge 2 ]] || fail "--evidence-dir requires a value"; evidence_dir="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown run option: $1" ;;
      esac
    done

    repo="$(repo_absolute "$repo")"
    validate_repo_layout "$repo" "$install_root"
    moon_bin="$(resolve_moon "$install_root")"
    if [[ -z "$evidence_dir" ]]; then
      evidence_dir=".moon/invocations/${task//:/_}"
    fi
    if [[ "$evidence_dir" != /* ]]; then
      evidence_dir="$repo/$evidence_dir"
    fi
    mkdir -p "$evidence_dir"

    log_file="$evidence_dir/moon.log"
    json_file="$evidence_dir/materialization.json"
    source_revision="$(git -C "$repo" rev-parse HEAD)"
    moon_version="$($moon_bin --version 2>&1 | tr -d '\r')"
    tool_version="$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION")"
    started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    started_ms="$(now_ms)"

    set +e
    (
      cd "$repo"
      "$moon_bin" run "$task" --log info
    ) 2>&1 | tee "$log_file"
    exit_code=${PIPESTATUS[0]}
    set -e

    finished_ms="$(now_ms)"
    finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    duration_ms=$((finished_ms - started_ms))
    status="success"
    [[ $exit_code -eq 0 ]] || status="failure"

    cat > "$json_file" <<EOF
{
  "schema_version": 1,
  "tool_git_project_version": "$tool_version",
  "moon_version": "$moon_version",
  "task": "$task",
  "source_revision": "$source_revision",
  "status": "$status",
  "exit_code": $exit_code,
  "started_at": "$started_at",
  "finished_at": "$finished_at",
  "duration_ms": $duration_ms
}
EOF

    [[ $exit_code -eq 0 ]] || exit "$exit_code"
    ;;

  -h|--help|help)
    usage
    ;;

  *)
    usage >&2
    fail "Unknown command: $command_name"
    ;;
esac
