#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <case-name>" >&2
  echo "  <case-name> is a directory name under test/cases/, e.g. 01-non-ignored-change" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
check_script="$repo_root/scripts/check-export-ignore.sh"
case_dir="$script_dir/cases/$1"

if [ ! -d "$case_dir" ]; then
  echo "Error: no such test case: $case_dir" >&2
  exit 1
fi

case_name="$(basename "$case_dir")"
base_dir="${case_dir}/base"
expected_file="${case_dir}/expected.json"
base_sha_override_file="${case_dir}/base-sha-override"
env_override_file="${case_dir}/env.sh"
setup_override_file="${case_dir}/setup.sh"

work_dir="$(mktemp -d)"

git init --quiet "$work_dir"
git -C "$work_dir" config user.email "test@example.com"
git -C "$work_dir" config user.name "Test"
git -C "$work_dir" config commit.gpgsign "false"

base_sha=""
head_sha=""

if [ -f "$setup_override_file" ]; then
  # Full control for cases whose git topology (e.g. a real merge commit) the generic
  # base/head*-directory copying below cannot express. Must set base_sha and head_sha itself,
  # and may set STAGE_SHA_<name> variables for env.sh to reference.
  # shellcheck disable=SC1090
  source "$setup_override_file"
else
  if [ -d "$base_dir" ]; then
    cp -a "$base_dir/." "$work_dir/"
    git -C "$work_dir" add -A
    git -C "$work_dir" commit --quiet -m "base"
    base_sha="$(git -C "$work_dir" rev-parse HEAD)"
    printf -v "STAGE_SHA_base" '%s' "$base_sha"
    find "$work_dir" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
  fi

  for head_stage_dir in "$case_dir"/head*; do
    [ -d "$head_stage_dir" ] || continue
    stage_name="$(basename "$head_stage_dir")"
    cp -a "$head_stage_dir/." "$work_dir/"
    git -C "$work_dir" add -A
    git -C "$work_dir" commit --quiet -m "$stage_name"
    head_sha="$(git -C "$work_dir" rev-parse HEAD)"
    printf -v "STAGE_SHA_${stage_name}" '%s' "$head_sha"
  done
fi

# Defaults: simulate a caller that passes the resolved base/head commits explicitly, with no
# pull_request context and not running on the main branch. A case can override any of these in
# env.sh, e.g. to simulate a pull_request event (clear INPUT_BASE_SHA/INPUT_HEAD_SHA and
# EVENT_BEFORE, set PR_BASE_SHA/PR_HEAD_SHA/EVENT_AFTER instead) or a push to main (set
# CURRENT_REF), referencing the recorded $STAGE_SHA_<stage> commits.
INPUT_BASE_SHA="$base_sha"
INPUT_HEAD_SHA="$head_sha"
EVENT_BEFORE=""
EVENT_AFTER=""
PR_BASE_SHA=""
PR_HEAD_SHA=""
INPUT_MAIN_BRANCH="refs/heads/main"
CURRENT_REF=""

if [ -f "$base_sha_override_file" ]; then
  INPUT_BASE_SHA="$(cat "$base_sha_override_file")"
fi

if [ -f "$env_override_file" ]; then
  # shellcheck disable=SC1090
  source "$env_override_file"
fi

output_file="$(mktemp)"
summary_file="$(mktemp)"

exit_code=0
(
  cd "$work_dir"
  INPUT_BASE_SHA="$INPUT_BASE_SHA" INPUT_HEAD_SHA="$INPUT_HEAD_SHA" \
    EVENT_BEFORE="$EVENT_BEFORE" EVENT_AFTER="$EVENT_AFTER" \
    PR_BASE_SHA="$PR_BASE_SHA" PR_HEAD_SHA="$PR_HEAD_SHA" \
    INPUT_MAIN_BRANCH="$INPUT_MAIN_BRANCH" CURRENT_REF="$CURRENT_REF" \
    GITHUB_OUTPUT="$output_file" GITHUB_STEP_SUMMARY="$summary_file" \
    "$check_script"
) || exit_code="$?"

expected_exit_code="0"
if jq -e 'has("exit_code")' "$expected_file" >/dev/null; then
  expected_exit_code="$(jq -r '.exit_code' "$expected_file")"
fi

result="PASS"
reason=""

if [ "$exit_code" != "$expected_exit_code" ]; then
  result="FAIL"
  reason="expected exit_code=$expected_exit_code, got $exit_code"
elif [ "$expected_exit_code" = "0" ] && jq -e 'has("files_changed")' "$expected_file" >/dev/null; then
  actual_files_changed="$(grep '^files_changed=' "$output_file" | cut -d= -f2)"
  expected_files_changed="$(jq -r '.files_changed' "$expected_file")"
  if [ "$actual_files_changed" != "$expected_files_changed" ]; then
    result="FAIL"
    reason="expected files_changed=$expected_files_changed, got $actual_files_changed"
  fi
fi

rm -rf "$work_dir" "$output_file" "$summary_file"

if [ "$result" = "PASS" ]; then
  echo "PASS: $case_name"
  exit 0
fi

echo "FAIL: $case_name ($reason)"
exit 1
