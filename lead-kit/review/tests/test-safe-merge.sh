#!/usr/bin/env bash
# Mocked-gh tests for safe-merge.sh. Run: bash test-safe-merge.sh
D=$(cd "$(dirname "$0")" && pwd); S="$D/../safe-merge.sh"; export GH_BIN="$D/mockgh" HUB_BIN="$D/mockhub"
H=aaaaaaa1111111111111111111111111111111111; O=bbbbbbb2222222222222222222222222222222222
export SAFE_MERGE_REVIEWER_LOGINS="reviewer,maintainer rb"
export SAFE_MERGE_DEFAULT_OWNER=example SAFE_MERGE_ALLOWED_REPOS=example/project
export SAFE_MERGE_CONFIG=$(mktemp)
trap 'rm -f "$SAFE_MERGE_CONFIG"; rm -rf "${test_dirs[@]}"' EXIT
test_dirs=()
pass=0; fail=0
setup(){ export MOCK_DIR=$(mktemp -d); test_dirs+=("$MOCK_DIR"); echo '[]' >"$MOCK_DIR/comments.json"
 echo '{"workflow_runs":[{"name":"ci","status":"completed","conclusion":"success"}]}' >"$MOCK_DIR/runs.json"
 echo '{"check_runs":[]}' >"$MOCK_DIR/cr.json"; }
