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

- `cicd/` - the local pipeline, its config, and the test and fuzz suites. Everything the demo gif is built from lives together under `cicd/utility/demo/`.

- `project/` - this file and the backlog.

- `assets/` - the logo and the demo shown at the top of the README.

- `reference/` - notes kept for lookup, not published as project docs.

- Root - the four installers, the license, and the public docs.

### Logical code structure

All three implementations follow the same shape, in the same order:

1. Parse arguments, and collapse a noun and its verb (including the unpublished spellings) into one command name.

2. Refuse anything unworkable up front: unknown commands, bad branch names, a version that is already tagged, no terminal to confirm on.

3. Fetch, so everything displayed afterward is current.

4. Show the repo state, then the exact commands about to run, then ask.

5. Run them, each one state-checked at the moment it runs.

6. Show the state again.

The Bash and PowerShell files are ports of each other, and were kept in step for as long as they were the implementation. Both are frozen now, and the Go build is the one that moves - see "Direction decisions" below. The suites run against all three.

### Execution flow

- Every mutating command is preview-then-confirm. `-q`/`-y` skips the prompt; nothing skips the state checks.

- The preview is a static recipe per command, with `*` marking steps that only happen if the repo state calls for them. It has to match what the command actually does, including where the command branches on state.

- No command shells out through `eval`. Arguments are passed as arrays, so a message or branch name is never re-parsed.

- Any command named inside an error message, or in the built-in help, has to be one the parser still accepts. The help is the only documentation most people read, so it drifting is a defect, not a typo.

- A recursive or forced removal may only target a path the running script itself created, and has to be able to prove it.
	- In practice that means the path came straight from `mktemp` and nothing else ever assigns it.
	- Where a path arrives from outside - an argument, an environment variable - proof means a marker the script wrote when it built the directory. Absent marker, absent removal.
	- Every such removal is written so an unset variable stops it rather than widening it, because the failure mode of getting this wrong is not recoverable.
	- The one product-side temp path is the throwaway git dir the publish preview uses. It is removed on the exit path, so an interrupt cannot strand it.

## Direction decisions

- There is no bare `commit`, and no bare `pull` that skips the commit. Both were escape hatches around the workflow the tool exists to enforce.
	- `commit` alone produces exactly the state gitsby was written to prevent: work committed locally that never reaches the remote, diverging quietly until the merge is painful.
	- `pull` alone was the only place gitsby let you take upstream changes without dealing with your own work first, which contradicts what it does everywhere else - `br switch`, `br merge`, and `pr create` park it; `br create` off `dev`/`main` carries it onto the new branch.
	- We decided the asymmetry settles it: dropping a command before release costs nothing, and adding one back later breaks nobody. Removing one after release would.
	- Removing `pull` exposed a real bug it had been masking - see the ordering decision below.
	- The word came back later as one of the spellings of `pullcom`, which does not reopen this: an alias onto the command that pulls *and* commits structurally cannot skip the commit.

- `pullcom` and `sync` pull *before* they commit.
	- Committing first mints a local commit, so a remote that has merely moved ahead is now diverged and a fast-forward-only pull must refuse. That is the everyday case, not an edge one, and it was failing.
	- Pulling first fast-forwards under `--autostash`, so the dirty tree rides over and the commit lands on top. History stays linear and fast-forward-only stays satisfiable, which is the whole reason the tool never merges behind your back.
	- Nothing is risked by pulling first: on a failed pull `--autostash` restores the tree as it found it, rather than stranding work in the stash. (A restore that conflicts is the one case git leaves the entry behind, and it says so.)

- Being offline must never turn a good commit into a failed command, now that `pullcom` is the only way to commit.
	- A remote that can't be reached warns and skips the pull. A remote that *is* reachable but can't fast-forward is a real problem and still fails hard - the distinction is what the pre-command fetch already discovered.
	- `--no-fetch` declines the incoming round trip, so it skips the pull as well as the fetch. Skipping only the fetch and then pulling anyway would have saved nothing. It is not a way to say "I am offline" - see the offline rule below for why that distinction is deliberate.

