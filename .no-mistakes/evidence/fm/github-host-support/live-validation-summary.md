# Live validation: PR tooling on any GitHub host

Change under test: `fm/github-host-support` (worktree, target commit 09d0de9).
Product: firstmate shell tooling (`bin/fm-pr-*.sh`, `bin/fm-teardown.sh`, `bin/fm-backlog-transition-lib.sh`).
There is no GUI surface; the end-user surface is the CLI and the files it records, so the evidence is CLI transcripts plus the recorded state.

## 1. Independent end-to-end drive against a disposable fixture

Script: a disposable fixture was built under `/tmp/fm-live-host-scenario/work`:
a throwaway home (`home/state`, `home/data`, `home/config`), a throwaway git worktree, and a fake `gh` on `PATH` that emulates a self-hosted forge and logs `HOST=<GH_HOST> ARGS=<command>` for every call.
The product scripts themselves are the real ones from the worktree; only the external forge CLI is the fixture.
Transcript: `live-host-scenario.txt`.

| Step | What an end user does | Observed result |
| --- | --- | --- |
| S1 | Arm a PR on `ghe.example.com` (`bin/fm-pr-check.sh task-ghe https://ghe.example.com/o/r/pull/7`) | `armed: state/task-ghe.check.sh`; meta holds `pr=https://ghe.example.com/o/r/pull/7` and the forge head; sidecar holds `github / https://ghe.example.com/o/r/pull/7 / ghe.example.com / o/r / 7`; both gh reads ran with `HOST=ghe.example.com` |
| S2 | Run the armed poll sidecar | prints `merged`; the gh read ran with `HOST=ghe.example.com` |
| S3 | `bin/fm-pr-state.sh https://ghe.example.com/o/r/pull/7` | rc=0, no blockers; both gh calls (`pr view`, `pr checks`) ran with `HOST=ghe.example.com` |
| S4 | `bin/fm-pr-reviewers.sh https://ghe.example.com/o/r/pull/7` | prints `alice 1 recent commit`; all three gh calls ran with `HOST=ghe.example.com` |
| S5 | Same arm + poll + state for `https://github.com/o/r/pull/8` | every call ran with `HOST=unset` (github.com untouched) |
| S6 | Doctor the sidecar so its host (`git.example.org`) differs from its URL (`ghe.example.com`), then run it | no output, zero gh calls |
| S7 | Doctor the sidecar to a leading-hyphen host label and to a 64-character host label | both: no output, zero gh calls |
| S8 | `bin/fm-pr-merge.sh task-merge https://ghe.example.com/o/r/pull/9` | `verified: ... is merged`; meta holds the host URL and head; all six gh calls (head read, mergeable read, branch rules, commit-rules list, `pr merge`, outcome graphql) ran with `HOST=ghe.example.com` |
| S9 | `bin/fm-pr-merge.sh task-merge-com https://github.com/o/r/pull/10` | `verified: ... is merged`; every call ran with `HOST=unset`, including `pr merge 10 --repo o/r --match-head-commit ... --squash` |

## 2. Repository tests that drive the real scripts end to end

Each of these executes the real product scripts with a disposable fixture `gh`/`gh-axi` that records `GH_HOST` per call. All exited 0.

* `bash tests/fm-github-host.test.sh` - parser identity, default-host rule, ambient `GH_HOST` ignored by the default rule, `fm_gh_at` per-command selection, bounded record read, poll host selection and sidecar refusal.
* `bash tests/fm-pr-state.test.sh` - state read at the PR's host and github.com untouched.
* `bash tests/fm-pr-reviewers.test.sh` - reviewer lookup at the PR's host.
* `bash tests/fm-pr-merge.test.sh` - every merge-path gh call at the PR's host; github.com leaves the environment untouched.
* `bash tests/fm-teardown.test.sh` - recorded URL read at its own host, Gerrit host never selected, bare-number/branch lookups at `FM_GITHUB_HOST`, unusual ambient `GH_HOST` tolerated, landed task on another host closed with the URL as a backlog note.
* `bash tests/fm-pr-check-security.test.sh` - re-arming after a retirement receipt for another host reads the new PR at its own host.

## 3. Not exercised

No real self-hosted GitHub Enterprise instance is reachable from this machine, so the forge CLI is a disposable stub in every run; the product scripts, their host selection, and their recorded state are real.
