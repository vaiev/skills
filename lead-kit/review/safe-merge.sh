#!/usr/bin/env bash
# safe-merge.sh <owner/repo|repo> <pr> [--dry-run] [--allow-unverified-ci]
# Pre-merge guard for explicitly allowed repositories.
# Env overrides: GH_BIN (default gh), HUB_BIN (default hub)
set -euo pipefail
GH="${GH_BIN:-gh}"; HUB="${HUB_BIN:-hub}"
DRY=0; ALLOW_CI=0; ARGS=()
for a in "$@"; do case "$a" in
  --dry-run) DRY=1;; --allow-unverified-ci) ALLOW_CI=1;;
  -h|--help) sed -n '2,5p' "$0"; exit 0;; *) ARGS+=("$a");; esac; done
[ ${#ARGS[@]} -eq 2 ] || { echo "usage: $0 <repo> <pr> [--dry-run] [--allow-unverified-ci]" >&2; exit 2; }
CONFIG="${SAFE_MERGE_CONFIG:-$HOME/.config/lead-kit/safe-merge.conf}"
# Config is a trusted shell file; isolate it so environment overrides win.
if [[ ${SAFE_MERGE_ALLOWED_REPOS+x} ]]; then
  ALLOWED=$SAFE_MERGE_ALLOWED_REPOS
elif [ -f "$CONFIG" ]; then
  ALLOWED=$( (unset ALLOWED_REPOS; source "$CONFIG"; printf '%s' "${ALLOWED_REPOS:-}") )
else
  ALLOWED=""
fi
if [[ ${SAFE_MERGE_REVIEWER_LOGINS+x} ]]; then
  REVIEWERS=$SAFE_MERGE_REVIEWER_LOGINS
elif [ -f "$CONFIG" ]; then
  REVIEWERS=$( (unset REVIEWER_LOGINS; source "$CONFIG"; printf '%s' "${REVIEWER_LOGINS:-}") )
else
  REVIEWERS=""
fi
[[ "${REVIEWERS//[,[:space:]]/}" ]] || { echo "REFUSE: empty reviewer login allowlist" >&2; exit 3; }
read -r -a ALLOWED_LIST <<< "${ALLOWED//,/ }"
[ ${#ALLOWED_LIST[@]} -gt 0 ] || { echo "REFUSE: empty repository allowlist" >&2; exit 3; }
REPO="${ARGS[0]}"; PR="${ARGS[1]}"
if [[ "$REPO" != */* ]]; then
  [ -n "${SAFE_MERGE_DEFAULT_OWNER:-}" ] || { echo "REFUSE: bare repo requires SAFE_MERGE_DEFAULT_OWNER" >&2; exit 3; }
  REPO="$SAFE_MERGE_DEFAULT_OWNER/$REPO"
fi
FOUND=0
for entry in "${ALLOWED_LIST[@]}"; do [ "$REPO" != "$entry" ] || FOUND=1; done
[ "$FOUND" = 1 ] || { echo "REFUSE: $REPO not in repository allowlist" >&2; exit 3; }
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "REFUSE: bad PR number" >&2; exit 2; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

"$GH" api "repos/$REPO/pulls/$PR" > "$TMP/pr.json"
HEAD=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["head"]["sha"])' "$TMP/pr.json")
echo "PR $REPO#$PR head=$HEAD"
"$GH" api --paginate "repos/$REPO/pulls/$PR/reviews" | python3 -c 'import sys,json;d=json.JSONDecoder();s=sys.stdin.read();o=[];i=0
while i<len(s):
  s2=s[i:].lstrip()
  if not s2:break
  v,n=d.raw_decode(s2);o+=v;i=len(s)-len(s2)+n
json.dump(o,sys.stdout)' > "$TMP/reviews.json"
"$GH" api "repos/$REPO/issues/$PR/comments?per_page=100" > "$TMP/comments.json"
"$HUB" --json note search "$REPO#$PR" > "$TMP/hub.json" 2>/dev/null || echo '[]' > "$TMP/hub.json"

python3 - "$HEAD" "$REPO" "$PR" "$TMP" "${SAFE_MERGE_REVIEWER:-Review Bot}" "$REVIEWERS" <<'PY' || exit 4
import json,sys,re
head,repo,pr,t,reviewer,reviewer_logins=sys.argv[1:]; short=repo.split('/')[1]
L=lambda f: json.load(open(f"{t}/{f}"))
allowed=set(re.split(r'[,\s]+', reviewer_logins.strip())) - {''}
def trusted(item):
    return (item.get("user") or {}).get("login") in allowed
revs=[r for r in L("reviews.json") if trusted(r)]
coms=[c for c in L("comments.json") if trusted(c)]
try: hub=L("hub.json"); hub=hub if isinstance(hub,list) else hub.get("results",[])
except Exception: hub=[]
def cites(body):
    return any(len(s)>=7 and head.startswith(s.lower()) for s in re.findall(r'\b[0-9a-fA-F]{7,40}\b', body or ''))
def verdict(body):
    b=body or ''
    if not re.search(re.escape(reviewer)+r'|^\W*Verdict:', b, re.M): return None
    m=re.search(r'Verdict:?\**\s*\**\s*([A-Z_]+)', b)
    if not m: return None
    v=m.group(1); return 'APPROVE' if v=='APPROVE' else ('BLOCK' if v in('BLOCK','REQUEST_CHANGES','CHANGES_REQUESTED') else None)
fail=[]
latest={}
for r in revs:
    if r.get("state") in ("APPROVED","CHANGES_REQUESTED","DISMISSED"):
        latest[r["user"]["login"]]=r
for u,r in latest.items():
    if r["state"]=="CHANGES_REQUESTED": fail.append(f"latest review from {u} is CHANGES_REQUESTED")
# Review Bot verdicts (posted as COMMENT reviews / PR comments, same GitHub identity)
ev=[]
for r in revs:
    v=verdict(r.get("body"))
    if v: ev.append((r.get("submitted_at",""),v,r.get("commit_id")==head or cites(r.get("body")),"review "+str(r.get("id"))))
for c in coms:
    v=verdict(c.get("body"))
    if v: ev.append((c.get("created_at",""),v,cites(c.get("body")),"comment "+str(c.get("id"))))
for n in hub:
    if n.get("author_bot")!=reviewer: continue
    txt=(n.get("title","")+"\n"+n.get("body",""))
    if not re.search(re.escape(short)+r'#'+pr+r'\b', txt): continue
    if re.search(r'\b(?:BLOCK|REQUEST_CHANGES|CHANGES_REQUESTED)\b',txt):
        ev.append((n.get("created",""),'BLOCK',cites(txt),"hub note "+str(n.get("id"))))
ev.sort()
if ev and ev[-1][1]=='BLOCK': fail.append(f"latest {reviewer} verdict is BLOCK ({ev[-1][3]})")
appr=[r for r in revs if r.get("state")=="APPROVED" and r.get("commit_id")==head]
rb=[e for e in ev if e[1]=='APPROVE' and e[2]]
if not appr and not rb: fail.append(f"no APPROVED review / {reviewer} APPROVE bound to head "+head[:7])
for f in fail: print("REFUSE:",f)
if fail: sys.exit(1)
print("OK reviews:", ", ".join([f"APPROVED by {r['user']['login']}" for r in appr]+[e[3] for e in rb]))
PY

# CI gate: GitHub Actions runs for head SHA (fine-grained PATs cannot read check-runs)
set +e; AR=$("$GH" api "repos/$REPO/actions/runs?head_sha=$HEAD&per_page=100" 2>&1); RC=$?; set -e
if [ $RC -ne 0 ]; then
  echo "WARNING: actions runs unreadable"
  [ $ALLOW_CI -eq 1 ] || { echo "REFUSE: CI unverified (pass --allow-unverified-ci to override)"; exit 5; }
else
  # Only the LATEST run per (workflow, event) counts, so a green re-run supersedes an
  # older failed run. Still fail closed: no runs, latest not completed, or latest not success.
  REQ_CONF=${SAFE_MERGE_REQUIRED_CONFIG:-$(dirname "$0")/required-workflows.conf}
  [ -n "${SAFE_MERGE_REQUIRED_CONFIG+x}" ] && echo "WARNING: SAFE_MERGE_REQUIRED_CONFIG is set ($REQ_CONF); the shipped required-workflows.conf is NOT used"
  if [ -n "${SAFE_MERGE_REQUIRED_WORKFLOWS+x}" ]; then
    echo "WARNING: SAFE_MERGE_REQUIRED_WORKFLOWS is set; it replaces the configured list for $REPO"
    REQ=$SAFE_MERGE_REQUIRED_WORKFLOWS; REQ_SRC="env SAFE_MERGE_REQUIRED_WORKFLOWS"; REQ_FOUND=1
  else
    REQ_LINE=$(awk -v r="$REPO" -F: '$0 !~ /^[[:space:]]*#/ && $1 == r { print; exit }' "$REQ_CONF" 2>/dev/null || true)
    REQ=${REQ_LINE#*:}; REQ_SRC="$REQ_CONF entry $REPO"; REQ_FOUND=$([ -n "$REQ_LINE" ] && echo 1 || echo 0)
  fi
  # Normalise: trim each entry, drop empties; an empty result is never "no requirement".
  REQ=$(printf '%s' "${REQ:-}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | paste -sd, - | sed 's/,/, /g' || true)
  if [ "$REQ_FOUND" = 0 ]; then
    echo "WARNING: no required workflows configured for $REPO in $REQ_CONF"
    [ $ALLOW_CI -eq 1 ] || { echo "REFUSE: CI unverified (repo not in $REQ_CONF; pass --allow-unverified-ci)"; exit 5; }
  elif [ -z "$REQ" ]; then
    echo "REFUSE: required workflow list is empty after trimming (source: $REQ_SRC)"; exit 5
  else
    echo "required workflows: $REQ (source: $REQ_SRC)"
  fi
  RES=$(python3 - "$AR" "$REQ" "$HEAD" <<'PY'
import json, sys
head = sys.argv[3]
# Client-side guard: only runs for exactly this head SHA count.
runs = [x for x in json.loads(sys.argv[1]).get("workflow_runs", []) if x.get("head_sha", head) == head]
required = [w.strip() for w in sys.argv[2].split(",") if w.strip()]
if not runs:
    print("NONE"); sys.exit()
latest = {}
for x in runs:
    key = (x.get("workflow_id") or x.get("name"), x.get("event", ""))
    rank = (x.get("run_number", 0), x.get("run_attempt", 1), x.get("created_at", ""), x.get("id", 0))
    if key not in latest or rank > latest[key][0]:
        latest[key] = (rank, x)
bad = [f'{x["name"]}[{x.get("event", "")}]:{x.get("conclusion") or x["status"]}'
       for _, x in latest.values()
       if x["status"] != "completed" or x.get("conclusion") != "success"]
names = {x["name"] for _, x in latest.values()}
bad += [f"{w}:missing" for w in required if w not in names]
print(" ".join(bad))
PY
)
  if [ "$RES" = NONE ]; then echo "WARNING: no Actions runs for head SHA"; [ $ALLOW_CI -eq 1 ] || { echo "REFUSE: CI unverified (no runs; pass --allow-unverified-ci)"; exit 5; }
  elif [ -n "$RES" ]; then echo "REFUSE: actions runs not green: $RES"; exit 5
  else echo "OK latest actions run per workflow+event completed+success"; fi
fi
# Optional: check-runs (informational only)
set +e; CR=$("$GH" api "repos/$REPO/commits/$HEAD/check-runs" 2>&1); RC=$?; set -e
if [ $RC -ne 0 ]; then grep -q 403 <<<"$CR" && echo "WARNING: checks unreadable, token lacks checks:read (informational; Actions gate used)" || echo "WARNING: check-runs query failed (informational)"
else
  BAD=$(python3 -c 'import json,sys;d=json.loads(sys.argv[1]);print(" ".join(c["name"]+":"+str(c.get("conclusion") or c["status"]) for c in d.get("check_runs",[]) if c.get("conclusion") not in("success","neutral","skipped")))' "$CR")
  [ -z "$BAD" ] || { echo "REFUSE: checks not green: $BAD"; exit 5; }
  echo "OK check-runs green"
fi
CMD=("$GH" pr merge "$PR" -R "$REPO" --squash --match-head-commit "$HEAD")
if [ $DRY -eq 1 ]; then echo "DRY-RUN: would run: ${CMD[*]}"; exit 0; fi
"${CMD[@]}"