- The command set is split by how often you type it. Daily verbs stay one word (`pullcom`, `sync`, `status`, `identity`, `release`); everything else is grouped under a noun (`repo`, `br`, `pr`).
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
	- `pr create` defaults its title to the last commit subject. The alternative, requiring a title, was rejected as inconsistent with `pullcom`/`sync`, which generate a message when none is given. The preview shows the resolved title before the prompt, so a bad default is visible rather than surprising.

- `br prune` deletes only what is provably already landed, and never takes a branch name.
	- `br merge` and `pr ok` delete the branch they merged, but nothing cleaned up after a PR merged from the web UI or another machine, after a superseded branch, or after one simply abandoned. Those accumulate, and a noisy `br list` works against the tool's own goal of keeping the repo easy to see at a glance.
	- The test is `merge-base --is-ancestor` against the merge target. That is exact here only because gitsby always lands with a real merge commit: a squash- or rebase-landed branch never looks contained, so it is kept rather than guessed at. Other tools' prune commands are unreliable for exactly that reason; the opinions are what make this one safe.
	- Unmerged branches are listed and left alone, and there is deliberately no `--force`. A bulk delete is the wrong place to offer an override, and the one branch the user cares about is the one an override would eat.
	- The remote copy goes only when origin's own copy of the merge target contains it. A landing that hasn't been pushed yet leaves origin holding the only ref to that work.
	- The current branch and `main`/`master`/`dev` are never candidates.
	- Deletion runs `git branch -D`, gated by our own containment check rather than git's. `git branch -d` asks whether the branch is contained in its *upstream*, or in *HEAD* when it has none - neither of which is the question prune asks. The first produces a warning about HEAD on every branch when you prune from anywhere but the target; the second silently refuses a genuinely-merged local-only branch, so the plan promises a deletion that never happens. Deferring to git here looked conservative and was actually wrong in both directions.
	- The containment check is re-run immediately before each delete rather than trusted from plan time, since the confirmation prompt can sit for a while.
	- It takes no arguments at all. Choosing branches by name is what raw git is for, and an argument slot would invite exactly the "delete this one specific thing" use that the ancestry gate cannot vouch for.

- The pre-2.0 command names were dropped outright rather than kept as hidden aliases. Version 2 is a deliberate break, the tool is invoked by a different name than it was, and not all of the old commands worked. Carrying dead spellings forward would have been the worst of both.

- A branch is displayed against the branch it is off of, as `base :: branch`.
	- Every line in the state block answered "where am I", and none answered "off what". Running `br hotfix` from `dev` showed `dev` on the current-branch line and `git checkout main` in the plan under it. Both true, and read together they look like a mistake.
	- The base shown is where the branch *lands*. Git records no fork point to read back, and for a branch gitsby made the two are the same by construction, so the land target is the honest answer and the only available one.
	- `main`, `master` and `dev` are shown bare. They are not off anything you would branch from, and `dev :: dev` is noise. `dev` does land on `main`, but only at release, and saying so on every line would imply otherwise.
	- Commands that create a branch state it outright, before the plan. That is pre-flight only: afterward the branch exists and the current-branch line already answers it.
	- The repo's default branch is its own line. It applies to the whole repo, not to the branch you are on, and parenthetical asides on one line do not scale to two facts.

- The pre-flight names gh's account, because it is not necessarily the one git pushes as.
	- gh authenticates to the API with its own token and never reads ssh config. So `pr create`, `pr ok`, and `repo create` act as gh's account, while `git push` in the same repo acts as whatever key the remote's host alias selects. With per-account aliases those are different people.
	- Showing it is not new policy - the identity block already exists to answer "who am I about to be on the remote", and for the gh-backed commands it was answering with the wrong identity.
	- We decided against validating gh's configuration more broadly. Policing another tool's setup is not gitsby's job, gh's config moves, and it would turn working commands into refusals. The failure that prompted this was a *hang*, and the fix for a hang is to never hang.

