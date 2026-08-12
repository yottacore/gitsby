<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD055 -- Table pipe style -->

# Multiple GitHub accounts

Most people with two GitHub accounts also have a folder for each: one tree for work, one for everything else. Gitsby takes that literally. Say which account owns which folder, once, and every command run anywhere under that folder acts as that account - `git` and `gh` alike.

Nothing here is required. With no configuration Gitsby uses whichever account `gh` is logged in as, exactly as it always did. A single-account machine never notices the feature exists.

- [Setting it up](#setting-it-up)
	- [One config file, several machines](#one-config-file-several-machines)
- [No SSH keys needed](#no-ssh-keys-needed)
- [Teaching plain git the same rules](#teaching-plain-git-the-same-rules)
- [Scripts](#scripts)
- [Which account are you acting as?](#which-account-are-you-acting-as)

## Setting it up

One file, flat `key = value` lines, `#` for comments:

~~~ini
# ~/.config/gitsby/config.shcl

protocol = https                            # how new remotes are set up; https needs no ssh key

account.work.path       = ~/dev/work        # the folder tree this account owns
account.work.ghAccount  = my-work-login
account.work.name       = Ada Lovelace
account.work.email      = ada@work.example

account.personal.path       = ~/dev/personal
account.personal.ghAccount  = my-personal-login
account.personal.email      = ada@home.example
~~~

Gitsby reads the first of these that exists:

1. `$XDG_CONFIG_HOME/gitsby/config.shcl`
2. `~/.config/gitsby/config.shcl` - the usual place on Linux and macOS, and it works on Windows too
3. `%APPDATA%\gitsby\config.shcl` - Windows

`--config FILE` (`-Config FILE`) overrides all of them, and so does the `GITSBY_CONFIG` environment variable.

Per-account keys, all optional except a `path` to match on:

| Key             | What it does
| :--             | :--
| `path`          | A folder tree this account owns. Repeat the key for more than one. The longest match wins, so a tree nested inside another account's tree belongs to the inner one.
| `pathContains`  | A run of folder names that appears anywhere in the path, so the same rule works on machines whose roots differ. Whole names only - `alice` never matches `alice-old`. Repeatable.
| `ghAccount`  | The GitHub login to act as.
| `tokenFile`  | A file holding that account's token, for a machine where `gh` was never logged in as it.
| `sshKey`     | A key to use instead of a token. See below.
| `name`       | Commit author name.
| `email`      | Commit author email.
| `protocol`   | `https` or `ssh`, for this account only.

Run `gitsby account` to see what it made of all that, and which account the folder you're standing in resolves to. It is the command to reach for when something went out as the wrong person. A `path` rule pointing at a directory that isn't there is marked as one that can never match, which is usually a typo.

### One config file, several machines

`path` names a tree on the machine you're on, so a config using it can't be synced as-is: the roots differ. `pathContains` names folder names instead, and matches wherever they appear:

~~~ini
account.work.pathContains = github.com/my-work-login
account.work.ghAccount    = my-work-login

account.personal.pathContains = github.com/my-personal-login
account.personal.ghAccount    = my-personal-login
~~~

That resolves under `C:/src/github.com/my-work-login/...` and `~/dev/github.com/my-work-login/...` alike, so the file syncs unchanged.

- Whole folder names only. `alice` never matches a directory called `alice-old`.
- More folder names is the more specific rule, so `github.com/alice` beats a bare `alice`.
- An absolute `path` beats a `pathContains` when both match - naming this machine's own tree is the more specific claim. Mix them freely.
- `gitsby account apply` hands these to git as `includeIf.gitdir:**/github.com/alice/**`, which git globs natively - so plain `git` follows the same rule on every machine too.

## No SSH keys needed

The usual way to hold two GitHub accounts on one machine is a pair of SSH keys and a `~/.ssh/config` full of host aliases, which then have to be baked into every remote URL. Gitsby does not need any of that.

Over HTTPS, `git` authenticates with the account's own token - the one `gh` already stores, or the one `tokenFile` names. Gitsby supplies it for the length of a single command, through the environment, and nothing is written anywhere. So a second account costs one `gh auth login` and three lines of config.

- New remotes follow `protocol`, so `repo connect owner/name` sets up an HTTPS remote by default.
- An existing repo still on SSH is converted with `gitsby repo url https`. Only the remote URL changes - same repo, same history. Gitsby points this out on the identity line when it applies, and setting `protocol = ssh` says you meant it and stops the suggestion.

SSH keys keep working, and stay the answer when you can't use a token. Give an account an `sshKey` and Gitsby uses it (with `IdentitiesOnly`, so the agent can't offer the wrong one first). Anything you have already set yourself - `GIT_SSH_COMMAND`, or `core.sshCommand` on the repo - was chosen more deliberately than a folder rule, and wins.

## Teaching plain git the same rules

`gitsby account apply` writes the same folder rules into your global git config, as ordinary `includeIf` blocks pointing at one small file per account. After that a bare `git commit` or `git push` in one of those folders uses the right identity and the right key, with Gitsby nowhere in the picture.

It is safe to re-run: it replaces only the entries it wrote before, leaves any you wrote by hand alone, and drops rules for accounts you have since removed.

## Scripts

`gitsby raw git ...` and `gitsby raw gh ...` run the real tool as the folder's account and then get out of the way. Everything after `git` or `gh` is passed through exactly as typed, stdout is the tool's alone, and the exit code is the tool's too - so an existing script becomes account-correct by prefixing its commands rather than being rewritten.

~~~bash
gitsby raw git push origin HEAD
gitsby raw gh pr list --json number

## One line on stderr says who you are acting as. -q silences it.
gitsby -q raw git rev-parse HEAD
~~~

`GITSBY_ACCOUNT` overrides the folder for one run, or for a whole script's environment. It takes either an account name from the config file or a bare GitHub login.

One exception to "exactly as typed", and only on the PowerShell build: a bare `--` never reaches the script. PowerShell reads it as an empty parameter name and fails before `gitsby.ps1` runs at all, so there is nothing gitsby can intercept. Where you need git's pathspec separator, escape it as `` `-- `` and gitsby hands git the `--` you meant:

~~~pwsh
gitsby raw git log --oneline `-- src/app.ps1
~~~

The Bash build takes a plain `--` and needs no escape.

## Which account are you acting as?

`gh` talks to GitHub's API with its own token and never reads your SSH config, so the `pr` commands and `repo create` act as **gh's account** - not the account whose SSH key `git push` uses. With per-account host aliases in `~/.ssh/config` those can easily be different people, and a pull request opened as the wrong one is public and awkward to undo.

So the pre-flight names both, and the commands that *write* through gh (`pr create`, `pr ok`, `repo create`, `repo connect owner/name`) compare them. The last two have no remote yet, but the one they are about to set is knowable - gh never uses a host alias, so it is always `git@github.com:owner/name.git` - which means the identity that repo will live with afterward is checked before anything is created.

- Interactively, a confirmed difference prints a warning immediately above the confirmation prompt.
- Unattended (`-q`/`-y`), a confirmed difference is an error and nothing runs.
- `--any-identity`/`-AnyIdentity` says the difference is intended: no error, no warning, and the mismatch still shows on the identity line.

If either side can't be determined - no SSH agent, an HTTPS remote, a deploy key, gh logged out - that is reported as unknown and never blocks anything. Only a difference *both* sides confirm counts.

One consequence worth knowing if you use per-account host aliases: `repo create` and `repo connect owner/name` set `origin` to the canonical `git@github.com:...` URL, because that is what gh produces and gh does not read your SSH config. Gitsby does not try to guess which of your aliases belongs to that account - that would be a guess about your setup, and a wrong one is worse than none. If you want the alias, either point it there afterward with `git remote set-url origin git@your-alias:owner/name.git`, or skip gh entirely and give `repo connect` the full URL: `gitsby repo connect git@your-alias:owner/name.git`.
