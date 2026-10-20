#!/bin/bash
set -uo pipefail

# The return contract for fan-out (parallel worktree) agents.
#
#   ./ralph/result.sh validate <file>          # schema only
#   ./ralph/result.sh verify <file> <base>     # schema + check the claims against git,
#                                              # then re-run AGENTS.md Checks in the
#                                              # agent's worktree and compare exit codes.
#                                              # The base branch's Checks are the floor:
#                                              # a branch that drops one fails verify.
#
# Each agent writes issues/<id>.result.json in its worktree (uncommitted — the
# commit it names cannot contain itself) and ends its reply with the same JSON.
# The orchestrator copies that file verbatim and runs `verify`, so a failing
# check can never be relayed as a pass.
#
#   { "issue": "002",
#     "status": "done" | "partial" | "blocked",
#     "branch": "issue-002-signup-form",
#     "commit": "<sha of the last commit on branch>",
#     "files_touched": ["src/app/signup/page.tsx", "..."],
#     "checks": [ { "command": "npm run lint", "exit_code": 0 } ],
#     "open_questions": ["..."] }
#
# "checks" is the output of `ralph/checks.sh --json`, pasted as-is.
# status "done" requires a non-empty checks list with every exit_code 0.

die() { echo "result: $*" >&2; exit 1; }