- A gh write acting as a different account than the ssh key is refused unattended, warned about interactively.
	- Every command that writes through gh compares identities: `pr create`, `pr ok`, `repo create`, and `repo connect` with an `owner/name`. The read-only `pr` forms never pay for the extra round trip.
	- `repo create` and `repo connect` have no origin to read, but they do not need one. gh never uses a host alias - it builds the canonical `git@github.com:owner/name.git` from its own protocol setting - so the identity that repo will live with afterward is knowable before anything is created, and is checked then.
	- There are three outcomes, not two: match, mismatch, and **unknown**. Unknown is common and harmless - no ssh agent (every CI runner), an https remote, a deploy key answering with a repo name instead of a login, gh logged out. It is reported and never blocks. Only a difference both sides confirm counts, or the check would break exactly the automated runs it cannot help.
	- Erroring under `-q` rather than warning follows the rule already set for a missing tty: when nobody is there to read a warning, refuse instead of guessing. Opening a pull request as the wrong account is public and awkward to undo, which is the same reasoning that gave `repo create` its own verb.
	- The warning prints immediately above the confirmation prompt, not with the rest of the state block, so it cannot scroll away behind the plan.
	- `--any-identity` says the difference is intended. It suppresses the error and the warning but not the identity line, so an override still leaves the mismatch visible on screen.
	- The remote these commands leave behind keeps gh's canonical URL. Gitsby will not guess which of your host aliases serves that account: it would have to infer your setup from `~/.ssh/config` and probe each candidate, and a wrong guess silently points a repo at the wrong key. Reporting the identity and leaving the URL alone is the honest version. Anyone who wants an alias can pass a full URL to `repo connect`, which never involves gh at all.

- The ssh identity is probed with the command git itself would run, not a bare `ssh`.
	- `core.sshCommand` is the usual way to keep two accounts apart on one machine: set per repo (often through `includeIf` on the path), it picks the key without any host alias, so every remote stays a plain `git@github.com` URL.
	- A bare probe cannot see that. It answers for ssh's default key while git pushes as somebody else, and the two wrong halves agree often enough to read as a clean bill of health - the check passed most confidently in exactly the setup it exists for.
	- `GIT_SSH_COMMAND` beats `core.sshCommand`, which is git's own precedence. The value is split, never re-shelled: config is not a place to run code, so a quoted path falls back to a plain probe instead of misparsing. Answering "unknown" is safe; answering with the wrong name is not.
	- The same command backs the fetch and the remote probe. Both used to force a bare `ssh` for the connect timeout, and because `GIT_SSH_COMMAND` outranks `core.sshCommand` that silently overrode the repo's key - a private repo only that key can read looked like being offline.
	- The key named in the identity line comes from the same place, so the line cannot report the right account beside the wrong key file. Half-right is worse than either half alone: it invites you to trust whichever half happens to be wrong.

- Which GitHub account you act as is decided by the folder you are in.
	- People who have two accounts almost always have a folder per account already. That existing habit is the configuration; asking them to restate it per repo would be asking twice.
	- One account is resolved per run and applied to everything at once - gh, git's credentials, the ssh key, and the commit identity - because a run that pushes as one person and commits as another is the failure this exists to prevent.
	- Resolution order, most specific first: `GITSBY_ACCOUNT`, then `gitsby.ghAccount` in git config, then the config file's folder rules, then the owner of the remote. Finding none of them is the ordinary single-account case and changes nothing.
	- Zero configuration stays the default case, and it is why the remote's owner is consulted at all: that fact is already knowable, so a single-account setup never notices the feature exists.
	- Everything degrades to silence. Unset keys, a missing or unreadable or empty token file, no config file, no gh at all: each falls back to gh's own account rather than failing. A checkout that was never set up this way still has to work, and a pipeline must not break on a box that has not been prepared.
	- Only when the account can be named *and* its token is held. An org or a fork we have no account for is ordinary, and is left alone rather than refused: `owner != your login` is the normal case for contributing to anyone else's repo, so asserting on it would fire constantly and wrongly.
	- Reads get this as well as writes. A `pr` listing against a private repo the active account cannot see fails the same way a write does.
	- The choice is named in the identity block, not silent. Picking an account is still a change of who you act as, and this is a tool that shows its plan before acting. `--any-identity` turns it off along with the mismatch check.

