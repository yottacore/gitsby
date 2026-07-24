<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Design

Design, requirements, and direction. The active pre-v1.0.0 bug/feature task list lives in `backlog.md`.

## Assumptions

## Project structure

### Folder structure

### Logical code structure

### Data flow

### Execution flow/loops

## Direction decisions

## Plan

## Architecture

### Software stack

### Configuration model

### Saves and persistence

### UI

### Testing

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
