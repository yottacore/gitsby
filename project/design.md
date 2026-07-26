<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Design

Design, requirements, and direction. The active bug and feature task list lives in `backlog.md`.

## Assumptions

- Any repo gitsby touches may also be touched by raw `git`, `gh`, or an IDE - before, during, and after. Nothing gitsby does can be allowed to confuse those tools.

- Repo state is never assumed. Every command re-checks what it needs at the moment it needs it, because the last command may have been interrupted, or someone else may have moved the remote.

- The awkward cases (partial staging, multiple remotes, rebases, conflict surgery) belong to raw `git`. Gitsby covers the common path and stays out of the way for the rest.

## Project structure

### Folder structure

- `bin/` - the two implementations, one file each.

- `cicd/` - the local pipeline, its config, and the test and fuzz suites.

- `project/` - this file and the backlog.

- `assets/` - the demo shown at the top of the README.

- Root - the four installers, the license, and the public docs.

### Logical code structure

Both implementations follow the same shape, in the same order:

1. Parse arguments, and resolve the command name through the old-name aliases.

2. Refuse anything unworkable up front: unknown commands, bad branch names, a version that is already tagged, no terminal to confirm on.

3. Fetch, so everything displayed afterward is current.

4. Show the repo state, then the exact commands about to run, then ask.

5. Run them, each one state-checked at the moment it runs.

6. Show the state again.

The two files are ports of each other. A change to one nearly always belongs in the other, and the suites run against both.

### Execution flow

- Every mutating command is preview-then-confirm. `-q`/`-y` skips the prompt; nothing skips the state checks.

- The preview is a static recipe per command, with `*` marking steps that only happen if the repo state calls for them. It has to match what the command actually does, including where the command branches on state.

- No command shells out through `eval`. Arguments are passed as arrays, so a message or branch name is never re-parsed.

## Direction decisions

- There is no bare `commit` and no bare `pull`. Both were escape hatches around the workflow the tool exists to enforce.
	- `commit` alone produces exactly the state gitsby was written to prevent: work committed locally that never reaches the remote, diverging quietly until the merge is painful.
	- `pull` alone was the only place gitsby let you take upstream changes without parking your own work, which contradicts what it does everywhere else - `br create`, `br switch`, `br land` and `pr create` all park first.
	- We decided the asymmetry settles it: dropping a command before release costs nothing, and adding one back later breaks nobody. Removing one after release would.
	- Removing `pull` exposed a real bug it had been masking - see the ordering decision below.

- `update` and `sync` pull *before* they commit.
	- Committing first mints a local commit, so a remote that has merely moved ahead is now diverged and a fast-forward-only pull must refuse. That is the everyday case, not an edge one, and it was failing.
	- Pulling first fast-forwards under `--autostash`, so the dirty tree rides over and the commit lands on top. History stays linear and fast-forward-only stays satisfiable, which is the whole reason the tool never merges behind your back.
	- Nothing is risked by pulling first: `--autostash` leaves the tree exactly as it found it if the pull fails.

- Being offline must never turn a good commit into a failed command, now that `update` is the only way to commit.
	- A remote that can't be reached warns and skips the pull. A remote that *is* reachable but can't fast-forward is a real problem and still fails hard - the distinction is what the pre-command fetch already discovered.
	- `--no-fetch` means offline, so it skips the pull too. Skipping only the fetch and then pulling anyway would have saved nothing.

- The command set is split by how often you type it. Daily verbs stay one word (`update`, `sync`, `status`, `release`); everything else is grouped under a noun (`repo`, `br`, `pr`).
	- Among the options considered, we decided the extra word is worth it for infrequent commands. It buys discoverability - three nouns to explore instead of a flat list to memorize - and it retires mashed-together abbreviations like `newbr`/`gobr`/`listbr`.
	- One verb per action across all three nouns: `create`, not `create` in one place and `new` in another. `new` and `go` still work as unpublished spellings, because they are what fingers reach for.
	- `repository` and `branch` are accepted in full. Only the short forms are published, so the help stays scannable.
	- Internally each noun/verb pair collapses to a single token, so the rest of the program still deals with one flat command name. Tokens carry a hyphen, which no typed command may, so they cannot be invoked directly.