- Gitsby does have a config file, and it is deliberately not a git config file.
	- The earlier decision was the opposite - `includeIf` on the repo path already selects the ssh key and the commit identity, so a second config system looked like a second thing to keep in step with reality.
	- What changed the answer is that folder rules are the point. `includeIf` can only say "when you are here, read this"; it cannot be listed, checked, or explained back to you, and writing one block per account per machine by hand is the chore the feature exists to remove.
	- So the file owns the mapping and `account apply` generates the `includeIf` blocks from it. There is still one source of truth, and plain `git` outside gitsby follows it.
	- Flat `key = value` lines, hand parsed. Neither build needs anything installed to read it, and neither can parse it differently from the other - which a real format with a real parser per language could not promise.
	- `gitsby.ghAccount` and `gitsby.ghTokenFile` in git config still work and still win, for a single repo that wants to answer for itself.
	- `gitsby.ghTokenFile` and the per-account `tokenFile` name a token for an account gh has never been logged in as, for a machine set up by copying files rather than by authenticating. gh's own store is consulted first, so a rotated login is never shadowed by a stale token on disk.
	- Paths are compared canonically, never as text. The Bash build sees `/c/x` where the PowerShell build sees `C:\x`, and a rule that matched in one build and not the other would be worse than no rule at all.

- A token, not a key, is the way to hold two accounts - and gitsby says so without taking the choice away.
	- The conventional answer is a key per account plus `~/.ssh/config` host aliases, which then have to be baked into every remote URL. It works, and it spreads the account across three places that can disagree.
	- Over https, git can authenticate with the same token gh already stores. Gitsby supplies it through the environment for one command, so nothing is written and a killed run leaves nothing behind.
	- `repo url` converts an existing remote, because that is the only thing standing between an ssh repo and a token. Only the URL changes.
	- Keys remain fully supported, and `IdentitiesOnly` is set with them: without it ssh offers every key the agent holds and the server takes the first that authenticates, which on a two-account machine is a coin toss.
	- Anything the user set themselves - `GIT_SSH_COMMAND`, `core.sshCommand` on the repo, a repo-local `user.email` - outranks a folder rule. A folder rule is a default, not an override.
	- The suggestion to convert is one line, shown only when it would actually help, and `protocol = ssh` retires it. Advice you cannot turn off is noise.

- `raw` is a noun, so the tools it fronts stay out of the command namespace.
	- `gitsby git ...` would have read better and cost more: `git` and `gh` would become reserved words in the command slot forever, and anything else needing verbatim passthrough later would have no home.
	- Everything after the tool name is the tool's, verbatim. Our own options have to come first, because past that point a `-q` is git's flag and not ours.
	- The PowerShell build cannot get those arguments from its own parameters: the binder claims `-m`, `-q` and friends wherever they appear, so `raw git commit -m "msg"` would arrive rearranged. It reads the process command line instead, and refuses rather than guessing when that is unavailable.
	- stdout belongs to the tool alone and the exit code is passed straight back, so a script can pipe it. The one line naming the account goes to stderr, and `-q` silences it.

- Commands that hand a branch to someone else's deletion must park work first.
	- `gh pr merge --delete-branch` removes the branch local and remote. Anything not pushed is outside the pull request, so merging it would drop that work from the branch it lived on.
	- We decided `pr ok` refuses rather than auto-pushing. Pushing and immediately merging would land commits nobody reviewed, which defeats the point of proposing a change for review.
	- `pr create` is the opposite case and does park work automatically: publishing is the whole intent, and nothing is being deleted.

- Offline is split by what a command is for, not handled once for all of them.
	- A command that means something locally runs and reports what it skipped: `pullcom` commits, `br create` and `br hotfix` make the branch, `br switch` switches, `br merge` merges. Each one names `sync` as the way to publish afterward.
	- A command that exists to publish refuses before the plan is shown: `sync`, `pr create`, `pr ok`, `release`. Reporting success having sent nothing is worse than a hard failure, and failing halfway through on raw git output is worse than refusing up front.
	- Offline is the state the pre-command fetch discovers, not a flag you pass. `--no-fetch` declines the incoming round trip - a reasonable thing to want against a reachable remote - so it does not stop a push. The cost is that it also declines the check, so a push while genuinely offline fails with git's own message.
	- Two places need more than a skipped push. `br merge` holds back the remote branch delete until the merge is published, because until then origin's copy is its only ref to that work. The hotfix back-merge normally merges `origin/<default>` (correct after `pr ok`, which lands server-side); offline that ref is the stale one, so it falls back to the local branch.

