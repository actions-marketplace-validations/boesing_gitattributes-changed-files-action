# Check Export-Ignore Changes

A composite GitHub Action that determines whether the changes between two commits touch any
path that is **not** marked `export-ignore` in `.gitattributes`. It has zero runtime
dependencies beyond `git`, which is already present on every GitHub-hosted runner.

## Usage

```yaml
name: Check export-ignore changes

on:
  push:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - id: check
        uses: boesing/gitattributes-changed-files-action@v1

      - name: React to the result
        if: steps.check.outputs.files_changed == 'true'
        run: echo "A file outside export-ignore paths changed."
```

The consuming workflow must check out the repository with enough history to contain both
compared commits (`fetch-depth: 0`, or at least enough to reach `base-sha`) before calling this
action — the action itself does not perform a checkout.

## Inputs

| Name          | Required | Description                                                                                                                                    |
|---------------|----------|------------------------------------------------------------------------------------------------------------------------------------------------|
| `base-sha`    | No       | The base commit SHA to diff from. Defaults to `github.event.pull_request.base.sha` on `pull_request` events, otherwise `github.event.before`.  |
| `head-sha`    | No       | The head commit SHA to diff to. Defaults to `github.event.pull_request.head.sha` on `pull_request` events, otherwise `github.sha`.             |
| `main-branch` | No       | The ref that must always be fast-forwarded via a merge commit (e.g. because squash/rebase merges are disabled). Defaults to `refs/heads/main`. |

### Diffing on `pull_request` events

`github.event.before`/`github.sha` are `push`-event fields — a `pull_request` event payload has
no `before` at all, and `github.sha` is the SHA of the ephemeral `refs/pull/<n>/merge` ref, not
necessarily the PR's actual last commit. Relying on those defaults on a `pull_request` run means
the action would fall back to diffing only the last commit against its parent (see below),
silently missing earlier commits in a multi-commit PR whose latest commit only touches
export-ignored paths.

To always get the full diff against the PR's target branch regardless of how many commits the PR
has, the action detects `pull_request` events and prefers
`github.event.pull_request.base.sha`/`github.event.pull_request.head.sha` over
`github.event.before`/`github.sha` automatically — no extra input needed.

### Requiring a merge commit on `main`

If your branch protection rules only allow "Create a merge commit" (squash and rebase merges
disabled) for a given branch, every push to that branch is expected to land a real, two-parent
merge commit — a plain, linear commit landing directly on it (e.g. from a bypassed protection rule
or a different merge strategy actually being used) indicates something went through that
shouldn't have.

When the workflow run's ref (`github.ref`) matches `main-branch` (default `refs/heads/main`), the
action fails the step outright if `head-sha` is not a merge commit, instead of silently reporting
`files_changed`. This check only runs when the current ref equals `main-branch`; it never fires on
`pull_request` runs, since `github.ref` there is the PR's merge ref, not the target branch.

## Outputs

| Name            | Description                                                              |
|-----------------|--------------------------------------------------------------------------|
| `files_changed` | `"true"` if any changed file is not export-ignored, otherwise `"false"`. |

## `.gitattributes` pattern notes

A directory-only pattern without a glob, e.g. `docs export-ignore` or `docs/ export-ignore`,
excludes everything under `docs/` — this action replicates `git archive`'s tree-pruning behavior
for such patterns. If you also want to un-ignore a specific file inside that directory with a
negation rule (`-export-ignore`), it will have **no effect**: once a directory itself matches
`export-ignore`, `git archive` (and this action) never looks at more specific rules inside it.

```gitattributes
docs export-ignore
docs/keep-me.txt -export-ignore   # ignored: docs/ already excludes everything below it
```

To make a per-file exception work, write the broad rule as a recursive glob (`docs/**`) instead,
which matches each file individually rather than pruning the whole directory:

```gitattributes
docs/** export-ignore
docs/keep-me.txt -export-ignore       # works: docs/** matches files individually
```

This only works one level deep, though. `docs/**` also matches subdirectories under `docs/` as
tree entries in their own right, so a negation for a file further down still gets pruned before
it's ever evaluated:

```gitattributes
docs/** export-ignore
docs/sub/keep-me.txt -export-ignore   # ignored: docs/sub itself already matches docs/**
```

## Job summary

The action writes a human-readable summary of the changed files to the job's
[GitHub Actions summary page](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary).

## Development

Each test case builds a throwaway git repository from the fixtures in `test/cases/` and
exercises `scripts/check-export-ignore.sh` directly. Run a single case by name:

```bash
test/run-test-case.sh 01-non-ignored-change
```

Run all cases:

```bash
for case_dir in test/cases/*/; do test/run-test-case.sh "$(basename "$case_dir")"; done
```

Most cases just provide `base/` and `head*/` directory snapshots (one commit each, in order) plus
an `expected.json` with `files_changed`. A case can add a `base-sha-override` file (literal SHA)
or an `env.sh` file (sourced with `$STAGE_SHA_<stage>` commit SHAs available, e.g.
`$STAGE_SHA_base`, `$STAGE_SHA_head`) to override any of the env vars the composite action passes
to the script (`INPUT_BASE_SHA`, `INPUT_HEAD_SHA`, `EVENT_BEFORE`, `EVENT_AFTER`, `PR_BASE_SHA`,
`PR_HEAD_SHA`, `INPUT_MAIN_BRANCH`, `CURRENT_REF`) — e.g. to simulate a `pull_request` event or a
push to `main`. A case whose git topology the generic snapshot commits can't express (e.g. an
actual merge commit) can provide a `setup.sh` instead, with full control over the repo at
`$work_dir`; it must set `base_sha`/`head_sha` itself. `expected.json` may use `"exit_code"`
instead of/in addition to `"files_changed"` to assert that the action fails outright.

## License

MIT, see [LICENSE](LICENSE).