rv(){ echo "{\"user\":{\"login\":\"$1\"},\"state\":\"$2\",\"commit_id\":\"$3\",\"submitted_at\":\"$4\",\"body\":\"$5\",\"id\":1}"; }
t(){ local name="$1" want="$2"; shift 2; out=$("$S" project 1 "$@" 2>&1); rc=$?
 merged=$([ -f "$MOCK_DIR/merged" ] && echo y || echo n)
 if { [ "$want" = ok ] && [ $rc -eq 0 ]; } || { [ "$want" = refuse ] && [ $rc -ne 0 ] && [ $merged = n ]; }; then echo "PASS $name"; pass=$((pass+1)); else echo "FAIL $name (rc=$rc)"; echo "$out"; fail=$((fail+1)); fi; }
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"; t approved-at-head ok
grep -q -- "--match-head-commit $H" "$MOCK_DIR/merged" && { echo "PASS merge-cmd-has-match-head"; pass=$((pass+1)); } || { echo FAIL merge-cmd; fail=$((fail+1)); }
setup; echo "[$(rv reviewer APPROVED $O 1)]" >"$MOCK_DIR/reviews.json"; t approved-stale-sha refuse
setup; echo "[$(rv reviewer APPROVED $H 1),$(rv maintainer CHANGES_REQUESTED $H 2)]" >"$MOCK_DIR/reviews.json"; t changes-requested refuse
setup; echo "[$(rv maintainer CHANGES_REQUESTED $H 1),$(rv maintainer APPROVED $H 2)]" >"$MOCK_DIR/reviews.json"; t cr-then-approved ok
setup; echo "[$(rv rb COMMENTED $H 1 'Verdict: APPROVE')]" >"$MOCK_DIR/reviews.json"; t reviewbot-approve-review ok
setup; echo "[$(rv rb COMMENTED $H 1 'Verdict: APPROVE'),$(rv rb COMMENTED $H 2 'Verdict: BLOCK @aaaaaaa')]" >"$MOCK_DIR/reviews.json"; t reviewbot-later-block refuse
setup; echo '[]' >"$MOCK_DIR/reviews.json"; echo '[{"id":9,"user":{"login":"rb"},"created_at":"1","body":"Review Bot\nVerdict: APPROVE at aaaaaaa"}]' >"$MOCK_DIR/comments.json"; t pr-comment-cited-sha ok
setup; echo '[]' >"$MOCK_DIR/reviews.json"; echo '[{"id":9,"user":{"login":"rb"},"created_at":"1","body":"Verdict: APPROVE at bbbbbbb"}]' >"$MOCK_DIR/comments.json"; t pr-comment-wrong-sha refuse
setup; echo '[]' >"$MOCK_DIR/reviews.json"; echo '[{"id":7,"author_bot":"Review Bot","created":"1","title":"project#1 APPROVE @aaaaaaa","body":""}]' >"$MOCK_DIR/hub.json"; t hub-only-approval-refused refuse
setup; echo '[]' >"$MOCK_DIR/reviews.json"
echo '[{"id":9,"user":{"login":"outsider"},"created_at":"1","body":"Verdict: APPROVE @aaaaaaa"}]' >"$MOCK_DIR/comments.json"
t foreign-comment-approval refuse
setup; echo "[$(rv outsider APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"; t foreign-review-approval refuse
setup; echo "[$(rv outsider COMMENTED $H 1 'Verdict: APPROVE')]" >"$MOCK_DIR/reviews.json"; t foreign-review-verdict refuse
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"
echo '[{"id":9,"user":{"login":"outsider"},"created_at":"2","body":"Verdict: BLOCK @aaaaaaa"}]' >"$MOCK_DIR/comments.json"
t foreign-block-ignored ok
setup; echo "[$(rv reviewer APPROVED $H 1),$(rv outsider CHANGES_REQUESTED $H 2)]" >"$MOCK_DIR/reviews.json"; t foreign-changes-requested-ignored ok
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"
echo '[{"id":9,"user":{"login":"rb"},"created_at":"2","body":"Verdict: BLOCK @aaaaaaa"}]' >"$MOCK_DIR/comments.json"
t allowlisted-comment-block refuse
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"
echo '[{"id":7,"author_bot":"Review Bot","created":"2","title":"project#1 Verdict: BLOCK @aaaaaaa","body":""}]' >"$MOCK_DIR/hub.json"
t hub-block-newer-than-approval refuse
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"
echo 'REVIEWER_LOGINS="reviewer"' >"$SAFE_MERGE_CONFIG"
export SAFE_MERGE_REVIEWER_LOGINS=""
t empty-reviewer-allowlist refuse
[[ "$out" == *"empty reviewer login allowlist"* ]] || { echo "FAIL empty-reviewer-reason"; fail=$((fail+1)); }
unset SAFE_MERGE_REVIEWER_LOGINS
t reviewer-allowlist-from-config ok
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"
export SAFE_MERGE_REVIEWER_LOGINS=outsider
t reviewer-env-overrides-config refuse
export SAFE_MERGE_REVIEWER_LOGINS="reviewer,maintainer rb"
setup; echo '[]' >"$MOCK_DIR/reviews.json"; t no-approval refuse
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"; echo '{"workflow_runs":[{"name":"ci","status":"completed","conclusion":"failure"}]}' >"$MOCK_DIR/runs.json"; t actions-failed refuse
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"; echo '{"workflow_runs":[{"name":"ci","status":"in_progress","conclusion":null}]}' >"$MOCK_DIR/runs.json"; t actions-in-progress refuse
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"; echo '{"workflow_runs":[]}' >"$MOCK_DIR/runs.json"; t no-runs refuse
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"; echo '{"workflow_runs":[]}' >"$MOCK_DIR/runs.json"; t no-runs-allow-unverified ok --allow-unverified-ci
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"; touch "$MOCK_DIR/cr403"; t checkruns-403-warn-only ok
grep -q "checks unreadable, token lacks checks:read" <<<"$out" && { echo "PASS 403-warning-printed"; pass=$((pass+1)); } || { echo FAIL 403-warning; fail=$((fail+1)); }
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"; t dry-run-no-merge ok --dry-run
[ -f "$MOCK_DIR/merged" ] && { echo FAIL dry-run-merged; fail=$((fail+1)); } || { echo "PASS dry-run-did-not-merge"; pass=$((pass+1)); }
out=$("$S" evil/repo 1 2>&1); [ $? -ne 0 ] && { echo "PASS unlisted-repo-refused"; pass=$((pass+1)); } || { echo FAIL repo-allowlist; fail=$((fail+1)); }
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"
export SAFE_MERGE_ALLOWED_REPOS="other/repo,example/project example/another"
t allowlist-from-env ok
unset SAFE_MERGE_ALLOWED_REPOS
echo 'ALLOWED_REPOS="example/project,other/repo"' >"$SAFE_MERGE_CONFIG"
t allowlist-from-config ok
setup; echo "[$(rv reviewer APPROVED $H 1)]" >"$MOCK_DIR/reviews.json"
export SAFE_MERGE_ALLOWED_REPOS=""
t empty-allowlist refuse
if [[ "$out" == *"empty repository allowlist"* ]]; then pass=$((pass+1)); else echo "FAIL empty-allowlist-reason"; fail=$((fail+1)); fi
export SAFE_MERGE_ALLOWED_REPOS=other/repo
t repo-not-in-list refuse
if [[ "$out" == *"not in repository allowlist"* ]]; then pass=$((pass+1)); else echo "FAIL unlisted-repo-reason"; fail=$((fail+1)); fi
setup; export SAFE_MERGE_ALLOWED_REPOS=example/project SAFE_MERGE_REVIEWER="Automation Reviewer"
echo '[]' >"$MOCK_DIR/reviews.json"
echo '[{"id":7,"author_bot":"Automation Reviewer","created":"1","title":"project#1 APPROVE @aaaaaaa","body":""}]' >"$MOCK_DIR/hub.json"
t custom-reviewer-hub-only-refused refuse
setup; echo '[]' >"$MOCK_DIR/reviews.json"
echo '[{"id":7,"author_bot":"Review Bot","created":"1","title":"project#1 APPROVE @aaaaaaa","body":""}]' >"$MOCK_DIR/hub.json"
t former-reviewer-refused refuse
echo "== $pass passed, $fail failed"; [ $fail -eq 0 ]