- The one command that publishes a directory shows what is in it first.
	- `repo create` and `repo connect` from a plain directory list the files before asking. Everything else in the tool previews what it touches; this is the step where a stray `.env` or private key becomes public.
	- The list has to be git's own answer, not a directory walk, or it would name files `git add --all` will skip and miss the exclusions that matter. A throwaway git dir outside the work tree asks git the real question and writes nothing into the user's directory - which is the point, since answering "n" must leave it untouched.

- The Bash and PowerShell scripts are frozen. The Go build in `src-go/` is the implementation that moves.
	- Both scripts stay in the tree, read-only, as the behavioral reference the port is measured against. Only a production hotfix reopens them.
	- Among the options considered, we decided that keeping three implementations in step triples the cost of every change and leaves the newest one nothing to be checked against - a reference that moves is not a reference. Pinned at 2.1.0 behavior, the scripts give the port something byte-for-byte to compare against.
	- The Go build keeps the whole 2.1.0 command surface. Where a command is renamed the old name stays as an unpublished spelling, so nothing that works today stops working. It may add a command or two of its own.
	- Byte-identical output stays the test for everything that has not deliberately changed. A rename moves help and error text on purpose, and those cases are carved out explicitly rather than left to read as regressions.

- `update` became `pullcom`, and `br land` became `br merge`. The old spellings keep working, permanently.
	- `update` said nothing about direction, and read like it updated gitsby itself. `pullcom` names both halves in the order they run - the ordering decision above, made visible in the name.
	- `sync` kept its name. It was never unclear on its own; the pair was. Two words that read as synonyms, with no hint which one publishes, and renaming one end settles it.
	- `merge` is the word people reach for before they learn `land`. `land` stays as a spelling, and stays the vocabulary the rest of the tool uses for the act itself.
	- `pullcom` also answers to `update`, `pull`, `pullc`, `pullco`, `pullcomm` and `pullcommit`. This is the only prefix ladder in the tool, and it earns the inconsistency: the command you type all day, with a tail nobody recalls exactly. Nothing else is prefix-tolerant, and the fix for that is not to spread it.
	- `finish` was considered as a second name for `br merge` and rejected. It overclaims - merging to `dev` still owes a release - and under a permanent-alias promise every spelling is forever.
	- Go build only. The scripts keep the names they shipped with and stay the reference for everything the rename does not touch.

- `identity` shows the identity block on its own.
	- `status` already answers "who does this act as", but buried under branch and working-tree state you did not ask about. `account list` answers a different question - what is configured, everywhere, rather than what applies here.
	- The same lines `status` prints, from the same code, so the two cannot drift apart. That includes the rule that the Account line appears only for an account asked for or configured, never one merely inferred from the remote's owner.
	- It answers outside a repository too. Which account a folder belongs to is worth knowing before there is anything in it, which is exactly when you are about to clone or create.

- The CI/CD stack follows the implementation into Go, rather than becoming cross-platform PowerShell.
	- Among the options considered, PowerShell was rejected for the stack. A single pwsh engine would have retired the hand-synced Windows copy, but only the interpreter is portable - the stack still shells out to git, gh, shellcheck, markdownlint and the rest, so the glue changes syntax without changing what it depends on. It also adds an interpreter that has to be installed, where Bash is already present everywhere the project builds and Go needs nothing at all.
	- The test suite was the specific reason. It fakes `gh`, `git` and `uname` by writing shebang scripts onto PATH, which a process launched from .NET cannot execute on Windows - so a PowerShell port would have traded one platform trap for a new one.
	- What stays as it is: the demo gif generator, already portable and pinned byte for byte to a font stack and an optimizer, and the lint stage, genuinely better expressed as a shell pipeline than as compiled code.
	- Done as of 2026-08-18. `cicd-win.ps1` is deleted, the engine runs seven stages, and the Go toolchain is required rather than probed. The remaining Bash is the pipeline's own, not the product's.

