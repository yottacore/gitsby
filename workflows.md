<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->

# The workflow, and the opinions behind it

Gitsby doesn't invent a branching model. It implements two well-known ones and chooses between them by looking at your repo: with a `dev` branch you get one, without it you get the other. Nothing to configure.

- [Why this exists](#why-this-exists)
- [The opinions](#the-opinions)
- [How it compares to the named workflows](#how-it-compares-to-the-named-workflows)

## Why this exists

Many years ago, I grew tired of my talented development team of expert git users making repeated, costly mistakes with the tool. (It's also possible I'm projecting and everything was my fault.)

Mistakes that arose not from incompetence, malice, recklessness, or carelessness - but because git is so powerful that the exact order of operations for tough edge-cases can be both hard to remember, and not inherently obvious.

Many of those edge-cases arose in the first place precisely because our git workflow wasn't enforced at an automation or tooling level.

I surveyed the git tools, wrappers, and standards available at the time and concluded they were also too flexible - none enforced an opinionated enough workflow. So I wrote x9git, the v1 forerunner of Gitsby.

For years it worked and was useful, but it never covered the whole job: bare git was still needed, and remembering *two* commonly-used tools was too burdensome. This v2 release - renamed Gitsby - finally fulfills the original vision, with a small but complete end-to-end set of commands.

## The opinions

The opinions are mostly informed by industry and conventional best-practices, learned over millions upon millions of collective human programmer-hours. There is no reinvention of any wheels - it's an exposed interface that places gentle guardrails and sanity checks around a way of working with Git that has proven to scale more easily and cause less trouble.

- `git pull --ff-only` is safer than and preferable to `git pull --rebase`.

- Merges are always `--no-ff`, so the fact that a branch existed stays visible in history.

- `git push` only to a feature branch you created.

- Don't `push` your own work to `dev`, `main`, or `master`; open a Pull Request instead. Even if you have the rights to, and even for small personal projects.

	While PRs are overkill for small personal projects, they are good hygiene, add little effort, and reinforce good habits at a reflexive level.

	(`br land` and `release` do push the target branch - but that push *is* the merge or the release, not a shortcut around one.)

- Pushed history is permanent. No rebase, no amend, no rewriting, and never `git push -f`.

- Feature branches are short-lived: branch off, do the work, land it, delete it (local and remote).

- The branching model is something a repo opts into by creating a `dev` branch.

- Published material can be corrected without waiting for a release. `br hotfix <name>` branches off the default branch rather than `dev`, lands there, then carries the change back into `dev` so the next release cannot undo it.

- Commit the whole working tree (`git add --all`), every time. The staging area is not a workspace; partial staging is one of those fringe cases left to raw `git`.

- Commit and pull frequently (`update`); push less often (`sync`).

- Uncommitted work should never block anything. The pull inside `update`/`sync` auto-stashes around itself, `br create` off `dev`/`main` carries uncommitted work onto the new branch, and everything else parks current work first - though never auto-committed onto `main`/`dev` - so nothing is ever stranded or lost.

- Every branch tracks a same-named branch on `origin`, from the moment it's created.

- One remote, and it's named `origin`. (Multi-remote setups are another fringe case left to raw `git`.)

- Releases are annotated semver tags (`vX.Y.Z`). With no version given, take the next one after the latest tag: usually a patch bump, except that a candidate like `v2.0.0-rc1` resolves to `v2.0.0`.

- Look before you leap: fetch first, show the current state and the exact commands about to run, and ask before doing anything that mutates.

## How it compares to the named workflows

- [GitFlow](https://nvie.com/posts/a-successful-git-branching-model/): You get most of this with Gitsby when your repo has a `dev` branch.

	- The idea: everyday work is merged into `dev`. `main` holds only versions that have actually been released. When you're ready to release, `dev` is merged into `main` and given a version tag.

	- Gitsby does exactly that. `br create` starts a branch from `dev`, `br land` merges it back into `dev`, and `release` merges `dev` into `main` and tags it.

	- GitFlow was later modified with the idea of a hotfix branch, for fixing something already released without waiting for the next release. `br hotfix` is that branch. It starts from `main`, merges back into `main`, and then copies the fix into `dev` too, so the next release can't undo it.

	- Two parts of GitFlow are left out on purpose: *release* branches, and the `develop` / `feature/` branch naming. Both earn their keep when several versions are maintained at once. Most projects don't do that, so they would be extra steps for nothing.

- [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow): You get this with Gitsby when your repo has no `dev` branch.

	- The idea: one permanent branch. You branch from it, open a pull request, merge back, delete the branch. Anything on that branch is considered ready to release.

	- Gitsby does this with the same commands as above. They simply start from, and merge back into, `main` (or whatever your default branch is named) instead of `dev`.

	- It's the simpler of the two, and the better fit if you don't do numbered releases.

- [GitLab Flow](https://about.gitlab.com/topics/version-control/what-is-gitlab-flow/): Purposely not supported.

	- The idea: extra permanent branches that mirror where the code is running, such as `staging` and `production`. Or one branch per released version, kept alive to receive bug fixes.

	- Gitsby has no notion of a deployment environment, and it records a release as a tag rather than a branch. You can still create and merge such branches with plain `git`; Gitsby just won't manage them for you.

- [Trunk-based development](https://trunkbaseddevelopment.com/): Half supported.

	- The idea: everyone works on one shared branch, the trunk. Branches, where used at all, last a day or two. Unfinished features are hidden behind feature flags instead of being parked on a branch.

	- The short-lived branch half is what Gitsby already encourages. Branches get created, merged, and deleted, and `br prune` removes the ones you forgot about.

	- The commit-straight-to-trunk half is the one thing Gitsby won't do. It won't push your own work to `main` or `dev`, even when you have permission. A team that works that way should use plain `git`.

- **Any workflow that rewrites history**: Purposely not supported.

	- The idea: keep the history tidy and linear. A branch's commits get squashed into one, or replayed on top of the target branch, so it reads as though the branch never existed.

	- Gitsby never rebases, amends, squashes, or force-pushes, and its merges leave the branch visible in the history. If your team requires "squash and merge" or "rebase and merge", this isn't the tool.

One difference matters more than which of these you pick: they're all conventions - a document the team agrees to, and then drifts away from as a deadline gets close.

With Gitsby, *the workflow is the tool*. There's no command for "push to `main` anyway", so there's nothing to remember and nothing to quietly erode over time.
