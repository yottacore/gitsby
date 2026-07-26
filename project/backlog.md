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
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
		- [Done - Code review 20260726](#done---code-review-20260726)
		- [Done - Code reviews 20260725 and 20260723](#done---code-reviews-20260725-and-20260723)
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

### Features and enhancements

### Done

#### Done - Bugs

#### Done - Features and enhancements

- ✅ Release-prep sweep over the docs and the built-in help.
	- The help still described `sync` as commit-then-pull. That order changed when the bare `pull` command was dropped, and this line was missed. The README already had it right.
	- A regression check pins the wording, so the same drift can't come back quietly.
	- Also two stale references in the project notes: a command name that was renamed, and a description of argument parsing from before the noun grouping.

- ✅ `br prune`: delete branches already merged into the merge target, local + remote.
	- Nothing cleaned up after a PR merged from the web UI or another machine, or after an abandoned branch. `br land` and `pr ok` only ever delete the one branch they just merged.
	- Kept safe by what the tool already enforces: every landing is a real merge commit, so ancestry is an exact test. Unmerged branches are listed and left alone, and there is no `--force`.
	- The remote copy is only deleted once origin's own merge target contains it, so an unpushed landing can't strand work.
	- Verified the safety gates discriminate: a version with the ancestry check removed deletes an unmerged branch, and one without the origin-side check deletes origin's only ref to unpushed work.
	- Deletes with `git branch -D` behind our own check. Deferring to `git branch -d` was tried first and was wrong both ways: it warns about HEAD on every branch when pruning from anywhere but the target, and it flatly refuses a merged branch that was never pushed, so the plan promised a deletion that silently didn't happen.
	- Closes with a count (`Pruned 3 local, 3 on origin`) and names what it kept, so a wall of git output still ends in a plain answer.

- ✅ Drop the bare `commit` and `pull` commands - both work around the opinionated workflow.
	- `commit` alone leaves work committed but unshared. `pull` alone was the only place the tool took upstream changes without parking your own, unlike every other command.
	- Reversible in one direction only: dropping now is free, adding back later breaks nobody, removing later would.

- ✅ `update`/`sync` pull before they commit (bug this exposed, present on dev).
	- Committing first guaranteed divergence whenever the remote had moved, so the ff-only pull refused - in the most ordinary case there is. `pull` had been the accidental workaround.
	- Verified against the pre-fix build: it fails, the fixed one lands the work on top and keeps history linear.

- ✅ An unreachable remote warns and skips the pull instead of failing; `--no-fetch` means offline and skips the pull too.
	- Needed because `update` is now the only way to commit; a genuine non-fast-forward still fails hard.

- ✅ Group the infrequent commands under nouns: `repo clone|create|connect`, `br list|create|switch|land`, `pr create|<n>|ok <n>`.
	- Daily verbs stay one word. The extra word only lands where you type it rarely, and it buys a discoverable set instead of a flat list of abbreviations.
	- One verb across all three nouns (`create`, never `new` in some places). `new` and `go` still work but aren't published.
	- Landed before v2.0.0 on purpose: every name being changed was unreleased, so it cost nothing now and would have cost a permanent alias later.

- ✅ Split the old `connect` into `repo create` and `repo connect`.
	- Creating a remote is the one irreversible, outward-facing step, so it gets its own verb instead of happening as a side effect.
	- Each refuses the other's case and names it, so a wrong guess costs one line of output.

- ✅ Drop every pre-2.0 command alias (`scommit`, `spull`, `scompul`, `saveup`, `spush`, `mkbranch`, `chbranch`, `mtm`, `list`).
	- v2 is a clean break under a new tool name, and not all of the old commands worked. The suite now asserts they're rejected, so none creeps back.

- ✅ `pr new [title]` opens a pull request, so the whole PR round trip lives in gitsby instead of half in `gh`.
	- Pushes the branch first - GitHub can only diff what the remote has.
	- Targets `dev` when the repo has one, else the default branch. Refuses from that branch, since there is nothing to propose.
	- No title given: the last commit subject, which is already a description of the work. The preview shows it before anything happens.
	- An already-open PR for the branch reports its number instead of letting `gh` error.

- ✅ `pr ok <n>` refuses while the current branch has uncommitted changes or unpushed commits.
	- Merging deletes the branch local and remote, so work that never reached origin was outside both the PR and the merge.
	- Every other mutating command already parked work first; this was the one that did not.

- ✅ The installers' default "latest release" lookup skips anything flagged as a pre-release on GitHub.
	- GitHub's `releases/latest` returns the newest full release, so a pre-release-only repo resolves to the last full one - for this repo, the 2022 release.
	- Decided: publish releases as full releases rather than adding a `--pre` flag. The semver suffix still marks a candidate for anyone reading the tag, and the one-liner installs keep working with no extra arguments.
	- `--ref`/`-Ref` remains the way to install a specific tag or branch, and is already documented.

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
	- Also swapped the stale sister-tool reference in the Bash "push local changes" one-liner for `gitsby update`.

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

#### Done - Code review 20260726

Release-prep pass over what changed since the last review: the noun grouping, `pr create`, and dropping bare `commit`/`pull`.

- ✅ Code Review 20260726 item 1: `br switch` from a dirty protected branch tells you to run a command that no longer exists (both implementations).
	- The refusal offered `gitsby commit` as the deliberate way to keep the work where it is. That command was dropped, so following the advice is a second error.
	- Fixed: it now names `update`, which commits on the current branch. Regression test asserts the suggested command is a real one.

- ✅ Code Review 20260726 item 2: offline only reached the pull in `update` and `sync` (both implementations).
	- `br create`, `br switch`, `br land`, `pr ok`, and `release` each pull as one of their steps, and those pulls ignored `--no-fetch` and an unreachable remote.
	- So the flag documented as "work offline" still went to the network in five of the seven commands that pull, which is exactly the thing the design note says it must not do.
	- Fixed: every in-command pull goes through one helper that applies the same rule. Regression test compares a `--no-fetch` switch (must not advance) against the same switch online (must).

- ✅ Code Review 20260726 item 3: built-in help drifted from the command set (both implementations).
	- `update` was still described as commit-then-pull, `--no-fetch` as skipping only the fetch, and the PowerShell parameter help still listed `pull` and `commit` as commands.
	- The `br create` line said it parks current work first, which is what it does from a feature branch but not from `main`/`dev`, where it carries the work along instead.
	- Also "stash only if dirty" in the summary blurb, describing a manual stash that no longer exists.
	- Fixed: all of the above, in both implementations.

- ✅ Code Review 20260726 item 4: the README command count was stale.
	- It said 13, from before the regroup and before `commit` and `pull` were dropped.
	- Fixed: 7 commands, or 15 counting subcommands, which is what the table below it lists.

- ✅ Code Review 20260726 item 5: the offline test passed on the PowerShell side for the wrong reason.
	- It spelled the flag `--no-fetch`, which PowerShell has no parameter for, and then matched output against a pattern that the resulting complaint about the flag also matched.
	- So the check went green on a command that had failed outright, and no offline behavior was ever exercised there.
	- Fixed: `-NoFetch`, which both implementations accept, and the pattern now matches only the skip message itself.

- ✅ Code Review 20260726 item 6: `br prune` could say "leaving it alone" and still delete the branch's remote copy (both implementations).
	- The delete-time re-check only guarded the local delete; the remote loop ran regardless.
	- Fixed: a branch kept by the re-check keeps its remote copy too.

- ✅ Code Review 20260726 item 7: a merged current branch vanished from `br prune`'s output (both implementations).
	- It was rightly never deleted, but appeared in neither the plan nor the Keeping list.
	- Worst case: it was the only merged branch, and the output claimed nothing was merged at all.
	- Fixed: the plan, the no-op path, and the closing summary all say it is kept because you are standing on it.

- ✅ Code Review 20260726 item 8: the README claimed 100% GitLab compatibility.
	- Every `pr` form, `repo create`, and `repo connect` with an `owner/name` go through `gh`, so they are GitHub-only. That is up to six of the sixteen subcommands.
	- Fixed: the claim now says any Git remote works and names the gh-backed exceptions.

- ✅ Code Review 20260726 item 9: "no version: bump the patch" was only one of three release paths (docs and help, both implementations).
	- A candidate tag resolves to its own release (`v2.0.0-rc1` -> `v2.0.0`), and a repo with no tag at all starts at `v0.1.0`. Neither is a patch bump.
	- Fixed: docs and help now say the next version after the latest tag. A regression check pins the help line.

- ✅ Code Review 20260726 item 10: `br create` still overpromised, in the opposite direction from item 3.
	- Item 3 changed the help from "parks current work" to "brings current work along". Both are half right: work is carried only from `main`/`dev`, and committed and pushed to the current branch otherwise.
	- Fixed: docs and help say carried or parked, and name which case is which. A regression check pins the help line.

- ✅ Code Review 20260726 item 11: the dev installers required a bash version gitsby does not.
	- Both told you gitsby itself needs bash 5+. The real floor is 4.4, set by `inherit_errexit`; design.md already said 4.4 and was the one that was right.
	- Fixed: both installers now check and report 4.4.

- ✅ Code Review 20260726 item 12: smaller doc corrections found in the same pass.
	- design.md said `gh` was needed for "the two commands that need it" - it is three.
	- The Direct-install one-liners never created the target directory, and the PowerShell one wrote to a *nix path inside the Windows section.
	- The README options list omitted `--public`/`--private` and never mentioned that the PowerShell version takes PowerShell-style parameter names.
	- "Every mutating command fetches first" ignored `repo clone` and `--no-fetch`. `br prune` was described as deleting every merged branch, which skips the current-branch and protected-branch exceptions. `repo create`'s steps were listed in the wrong order.
	- design.md's folder list omitted `reference/` and described `assets/` as holding only the demo.

#### Done - Code reviews 20260725 and 20260723

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

- ✅ Code Review 20260725 item 5: `pr ok <n>` run from the branch that PR came from ends in a failed pull (both implementations).
	- `gh` deletes the branch on the remote through the API, which leaves the local `origin/*` copy in place, so the upstream still looks alive.
	- The trailing `git pull --ff-only` then asks for a branch the remote no longer has, and the whole command reports as failed.
	- Fixed: prune first, and if the branch we are standing on is the one that just went away, check out the merge target and pull that instead. The plan shows the extra step. Regression test added, with the fake `gh` restoring the stale ref so the real condition is reproduced.

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

- ✅ Code Review 20260725 item 6: `release` with no version bumps the patch of a candidate tag's base, skipping that base version (both implementations).
	- After `v2.0.0-rc1`, a bare `release` proposed `v2.0.1` rather than `v2.0.0`.
	- Fixed: a candidate's own version is now what comes next, so `v2.0.0-rc1` leads to `v2.0.0`.
	- The tag scan also needed `versionsort.suffix=-`, since git's default version sort ranks `v2.0.0-rc1` above `v2.0.0` and would otherwise propose an already-cut version once the real release exists.
	- Regression tests cover both halves: the candidate's version is taken, and the release after it bumps normally.

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
	- Use `mapfile -n 1` / array counts, minding that a bare `read` returns nonzero on empty input under strict mode.
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

### Future and/or deferred

### Canceled