- The frozen builds live in `legacy/`, holding the deliverables alone - both scripts and the four installers of that era. No copy of the pipeline went with them.
	- Among the options considered, copying `cicd/` into `legacy/cicd/` was rejected. The v2.1.0 tag is a better hotfix tree than any copy: it holds the scripts, the pipeline that built them and the installers all in their original places, wired to each other and unmodified. A copy would have needed its config edited - no dogfood, no publish, no demo, different lint globs - so the thing reached for during a hotfix would no longer have matched what shipped.
	- Rot argues the same way. In a few years the old suite may not run from either location, and a rotted copy at a tag is inert where a rotted copy in the working tree keeps surfacing in greps, lint globs and reviews.
	- So a hotfix starts at the tag, ships from its own branch with its own tag, and is never merged back to `main` - those paths do not exist there.
	- What keeps the six files in the tree at all is the port, not hotfixes: they are the reference this build is compared against. When that comparison retires, they can go, and the tag still holds them.

- `parity.bash` was kept and repointed rather than dropped. It used to compare the two scripts against each other; it now compares this build against the frozen v2.1.0 one.
	- That is the backwards-compatibility question, and it is the one still worth asking. The behavioural suite asks "is this correct?" of one build at a time, so it passes while two builds quietly disagree about the same input - which is what every port defect that reached users actually was.
	- The PowerShell build is not a third leg. The two scripts were proven identical to each other at v2.1.0, so agreeing with one is agreeing with both, and a third leg would only add an interpreter to find.
	- It also checks that `update` and `br land` still route where they always did, under both spellings. A permanent alias is a promise, and promises get checks.

- The version lives in the tag and nowhere else.
	- The scripted builds each carried a `thisVersion` string by hand, and a release rewrote both. They had drifted before, which is why phase 1 compared them.
	- A Go build takes its version from `-ldflags` at build time, so there is nothing in the tree that can disagree with the tag. Cutting a release now edits exactly one file: the changelog heading.

## Branching model

Gitsby's own repo runs the model gitsby enforces, so the tool is its own first user.

### How the common models compare

| Model | Long-lived branches | Feature branches | Release | Path to the published branch between releases
| :-- | :-- | :-- | :-- | :--
| GitFlow | `master` + `develop` | off `develop`, back to `develop` | `release/*` off `develop`, merged to `master`, tagged | `hotfix/*` off `master`, merged to `master` and `develop`
| GitHub Flow | `main` | off `main`, back via pull request | tag on `main` | not needed - `main` is always current
| Trunk-based | `main` | very short-lived, sometimes direct commits | `release-X.Y` cut from `main` | cherry-pick onto the release branch
| GitLab Flow | `main` + environment or release branches | off `main` | promote downstream through one-way merges | fix on `main`, cherry-pick downstream
| Gitsby | `dev` + `main` | off `dev`, back to `dev` | `dev` merged to `main`, tagged | `hotfix/*` off `main`, merged to `main` and `dev`

### Which model this is

Gitsby follows GitFlow, with the stabilization branches left out.

- Two long-lived branches. Feature work lands on `dev`. `main` advances only through a release or a hotfix, so it always describes published state.

- No `release/*` branches. Those hold a version steady while it stabilizes and `develop` keeps moving, which matters when several versions are supported at once. Gitsby supports one. Cutting the release straight from `dev` costs nothing here and removes a branch type.

- `hotfix/*` branches come off `main`. `main` is what the world sees: GitHub renders the README from it, and the install one-liners are served from it. A correction to published material should not have to wait for a release, and should not have to cause one.

- Feature branches are short-lived and land with a real merge commit. That is also what makes `br prune`'s ancestry test exact.

### Why not GitHub Flow

- GitHub Flow keeps one long-lived branch, so what is on `main` is both the published state and the in-progress state. For software distributed by version those are different things: the README should describe the release people can install, while unreleased work has to live somewhere.

- Among the options considered, we decided the second branch earns its place. `dev` is where unreleased work accumulates, and `main` stays a truthful description of the current release.

### The GitFlow author's caveat

