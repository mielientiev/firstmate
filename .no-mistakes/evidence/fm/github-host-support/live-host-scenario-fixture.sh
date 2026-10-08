#!/usr/bin/env bash
# Independent live drive of firstmate's PR tooling against a disposable
# self-hosted GitHub host fixture. The real product scripts run; only the
# external forge CLI (gh) is a stub that records the host each command saw.
set -u
REPO=${REPO:-/home/coder/.no-mistakes/worktrees/a51cecb24137/01M4E01THEKA92YHWE931E4XJ0}
DIR=${DIR:-/tmp/fm-live-host-scenario/work}
rm -rf "$DIR"; mkdir -p "$DIR/home/state" "$DIR/home/data" "$DIR/home/config" "$DIR/fakebin" "$DIR/root/bin" "$DIR/wt"

git -C "$DIR/wt" -c init.defaultBranch=main init -q
git -C "$DIR/wt" config user.email t@example.invalid
git -C "$DIR/wt" config user.name t
git -C "$DIR/wt" commit -q --allow-empty -m init
git -C "$DIR/wt" branch -M feat-x
HEAD_SHA=$(git -C "$DIR/wt" rev-parse HEAD)
git -C "$DIR/wt" update-ref refs/remotes/origin/main "$HEAD_SHA"

cat > "$DIR/root/bin/fm-guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$DIR/root/bin/fm-guard.sh"

cat > "$DIR/fakebin/gh" <<SH
#!/usr/bin/env bash
printf 'HOST=%s ARGS=%s\n' "\${GH_HOST-unset}" "\$*" >> "$DIR/gh.log"
case " \$* " in
  *" repos/o/r/branches/main "*) printf '{"name":"main","protected":false}\n'; exit 0 ;;
  *" repos/o/r/rules/branches/main "*) printf '[]\n'; exit 0 ;;
esac
case "\${1:-} \${2:-}" in
  "pr view")
    case " \$* " in
      *" --json isDraft "*) printf '{"isDraft":false}\n'; exit 0 ;;
      *" --json headRefOid "*) printf '%s\n' "$HEAD_SHA"; exit 0 ;;
      *" --json state -q .state "*) printf 'MERGED\n'; exit 0 ;;
      *" --json state,mergedAt,isDraft,headRefOid,author,mergeable,reviewDecision "*)
        printf 'state=open\nmerged_at=\ndraft=false\nhead=%s\nauthor=author\nmergeability=mergeable\nreview_decision=APPROVED\n' "$HEAD_SHA"; exit 0 ;;
      *statusCheckRollup*)
        printf '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"%s","baseRefName":"main","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}\n' "$HEAD_SHA"; exit 0 ;;
    esac
    ;;
  "pr checks")
    exit 0
    ;;
  "pr merge")
    printf 'merged:\n  number: 9\n  status: ok\n'; exit 0
    ;;
  "api graphql")
    printf 'state=MERGED\nmerged=true\nqueued=false\nbase=main\n'; exit 0
    ;;
  "api /repos/o/r/pulls/7"*|"api /repos/o/r/pulls/8"*)
    case " \$* " in
      *"/files"*) printf 'src/a.sh\n'; exit 0 ;;
    esac
    printf 'author=author\nbase=%s\n' "$HEAD_SHA"; exit 0
    ;;
  "api --method")
    printf '%s\talice\n' "$HEAD_SHA"; exit 0
    ;;
esac
exit 0
SH
chmod +x "$DIR/fakebin/gh"
: > "$DIR/gh.log"

write_meta() {  # <id>
  local id=$1
  cat > "$DIR/home/state/$id.meta" <<META
window=firstmate:fm-$id
endpoint_task_id=$id
worktree=$DIR/wt
project=$DIR/project
kind=ship
mode=no-mistakes
META
  chmod 0600 "$DIR/home/state/$id.meta"
}

run_product() {  # <command...>
  PATH="$DIR/fakebin:/usr/bin:/bin" FM_ROOT_OVERRIDE="$DIR/root" FM_HOME="$DIR/home" "$@"
}

echo "=================== S1: arm a PR on a self-hosted host ==================="
write_meta task-ghe
run_product bash "$REPO/bin/fm-pr-check.sh" task-ghe https://ghe.example.com/o/r/pull/7
echo "--- recorded pr= and pr_head= ---"
grep -E '^(pr|pr_head)=' "$DIR/home/state/task-ghe.meta"
echo "--- armed poll sidecar (provider,url,host,path,number) ---"
cat "$DIR/home/state/task-ghe.pr-poll"
echo "--- gh calls during arm ---"
cat "$DIR/gh.log"
: > "$DIR/gh.log"

