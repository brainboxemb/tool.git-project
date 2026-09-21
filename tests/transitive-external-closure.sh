#!/usr/bin/env bash
set -euo pipefail

repo="${1:?fixture repository path required}"
mechint_path="deps/lib.scad.mechint"
root_util_path="deps/lib.scad.util"
nested_util_path="$mechint_path/ext/lib.scad.util"
mechint_ref="bdd39925f2ad391b32fad7ba56770053d4d5e2bc"
root_util_ref="da1892a201c3bfc78a65e10df84d4a8d142ae8f6"
nested_util_ref="5c88cd9b6b118d376825927ed67e26aff6eaee2d"

cd "$repo"
cat >> project.yml <<'EOF'

  - name: lib.scad.mechint
    role: external
    type: git-submodule
    url: https://github.com/brainboxemb/lib.scad.mechint.git
    path: deps/lib.scad.mechint
    ref: v0.1.6

  - name: lib.scad.util
    role: external
    type: git-submodule
    url: https://github.com/brainboxemb/lib.scad.util.git
    path: deps/lib.scad.util
    ref: v0.2.0
EOF

git submodule add https://github.com/brainboxemb/lib.scad.mechint.git "$mechint_path"
git -C "$mechint_path" checkout --detach "$mechint_ref"
git submodule add https://github.com/brainboxemb/lib.scad.util.git "$root_util_path"
git -C "$root_util_path" checkout --detach "$root_util_ref"
git add project.yml .gitmodules "$mechint_path" "$root_util_path"
git commit -m "add transitive external fixture"

git submodule deinit -f -- "$mechint_path" "$root_util_path"
rm -rf "$mechint_path" "$root_util_path"

./bootstrap.sh
test "$(git -C "$mechint_path" rev-parse HEAD)" = "$mechint_ref"
test "$(git -C "$root_util_path" rev-parse HEAD)" = "$root_util_ref"
test "$(git -C "$nested_util_path" rev-parse HEAD)" = "$nested_util_ref"

for path in tools/tool.git-project tools/tool.scad-project; do
  git -C "$mechint_path" submodule status -- "$path" | grep -q '^-'
  git -C "$nested_util_path" submodule status -- "$path" | grep -q '^-'
done

status="$(./update-repo.sh status)"
printf '%s\n' "$status"
printf '%s\n' "$status" | grep -F "nested lib.scad.util" | grep -F "owner=$mechint_path" | grep -F "path=ext/lib.scad.util" | grep -F "ref=v0.1.0" | grep -F "OK"

printf '\nowner-test dirty marker\n' >> "$nested_util_path/README.md"
dirty_status="$(./update-repo.sh status)"
printf '%s\n' "$dirty_status" | grep -F "nested lib.scad.util" | grep -F "owner=$mechint_path" | grep -F "DIRTY"
if ./update-repo.sh > transitive-dirty-update.log 2>&1; then
  cat transitive-dirty-update.log
  echo "update unexpectedly succeeded with dirty nested dependency" >&2
  exit 1
fi
git -C "$nested_util_path" checkout -- README.md
test "$(git -C "$root_util_path" rev-parse HEAD)" = "$root_util_ref"
test "$(git -C "$nested_util_path" rev-parse HEAD)" = "$nested_util_ref"

cp project.yml project.yml.owner-test
sed -i '0,/ref: v0.2.0/s//ref: v0.1.0/' project.yml
./update-repo.sh
test "$(git -C "$root_util_path" rev-parse HEAD)" = "$nested_util_ref"
test "$(git -C "$nested_util_path" rev-parse HEAD)" = "$nested_util_ref"
mv project.yml.owner-test project.yml
./update-repo.sh
test "$(git -C "$root_util_path" rev-parse HEAD)" = "$root_util_ref"
test "$(git -C "$nested_util_path" rev-parse HEAD)" = "$nested_util_ref"

git -C "$mechint_path" submodule deinit -f -- ext/lib.scad.util >/dev/null
uninit_status="$(./update-repo.sh status)"
printf '%s\n' "$uninit_status" | grep -F "nested lib.scad.util" | grep -F "owner=$mechint_path" | grep -F "UNINITIALIZED"
./update-repo.sh
test "$(git -C "$nested_util_path" rev-parse HEAD)" = "$nested_util_ref"

mkdir -p deps/local-sentinel
printf 'keep\n' > deps/local-sentinel/keep.txt
./update-repo.sh
test -f deps/local-sentinel/keep.txt
rm -rf deps/local-sentinel

final_status="$(./update-repo.sh status)"
printf '%s\n' "$final_status"
if printf '%s\n' "$final_status" | grep -E 'nested .* (DIRTY|DIFF|UNINITIALIZED|MISSING_GITLINK|CYCLE)' >/dev/null; then
  echo "nested closure did not return clean" >&2
  exit 1
fi
test -z "$(git status --porcelain)"