- Vincent Driessen added a note to the original 2010 post recommending simpler models, GitHub Flow among them, for teams doing continuous delivery of a single always-current version.

- That caveat is aimed at applications deployed from trunk. Gitsby is versioned released software with downloadable artifacts and an installer that resolves the latest release, which is the case GitFlow was written for.

- What does not apply is supporting several versions simultaneously. That is the part of GitFlow the stabilization branches serve, and the reason they are left out.

### Hotfix branches

- The `hotfix/` prefix marks a branch that targets `main` rather than `dev`. The prefix lives in the ref name, so it survives a clone and shows up in a branch listing. It is also the name the model already uses, so it reads correctly to anyone who knows GitFlow.

- Landing one merges to `main`, then merges `main` back into `dev`. The back-merge is not optional. Without it the next release either conflicts on the same file or quietly reinstates the superseded text.

- A hotfix that touches nothing under `bin/` needs no version bump, because nothing shipped changed. Documentation is not versioned with the binary - the README describes the release, and it is served from `main`, not from the tag.

- A hotfix that does touch `bin/` leaves `main` carrying code that no tag contains, so the assets on the latest release stop matching it. That warrants a patch release, and landing says so rather than leaving it to be noticed later.

### Enforcement

- A GitHub ruleset covers `refs/heads/main` and `refs/heads/dev`: pull request required, deletion blocked, non-fast-forward blocked. A second ruleset blocks deletion of `v*` tags.

- Repository admins bypass the pull-request rule, which is what lets `release` push the release merge and the tag directly.

- Nothing in the model asks for that bypass to be widened. A hotfix reaches `main` through a pull request like every other change.

### Repos that have no dev branch

- Gitsby adapts to the repo it runs in. With no `dev`, the merge target falls back to the default branch, so feature branches come off `main` and land back on `main`.

- That is GitHub Flow, and it is the better default for a project with no release cadence. The model above is what a repo opts into by creating a `dev` branch.

See also the release policy under Architecture, which covers how releases are published once `main` has advanced.

## Architecture

### Software stack

- Go for the live build: one binary per platform, nothing to install alongside it.

- The frozen scripts need Bash 4.4+ (for *nix or WSL), and/or PowerShell 7+ (cross-platform).

- Nothing else at run time except `git`, plus `gh` for the commands that need it: every `pr` form, `repo create`, and `repo connect` when given an `owner/name` rather than a URL.

- No state of its own. Everything gitsby knows about a repo, it asks `git` for, so there is nothing to get out of sync and nothing to migrate.

	- The one file it does read is the accounts config, and it is read-only from gitsby's side: it maps folders to accounts and nothing else. Every value it yields is applied through the environment for the length of one command. See "Gitsby does have a config file" above for why that exception was made.

### UI

- Terminal text, one screen at a time. Output opens and closes with a blank line, and sections are separated by blank lines rather than rules.

- Lists of files are one per line, truncated to the terminal width and capped, so a large working tree cannot scroll the prompt out of view.

- Before anything touches a remote, the display names who you would be acting as: the account the SSH key authenticates as, the connection behind it once host aliases are resolved, and the author that would be stamped on commits. Having more than one account configured is common, and pushing as the wrong one is easy and awkward to undo.

- The account is resolved by asking the host, not inferred from the key filename or the connection. A name that is merely likely is worse than none here, because it gets believed. When it cannot be resolved the display says so.

### Testing

- A regression suite and a fuzz suite, both run once per implementation, both against throwaway repos built under a temp directory. Neither touches the network or a real repo.

- The fuzz suite asserts three things: no internal crash, no shell or command injection, and that inputs which must be refused exit nonzero and leave the repo unchanged.

- The `gh` paths are covered by a stub on `PATH`, so the GitHub-facing branches are exercised without a network or an account.

