#!/usr/bin/env bash
set -euo pipefail

command_name="${1:-status}"
if [[ $# -gt 0 ]]; then shift; fi
repo_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo_root="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$command_name" in
  validate|bootstrap|status|update) ;;
  *) echo "Usage: $0 {validate|bootstrap|status|update} [--repo PATH]" >&2; exit 2 ;;
esac

command -v git >/dev/null 2>&1 || { echo "Git was not found in PATH." >&2; exit 1; }

if [[ -n "$repo_root" ]]; then
  repo_root="$(git -C "$repo_root" rev-parse --show-toplevel)"
else
  repo_root="$(git rev-parse --show-toplevel)"
fi
project_file="$repo_root/project.yml"
[[ -f "$project_file" ]] || { echo "project.yml not found at $project_file" >&2; exit 1; }

unquote() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  if [[ ${#value} -ge 2 ]]; then
    if [[ ( "${value:0:1}" == '"' && "${value: -1}" == '"' ) || ( "${value:0:1}" == "'" && "${value: -1}" == "'" ) ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

schema_version=""
project_name=""
profile_types=()
profile_configs=()
dep_names=()
dep_roles=()
dep_types=()
dep_urls=()
dep_paths=()
dep_refs=()
section=""
current=-1

while IFS= read -r raw || [[ -n "$raw" ]]; do
  trimmed="${raw#${raw%%[![:space:]]*}}"
  [[ -z "$trimmed" || "${trimmed:0:1}" == "#" ]] && continue
  leading="${raw%%[![:space:]]*}"
  [[ "$leading" == *$'\t'* ]] && { echo "Tabs are not supported in project.yml indentation." >&2; exit 1; }
  indent=${#leading}
  text="${raw:$indent}"

  if (( indent == 0 )); then
    current=-1
    if [[ "$text" =~ ^schema_version:[[:space:]]*(.+)$ ]]; then
      schema_version="$(unquote "${BASH_REMATCH[1]}")"; section=""
    elif [[ "$text" == "project:" ]]; then section="project"
    elif [[ "$text" == "profiles:" ]]; then section="profiles"
    elif [[ "$text" == "dependencies:" ]]; then section="dependencies"
    else echo "Unsupported top-level project.yml entry: $text" >&2; exit 1
    fi
    continue
  fi

  if [[ "$section" == "project" ]]; then
    if (( indent == 2 )) && [[ "$text" =~ ^name:[[:space:]]*(.+)$ ]]; then
      project_name="$(unquote "${BASH_REMATCH[1]}")"
    else
      echo "Only project.name is supported in generic project.yml v1." >&2; exit 1
    fi
    continue
  fi

  if [[ "$section" == "profiles" ]]; then
    if (( indent == 2 )) && [[ "$text" =~ ^-[[:space:]]*type:[[:space:]]*(.+)$ ]]; then
      current=${#profile_types[@]}
      profile_types+=("$(unquote "${BASH_REMATCH[1]}")")
      profile_configs+=("")
    elif (( current >= 0 && indent == 4 )) && [[ "$text" =~ ^config:[[:space:]]*(.+)$ ]]; then
      profile_configs[$current]="$(unquote "${BASH_REMATCH[1]}")"
    else
      echo "Unsupported profiles entry: $text" >&2; exit 1
    fi
    continue
  fi

  if [[ "$section" == "dependencies" ]]; then
    if (( indent == 2 )) && [[ "$text" =~ ^-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
      current=${#dep_names[@]}
      dep_names+=("$(unquote "${BASH_REMATCH[1]}")")
      dep_roles+=(""); dep_types+=(""); dep_urls+=(""); dep_paths+=(""); dep_refs+=("")
    elif (( current >= 0 && indent == 4 )) && [[ "$text" =~ ^([^:]+):[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"; value="$(unquote "${BASH_REMATCH[2]}")"
      case "$key" in
        role) dep_roles[$current]="$value" ;;
        type) dep_types[$current]="$value" ;;
        url) dep_urls[$current]="$value" ;;
        path) dep_paths[$current]="$value" ;;
        ref) dep_refs[$current]="$value" ;;
        *) echo "Unsupported dependency field '$key'." >&2; exit 1 ;;
      esac
    else
      echo "Unsupported dependencies entry: $text" >&2; exit 1
    fi
    continue
  fi

  echo "Entry outside a supported project.yml section: $text" >&2; exit 1
done < "$project_file"

[[ "$schema_version" == "1" ]] || { echo "schema_version must be 1." >&2; exit 1; }
[[ -n "$project_name" ]] || { echo "project.name is required." >&2; exit 1; }

declare -A seen_profile=() seen_name=() seen_path=()
for i in "${!profile_types[@]}"; do
  [[ -n "${profile_types[$i]}" && -n "${profile_configs[$i]}" ]] || { echo "Each profile requires type and config." >&2; exit 1; }
  [[ -z "${seen_profile[${profile_types[$i]}]+x}" ]] || { echo "Duplicate profile type '${profile_types[$i]}'." >&2; exit 1; }
  seen_profile["${profile_types[$i]}"]=1
  [[ -f "$repo_root/${profile_configs[$i]}" ]] || { echo "Profile config not found: ${profile_configs[$i]}" >&2; exit 1; }
done

for i in "${!dep_names[@]}"; do
  for value in "${dep_names[$i]}" "${dep_roles[$i]}" "${dep_types[$i]}" "${dep_urls[$i]}" "${dep_paths[$i]}" "${dep_refs[$i]}"; do
    [[ -n "$value" ]] || { echo "Dependency ${dep_names[$i]:-<unnamed>} has a missing required field." >&2; exit 1; }
  done
  [[ "${dep_types[$i]}" == "git-submodule" ]] || { echo "Unsupported dependency type '${dep_types[$i]}'." >&2; exit 1; }
  [[ "${dep_paths[$i]}" != /* && "${dep_paths[$i]}" != *"../"* && "${dep_paths[$i]}" != ".." ]] || { echo "Dependency path must be repository-relative: ${dep_paths[$i]}" >&2; exit 1; }
  [[ -z "${seen_name[${dep_names[$i]}]+x}" ]] || { echo "Duplicate dependency name '${dep_names[$i]}'." >&2; exit 1; }
  [[ -z "${seen_path[${dep_paths[$i]}]+x}" ]] || { echo "Duplicate dependency path '${dep_paths[$i]}'." >&2; exit 1; }
  seen_name["${dep_names[$i]}"]=1; seen_path["${dep_paths[$i]}"]=1
done

if [[ "$command_name" == "validate" ]]; then
  echo "project.yml valid: $project_name (${#dep_names[@]} dependencies, ${#profile_types[@]} profiles)"
  exit 0
fi

test_gitlink() {
  local path="$1" entry
  entry="$(git -C "$repo_root" ls-files --stage -- "$path" 2>/dev/null || true)"
  [[ "$entry" =~ ^160000[[:space:]] ]]
}

submodule_name_for_path() {
  local path="$1" line key value
  [[ -f "$repo_root/.gitmodules" ]] || return 1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%[[:space:]]*}"
    value="${line#${key}}"; value="${value#${value%%[![:space:]]*}}"
    if [[ "$value" == "$path" ]]; then
      key="${key#submodule.}"; key="${key%.path}"; printf '%s' "$key"; return 0
    fi
  done < <(git -C "$repo_root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
  return 1
}

ensure_registration() {
  local i="$1" path="${dep_paths[$i]}" url="${dep_urls[$i]}" full="$repo_root/${dep_paths[$i]}" name parent current_url
  name="$(submodule_name_for_path "$path" || true)"
  if ! test_gitlink "$path"; then
    if [[ -e "$full" ]]; then
      if [[ -d "$full" && -z "$(find "$full" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        rmdir "$full"
      elif [[ ! -e "$full/.git" ]]; then
        echo "Cannot register '$path': target contains non-submodule files." >&2; exit 1
      fi
    fi
    parent="$(dirname "$full")"; mkdir -p "$parent"
    echo "Registering ${dep_names[$i]} at $path"
    git -C "$repo_root" submodule add --force "$url" "$path"
    name="$(submodule_name_for_path "$path" || true)"
  fi
  if [[ -z "$name" ]]; then
    name="${dep_names[$i]}"
    git -C "$repo_root" config -f .gitmodules "submodule.$name.path" "$path"
    git -C "$repo_root" config -f .gitmodules "submodule.$name.url" "$url"
  else
    current_url="$(git -C "$repo_root" config -f .gitmodules --get "submodule.$name.url" 2>/dev/null || true)"
    [[ "$current_url" == "$url" ]] || git -C "$repo_root" config -f .gitmodules "submodule.$name.url" "$url"
  fi
  git -C "$repo_root" submodule sync -- "$path" >/dev/null
  if [[ ! -d "$full" ]] || ! git -C "$full" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$repo_root" submodule update --init -- "$path" >/dev/null
  fi
}

assert_clean() {
  local full="$1" name="$2"
  [[ -z "$(git -C "$full" status --porcelain)" ]] || { echo "Dependency '$name' has local changes; refusing checkout/update." >&2; exit 1; }
}

resolve_commit() {
  local full="$1" ref="$2" fetch="${3:-no}" candidate resolved
  if [[ "$fetch" == "yes" ]]; then git -C "$full" fetch origin --prune --tags >/dev/null; fi
  candidates=()
  [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]] && candidates+=("$ref^{commit}")
  candidates+=("refs/tags/$ref^{commit}" "origin/$ref^{commit}" "$ref^{commit}")
  for candidate in "${candidates[@]}"; do
    if resolved="$(git -C "$full" rev-parse --verify "$candidate" 2>/dev/null)"; then printf '%s' "$resolved"; return 0; fi
  done
  return 1
}

sync_dependency() {
  local i="$1" mode="$2" full expected current
  ensure_registration "$i"
  full="$repo_root/${dep_paths[$i]}"
  assert_clean "$full" "${dep_names[$i]}"
  expected="$(resolve_commit "$full" "${dep_refs[$i]}" yes || true)"
  [[ -n "$expected" ]] || { echo "Unable to resolve ref '${dep_refs[$i]}' for ${dep_names[$i]}." >&2; exit 1; }
  current="$(git -C "$full" rev-parse HEAD)"
  if [[ "$current" != "$expected" ]]; then
    echo "$mode ${dep_names[$i]}: $current -> $expected (${dep_refs[$i]})"
    git -C "$full" checkout --detach "$expected" >/dev/null
  else
    echo "${dep_names[$i]}: already at $expected (${dep_refs[$i]})"
  fi
}

show_status() {
  local i full current expected dirty state
  for i in "${!dep_names[@]}"; do
    full="$repo_root/${dep_paths[$i]}"
    if ! test_gitlink "${dep_paths[$i]}" || [[ ! -d "$full" ]]; then
      printf '%-28s MISSING  ref=%s path=%s\n' "${dep_names[$i]}" "${dep_refs[$i]}" "${dep_paths[$i]}"
      continue
    fi
    if ! current="$(git -C "$full" rev-parse HEAD 2>/dev/null)"; then
      printf '%-28s UNINITIALIZED ref=%s path=%s\n' "${dep_names[$i]}" "${dep_refs[$i]}" "${dep_paths[$i]}"
      continue
    fi
    expected="$(resolve_commit "$full" "${dep_refs[$i]}" no || true)"
    dirty="$(git -C "$full" status --porcelain)"
    if [[ -n "$dirty" ]]; then state="DIRTY"
    elif [[ -n "$expected" && "$expected" == "$current" ]]; then state="OK"
    elif [[ -n "$expected" ]]; then state="DIFF"
    else state="UNKNOWN"
    fi
    printf '%-28s %-7s current=%s ref=%s\n' "${dep_names[$i]}" "$state" "${current:0:12}" "${dep_refs[$i]}"
  done
}

if [[ "$command_name" == "status" ]]; then show_status; exit 0; fi

for i in "${!dep_names[@]}"; do
  if [[ "$command_name" == "bootstrap" ]]; then sync_dependency "$i" "Bootstrapping"; else sync_dependency "$i" "Updating"; fi
done

echo
show_status
echo
if [[ "$command_name" == "bootstrap" ]]; then
  echo "Bootstrap complete. Review parent changes with: git status"
else
  echo "Update complete. Review project.yml and gitlink changes before committing."
fi