- Getting connected is three commands, not one overloaded one: `repo clone` (get an existing repo), `repo create` (make the remote, then publish to it), and `repo connect` (publish to a remote that already exists). The mental models differ, and a single command inferring intent from directory and remote state could silently do the wrong thing in the wrong directory.
	- All three use the same preview-then-confirm flow as every other mutating command.
	- Creating a remote is the one irreversible, outward-facing thing here, so it was given its own verb rather than left as a side effect of connecting. `repo connect` now refuses a target that doesn't exist and names `repo create`; `repo create` refuses one that does and names `repo connect`.
	- `repo connect` refuses remotes that already have history rather than auto-merging: forgiving means not destroying either side. Reconciling unrelated histories stays raw-git territory.
	- `owner/name` targets go through gh (honoring gh's git_protocol setting); plain URLs never touch gh, and can only be connected to, never created.

- Pull requests are subcommands of one noun (`pr`, `pr create`, `pr <n>`, `pr ok <n>`) rather than separate top-level verbs.
	- This puts everything about a PR in one place to look, and matches how `repo` and `br` group.
	- `pr create` defaults its title to the last commit subject. The alternative, requiring a title, was rejected as inconsistent with `update`/`sync`, which generate a message when none is given. The preview shows the resolved title before the prompt, so a bad default is visible rather than surprising.

- `br prune` deletes only what is provably already landed, and never takes a branch name.
	- `br land` and `pr ok` delete the branch they merged, but nothing cleaned up after a PR merged from the web UI or another machine, after a superseded branch, or after one simply abandoned. Those accumulate, and a noisy `br list` works against the tool's own goal of staying easy to see.
	- The test is `merge-base --is-ancestor` against the merge target. That is exact here only because gitsby always lands with a real merge commit: a squash- or rebase-landed branch never looks contained, so it is kept rather than guessed at. Other tools' prune commands are unreliable for exactly that reason; the opinions are what make this one safe.
	- Unmerged branches are listed and left alone, and there is deliberately no `--force`. A bulk delete is the wrong place to offer an override, and the one branch the user cares about is the one an override would eat.
	- The remote copy goes only when origin's own copy of the merge target contains it. A landing that hasn't been pushed yet leaves origin holding the only ref to that work.
	- The current branch and `main`/`master`/`dev` are never candidates. Deletion runs through `git branch -d`, never `-D`, so git gets the last word even after our own check passed; a refusal warns and moves on.
	- It takes no arguments at all. Choosing branches by name is what raw git is for, and an argument slot would invite exactly the "delete this one specific thing" use that the ancestry gate cannot vouch for.

- The pre-2.0 command names were dropped outright rather than kept as hidden aliases. Version 2 is a deliberate break, the tool is invoked by a different name than it was, and not all of the old commands worked. Carrying dead spellings forward would have been the worst of both.

- Commands that hand a branch to someone else's deletion must park work first.
	- `gh pr merge --delete-branch` removes the branch local and remote. Anything not pushed is outside the pull request, so merging it would drop that work from the branch it lived on.
	- We decided `pr ok` refuses rather than auto-pushing. Pushing and immediately merging would land commits nobody reviewed, which defeats the point of proposing a change for review.
	- `pr create` is the opposite case and does park work automatically: publishing is the whole intent, and nothing is being deleted.

## Architecture

### Software stack

- Bash 4.4+ (for *nix or WSL), and/or PowerShell 7+ (cross-platform). Nothing else at run time except `git`, plus `gh` for the two commands that need it.

- No configuration file, and no state of its own. Everything gitsby knows, it asks `git` for. That is deliberate: there is nothing to get out of sync, and nothing to migrate.

### UI

- Terminal text, one screen at a time. Output opens and closes with a blank line, and sections are separated by blank lines rather than rules.

- Lists of files are one per line, truncated to the terminal width and capped, so a large working tree cannot scroll the prompt out of view.

- Before anything touches a remote, the display names who you would be acting as: the SSH identity after host aliases are resolved, and the author that would be stamped on commits. Having more than one account configured is common, and pushing as the wrong one is easy and awkward to undo.

### Testing

- A regression suite and a fuzz suite, both run once per implementation, both against throwaway repos built under a temp directory. Neither touches the network or a real repo.

- The fuzz suite asserts three things: no internal crash, no shell or command injection, and that inputs which must be refused exit nonzero and leave the repo unchanged.

- The `gh` paths are covered by a stub on `PATH`, so the GitHub-facing branches are exercised without a network or an account.

### Release policy

GitHub's `releases/latest` returns the newest release not flagged as a pre-release, and both installers resolve through that redirect. Among the options - flag candidates as pre-releases and teach the installers a `--pre` switch, or publish everything as a full release - we decided on the latter. The semver suffix in the tag already tells a reader that `v2.0.0-rc1` is a candidate, and it keeps the documented one-liner installs working with no extra arguments. `--ref`/`-Ref` covers anyone who wants a specific tag or branch.

## Code review 20260726

Fix notes for the "Code Review 20260726" backlog items. Numbering matches the backlog. All five apply to both implementations.

- Item 1 - a refusal naming a dropped command:
	- `br switch` off a dirty `main`/`dev` offered `gitsby commit` as the alternative. Dropping the bare `commit` left the message behind.
	- `update` is the replacement, since it commits on the branch you are standing on.
	- Worth a standing check: every command named inside an error message should be one the parser still accepts.

- Item 2 - one rule for offline, applied once:
	- Seven commands pull. Only `update` and `sync` went through the helper that knows about `--no-fetch` and an unreachable remote; the other five called `git pull` directly.
	- The pulls now share a helper, so the rule is stated in one place instead of five.
	- It stays quiet where the old code was quiet: a skipped pull inside a multi-step command prints nothing, while `update`, whose whole job is the pull, still says why it skipped.
	- The offline warning also claimed the work was already committed, which stopped being true when the pull moved ahead of the commit.

- Item 3 - help text as documentation:
	- The built-in help is the only documentation most people will read, so it drifting is a real defect, not a typo.
	- Three separate drifts: the command order in `update`, the scope of `--no-fetch`, and a PowerShell parameter block still listing `pull` and `commit`.

- Item 5 - a test green for the wrong reason:
	- Asserting on output means the assertion has to be specific enough that a failure cannot satisfy it. The pattern matched the flag name, and the error message about the flag contained the flag name.
	- Both implementations take `-NoFetch`; only Bash takes `--no-fetch`. Shared checks use the spelling both accept.

## Code review 20260723

Fix notes for the "Code Review 20260723" backlog items. Numbering matches the backlog. Unless marked bash-only or pwsh-only, apply to both implementations.

### High severity

- Item 1 - pull failure strands the autostash:
	- Preferred: replace the manual stash push/list/pop dance with `git pull --ff-only --autostash`.
		- Verified on the failing fixture: the tree is left fully intact on ff refusal.
		- Autostash skips untracked files, but an ff-only pull never needs them stashed (git aborts safely on collisions), so it's equal-or-better.
		- Also removes 4 subprocess spawns and makes item 21 moot.
	- If keeping the manual dance: soften the error path around the pull, always pop when a stash was pushed, and on failure print "your changes are in the stash; run git stash pop" before exiting nonzero.
- Item 2 - land deletes the remote branch before the merge reaches origin:
	- Gate the remote delete on the merge actually having been pushed, not just on the branch existing remotely.
	- When the merge target has no upstream, publish it first (`git push -u origin HEAD`, same as the push command already does), then delete.
- Item 3 - newbr/gobr park WIP onto main/dev:
	- newbr: a dirty tree survives `git checkout -b`, so when on the merge target just carry the work to the new branch instead of committing first.
	- gobr and sync from main/dev: refuse or warn loudly and require explicit confirmation before any commit+push lands on a protected branch.
	- The preview should name the branch being pushed so the interactive prompt is informative.

### Medium severity

- Item 4 - -h/-v matches inside messages (bash-only):
	- The `case " ${*,,} "` scan runs before fParseArgs and substring-matches the joined argv.
	- Check only the command slot, or fold -h/-v handling into fParseArgs where switches are already distinguished - matching the pwsh approach.
- Item 5 - non-tty auto-confirm:
	- Fail closed: no tty + no explicit -q = abort mutating commands with "no tty to confirm; re-run with -q". Read-only commands can keep the implicit quiet.
	- install.bash already demonstrates the pattern (tty probe, then hard error demanding -y).
- Item 6 - dropped second message word:
	- For message-taking commands, join remaining positionals into the message, or reject a non-empty third positional with "quote your commit message".
- Item 7 - trap dump on git failures (bash-only):
	- Let fRun report its own failures ("git pull --ff-only failed (exit N)" + next step where knowable), reserving the trap dump for unexpected script errors.
- Item 8 - echo -e escape expansion (bash-only):
	- `printf '%s\n' "$*"` in fEcho_Clean; nothing in the script relies on -e expansion.
	- The attack vector is raw control bytes in filenames: git C-quotes them to octal text, and -e re-animates them into live escape sequences. Plain printf keeps them inert; no extra stripping needed.
- Item 9 - pwsh case-insensitive branch compares: `-ceq`/`-cne` at lines 489, 498, 515, 516, 573, 577, 602. Keep `-eq` for the 'ok' arg and 'y' prompt (intentionally case-insensitive, matches bash lowercasing).
- Item 10 - pwsh release tag crash: pad missing minor/patch components before arithmetic (bash yields v1.2.1 from v1.2; mirror that), or validate against the X.Y.Z regex and fall back cleanly.
- Item 11 - install.ps1 temp file: download into a freshly created private random subdirectory (or `[IO.Path]::GetRandomFileName()`); keep the finally-cleanup.
- Item 12 - credential leak in remote URL display: mask anything between `://` and `@` before printing (`https://***@github.com/...`). Only the two display lines need it; fSshTarget already ignores userinfo.
- Item 13 - default-branch detection:
	- Run `git remote set-head origin --auto` alongside the existing per-run fetch (or once when origin/HEAD is unset); keep the local read as offline fallback.
	- Fixes both the missing-ref case (git < 2.47 never auto-creates it) and the stale case (upstream master->main rename; reproduced stale even on git 2.51).
- Item 14 - fetch timeout/offline:
	- Bound the fetch (ssh: `GIT_SSH_COMMAND='ssh -o ConnectTimeout=3'`; note `timeout(1)` isn't on stock macOS, and ConnectTimeout doesn't cover https).
	- Add a --no-fetch/offline flag. Don't just skip the fetch for commit: the pre-flight ahead/behind + incoming display deliberately depends on it.
- Item 15 - per-run caching:
	- After the fetch, resolve currentBranch, defaultBranch, mergeTarget, hasUpstream, and ahead/behind (one `rev-list --left-right --count`) into locals; pass down to status/preview/commands.
	- Keep live helper calls where state genuinely mutates mid-command; the post-run status re-check is intentional, leave it.
- Item 16 - test gaps: add fixtures for diverged-pull-with-dirty-tree (assert the edit is back in the tree), no-remote sync/newbr/land, `newbr feat/x`, `commit "add -v flag"` (assert a commit lands), the -m and -m= forms, and release started from a feature branch (assert it returns there).
- Item 17 - README commands section: the built-in help table plus one worked flow (newbr -> hack -> update -> land), the -q/-m options, and the gh dependency for pr/release.
- Item 18 - which -> command -v (bash-only): `command -v "${prog}" >/dev/null 2>&1 || fThrowError ...`. Also drop the unused second argument passed to fThrowError there.

### Low severity

- Item 19 - checksums: publish SHA256SUMS from cicd next to release assets; verify with `sha256sum -c --ignore-missing` / Get-FileHash before install. Checksums only apply on the release path; document that --ref skips verification.
- Item 20 - release lookup: `curl -sI -o /dev/null -w '%{redirect_url}' .../releases/latest` and parse the tag from the Location header; API scrape as fallback; mention rate limiting in the error text.
- Item 21 - stash-before-upstream-check: early-return "nothing to pull" before touching the tree. Moot if item 1 lands as --autostash.
- Item 22 - fIsAhead: `git rev-list -n 1 '@{u}..'` (stops at first commit; `--count` still walks the whole range).
- Item 23 - prune: `git fetch --quiet --prune`, and tolerate "remote ref does not exist" in land's remote delete.
- Item 24 - pwsh exit codes: check $LASTEXITCODE after `gh pr view` before running the diff; same check after the bare git calls in the read-only path (status/listbr) instead of unconditional exit 0.
- Item 25 - drive letters: `if ($Url -match '^[A-Za-z]:[\\/]') { return '' }` before the scp-like match (git's own rule: single-letter prefix before the colon is a drive).
- Item 26 - ssh -G: add `--` before the host argument. Currently fails closed (ssh errors out, identity line just goes missing), so hardening only.
- Item 27 - install-dev.ps1: reject option-shaped $Directory (`^-`) and/or pass `-- $Directory` to git clone, matching install-dev.bash.
- Item 28 - install.ps1 content check: before Move-Item, verify the first line matches `^#!`, mirroring install.bash. (HTTP 4xx/5xx already throw; the residual case is wrong content with a 200.)
- Item 29 - GIT_MERGE_AUTOEDIT: delete the line; both merges pass -m so the editor never opens anyway. (In-process .ps1 invocation leaks $env: changes into the caller's session.)
- Item 30 - head/wc pipelines (bash-only): `mapfile -t -n 1` for the tag read, array count for the stash lists. Gotcha: bare `read` under set -e + inherit_errexit returns 1 on empty input - use mapfile or `|| true`. Keep the before/after stash count compare (push can no-op).
- Items 31-34 - mechanical style fixes; see the backlog bullets.
- Item 35 - early validation: hoist newbr/gobr branch checks into the main flow next to the existing pr-number and release-version checks (after the repo check, before status/preview/prompt).
- Item 36 - help/version words: one alias case entry each, both implementations.
- Item 37 - stack-line noise (bash-only): add a usage-error variant of fThrowError (or a flag) that skips the call-stack line.
- Item 38 - -y alias: add y/yes to the existing switch case (bash) and Alias list (pwsh); describe as "assume yes / no prompts".
- Item 39 - typos: three one-word fixes in README.
