#!/usr/bin/env bash
# Managed-Source: brainboxemb/tool.git-project/bootstrap/consumer-update.sh
# Managed-Source-Version: @TOOL_GIT_PROJECT_VERSION@
# Managed-Source-Revision: @TOOL_GIT_PROJECT_REVISION@
# Managed-Local-Patch: none
set -euo pipefail

mode="${1:-update}"
tool_path="tools/tool.git-project"
command -v git >/dev/null 2>&1 || { echo "Git was not found in PATH." >&2; exit 1; }
root="$(git rev-parse --show-toplevel)"
entry="$(git -C "$root" ls-files --stage -- "$tool_path" 2>/dev/null || true)"
if [[ ! "$entry" =~ ^160000[[:space:]]+([0-9a-fA-F]{40})[[:space:]] ]]; then
  echo "Bootstrap dependency '$tool_path' is not a committed gitlink." >&2
  exit 1
fi
expected="${BASH_REMATCH[1],,}"
tool_root="$root/$tool_path"
tool="$tool_root/git-project.sh"

bootstrap_head() {
  [[ -d "$tool_root" ]] || return 1
  git -C "$tool_root" rev-parse --show-toplevel >/dev/null 2>&1 || return 1
  git -C "$tool_root" rev-parse HEAD 2>/dev/null
}

bootstrap_version() {
  local value=""
  if [[ -f "$tool_root/VERSION" ]]; then
    value="$(tr -d '\r\n' < "$tool_root/VERSION")"
  fi
  [[ -n "$value" ]] || { printf 'unknown'; return; }
  [[ "$value" == v* ]] && printf '%s' "$value" || printf 'v%s' "$value"
}

show_bootstrap_mismatch() {
  local state="$1" current="${2:-}" current_label="-"
  [[ -z "$current" ]] || current_label="${current:0:12}"
  printf '%-28s BOOTSTRAP state=%-13s current=%s gitlink=%s version=%s\n'     "tool.git-project" "$state" "$current_label" "${expected:0:12}" "$(bootstrap_version)"
}

current="$(bootstrap_head || true)"

case "$mode" in
  status)
    if [[ -z "$current" ]]; then
      show_bootstrap_mismatch "UNINITIALIZED"
      echo "Bootstrap engine is not initialized. Run ./bootstrap.sh or ./update.sh." >&2
      exit 1
    fi
    if [[ -n "$(git -C "$tool_root" status --porcelain)" ]]; then
      show_bootstrap_mismatch "DIRTY" "$current"
      echo "Bootstrap engine has local changes; status will not execute modified tool code." >&2
      exit 1
    fi
    if [[ "$current" != "$expected" ]]; then
      show_bootstrap_mismatch "DIFF" "$current"
      echo "Bootstrap engine differs from the committed gitlink. Run ./update.sh to align it." >&2
      exit 1
    fi
    [[ -x "$tool" ]] || { echo "Bootstrap engine entrypoint not found at $tool" >&2; exit 1; }
    "$tool" status --repo "$root"
    ;;
  update)
    if [[ -n "$current" && -n "$(git -C "$tool_root" status --porcelain)" ]]; then
      echo "Bootstrap engine 'tool.git-project' has local changes; refusing to align it to the committed gitlink." >&2
      exit 1
    fi
    git -C "$root" submodule sync -- "$tool_path" >/dev/null
    if [[ -n "$current" && "$current" != "$expected" ]]; then
      echo "Aligning bootstrap tool.git-project: $current -> $expected (committed gitlink)"
    fi
    git -C "$root" submodule update --init -- "$tool_path" >/dev/null
    current="$(bootstrap_head || true)"
    [[ "$current" == "$expected" ]] || {
      echo "Bootstrap engine did not align to committed gitlink $expected." >&2
      exit 1
    }
    [[ -x "$tool" ]] || { echo "Bootstrap engine entrypoint not found at $tool" >&2; exit 1; }
    "$tool" update --repo "$root"
    ;;
  *)
    echo "Usage: ./update.sh [update|status]" >&2
    exit 2
    ;;
esac
