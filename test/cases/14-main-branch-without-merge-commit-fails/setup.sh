# On main, the tip is a plain, linear commit (one parent) — e.g. a squash-merge, rebase-merge, or
# direct push. The guard must fail the action outright when only merge commits are allowed on
# main.
git -C "$work_dir" checkout --quiet -b main

mkdir -p "$work_dir/src" "$work_dir/tests"
printf 'tests/ export-ignore\n' >"$work_dir/.gitattributes"
printf '<?php\n' >"$work_dir/src/Foo.php"
printf '<?php\n' >"$work_dir/tests/FooTest.php"
git -C "$work_dir" add -A
git -C "$work_dir" commit --quiet -m base
base_sha="$(git -C "$work_dir" rev-parse HEAD)"
printf -v "STAGE_SHA_base" '%s' "$base_sha"

printf '<?php // changed\n' >"$work_dir/src/Foo.php"
git -C "$work_dir" add -A
git -C "$work_dir" commit --quiet -m "squashed feature change"
head_sha="$(git -C "$work_dir" rev-parse HEAD)"
printf -v "STAGE_SHA_head" '%s' "$head_sha"
