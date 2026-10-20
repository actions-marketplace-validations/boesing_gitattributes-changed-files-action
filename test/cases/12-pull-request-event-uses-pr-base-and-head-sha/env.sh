# Simulates a pull_request-triggered run where the caller passes no base-sha/head-sha input:
# github.event.before does not exist for pull_request events, and github.sha here happens to be
# the fast-forwarded "head" commit (only the tests-only follow-up commit is missing from it) —
# exactly what happens when the PR's merge ref needed no synthetic merge commit. Without the
# pull_request.base.sha / pull_request.head.sha fallback, this would regress to head^ and miss
# the earlier src/ change (see case 11).
INPUT_BASE_SHA=""
INPUT_HEAD_SHA=""
EVENT_BEFORE=""
EVENT_AFTER="$STAGE_SHA_head"
PR_BASE_SHA="$STAGE_SHA_base"
PR_HEAD_SHA="$STAGE_SHA_head2"
