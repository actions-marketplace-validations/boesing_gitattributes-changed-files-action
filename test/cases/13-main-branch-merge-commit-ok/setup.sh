# On main, the tip is a real merge commit (two parents) — the guard must not block this, and the
# usual export-ignore diff logic must still run normally against it.
git -C "$work_dir" checkout --quiet -b main

mkdir -p "$work_dir/src" "$work_dir/tests"
printf 'tests/ export-ignore\n' >"$work_dir/.gitattributes"
printf '<?php\n' >"$work_dir/src/Foo.php"
printf '<?php\n' >"$work_dir/tests/FooTest.php"
git -C "$work_dir" add -A
git -C "$work_dir" commit --quiet -m base
base_sha="$(git -C "$work_dir" rev-parse HEAD)"
printf -v "STAGE_SHA_base" '%s' "$base_sha"

git -C "$work_dir" checkout --quiet -b feature
printf '<?php // changed\n' >"$work_dir/src/Foo.php"
git -C "$work_dir" add -A
git -C "$work_dir" commit --quiet -m "feature change"
printf -v "STAGE_SHA_feature" '%s' "$(git -C "$work_dir" rev-parse HEAD)"

git -C "$work_dir" checkout --quiet main
git -C "$work_dir" merge --quiet --no-ff --no-edit feature -m "Merge pull request from feature"
head_sha="$(git -C "$work_dir" rev-parse HEAD)"
printf -v "STAGE_SHA_head" '%s' "$head_sha"