echo "=================== S2: armed poll watches the self-hosted host ==================="
poll_out=$(run_product bash "$DIR/home/state/task-ghe.check.sh")
printf 'poll stdout: %s\n' "$poll_out"
printf 'gh calls during poll:\n'; cat "$DIR/gh.log"
: > "$DIR/gh.log"

echo "=================== S3: fm-pr-state reads the PR at its host ==================="
run_product bash "$REPO/bin/fm-pr-state.sh" https://ghe.example.com/o/r/pull/7; rc=$?
printf 'fm-pr-state rc=%s (no blockers printed)\n' "$rc"
printf 'gh calls during state read:\n'; cat "$DIR/gh.log"
: > "$DIR/gh.log"

echo "=================== S4: fm-pr-reviewers reads the PR at its host ==================="
run_product bash "$REPO/bin/fm-pr-reviewers.sh" https://ghe.example.com/o/r/pull/7
printf 'gh calls during reviewer lookup:\n'; cat "$DIR/gh.log"
: > "$DIR/gh.log"

echo "=================== S5: github.com control is untouched ==================="
write_meta task-com
run_product bash "$REPO/bin/fm-pr-check.sh" task-com https://github.com/o/r/pull/8 >/dev/null
poll_out=$(run_product bash "$DIR/home/state/task-com.check.sh")
run_product bash "$REPO/bin/fm-pr-state.sh" https://github.com/o/r/pull/8 >/dev/null
printf 'poll stdout: %s\n' "$poll_out"
printf 'gh calls across arm+poll+state for github.com (every HOST must be unset):\n'; cat "$DIR/gh.log"
: > "$DIR/gh.log"

echo "=================== S6: adversarial - a doctored sidecar host is never polled ==================="
sed -i '3s/^ghe\.example\.com$/git.example.org/' "$DIR/home/state/task-ghe.pr-poll"
printf 'doctored sidecar (host differs from URL):\n'; cat "$DIR/home/state/task-ghe.pr-poll"
poll_out=$(run_product bash "$DIR/home/state/task-ghe.check.sh")
printf 'poll stdout: [%s]\n' "$poll_out"
printf 'gh calls during doctored poll (must be none):\n'; cat "$DIR/gh.log"
printf 'gh log line count: %s\n' "$(wc -l < "$DIR/gh.log")"

echo "=================== S7: adversarial - malformed host labels are never polled ==================="
printf '%s\n' github "-ghe.example.com/o/r/pull/7" -ghe.example.com o/r 7 > "$DIR/home/state/task-ghe.pr-poll"
poll_out=$(run_product bash "$DIR/home/state/task-ghe.check.sh")
printf 'leading-hyphen: stdout=[%s] gh-log-lines=%s\n' "$poll_out" "$(wc -l < "$DIR/gh.log")"
longlabel=$(printf 'a%.0s' {1..64})
printf '%s\n' github "https://$longlabel.example.com/o/r/pull/7" "$longlabel.example.com" o/r 7 > "$DIR/home/state/task-ghe.pr-poll"
poll_out=$(run_product bash "$DIR/home/state/task-ghe.check.sh")
printf '64-char label: stdout=[%s] gh-log-lines=%s\n' "$poll_out" "$(wc -l < "$DIR/gh.log")"

: > "$DIR/gh.log"
echo "=================== S8: fm-pr-merge merges a PR on the self-hosted host ==================="
write_meta task-merge
run_product bash "$REPO/bin/fm-pr-merge.sh" task-merge https://ghe.example.com/o/r/pull/9; rc=$?
printf 'fm-pr-merge rc=%s\n' "$rc"
printf 'recorded identity in meta:\n'; grep -E '^(pr|pr_head)=' "$DIR/home/state/task-merge.meta"
printf 'gh calls during merge:\n'; cat "$DIR/gh.log"
printf 'distinct hosts seen by every gh call: %s\n' "$(sed -n 's/^HOST=\([^ ]*\).*/\1/p' "$DIR/gh.log" | sort -u | tr '\n' ' ')"

: > "$DIR/gh.log"
echo "=================== S9: fm-pr-merge leaves github.com untouched ==================="
write_meta task-merge-com
run_product bash "$REPO/bin/fm-pr-merge.sh" task-merge-com https://github.com/o/r/pull/10 >/dev/null; rc=$?
printf 'fm-pr-merge rc=%s\n' "$rc"
printf 'distinct hosts seen by every gh call: %s\n' "$(sed -n 's/^HOST=\([^ ]*\).*/\1/p' "$DIR/gh.log" | sort -u | tr '\n' ' ')"
printf 'merge line: %s\n' "$(grep 'ARGS=pr merge' "$DIR/gh.log" || true)"
