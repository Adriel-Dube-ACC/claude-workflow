#!/bin/bash
set -uo pipefail

# Behaviour tests for the harness scripts: ralph/checks.sh, ralph/status.sh,
# ralph/result.sh, ralph/context-hooks.sh, the progress lines and inbox flag of
# ralph/loop.sh, and bin/ralphify's AGENTS.md handling. Each test builds a
# throwaway git repo, so nothing here touches a real project.
#   tests/harness.test.sh        # exit 0 only if every assertion holds

TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/harness-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASSES=0; FAILS=0

ok()   { PASSES=$((PASSES + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAILS=$((FAILS + 1));   printf '  FAIL %s\n' "$1"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
refute() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$name"; else ok "$name"; fi; }

new_repo() { # new_repo <name> — git repo with the harness scripts copied in
  local d="$WORK/$1"
  mkdir -p "$d/ralph" "$d/issues/done"
  cp "$TEMPLATE"/ralph/*.sh "$d/ralph/"
  git -C "$d" init -q -b main
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  echo "$d"
}

agents_md() { # agents_md <dir> <check>...
  local d="$1"; shift
  {
    echo "# AGENTS.md"
    echo
    echo "## Checks (must all exit 0 before any commit)"
    echo
    echo "<!--"
    echo "- \`echo commented-out candidate must not run && false\`"
    echo "-->"
    for c in "$@"; do echo "- \`$c\` (note after the command is ignored)"; done
    echo
    echo "## Build & run"
    echo
    echo "- \`echo not a check\`"
  } >"$d/AGENTS.md"
}

status_json() { # status_json <dir> <check for 002>
  cat >"$1/issues/status.json" <<EOF
{ "version": 1, "prd": "issues/prd.md", "issues": [
  { "id": "001", "file": "001-walking-skeleton.md", "title": "Walking skeleton", "type": "HITL",
    "behaviour": "app loads", "check": "test -f skeleton.ok", "blockedBy": [], "passes": false },
  { "id": "002", "file": "002-feature.md", "title": "Feature", "type": "AFK",
    "behaviour": "feature works", "check": "$2", "blockedBy": ["001"], "passes": false } ] }
EOF
  touch "$1/issues/001-walking-skeleton.md" "$1/issues/002-feature.md"
}

echo "checks.sh"
R=$(new_repo checks)
agents_md "$R"
refute "empty Checks section is a failure, not a pass" bash -c "cd '$R' && ./ralph/checks.sh"
agents_md "$R" "true" "test 1 -eq 1"
check "all-green Checks exit 0" bash -c "cd '$R' && ./ralph/checks.sh"
check "--list prints only uncommented checks under ## Checks" \
  bash -c "cd '$R' && [[ \"\$(./ralph/checks.sh --list)\" == \$'true\ntest 1 -eq 1' ]]"
agents_md "$R" "true" "exit 3"
refute "one failing check fails the gate" bash -c "cd '$R' && ./ralph/checks.sh"
check "--json reports each real exit code" \
  bash -c "cd '$R' && ./ralph/checks.sh --json | jq -e 'map(.exit_code) == [0,3]'"

echo "status.sh"
R=$(new_repo status)
agents_md "$R" "true"
status_json "$R" "test -f feature.ok"
check "fresh status file validates" bash -c "cd '$R' && ./ralph/status.sh validate"
check "next runnable is none while the HITL skeleton fails" bash -c "cd '$R' && ! ./ralph/status.sh next"
jq '.issues[1].passes = true' "$R/issues/status.json" >"$R/s" && mv "$R/s" "$R/issues/status.json"
refute "a hand-flipped passes:true is rejected" bash -c "cd '$R' && ./ralph/status.sh validate"
status_json "$R" "test -f feature.ok"
touch "$R/issues/003-orphan.md"
refute "an issue file with no status entry is rejected" bash -c "cd '$R' && ./ralph/status.sh validate"
rm "$R/issues/003-orphan.md"
refute "pass is refused while a blocker fails" bash -c "cd '$R' && ./ralph/status.sh pass 002"
check "refusal is logged to progress.md" grep -q 'FAIL 002 — refused: blocker(s) 001' "$R/issues/progress.md"
refute "pass fails when the issue's own check fails" bash -c "cd '$R' && ./ralph/status.sh pass 001"
check "passes stays false after a failed check" jq -e '.issues[0].passes == false' "$R/issues/status.json"
check "the failed check and its exit code are logged" grep -q 'FAIL 001 — issue check `test -f skeleton.ok` exited 1' "$R/issues/progress.md"
agents_md "$R" "false"
touch "$R/skeleton.ok"
refute "pass fails when AGENTS.md Checks are red even if the issue check is green" bash -c "cd '$R' && ./ralph/status.sh pass 001"
agents_md "$R" "true"
git -C "$R" add -A && git -C "$R" commit -qm "baseline"
jq '.issues[0].check = "true"' "$R/issues/status.json" >"$R/s" && mv "$R/s" "$R/issues/status.json"
refute "pass is refused when the issue's check was edited but not committed" bash -c "cd '$R' && ./ralph/status.sh pass 001"
git -C "$R" checkout -q -- issues/status.json
agents_md "$R"
refute "pass is refused when the working AGENTS.md drops a committed Check" bash -c "cd '$R' && ./ralph/status.sh pass 001"
agents_md "$R" "true" "rm -f skeleton.ok"
refute "pass is refused when the working AGENTS.md adds an uncommitted Check" bash -c "cd '$R' && ./ralph/status.sh pass 001"
check "the extra check never ran (the tree was not touched)" test -f "$R/skeleton.ok"
agents_md "$R" "true"
echo '# tampered' >>"$R/ralph/checks.sh"
refute "pass is refused when ralph/ has uncommitted changes" bash -c "cd '$R' && ./ralph/status.sh pass 001"
git -C "$R" checkout -q -- ralph/checks.sh
check "pass succeeds when Checks and the issue check are green" bash -c "cd '$R' && ./ralph/status.sh pass 001"
check "passes flipped with verified evidence" \
  jq -e '.issues[0].passes == true and .issues[0].verified.check.exit_code == 0 and (.issues[0].verified.agentsChecks | length) == 1' "$R/issues/status.json"
check "PASS line logged" grep -q 'PASS 001 — issue check `test -f skeleton.ok` → 0' "$R/issues/progress.md"
check "a verified pass still validates" bash -c "cd '$R' && ./ralph/status.sh validate"
cp "$R/issues/status.json" "$WORK/good-status.json"
jq '.issues[0].check = "true"' "$WORK/good-status.json" >"$R/issues/status.json"
refute "evidence recorded for a different check is rejected" bash -c "cd '$R' && ./ralph/status.sh validate"
jq '.issues[0].verified.base = "deadbee"' "$WORK/good-status.json" >"$R/issues/status.json"
refute "evidence pointing at a non-existent commit is rejected" bash -c "cd '$R' && ./ralph/status.sh validate"
cp "$WORK/good-status.json" "$R/issues/status.json"
check "next runnable is now the AFK issue it unblocked" bash -c "cd '$R' && [[ \$(./ralph/status.sh next) == 002 ]]"
mv "$R/issues/001-walking-skeleton.md" "$R/issues/done/"
check "an issue moved to done/ still resolves" bash -c "cd '$R' && ./ralph/status.sh validate"

echo "loop.sh progress lines"
R=$(new_repo loop)
cp "$TEMPLATE/ralph/PROMPT_build.md" "$R/ralph/"
agents_md "$R" "true"
status_json "$R" "true"
git -C "$R" add -A && git -C "$R" commit -qm init
mkdir -p "$WORK/fakebin"
cat >"$WORK/fakebin/claude" <<'EOF'
#!/bin/bash
echo '{"type":"result","result":"<promise>NO MORE TASKS</promise>"}'
EOF
chmod +x "$WORK/fakebin/claude"
check "loop.sh runs to completion with a stub claude" bash -c "cd '$R' && PATH='$WORK/fakebin:$PATH' ./ralph/loop.sh build 2"
check "loop logs the iteration start with HEAD and status" grep -qE 'loop: build iteration 1/2 started — HEAD [0-9a-f]+, 0/2 passing' "$R/issues/progress.md"
check "loop logs completion" grep -q 'loop: build complete after 1 iteration(s)' "$R/issues/progress.md"

echo "result.sh"
R=$(new_repo result)
agents_md "$R" "true"
status_json "$R" "test -f feature.txt"
echo base >"$R/README.md"
git -C "$R" add -A && git -C "$R" commit -qm base
git -C "$R" worktree add -q -b issue-002 "$WORK/result-wt" main
echo feature >"$WORK/result-wt/feature.txt"
git -C "$WORK/result-wt" add feature.txt && git -C "$WORK/result-wt" commit -qm feature
SHA=$(git -C "$WORK/result-wt" rev-parse HEAD)
contract() { # contract <status> <files json> <checks json> <questions json>
  printf '{"issue":"002","status":"%s","branch":"issue-002","commit":"%s","files_touched":%s,"checks":%s,"open_questions":%s}\n' \
    "$1" "$SHA" "$2" "$3" "$4" >"$R/issues/002.result.json"
}
GREEN='[{"command":"true","exit_code":0},{"command":"test -f feature.txt","exit_code":0}]'
contract 'done' '["feature.txt"]' "$GREEN" '[]'
refute "a result naming a different branch than the one dispatched fails verify" \
  bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main issue-002-other"
check "a truthful done result validates" bash -c "cd '$R' && ./ralph/result.sh validate issues/002.result.json"
check "a truthful done result verifies against git and a re-run (Checks + issue check)" \
  bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main issue-002"
contract 'done' '["feature.txt"]' '[{"command":"true","exit_code":1}]' '[]'
refute "done with a non-zero exit code is rejected" bash -c "cd '$R' && ./ralph/result.sh validate issues/002.result.json"
contract partial '["feature.txt"]' '[{"command":"true","exit_code":0}]' '[]'
refute "partial without open_questions is rejected" bash -c "cd '$R' && ./ralph/result.sh validate issues/002.result.json"
contract 'done' '["feature.txt"]' '[{"command":"true","exit_code":0}]' '[]'
refute "a report that leaves out the issue's own check fails verify" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
contract 'done' '["feature.txt","src/other.ts"]' "$GREEN" '[]'
refute "files_touched that disagree with the diff fail verify" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
contract 'done' '["feature.txt"]' "$GREEN" '[]'
echo scratch >"$WORK/result-wt/uncommitted.txt"
refute "uncommitted work in the worktree fails verify" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
rm "$WORK/result-wt/uncommitted.txt"
agents_md "$WORK/result-wt" "true" "exit 4"
git -C "$WORK/result-wt" commit -qam "add a failing check"
SHA=$(git -C "$WORK/result-wt" rev-parse HEAD)
contract 'done' '["AGENTS.md","feature.txt"]' '[{"command":"true","exit_code":0},{"command":"exit 4","exit_code":0},{"command":"test -f feature.txt","exit_code":0}]' '[]'
refute "a claimed exit 0 that re-runs as non-zero fails verify" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
contract partial '["AGENTS.md","feature.txt"]' '[{"command":"true","exit_code":0},{"command":"exit 4","exit_code":4},{"command":"test -f feature.txt","exit_code":0}]' '["exit 4 still fails: needs a human decision"]'
check "an honest partial (failing check reported as failing) verifies" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
agents_md "$WORK/result-wt" "test 2 -gt 1"
git -C "$WORK/result-wt" commit -qam "swap the gate for an easier one"
SHA=$(git -C "$WORK/result-wt" rev-parse HEAD)
contract 'done' '["AGENTS.md","feature.txt"]' '[{"command":"test 2 -gt 1","exit_code":0},{"command":"test -f feature.txt","exit_code":0}]' '[]'
refute "a branch that drops a base-branch Check fails verify" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
git -C "$WORK/result-wt" reset -q --hard "$SHA~1"
jq '.issues[1].passes = true' "$WORK/result-wt/issues/status.json" >"$WORK/s" && mv "$WORK/s" "$WORK/result-wt/issues/status.json"
git -C "$WORK/result-wt" commit -qam "flip my own flag"
SHA=$(git -C "$WORK/result-wt" rev-parse HEAD)
contract partial '["AGENTS.md","feature.txt","issues/status.json"]' '[{"command":"true","exit_code":0},{"command":"exit 4","exit_code":4},{"command":"test -f feature.txt","exit_code":0}]' '["x"]'
refute "a branch that edits issues/status.json fails verify" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
git -C "$WORK/result-wt" reset -q --hard "$SHA~1"
git -C "$WORK/result-wt" mv issues/status.json issues/moved.json
git -C "$WORK/result-wt" commit -qm "move the status file away"
SHA=$(git -C "$WORK/result-wt" rev-parse HEAD)
contract partial '["AGENTS.md","feature.txt","issues/moved.json"]' '[{"command":"true","exit_code":0},{"command":"exit 4","exit_code":4},{"command":"test -f feature.txt","exit_code":0}]' '["x"]'
refute "renaming issues/status.json away is still caught" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
git -C "$WORK/result-wt" reset -q --hard "$SHA~1"
echo 'exit 0' >"$WORK/result-wt/ralph/checks.sh"
git -C "$WORK/result-wt" commit -qam "neuter the gate"
SHA=$(git -C "$WORK/result-wt" rev-parse HEAD)
contract partial '["AGENTS.md","feature.txt","ralph/checks.sh"]' '[{"command":"true","exit_code":0},{"command":"exit 4","exit_code":4},{"command":"test -f feature.txt","exit_code":0}]' '["x"]'
refute "a branch that edits ralph/ fails verify" bash -c "cd '$R' && ./ralph/result.sh verify issues/002.result.json main"
cp "$R/issues/002.result.json" "$R/issues/003.result.json"
refute "a result whose issue id disagrees with its file name fails verify" bash -c "cd '$R' && ./ralph/result.sh verify issues/003.result.json main"
jq '.issue = "009"' "$R/issues/002.result.json" >"$R/issues/009.result.json"
refute "an issue with no status.json entry fails verify instead of skipping its check" bash -c "cd '$R' && ./ralph/result.sh verify issues/009.result.json main"
refute "missing required fields are rejected" bash -c "cd '$R' && echo '{\"issue\":\"002\"}' >issues/bad.json && ./ralph/result.sh validate issues/bad.json"

echo "checks.sh --from"
check "--from reads another AGENTS.md" bash -c "cd '$R' && git show main:AGENTS.md >'$WORK/base-agents.md' && [[ \$(./ralph/checks.sh --from '$WORK/base-agents.md' --list) == true ]]"

echo "ralphify AGENTS.md handling"
N="$WORK/next-app"
mkdir -p "$N"
printf '<!-- BEGIN:nextjs-agent-rules -->\n\n## This is NOT the Next.js you know\n\nRead node_modules/next/dist/docs/.\n\n<!-- END:nextjs-agent-rules -->\n' >"$N/AGENTS.md"
echo '{"name":"x","scripts":{"lint":"eslint","build":"next build"}}' >"$N/package.json"
cp "$N/AGENTS.md" "$WORK/original-agents.md"
git -C "$N" init -q
check "ralphify runs on a create-next-app style project" env CLAUDE_WORKFLOW_TEMPLATE="$TEMPLATE" "$TEMPLATE/bin/ralphify" "$N"
check "the original AGENTS.md is kept byte-for-byte as the prefix" \
  bash -c "head -c \$(wc -c <'$WORK/original-agents.md') '$N/AGENTS.md' | cmp -s - '$WORK/original-agents.md'"
check "the managed Next.js markers survive" bash -c "grep -q 'BEGIN:nextjs-agent-rules' '$N/AGENTS.md' && grep -q 'END:nextjs-agent-rules' '$N/AGENTS.md'"
check "a Checks section is appended inside ralph-harness markers" \
  bash -c "awk '/BEGIN:ralph-harness/{a=1} a && /^## Checks/{c=1} /END:ralph-harness/{e=a&&c} END{exit !e}' '$N/AGENTS.md'"
check "detected candidates are commented out, so checks.sh still reports no gate" \
  bash -c "grep -q '^- \`npm run lint\`' '$N/AGENTS.md' && cd '$N' && ! ./ralph/checks.sh"
check "the new CLAUDE.md imports AGENTS.md" grep -qx '@AGENTS.md' "$N/CLAUDE.md"
cp "$N/AGENTS.md" "$WORK/after-first.md"
env CLAUDE_WORKFLOW_TEMPLATE="$TEMPLATE" "$TEMPLATE/bin/ralphify" "$N" >/dev/null 2>&1
check "a second ralphify run appends nothing" cmp -s "$N/AGENTS.md" "$WORK/after-first.md"
check "next's own upsert still finds its block (replace in place, not re-append)" \
  bash -c "[[ \$(grep -c 'BEGIN:nextjs-agent-rules' '$N/AGENTS.md') == 1 ]]"
F="$WORK/filled"
mkdir -p "$F" && agents_md "$F" "true" && cp "$F/AGENTS.md" "$WORK/filled-orig.md"
env CLAUDE_WORKFLOW_TEMPLATE="$TEMPLATE" "$TEMPLATE/bin/ralphify" "$F" >/dev/null 2>&1
check "an AGENTS.md that already has Checks is left untouched" cmp -s "$F/AGENTS.md" "$WORK/filled-orig.md"

echo "status.sh agreement with issue files"
R=$(new_repo agree)
agents_md "$R" "true"
status_json "$R" "test -f feature.ok"
issue_file() { # issue_file <path> <type line> <check> <blocked-by body>
  printf '# Title\n\n## Type\n\n%s\n\n## Check\n\n`%s`\n\n## Blocked by\n\n%s\n' "$2" "$3" "$4" >"$1"
}
agree_files() {
  issue_file "$R/issues/001-walking-skeleton.md" "HITL (human prerequisites below) — or AFK if they already exist" \
    "test -f skeleton.ok" "None - can start immediately"
  issue_file "$R/issues/002-feature.md" "AFK" "test -f feature.ok" "- Blocked by \`issues/001-walking-skeleton.md\`"
}
agree_files
check "issue files that agree with status.json validate" bash -c "cd '$R' && ./ralph/status.sh validate"
issue_file "$R/issues/002-feature.md" "HITL" "test -f feature.ok" "- Blocked by \`issues/001-walking-skeleton.md\`"
refute "an issue file whose Type disagrees is rejected" bash -c "cd '$R' && ./ralph/status.sh validate"
check "the disagreement names both sides" bash -c "cd '$R' && ./ralph/status.sh validate 2>&1 | grep -q 'says type HITL, issues/status.json says AFK'"
agree_files; issue_file "$R/issues/002-feature.md" "AFK" "true" "- Blocked by \`issues/001-walking-skeleton.md\`"
refute "an issue file whose Check disagrees is rejected" bash -c "cd '$R' && ./ralph/status.sh validate"
agree_files; issue_file "$R/issues/002-feature.md" "AFK" "test -f feature.ok" "None - can start immediately"
refute "an issue file whose Blocked by disagrees is rejected" bash -c "cd '$R' && ./ralph/status.sh validate"
agree_files
mv "$R/issues/002-feature.md" "$R/issues/feature-002.md"
jq '.issues[1].file = "feature-002.md"' "$R/issues/status.json" >"$R/s" && mv "$R/s" "$R/issues/status.json"
refute "a file name that does not start with its id is rejected" bash -c "cd '$R' && ./ralph/status.sh validate"

echo "checks.sh run record"
R=$(new_repo record)
agents_md "$R" "true" "exit 3"
(cd "$R" && ./ralph/checks.sh >/dev/null 2>&1)
REC="$(git -C "$R" rev-parse --path-format=absolute --git-path ralph/last-checks.json)"
check "checks.sh records each exit code of its last run" jq -e '.results | map(.exit_code) == [0,3]' "$REC"
check "the record lives under the git dir, not the working tree" bash -c "[[ '$REC' == \"\$(git -C '$R' rev-parse --absolute-git-dir)/\"* ]]"

echo "context-hooks.sh"
R=$(new_repo hooks)
agents_md "$R" "true" "exit 3"
status_json "$R" "test -f feature.ok"
git -C "$R" add -A && git -C "$R" commit -qm init
git -C "$R" checkout -q -b issue-002
(cd "$R" && ./ralph/checks.sh >/dev/null 2>&1; ./ralph/status.sh progress "002: WIP — wired the form; next: make the save test pass")
NOTE="$(git -C "$R" rev-parse --path-format=absolute --git-path ralph/context.md)"
PRE='{"session_id":"s-1","hook_event_name":"PreCompact","trigger":"manual","custom_instructions":"keep the save-test plan"}'
check "precompact exits 0 and writes the note" bash -c "cd '$R' && echo '$PRE' | ./ralph/context-hooks.sh precompact && test -s '$NOTE'"
check "the note names the current issue (from the branch)" grep -q 'Current issue: 002 — Feature (AFK), check: `test -f feature.ok` (from branch issue-002)' "$NOTE"
check "the note names the failing check and its exit code" grep -q 'failing: `exit 3` (exit 3)' "$NOTE"
check "the note carries the last progress line as the next step" grep -q 'next: make the save test pass' "$NOTE"
check "the note carries the /compact focus line" grep -q '/compact focus: keep the save-test plan' "$NOTE"
check "the note is never in the working tree" bash -c "[[ '$NOTE' == \"\$(git -C '$R' rev-parse --absolute-git-dir)/\"* ]] && ! git -C '$R' status --porcelain --ignored | grep -q context.md"
check "sessionstart(compact) re-injects the note as additionalContext" bash -c "cd '$R' && echo '{\"session_id\":\"s-1\",\"source\":\"compact\"}' | ./ralph/context-hooks.sh sessionstart \
  | jq -e '.hookSpecificOutput.hookEventName == \"SessionStart\" and (.hookSpecificOutput.additionalContext | contains(\"Current issue: 002\"))'"
check "sessionstart on a fresh startup injects nothing" bash -c "cd '$R' && [[ -z \$(echo '{\"session_id\":\"s-1\",\"source\":\"startup\"}' | ./ralph/context-hooks.sh sessionstart) ]]"
touch -t 202001010000 "$NOTE"
check "an old note from another session is not injected" bash -c "cd '$R' && [[ -z \$(echo '{\"session_id\":\"s-2\",\"source\":\"compact\"}' | ./ralph/context-hooks.sh sessionstart) ]]"
check "an old note from the same session still is" bash -c "cd '$R' && echo '{\"session_id\":\"s-1\",\"source\":\"compact\"}' | ./ralph/context-hooks.sh sessionstart | jq -e .hookSpecificOutput"
check "precompact never blocks compaction, even on garbage input" bash -c "cd '$R' && echo 'not json' | ./ralph/context-hooks.sh precompact"
U=$(new_repo unwritable)
touch "$(git -C "$U" rev-parse --absolute-git-dir)/ralph"
check "precompact exits 0 even when the note cannot be written (exit 2 would block compaction)" \
  bash -c "cd '$U' && echo '$PRE' | ./ralph/context-hooks.sh precompact"
git -C "$R" checkout -q main
(cd "$R" && ./ralph/context-hooks.sh snapshot >/dev/null)
check "off an issue branch the issue comes from the last progress line" grep -q 'Current issue: 002 .*(from last progress line)' "$NOTE"
git -C "$R" worktree add -q -b issue-001 "$WORK/hooks-wt" main
(cd "$WORK/hooks-wt" && echo '{"session_id":"w"}' | ./ralph/context-hooks.sh precompact)
WTNOTE="$(git -C "$WORK/hooks-wt" rev-parse --path-format=absolute --git-path ralph/context.md)"
check "each worktree keeps its own note" bash -c "[[ '$WTNOTE' != '$NOTE' ]] && grep -q 'Current issue: 001' '$WTNOTE' && grep -q 'Current issue: 002' '$NOTE'"
mkdir -p "$R/.claude"
echo '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' >"$R/.claude/settings.local.json"
check "install adds the two hooks to settings.local.json" bash -c "cd '$R' && ./ralph/context-hooks.sh install"
S="$R/.claude/settings.local.json"
check "install keeps the user's own hooks and settings" \
  jq -e '(.hooks.PreCompact | length) == 2 and .hooks.PreCompact[0].hooks[0].command == "echo mine" and .permissions.allow == ["Bash(ls)"]' "$S"
check "SessionStart is matched to compact only" jq -e '.hooks.SessionStart == [.hooks.SessionStart[0]] and .hooks.SessionStart[0].matcher == "compact"' "$S"
(cd "$R" && ./ralph/context-hooks.sh install >/dev/null)
check "a second install adds nothing" jq -e '(.hooks.PreCompact | length) == 2 and (.hooks.SessionStart | length) == 1' "$S"
check "settings.local.json is kept out of git" git -C "$R" check-ignore -q .claude/settings.local.json
rm -f "$NOTE"
CMD="$(jq -r '.hooks.PreCompact[1].hooks[0].command' "$S")"
check "the installed PreCompact command runs as Claude Code would run it" \
  bash -c "cd /tmp && echo '$PRE' | CLAUDE_PROJECT_DIR='$R' bash -c '$CMD' && grep -q 'Current issue: 002' '$NOTE'"
(cd "$R" && ./ralph/context-hooks.sh uninstall >/dev/null)
check "uninstall removes only the harness hooks" \
  jq -e '.hooks == {"PreCompact":[{"hooks":[{"type":"command","command":"echo mine"}]}]} and .permissions.allow == ["Bash(ls)"]' "$S"
(cd "$R" && ./ralph/context-hooks.sh install --shared >/dev/null)
check "install --shared writes the committed settings.json" jq -e '.hooks.SessionStart[0].matcher == "compact"' "$R/.claude/settings.json"
(cd "$R" && ./ralph/context-hooks.sh uninstall --shared >/dev/null)
check "uninstall --shared leaves no empty hooks object" jq -e 'has("hooks") | not' "$R/.claude/settings.json"

echo "loop.sh inbound messages"
R=$(new_repo inbound)
cp "$TEMPLATE/ralph/PROMPT_build.md" "$R/ralph/"
agents_md "$R" "true"
status_json "$R" "true"
git -C "$R" add -A && git -C "$R" commit -qm init
mkdir -p "$WORK/argbin"
cat >"$WORK/argbin/claude" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >"$WORK/claude-args"
echo '{"type":"result","result":"<promise>NO MORE TASKS</promise>"}'
EOF
chmod +x "$WORK/argbin/claude"
check "RALPH_INBOUND=accept starts claude with crossSessionInbound accept" \
  bash -c "cd '$R' && RALPH_INBOUND=accept PATH='$WORK/argbin:$PATH' ./ralph/loop.sh build 1 >/dev/null && grep -A1 -x -- '--settings' '$WORK/claude-args' | grep -qx '{\"crossSessionInbound\":\"accept\"}'"
check "without RALPH_INBOUND no settings are passed" \
  bash -c "cd '$R' && PATH='$WORK/argbin:$PATH' ./ralph/loop.sh build 1 >/dev/null && ! grep -qx -- '--settings' '$WORK/claude-args'"
refute "an unknown RALPH_INBOUND value is refused" bash -c "cd '$R' && RALPH_INBOUND=yes PATH='$WORK/argbin:$PATH' ./ralph/loop.sh build 1"

echo "AGENTS.md context section"
check "the template AGENTS.md has the Context & handoff section" grep -q '^## Context & handoff' "$TEMPLATE/AGENTS.md"
check "the context section does not leak into the parsed Checks" \
  bash -c "cp '$TEMPLATE/AGENTS.md' '$WORK/tpl-agents.md' && ! '$TEMPLATE/ralph/checks.sh' --from '$WORK/tpl-agents.md' --list"
check "ralphify's appended harness section includes it" grep -q '^## Context & handoff' "$WORK/next-app/AGENTS.md"

echo
echo "harness tests: $PASSES passed, $FAILS failed"
(( FAILS == 0 ))
