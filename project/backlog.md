<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Requirements

This is a product backlog for the run-up to v2.0.0. After that release, bugs, features, and enhancements move to GitHub Issues.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Backlog](#backlog)
	- [Misc to-do](#misc-to-do)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Initial requirements](#done---initial-requirements)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
	- [Future and/or deferred](#future-andor-deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Backlog

### Misc to-do

### Bugs

- 🔘 Code Review 20260725 item 5: `pr ok <n>` run from the branch that PR came from ends in a failed pull.
	- `gh pr merge --delete-branch` removes the remote branch, then the trailing `git pull --ff-only` has nothing to track.
	- Harmless (the merge already happened) but it reports as a command failure.
	- Probable fix: skip or soften the trailing pull when the current branch's upstream is gone.

### Features and enhancements

- 🔘 Code Review 20260725 item 6: `release` with no version bumps the patch of a pre-release tag's base, skipping that base version.
	- After `v2.0.0-rc1`, a bare `release` proposes `v2.0.1` rather than `v2.0.0`.
	- Matches the documented "bump the patch" rule, but it is not what someone finishing a release candidate expects.
	- Options: drop the suffix and keep the base when the newest tag is a pre-release, or just say so in the help text.

- 🔘 The installers' default "latest release" lookup skips anything flagged as a pre-release on GitHub.
	- GitHub's `releases/latest` returns the newest full release, so a pre-release-only repo resolves to the last full one.
	- Matters for v2.0.0-rc1: unless it is published as a full release, the one-liner installs still land on the 2022 release.
	- Options: publish release candidates as full releases, add a `--pre`/`-Pre` flag, or document `--ref` for candidates.

### Done

#### Done - Initial requirements

#### Done - Bugs

- ✅ Code Review 20260725 item 1: `release` pushes only the tag when the default branch has no upstream (both implementations).
	- The branch push is gated on an upstream; the tag push is not.
	- Origin ends up holding the release commits as tag payload while its `main` still points at the previous release.
	- Same shape as item 2 of the previous review, which was fixed in `land` but not here.
	- Fixed: an upstream-less default branch is published with `git push -u origin HEAD` before the tag goes up. Regression test added.

- ✅ Code Review 20260725 item 2: `release` refuses a duplicate tag only after it has already committed and pushed (both implementations).
	- The check sat inside the command, past the plan, the confirmation, and the "park current work" step.
	- Nothing is lost, but the run mutates the repo and then dies on something knowable up front.
	- Fixed: the tag-exists check moved next to the version resolution, before anything is shown or run. Regression test added.

- ✅ Code Review 20260725 item 3: `gobr` refuses a dirty protected branch only after the plan is confirmed (both implementations).
	- Same class as item 2, and the same fix as code review 20260723 item 35 applied to the other branch arguments.
	- Fixed: the refusal moved up front, alongside the other branch-argument checks. Regression test added.

- ✅ Code Review 20260725 item 4: `newbr` shows a plan it does not follow when run from `main`/`dev` (both implementations).
	- The preview always listed the commit-and-push steps, but on a protected branch the tree is carried to the new branch instead.
	- The preview is the safety feature, so it misreporting in exactly the case that was special-cased is the wrong way round.
	- Fixed: the plan now branches on protected state and shows the checkout-and-carry steps. Regression test added.

- ✅ Code Review 20260723 item 1: `pull` failure strands the autostash (both implementations).
	- Dirty tree gets stashed, then a failed `git pull --ff-only` (diverged or offline) aborts before `git stash pop`.
	- Work vanishes from the tree into the stash with no message; re-runs see a clean tree and never pop it.
	- Contradicts the "never risk losing work" promise; worst finding of the review.
	- Fixed: replaced the manual stash dance with `git pull --ff-only --autostash`; a failed pull now leaves the tree intact. Regression test added.

- ✅ Code Review 20260723 item 2: `land` can delete the remote work branch before the merge ever reaches origin (both implementations).
	- Push of the merge is gated on the target having an upstream; the remote branch delete is not.
	- With a local-only `dev`, the merge stays local but `git push origin --delete <branch>` still removes origin's only ref to those commits.
	- Fixed: an upstream-less target is published first (`git push -u origin HEAD`) before the remote delete. Regression test added.

- ✅ Code Review 20260723 item 3: `newbr`/`gobr` from a dirty `main`/`dev` commit and push WIP straight to the protected branch (both implementations).
	- The "park current work" step is commit+push on whatever branch you're on - including main/dev, with an auto message in quiet mode.
	- Contradicts the tool's own opinions ("don't push to dev, main, or master").
	- Fixed: `newbr` carries dirty work to the new branch (no commit on the base); `gobr` refuses with guidance instead of auto-committing; sync preview now names the branch being pushed. Regression tests added.

- ✅ Code Review 20260723 item 4: a commit message containing `-h`/`-v` as a word makes the bash version silently no-op with exit 0.
	- The early help check scans the whole joined argv, so `gitsby commit "add -v flag"` prints the banner and skips the commit.
	- Bash only; the pwsh port checks just the command slot.
	- Fixed: -h/-v now only recognized in the command slot, matching the pwsh port. Test added.

- ✅ Code Review 20260723 item 5: non-tty stdin silently auto-confirms all mutating commands (both implementations).
	- Piped/cron/redirected input behaves as implicit `-q`: release/land/sync run with zero confirmation, even `echo n |` is ignored.
	- Should fail closed like the installers do (require explicit flag when no tty).
	- Fixed: mutating commands with no tty and no -q abort with guidance; read-only commands keep the implicit quiet. Tests added.

- ✅ Code Review 20260723 item 6: unquoted two-word positional message silently drops the second word (both implementations).
	- `gitsby commit Fixed bug` commits as "Fixed"; three words error but two don't.
	- Fixed: a non-empty third positional is rejected with "quote your commit message" (both implementations). Test added.

- ✅ Code Review 20260723 item 7: git failures print the raw trap dump instead of a plain error (bash).
	- Diverged pull shows "Signal: ERR / Message: '--ff-only' / Command#: '"${@}"'" - reads as a gitsby crash.
	- The pwsh port already prints a clean one-liner; match it.
	- Fixed: fRun reports a plain one-liner ("'git ...' failed (exit N)") and exits; the trap dump stays for real script errors. Tests added.

- ✅ Code Review 20260723 item 8: `echo -e` in fEcho_Clean expands escapes in user data (bash).
	- Mangles commit messages/filenames in the preview; a hostile repo's filenames (raw ESC bytes, C-quoted by git) can spoof the confirm display.
	- Switch to `printf '%s\n'`.
	- Fixed: fEcho_Clean uses printf '%s\n'; escape bytes in user data stay inert.

- ✅ Code Review 20260723 item 9: pwsh branch-name comparisons are case-insensitive.
	- `-eq` treats 'Main' = 'main'; newbr can branch off the wrong base. Use `-ceq`/`-cne` at the seven branch compares.
	- Fixed: -ceq/-cne at the branch compares; 'ok' and prompt answers stay case-insensitive.

- ✅ Code Review 20260723 item 10: pwsh `release` crashes under strict mode when the newest v* tag isn't X.Y.Z.
	- `v1.2` or `v2020` throws on array indexing; bash handles the same input gracefully.
	- Fixed: split parts padded before arithmetic (v1.2 -> v1.2.1, v2020 -> v2020.0.1); bash pads the same way now too. Verified on both.

- ✅ Code Review 20260723 item 11: install.ps1 downloads to a predictable temp filename.
	- `gitsby-install-$PID.ps1` in shared temp; race window before install. install.bash already uses mktemp - mirror it.
	- Fixed: downloads into a fresh random private subdirectory; recursive cleanup in finally.

- ✅ Code Review 20260723 item 12: remote URLs print verbatim, leaking embedded credentials (both implementations).
	- An `https://user:token@host/...` origin echoes the token on every run, including CI logs. Mask the userinfo part.
	- Fixed: userinfo masked in the displayed URL (https://***@host) in both implementations. Tests added.

- ✅ Code Review 20260723 item 13: default-branch detection trusts a possibly missing/stale local origin/HEAD (both implementations).
	- Ref goes stale on upstream master->main renames and can be absent on git < 2.47; release then tags the wrong branch.
	- Cheap fix: `git remote set-head origin --auto` alongside the existing fetch.
	- Fixed: successful fetch now runs git remote set-head origin --auto, healing a missing or stale origin/HEAD; local read remains the offline fallback.

- ✅ Code Review 20260723 item 18: fMustBeInPath shells out to external `which` (bash).
	- `which` is absent on some minimal distros, making every command abort with "Not found in path: git". Use builtin `command -v`.
	- Fixed: builtin command -v; dropped the stray second fThrowError argument.

- ✅ Code Review 20260723 item 21: `pull` stashes a dirty tree before checking for an upstream (both implementations).
	- No-upstream + dirty = pointless stash push/pop that rewrites every file's mtime. Check upstream first. (Goes away if item 1 lands as `--autostash`.)
	- Moot: item 1's `--autostash` fix removed the manual stash entirely; no upstream now means no stash is touched at all.

- ✅ Code Review 20260723 item 23: fetch without `--prune` leaves stale origin/* refs that existence checks trust (both implementations).
	- Stale refs make gobr check out dead branches, land abort on the remote delete, newbr refuse reusable names.
	- Fetch with `--prune`; make land's remote delete tolerant of "remote ref does not exist".
	- Fixed: fetch uses --prune, and land's remote delete warns-and-continues instead of dying if the branch is already gone.

- ✅ Code Review 20260723 item 24: pwsh skips native exit-code checks in the pr/read-only paths.
	- `gh pr view` failure isn't caught before `gh pr diff` runs; `listbr`/`status` exit 0 even if git fails.
	- Fixed: gh pr view checked before the diff; listbr throws on git failure.

- ✅ Code Review 20260723 item 25: pwsh parses Windows drive-letter remotes (`C:\...`) as ssh hosts.
	- Pre-flight then shows a bogus SSH identity line. Treat a single-letter-colon prefix as a path, like git does.
	- Fixed: single-letter-colon prefixes are treated as drive paths, not ssh hosts.

- ✅ Code Review 20260723 item 26: `ssh -G` called without `--` on a host string derived from .git/config (both implementations).
	- Option-shaped "hosts" from a hostile config parse as ssh options. Currently fails closed, but add `--`.
	- Fixed: -- added in both implementations.

- ✅ Code Review 20260723 item 27: install-dev.ps1 passes an option-shaped `-Directory` straight to `git clone`.
	- Binds as a real clone option (`--config=...`). install-dev.bash already rejects `-*`; mirror it (and/or pass `--` before the path).
	- Fixed: option-shaped -Directory rejected, same wording as the bash guard.

- ✅ Code Review 20260723 item 28: install.ps1 lacks the downloaded-content sanity check install.bash has.
	- No shebang check before install+execute; wrong-content 200s (captive portal, truncation) get installed. Mirror the `^#!` test.
	- Fixed: first line must match ^#! before install, mirroring install.bash.

- ✅ Code Review 20260723 item 29: gitsby.ps1 sets GIT_MERGE_AUTOEDIT process-wide, persisting in the caller's pwsh session.
	- The var is redundant anyway (merges pass `-m`); just delete the line.
	- Fixed: line deleted (merges pass -m, so it was redundant).

#### Done - Features and enhancements

- ✅ Code Review 20260723 item 14: bound the unconditional pre-command fetch and add an offline escape hatch (both implementations).
	- A dead/black-holed remote blocks every command for the full TCP/ssh timeout before the "offline?" warning.
	- Add a connect timeout on the fetch and a `--no-fetch`/offline flag.
	- Done: ssh fetches get ConnectTimeout=3 (user GIT_SSH_COMMAND respected), and --no-fetch/-NoFetch skips the fetch entirely.

- ✅ Code Review 20260723 item 15: cache per-run-constant git facts (both implementations).
	- Measured: 12 git spawns for `status`, 45 for `land`, 55 for `release`; upstream/branch/ahead-behind re-queried repeatedly in one display block.
	- Resolve once after the fetch, pass down; keep live re-checks only where state actually mutates. Matters most on Windows.
	- Done: default branch and merge target now resolve once per run post-fetch; branch/upstream/ahead checks stay live since checkouts change them mid-command.

- ✅ Code Review 20260723 item 16: close the test-suite gaps that hid this review's bugs.
	- Failed-pull-with-dirty-tree, no-remote fixtures, slash branch names, `-m`/`-m=` flag forms, option-like words in messages, release from a feature branch.
	- Done so far: failed-pull-with-dirty-tree, upstream-less land, dirty-protected-branch newbr/gobr fixtures.
	- Done: all listed fixtures added (failed pull, no-remote sync/newbr/land, feat/x names, -m and -m= forms, option-like message words, release from a feature branch). Suite 140 -> 199 checks.

- ✅ Code Review 20260723 item 17: README has no Commands/Usage section.
	- The pitch is "Gitsby has 11" commands, but they're never listed or demonstrated. Add the help table plus a worked newbr -> update -> land example.
	- Done: Commands section added (table of all 11, options, a typical-day flow, gh note for pr/release).

- ✅ Code Review 20260723 item 19: installer checksum + version pinning - confirms the already-open installer item below.
	- Publish SHA256SUMS from cicd, verify in both installers, allow pinning an exact tag; document that `--ref` skips verification.
	- Done: installers verify release-asset downloads against a SHA256SUMS release asset when published (note-and-continue when absent); cicd/utility/gen-checksums.bash generates it for release cuts; --ref/-Ref pins a tag but skips verification (documented in README).

- ✅ Code Review 20260723 item 20: "latest release" lookup uses the unauthenticated GitHub API (60 req/hr).
	- Shared-NAT/CI installs will 403. Read the tag from the `releases/latest` redirect Location header instead; keep the API as fallback.
	- Done: tag read from the releases/latest redirect (curl url_effective / wget Location / pwsh 302 handling); API scrape kept as fallback; rate-limit mentioned in the error.

- ✅ Code Review 20260723 item 22: fIsAhead materializes the whole ahead-range log just to test emptiness (both implementations).
	- Use `git rev-list -n 1 '@{u}..'` (or the cached ahead count from item 15).
	- Done: git rev-list -n 1 in both implementations.

- ✅ Code Review 20260723 item 30: needless external `head`/`wc` pipeline stages (bash).
	- Use `mapfile -n 1` / array counts; watch the set -e empty-input gotcha noted in design.md.
	- Done: tag lookup via mapfile -n 1; the stash wc pipelines were already removed by item 1.

- ✅ Code Review 20260723 item 31: positional parameter binding in the ps1 files (style guide requires named).
	- gitsby.ps1 one spot (`Get-Command ssh`); install.ps1 and install-dev.ps1 throughout (Join-Path, Move-Item, Test-Path, Get-Command).
	- Done: named parameters at the flagged sites in all three ps1 files.

- ✅ Code Review 20260723 item 32: no comment-based help on any gitsby.ps1 function.
	- Either add `.SYNOPSIS` to the non-trivial functions, or scope the style-guide rule to script-level + exported functions.
	- Done: style-guide rule scoped to script level + exported/public functions; private helpers take a terse ## comment.

- ✅ Code Review 20260723 item 33: installer output ends without the trailing blank line the style guide requires (all four installers).
	- Done: all four installers end with a blank line.

- ✅ Code Review 20260723 item 34: rename fpPreview's `p` padding variable to `pad` (matches the pwsh twin).
	- Done: renamed.

- ✅ Code Review 20260723 item 35: branch-argument validation runs after the status display and confirm prompt (both implementations).
	- `newbr` with a bad/missing name shows a nonsense plan ("git checkout -b ") and only errors after "y". Hoist checks next to the existing pr/release ones.
	- Done: newbr/gobr arguments validate right after the release-version check, before status/preview/prompt; command functions no longer duplicate the checks. Test added.

- ✅ Code Review 20260723 item 36: `gitsby help` / `gitsby version` are unknown-command errors (both implementations).
	- Alias the bare words to the -h/-v paths; one case entry each.
	- Done: bare words route to the same paths as -h/-v (both implementations). Tests added.

- ✅ Code Review 20260723 item 37: usage errors carry "Reverse call stack: fMain()" noise (bash).
	- Suppress the stack line for expected validation errors; keep it for real internal failures.
	- Done: fThrowError_Usage variant skips the stack line; all user-facing validation errors use it. Real script errors keep the stack.

- ✅ Code Review 20260723 item 38: accept `-y`/`--yes` as a prompt-skip alias (both implementations).
	- Installers teach -y, gitsby only takes -q; and -q's real function is "assume yes", not quiet. Keep -q, add -y, fix the help wording.
	- Done: -y/--yes (bash) and -y/-yes (pwsh) alias -q; help wording now says "assume yes". Test added.

- ✅ CICD process (full spec in private notes):

	- Done: every stage below is live and runs on each publish. The pipeline is local by design - no cloud service, no account to pay for.

	- ✅ `cicd.bash`: `-q|--quiet`, `-m|--msg|--message`, prompt for commit message when neither given (CTRL+C aborts); silkterm output style; `fEcho`/`fParseArgs` conventions.

	- ✅ Linting stage: shellcheck (+ markdownlint), no auto-format for Bash; output GFS-rotated to `cicd/artifacts/lint/`; zero-error goal.
		- Everything gates clean now, including `bin/gitsby` (the refactor cleared its ~80 legacy findings; report-only list emptied). PSScriptAnalyzer gates the three `.ps1` files.

	- ✅ Dogfood install stage: copy to first existing preferred dir (bash + pwsh lists).
		- Both legs live since the pwsh port landed.

	- ✅ Regression tests; keep updated as features/bugs land.
		- `cicd/test.bash`: throwaway repos (bare origin + two clones), every command plus failure guards, run once per implementation - 140 checks.

	- ✅ Adversarial fuzz/security testing (our input surface + what we depend on).
		- Done: `cicd/fuzz.bash` - bombards the command slot, options, and branch/message/version/pr args with malformed + injection vectors, per implementation (bash + pwsh). Asserts three invariants: no internal crash (bash/pwsh error-dump signatures), no shell/command injection (a canary side-effect never fires), and inputs-that-must-refuse exit nonzero leaving the repo unchanged. 191 checks. Found + fixed two real pwsh-port bugs (see next items). Scope is gitsby's own input, not upstream git.
		- Fuzz-found bug (fixed here): the pwsh port passed user-supplied values to native git UNquoted, so PowerShell wildcard-expanded `*`/`?` against the filesystem before git saw them - `newbr '*'` slipped past `check-ref-format` and created a branch named after a file. Quoted the user values in the direct git/gh calls (branch validation, clone-dir, gh target), mirroring the bash port. bash was never affected (always quoted).

	- ✅ pwsh: `Invoke-Git` splatted an argument array (`git @GitArgs`), and PowerShell wildcard-expands any element that is a bare `*`/`?`/`[...]` matching files in the cwd - so a commit message of exactly `*` globbed to filenames.
		- Done: `Invoke-Git` now runs git via `System.Diagnostics.ProcessStartInfo` + `ArgumentList` (a literal argv - no PowerShell reshell or globbing), `UseShellExecute=$false` with no redirection so git output still shows inline. Tried and rejected: quoting splat elements (splat drops quoting), `[WildcardPattern]::Escape` (git receives the backtick), `Start-Process -ArgumentList` (re-splits multi-word elements like a spaced message). Verified messages with `*`, spaces, `?`, `[ab]`, `;$(...)`, quotes, and emoji all land verbatim; exit codes propagate; no injection. Locked with `fMsgLiteral` verbatim-message vectors in `cicd/fuzz.bash` (both implementations). Fuzz 183 -> 191; test.bash still 269/0; PSSA clean.

	- ✅ Automated demo GIF (fake terminal, `--quick` skips); copy `gen-demo-gif.py` from convert-base-v2; embed `assets/demo.gif` in README.
		- Done: scenario `cicd/demo-scenario.toml` + repo builder `cicd/utility/demo-repo.bash`; embedded in README top with a commented YouTube placeholder. Single hero `land` command (state block + full plan + commit/push/merge/cleanup) in an anonymized throwaway repo built offline; runs real gitsby so it can't go stale. 960x540 (the tool's default, a blessed alternative in the private note; not 640x360, and the tool has no fixed-fps knob). Pinned commit dates make it byte-deterministic so cicd only regenerates on real change. 18.4s loop, 823 KiB.
		- Follow-up: one command was too thin a story, so the scenario now runs a whole feature end to end - `status`, `newbr`, `update`, a real edit typed at the prompt, `sync`, `land` - with a short comment line introducing each. Two generator fixes came out of it: stderr now shares the stdout pipe (git writes its progress there, so it was all landing after the program's own output instead of under the step that produced it), and the palette pads to the next power of two rather than a flat 256 (same pixels, ~12% smaller file).
		- Follow-up: the smooth scroll and the cursor glide were never actually running. Both stepped once per 80ms frame, and a line of scroll is 21px, so any scroll rate over ~275 px/s finished a line in a single frame - a hard jump, and the rate knob did nothing (325, 520 and 820 all rendered byte-identical). Frame interval is now 20ms (50 fps) and the cursor glide follows it, so both move as intended. A smooth scroll redraws the whole text block every frame, which is expensive, so a new per-step `clear = true` starts each command on a fresh screen and roughly halves how far the view ever travels. 60.0s loop, still byte-deterministic.
		- Follow-up: cicd now runs the render through `gifsicle -O3` when it is installed, before the compare, so the committed file is the optimized one (`DEMOGIF_OPT_CMD` in config.bash; silently skipped when absent). Worth about 9% - 7.3 -> 6.6 MiB. Less than it sounds like it should be: the renderer already crops each frame to what changed, so most of the win was banked, and the lossy modes buy almost nothing on a 35-colour text demo.

- ✅ New commands for getting connected: `clone` (get an existing repo) and `connect` (publish work that only exists locally to a new or empty remote).
	- `clone <url> [dir]`: derives the dir from the URL, checks out `dev` when the repo has one, re-run is a no-op.
	- `connect [target]`: init if needed, commit, push. URL to an existing empty remote, or `owner/name` creates the GitHub repo via gh (`--public`/`--private`). Refuses remotes with history and won't change an existing origin.
	- Done: both implementations, previewed + confirmed like the rest; tests 207 -> 241.
	- Follow-up: logically validated (no bugs) and exhaustively tested. Closed the "gh paths untested offline" gap with a hermetic fake gh (create / add https+ssh / refuse-nonempty), plus clone edges (no-dev, pre-existing empty dir, different-url refuse) and connect edges (empty inited repo, matching-url re-connect). Tests 241 -> 269, both implementations.

- ✅ Add a PowerShell badge to README.md.
	- Added next to the bash badge in the header block, linking to the PowerShell docs.

- ✅ One-liner installers for Bash and PowerShell: download the release, verify the checksum, install the script. Idempotent, and they state the plan and ask before touching anything. Documented in README under "Installation", including a "Direct" subsection with the commands and the install locations.

	- Done: `install.bash` and `install.ps1` cover it. Checksum verification against a published `SHA256SUMS` landed with code review item 19, and the README "Direct" subsection lists both the commands and the paths each installer uses.

	- Note on the spec's option names: `--arch` doesn't apply, since gitsby is a script rather than a compiled binary. `--release dev|stable` is spelled `--ref`, and `--target user|system` is spelled `--system` (user is the default).

	- Note on install paths: gitsby is a single file, so it goes straight to `~/.local/bin` or `/usr/local/bin` rather than into a program directory with a symlink.

- ✅ Code Review 20260723 item 39: README typos.
	- Line 82 "devoted to to", line 100 "besome", line 218 "cononical".
	- Done: all three fixed.

- ✅ Rename `saveup` to `update`.
	- Done in both implementations; `saveup` stays as a hidden alias like the other old names. Docs and changelog swept.

- ✅ Script output starts and ends with a blank line (breathing room between prompt text).
	- Trailing blanks already existed on every exit path; added the leading one (both implementations). Error paths were already blank-wrapped.

- ✅ After `release` merges dev to main, bring dev up to include the release merge and tag.
	- Done via `git merge --ff-only main` on dev (then push), not `git branch -f dev main`: same result normally, but if dev gained commits mid-release it skips with a warning instead of discarding work. Previews updated; tests cover it.

- ✅ 'git_notes_and_oneliners.md': Move the current commands under a "Bash" section, and add a "PowerShell" section below it, with pwsh v7 parity versions of the same one-liners.
	- Two mirrored sections, same task headings in the same order, so the two are easy to compare side by side.
	- The PowerShell section opens with the three gotchas that bite when translating from Bash: `&&`/`||` need pwsh 7, `@{u}` has to be quoted, and staged-change tests read `$LASTEXITCODE`.
	- Every pwsh one-liner was run against throwaway repos, not just eyeballed. Two spots deviate on purpose: no `less` (git pages its own diff), and `Remove-Item` deletes outright since there is no cross-platform `trash`.
	- Also swapped the stale sister-tool reference in the Bash "push local changes" one-liner for `gitsby saveup`.

- ✅ All potentially destructive or conflict-producing commands - or anything that will reveal a user identity on the remote - should:
	- Show what's going to change (including a list of changed files, piped through an internal equivalent of `... | less -FX` if necessary)
	- git status without line-breaks, and SSH connection info. And a prompt to continue. All with standard 1 blank line where appropriate.
	- Every mutating command already previewed its plan and prompted; this added the identity and change detail. `status` shows the same block.
	- SSH line resolves the remote URL through `ssh -G`, so a `~/.ssh/config` host alias shows the real host, user, and key it will use - the point being to catch acting as the wrong account before you push. Author line shows what git will actually stamp on the commit.
	- Changes list one file per line (short form), truncated to the terminal width and capped at 25 with an "and N more" tail - the `less -FX` idea without depending on a pager. Incoming section lists what a pull would change, and the branch line carries ahead/behind.

- ✅ Better command names; dev-aware merging; PR and release commands (both implementations).
	- Renames: scompul->saveup, spush->sync, scommit->commit, spull->pull, mkbranch->newbr, chbranch->gobr, list->listbr, mtm->land. Old names still work as hidden aliases.
	- newbr/gobr/land now branch off / land on dev when the repo has one, else main/master. land refuses to run from the default branch.
	- New: pr (bare = list, n = view + diff, ok n = approve + merge, via gh), release (merge dev into main --no-ff, tag, push; no version = patch bump on the latest v* tag).

- ✅ PowerShell port of gitsby (style guide already covers pwsh; dogfood pwsh leg activates when it lands).
	- `bin/gitsby.ps1`: same commands, checks, and flow as the bash version. Regression suite now runs once per implementation (78 checks total); PSScriptAnalyzer joined the lint stage (gates all three .ps1 files); dogfood pwsh leg live. Not in a release yet - README says to use `-Ref dev` until one is cut.

- ✅ Create a release-install script per platform (`bash` and \[`pwsh` or `cmd`\]), runnable via a single `curl`/`wget` (etc.) and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort. Update README.md with one-liner for both local and system-level installs.
	- `install.bash` + `install.ps1` at repo root; plan-then-confirm, `--system`/`-y`/`--ref`; README Installation one-liners filled in (user + system, curl and wget). Resolves the latest release tag, prefers a release asset, falls back to the tagged tree. The 2022-era releases predate the `bin/` layout so the release path activates for real once a v2 release is cut (`--ref main`/`--ref dev` works today); the pwsh installer says the port hasn't shipped and points at the bash one until then.

	- ✅ Do the same thing for a dev-branch install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort. Update README.md with one-liner for both local and system-level installs.
		- `install-dev.bash` + `install-dev.ps1`: clone, check out `dev`, check tooling (offers package-manager install where one is found), verify, print next steps. Documented in README "How to develop" + contributing.md "Your First Code Contribution". Bash installers run on macOS stock bash 3.2.

- ✅ Get original commands and options working. At some point some just kind of broke (pre-git), and were never fixed.
	- All commands work and are regression-tested; the commit/save/sync/land family takes -m or a positional message, newbr/gobr validate their branch argument.

- ✅ Integrate these rules and ideals: `reference/git.txt` (in this repo), including:
	- Push hygiene (stash / pull --ff-only / stash apply / add / commit / push) is now the core of pull/saveup/sync; branch workflow lives in newbr/gobr/land.
	- Work on feature branches
	- PRs to merge to develop
	- Commit frequently
	- Pull frequently, push infrequently
	- Push hygene:

		~~~bash
		git stash
		git pull --ff-only
		git stash apply
		git add .
		git commit -m ""
		git push
		~~~

- ✅ Make sure everything done with git:
	- Every command verifies state first and is idempotent: stash only if dirty (pop only what was pushed), pull only with an upstream, push only if ahead, commit only if changes; main/master detected from origin HEAD, not hardcoded. All covered by the regression tests.

	- Is done safely. E.g. before stashing, verify safely in a robust way that makes no assumptions, that there is anything to pull. `n8git_backup-and-publish` has examples.

	- Never make assumptions about the local and/or repo state. Verify first for every command, whatever is relevant for the command.

	- Everything must be idempotent.

- ✅ Refactor the bash script:
	- Rewritten 2142 -> ~620 lines on the current template generation (same one as `n8git_backup-and-publish`): strict mode, trap suite, arg parser, minified header trio.

	- ✅ Use newer, easier-to-maintain Bash template/boilerplate/common functions. (E.g. from sister project silkterm.) But even those examples need to be cleaner (don't change anything outside of repo.)

	- ✅ Modernize function and variable naming convention. Be descriptive with names, but not too long. Use of one-letter variables in small loop structures is OK.

	- ✅ Remove dead code.
		- Dropped the unused ~1400-line generic library (ping, symlink, editor pickers, sudo plumbing, glob-permutation engine, platform detection).

	- ✅ Refactor to maximize usefulness of idiomatic Bash 5 features.
		- Argument arrays instead of eval (which also retired the curly-quote message mangling), `[[ -v ]]`, parameter transforms, arithmetic conditionals.

- ✅ Work on dev branch. Push releases to main.

	- ✅ `dev` branch created from `main` and pushed; feature branches now merge to `dev`, `main` is release-only.

- ✅ Create PRs rather than pushing directly (for this project).
	- Feature branches now go up as PRs to `dev` and land via merge commit; direct local merges retired.

- ✅ Delete stale branch from 2020.
	- `20201003-074416_jc_rewrite-in-golang` (abandoned golang rewrite) deleted from origin.

### Future and/or deferred

### Canceled