validate() {
  local file="$1" errs=0 line
  [[ -f "$file" ]] || die "no such file: $file"
  jq -e . "$file" >/dev/null 2>&1 || die "$file is not valid JSON"
  while IFS= read -r line; do
    [[ -n "$line" ]] && { echo "result: $line" >&2; errs=$((errs + 1)); }
  done < <(jq -r '
    def req($k; $t): if (has($k) and (.[$k] | type) == $t) then empty
                     else "field \"\($k)\" missing or not a \($t)" end;
    req("issue"; "string"), req("status"; "string"), req("branch"; "string"),
    req("commit"; "string"), req("files_touched"; "array"), req("checks"; "array"),
    req("open_questions"; "array"),
    (if (.status | IN("done", "partial", "blocked")) then empty
     else "status must be done, partial or blocked" end),
    ((.checks // [])[] | select((.command | type) != "string" or (.exit_code | type) != "number")
       | "every checks entry needs a string command and a numeric exit_code"),
    (if .status == "done" and ((.checks | length) == 0) then "status done with no checks run" else empty end),
    (if .status == "done" and any(.checks[]?; .exit_code != 0)
     then "status done but a check exited non-zero: \([.checks[] | select(.exit_code != 0) | .command] | join(", "))"
     else empty end),
    (if .status != "done" and (.open_questions | length) == 0
     then "status \(.status) must say why in open_questions" else empty end)
  ' "$file")
  if (( errs )); then echo "result: INVALID $file ($errs problem(s))" >&2; return 1; fi
  echo "result: $file matches the contract (issue $(jq -r .issue "$file"), status $(jq -r .status "$file"))"
}

verify() {
  local file="$1" base="${2:-}"
  [[ -n "$base" ]] || die "usage: result.sh verify <file> <base-branch>"
  validate "$file" || return 1
  # Every path the branch changed: renames listed as delete + add (so moving a
  # protected file can't hide it), NUL-separated so odd names aren't quoted.
  changed() { git diff --name-only --no-renames -z "$base...$branch" | tr '\0' '\n' | sed '/^$/d'; }
  local branch commit errs=0
  branch=$(jq -r .branch "$file")
  # The orchestrator names the file after the issue it dispatched; the agent's
  # "issue" field must agree, or it could borrow another issue's (weaker) check.
  local named; named="$(basename "$file" .result.json)"
  if [[ "$named" != "$(jq -r .issue "$file")" ]]; then
    echo "result: $file reports issue $(jq -r .issue "$file") — the file name says $named" >&2
    errs=$((errs + 1))
  fi
  commit=$(jq -r .commit "$file")

  git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null || die "branch $branch does not exist"
  git cat-file -e "$commit^{commit}" 2>/dev/null || die "commit $commit does not exist"
  local tip; tip=$(git rev-parse "refs/heads/$branch")
  [[ "$(git rev-parse "$commit")" == "$tip" ]] \
    || { echo "result: commit $commit is not the tip of $branch ($tip) — the agent committed after reporting, or reported the wrong sha" >&2; errs=$((errs + 1)); }

  # files_touched must equal what the branch actually changed.
  local claimed actual
  claimed=$(jq -r '.files_touched[]' "$file" | sort -u)
  actual=$(changed | sort -u)
  if [[ "$claimed" != "$actual" ]]; then
    echo "result: files_touched does not match git diff $base...$branch" >&2
    diff <(echo "$claimed") <(echo "$actual") | sed 's/^</  claimed only:/; s/^>/  in diff only:/' | grep -E 'only:' >&2
    errs=$((errs + 1))
  fi

  # Shared state belongs to the orchestrator; parallel branches editing it collide
  # at merge, a branch must never flip its own passes flag, and ralph/ is the gate
  # that runs after the merge.
  local owned
  owned=$(changed | grep -E '^(issues/(status\.json|progress\.md|done/)|ralph/)' || true)
  if [[ -n "$owned" ]]; then
    echo "result: the branch edits orchestrator-owned files:" >&2
    sed 's/^/  /' <<<"$owned" >&2
    errs=$((errs + 1))
  fi

  # The gate itself is untrusted input from the branch: the base branch's Checks
  # are the floor. Adding a check is fine (the walking skeleton must); removing
  # or rewording one would let the re-run below agree with a weakened gate.
  local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local base_agents branch_agents dropped
  base_agents="$(mktemp)"; branch_agents="$(mktemp)"
  git show "$base:AGENTS.md" >"$base_agents" 2>/dev/null || : >"$base_agents"
  git show "$commit:AGENTS.md" >"$branch_agents" 2>/dev/null || : >"$branch_agents"
  dropped=$(comm -23 <("$here/checks.sh" --from "$base_agents" --list 2>/dev/null | sort -u) \
                     <("$here/checks.sh" --from "$branch_agents" --list 2>/dev/null | sort -u))
  rm -f "$base_agents"
  if [[ -n "$dropped" ]]; then
    echo "result: the branch removes or rewrites Checks that $base has — the gate cannot be weakened from a worktree:" >&2
    sed 's/^/  /' <<<"$dropped" >&2
    errs=$((errs + 1))
  fi

  # Re-run the gate in the agent's own worktree and compare exit codes. Ignored
  # files there (node_modules, .env.local) are part of the run; the clean-tree
  # gate is `ralph/status.sh pass` on the merged main checkout afterwards.
  local wt
  wt=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '
    /^worktree / { p = substr($0, 10) } $0 == "branch " b { print p; exit }')
  local dirty=""
  [[ -n "$wt" ]] && dirty=$(git -C "$wt" status --porcelain | grep -vE '^\?\? issues/[^/]+\.result\.json$' || true)
  if [[ -z "$wt" ]]; then
    echo "result: no worktree has $branch checked out — cannot re-run its checks" >&2
    errs=$((errs + 1))
  elif [[ -n "$dirty" ]]; then
    echo "result: $wt has uncommitted changes — the re-run would test those, not $commit:" >&2
    sed 's/^/  /' <<<"$dirty" >&2
    errs=$((errs + 1))
  else
    local rerun
    rerun=$(cd "$wt" && "$here/checks.sh" --from "$branch_agents" --json)
    # The issue's own check comes from the orchestrator's status file, not the report.
    local issue icheck=""
    issue=$(jq -r .issue "$file")
    if [[ -f issues/status.json ]]; then
      icheck=$(jq -r --arg id "$issue" '.issues[] | select(.id == $id) | .check // empty' issues/status.json)
      if [[ -z "$icheck" ]]; then
        echo "result: issue $issue has no check in issues/status.json — nothing to re-run it against" >&2
        errs=$((errs + 1))
      fi
    else
      echo "result: WARNING no issues/status.json — only the AGENTS.md Checks are re-run, not the issue's own check" >&2
    fi
    if [[ -n "$icheck" ]]; then
      echo "result: re-running issue $issue check in $wt: $icheck"
      local icode
      (cd "$wt" && bash -c "$icheck") >/dev/null 2>&1
      icode=$?
      rerun=$(jq -c --arg c "$icheck" --argjson e "$icode" '. + [{command: $c, exit_code: $e}]' <<<"$rerun")
    fi
    local mismatch
    mismatch=$(jq -rn --argjson claimed "$(jq .checks "$file")" --argjson rerun "$rerun" \
                      --arg status "$(jq -r .status "$file")" '
      ($rerun | map({key: .command, value: .exit_code}) | from_entries) as $r
      | ($claimed | map({key: .command, value: .exit_code}) | from_entries) as $c
      | ($claimed[] | .command as $cmd | select($r | has($cmd)) | select($r[$cmd] != .exit_code)
          | "  \(.command): agent said \(.exit_code), re-run gave \($r[.command])"),
        ($rerun[] | .command as $cmd | select($c | has($cmd) | not)
          | "  \(.command): left out of the report (re-run gave \(.exit_code))"),
        (if $status == "done" then ($rerun[] | select(.exit_code != 0)
          | "  \(.command) exits \(.exit_code) on re-run, but status is done") else empty end)
    ' | sort -u)
    if [[ -n "$mismatch" ]]; then
      echo "result: re-running the checks in $wt disagrees with the report:" >&2
      echo "$mismatch" >&2
      errs=$((errs + 1))
    else
      echo "result: re-ran $(jq length <<<"$rerun") check(s) in $wt — exit codes match the report"
    fi
  fi
  rm -f "$branch_agents"

  if (( errs )); then echo "result: NOT VERIFIED $file ($errs problem(s))" >&2; return 1; fi
  echo "result: VERIFIED $file — $(jq -r '"issue \(.issue) \(.status) on \(.branch) @ \(.commit[0:7])"' "$file")"
}

case "${1:-}" in
  validate) [[ -n "${2:-}" ]] || die "usage: result.sh validate <file>"; validate "$2" ;;
  verify)   [[ -n "${2:-}" ]] || die "usage: result.sh verify <file> <base-branch>"; verify "$2" "${3:-}" ;;
  *)        sed -n '4,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