- Both suites run on Windows as well as Linux, and the PowerShell leg matters most there - it is the only place that build is what people actually use.
	- Stubs are shebang scripts, which PowerShell locates on `PATH` but cannot start. It reports no error, so the stub silently produces nothing and the check passes or fails for the wrong reason. The regression suite gives each stub a `.cmd` sibling that hands the body back to bash.
	- The fuzz suite deliberately does not, and skips the affected checks with a printed reason. A `.cmd` goes through `cmd.exe`, which re-parses an unquoted `&` or `>` in an argument - so a vector this suite hands gitsby would partly run for real, and be reported as an injection that gitsby never had. Its glob vectors break the same way. A named skip is worth more than a green that means nothing.
	- Checks that reach a confirmation need it to refuse rather than wait. `setsid` does that on Linux; Windows has no equivalent and needs none for the PowerShell build, which reads redirected stdin and never falls back to a terminal. The Bash installer does fall back to `/dev/tty`, so its checks additionally require that open to fail.

### Demo

- The demo in the README is drawn, not screen-recorded, and the commands in it really run. They act on a throwaway repo built offline for each render, so the output cannot drift from what the tool actually prints.

- Commit dates in that repo are pinned. An unchanged demo therefore renders byte for byte identical, which is what lets the pipeline replace the committed file only when the demo really changed.

- The demo is described twice on purpose. `script.txt` is the readable version - scenes, captions, typed lines, hold times - and is the one to edit; the scenario file beside it is the machine version. We decided the readable one is the source of truth, because the parameters that shape a demo are aesthetic judgements, and they are far easier to argue about in prose than in a table of numbers.

- Nothing parses `script.txt`. Keeping the two in step is a habit, not a mechanism - a parser would have to be maintained, and the file's value is that a person can change it without learning a format.

- The demo must not be handed the answer it is demonstrating. Its throwaway world deliberately withholds the environment variables that would supply an identity, so the commit author on screen is the one the folder rules chose and not one exported ahead of them. A demo that cannot fail to look right is showing nothing.

- Where a feature is about context - which folder, which account - the demo has to show that context. That is why the prompt carries the working directory: a scene proving the folder decides who you act as, above a prompt that never names a folder, asks to be taken on trust.

### Release policy

GitHub's `releases/latest` returns the newest release not flagged as a pre-release, and both installers resolve through that redirect. Among the options - flag candidates as pre-releases and teach the installers a `--pre` switch, or publish everything as a full release - we decided on the latter. The semver suffix in the tag already tells a reader that `v2.0.0-rc1` is a candidate, and it keeps the documented one-liner installs working with no extra arguments. `--ref`/`-Ref` covers anyone who wants a specific tag or branch.

### Automating a release

The `release` command already does the git half well: merge `dev` into `main`, tag, push, fast-forward `dev`. What stays manual is everything around it, and each manual step has been forgotten at least once.

- What is missing, in order: bump the version in both builds, rename the changelog's `vNEXT` heading to the version and today's date, update the in-script history footers, publish the GitHub release with a title and a body, attach `gitsby`, `gitsby.ps1` and `SHA256SUMS`, and verify the result end to end.

- Where it belongs: `cicd/release.bash`, not the product. Cutting a release is a maintainer's pipeline task that wants `gh`, the checksum generator, and the working tree - none of which the shipped tool should grow a dependency on. `gitsby release` stays the git half and is called by the script.

- The shape, as three phases so a failure never leaves a half-cut release:
	1. Prepare and verify, changing nothing outside the working tree. Resolve the version (argument, else the same bump `release` would choose), refuse if the changelog has no `vNEXT` section, refuse if either build's version string already matches, then run the full pipeline. Nothing here needs undoing.
	2. Land. Write the version into both builds and the changelog heading, commit, PR, merge, then `gitsby release`. This is the only phase that pushes.
	3. Publish and prove. Create the GitHub release with the changelog section as the body, upload the three assets, then verify: `releases/latest` resolves to the new tag, and both documented installer one-liners install it into a throwaway `HOME` and report the new version. A failure here is recoverable by hand and does not corrupt anything.

- Two guards worth building in, because both have already bitten: the history footers in `bin/gitsby` and `bin/gitsby.ps1` are checked for an entry newer than the last release tag, and the two builds' version strings are compared to each other before anything is pushed.

- The verification in phase 3 is the part that pays for itself. Running both installer one-liners side by side is what caught the PowerShell checksum bug, which had silently skipped verification since the day it was added.
