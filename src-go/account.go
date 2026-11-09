// Account resolution and selection. Resolved once per run, applied through the
// environment only (GIT_CONFIG_COUNT and friends) - nothing is written to a file,
// so a killed run leaves no trace.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"context"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"unicode"
)

// resolveAccount works out who 'dir' says to act as: GITSBY_ACCOUNT, then
// 'gitsby.ghAccount' in git config, the folder rules, then the owner of 'url'. None
// leaves gh's own account. An empty 'url' skips the last.
func (a *app) resolveAccount(dir, url string) error {
	if err := a.cfg.load(a.opt); err != nil {
		return err
	}
	a.reportMigration()
	a.acct.name, a.acct.ghWho, a.acct.source, a.acct.explicit, a.acct.fromFile = "", "", "", false, false
	a.acct.pickedBy = ""
	if who := os.Getenv("GITSBY_ACCOUNT"); who != "" {
		// A configured account's name or a bare login. Which one turns on whether the
		// file defines the name, not whether it names a GitHub login, or an ssh-only
		// account reads as a login.
		if a.cfg.knowsAccount(who) {
			a.acct.name, a.acct.ghWho = strings.ToLower(who), a.cfg.value(who, "ghAccount")
			a.acct.pickedBy = "it names an account block called '" + a.acct.name + "'"
		} else {
			a.acct.ghWho = who
			a.acct.pickedBy = "it names the login directly - no account block matched it"
		}
		a.acct.source, a.acct.explicit = "the GITSBY_ACCOUNT environment variable", true
		return nil
	}
	// git config answers for the repo we stand in, so not for a clone's destination,
	// which has no config yet. The folder rules below are matched against any path.
	if dir == a.contextDir() {
		scope, fromGit, _ := strings.Cut(runOut("git", "config", "--show-scope", "--get", "gitsby.ghAccount"), "\t")
		if fromGit != "" {
			// Led by "the" so the sentence form doesn't capitalize the key.
			a.acct.ghWho, a.acct.source, a.acct.explicit = fromGit, "the gitsby.ghAccount key in "+gitScopeText(scope), true
			// Keep the config account when one claims this folder, so its key and
			// identity still apply. Dropped only when it names a different login.
			a.acct.name = a.cfg.accountForDir(dir)
			if acctWho := a.cfg.value(a.acct.name, "ghAccount"); acctWho != "" && acctWho != a.acct.ghWho {
				a.acct.name = ""
			}
			return nil
		}
	}
	a.acct.name = a.cfg.accountForDir(dir)
	if a.acct.name != "" {
		// A folder rule with no account named still has a key and a commit
		// identity, worth applying on their own - it says nothing about gh.
		a.acct.ghWho = a.cfg.value(a.acct.name, "ghAccount")
		// Named as what it IS, not just what it is called: "account 'work'" read
		// back as a bare repeat of the name already on the line above, so the one
		// question a first-time reader asks - what is that string, and where did
		// gitsby get it - had no answer anywhere on screen.
		a.acct.source, a.acct.fromFile = "an account block named '"+a.acct.name+"'", true
		a.acct.pickedBy = "its folder rule covers this directory"
		return nil
	}
	if fromRemote := remoteOwner(url); fromRemote != "" {
		a.acct.ghWho, a.acct.source = fromRemote, "the owner of this repo's remote"
	}
	return nil
}

// gitScopeText names the config a 'git config --show-scope' scope stands for. An
// includeIf fragment reports the scope of the file that included it, which is where
// somebody would go looking for the rule that pulled it in.
func gitScopeText(scope string) string {
	switch scope {
	case "local":
		return "this repo's git config"
	case "worktree":
		return "this worktree's git config"
	case "global":
		return "your global git config"
	case "system":
		return "the system git config"
	case "command":
		return "git config set on the command line or in the environment"
	}
	return "git config"
}

// remoteOwner names the GitHub account a remote belongs to, or nothing. Only on a host
// gh serves. Empty is "no opinion", so a remote we can't parse never refuses a run.
func remoteOwner(url string) string {
	ref := parseRemote(url)
	if !isGitHubHost(ref.host) || ref.name == "" {
		return ""
	}
	return ref.owner
}

func isLetter(b byte) bool { return (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') }

func isDrivePath(p string) bool {
	return len(p) >= 3 && isLetter(p[0]) && p[1] == ':' && (p[2] == '/' || p[2] == '\\')
}

// resolveSSHHost finds the real hostname behind an ssh_config alias
// ('github_work' -> 'github.com'), so an aliased remote can still be recognized
// as GitHub. The alias itself when ssh can't say. It asks about the connect
// target, as the SSH line does, so both take the one 'ssh -G' read.
func resolveSSHHost(alias, target string) string {
	if alias == "" || !inPath("ssh") {
		return alias
	}
	if target == "" {
		target = alias
	}
	for _, line := range splitLines(sshConfigText(target)) {
		key, value, found := strings.Cut(line, " ")
		if found && key == "hostname" && value != "" {
			return value
		}
	}
	return alias
}

// ghTokenFor reads the stored token for an account gh already has, or nothing.
// Asked once per login: gh answers about one account at a time, so the listing
// spent a process on every account it printed, twice over for 'account set'.
func (a *app) ghTokenFor(who string) string {
	if token, asked := a.remote.tokens[who]; asked {
		return token
	}
	token := probeGhToken(who)
	if a.remote.tokens == nil {
		a.remote.tokens = map[string]string{}
	}
	a.remote.tokens[who] = token
	return token
}

// askGhTokens asks gh for every login at once, ahead of a listing that prints
// them in turn. A handful at a time: one gh each, and a long accounts file should
// not start them all together. One login is left to ghTokenFor - nothing to
// overlap it with.
func (a *app) askGhTokens(logins []string) {
	var asking []string
	for _, who := range logins {
		if _, asked := a.remote.tokens[who]; !asked && who != "" && !slices.Contains(asking, who) {
			asking = append(asking, who)
		}
	}
	if len(asking) < 2 {
		return
	}
	answers := make([]string, len(asking))
	slots := make(chan struct{}, 8)
	var wg sync.WaitGroup
	for i, who := range asking {
		wg.Go(func() {
			slots <- struct{}{}
			defer func() { <-slots }()
			answers[i] = probeGhToken(who)
		})
	}
	wg.Wait()
	if a.remote.tokens == nil {
		a.remote.tokens = map[string]string{}
	}
	for i, who := range asking {
		a.remote.tokens[who] = answers[i]
	}
}

// probeGhToken asks gh's own credential store - no network, no prompt - so it
// doubles as the "does gh have this account" test.
func probeGhToken(who string) string {
	if who == "" || !inPath("gh") {
		return ""
	}
	return runOut("gh", "auth", "token", "--user", who)
}

// accountHost is the git host the resolved account belongs to. Unstated means
// github.com: every account that existed before this key did was a GitHub one, and
// a config that never mentions a host has to keep behaving exactly as it always did.
func (a *app) accountHost() string {
	return a.cfg.hostOf(a.acct.name)
}

// accountServesHost: whether the account we resolved has credentials for this
// host. A token is a credential for the git host that ISSUED it and for nowhere else,
// so handing a GitHub token to a Gitea push authenticates nothing - and does it
// while looking thoroughly configured, which is the part that costs an afternoon.
func (a *app) accountServesHost(host string) bool {
	return host != "" && strings.EqualFold(host, a.accountHost())
}

// accountWho is the login this run's account has on a host, or nothing. 'user' wins
// where given; 'ghAccount' answers for GitHub alone. Nothing is "no claim", never a
// match.
func (a *app) accountWho(host string) string {
	if user := a.cfg.value(a.acct.name, "user"); user != "" {
		return user
	}
	if isGitHubHost(host) {
		return a.acct.ghWho
	}
	return ""
}

// accountLogin is the username the credential helper offers. GitHub ignores it
// entirely when the password is a token, which is why a literal 'x' served here for
// as long as this was a GitHub-only program; Gitea checks it, so an account on one
// has to be able to say who it is.
func (a *app) accountLogin() string {
	if who := a.accountWho(a.acct.credHost); who != "" {
		return who
	}
	return "x"
}

// serviceHost drops a leading 'ssh.', the name some hosts give their ssh
// endpoint (ssh.gitlab.gnome.org, ssh.github.com). Tokens and the credential
// helper belong to the web host.
func serviceHost(host string) string {
	if rest, ok := strings.CutPrefix(host, "ssh."); ok && strings.Contains(rest, ".") {
		return rest
	}
	return host
}

// authHost is the git host this run authenticates to. A clone takes it from its URL,
// since the folder we stand in isn't what the command is about.
func (a *app) authHost() string {
	if a.cmd.name == "repo-clone" {
		if host := parseRemote(a.cmd.arg).host; host != "" {
			return serviceHost(host)
		}
		// 'owner/name' shorthand has no host in it, and only ever meant github.com.
		if ownerNameRE.MatchString(a.cmd.arg) && !pathExists(a.cmd.arg) {
			return "github.com"
		}
		return a.accountHost()
	}
	if host := a.originHost(); host != "" {
		return serviceHost(host)
	}
	// No remote yet - 'repo create' and 'repo connect' are about to make one, and
	// the account's own host is the only evidence available about where.
	return a.accountHost()
}

// tokenEnvVar is the variable the credential helper reads the token out of. GH_TOKEN
// for GitHub, because gh itself reads that one and the two have to agree; anything
// else gets its own name, so a Gitea token is never exported into every child
// process under a variable gh will pick up and act on.
func tokenEnvVar(host string) string {
	if isGitHubHost(host) {
		return "GH_TOKEN"
	}
	return "GITSBY_HOST_TOKEN"
}

// userEnvVar is where the credential helper reads the username from. Ours alone -
// nothing else reads it, and no caller sets it - so unlike the token variable it
// needs no per-host spelling.
const userEnvVar = "GITSBY_HOST_USER"

// readTokenFile pulls a token out of a file. Unset, missing, unreadable, empty or
// relative are all "no token", so a machine not set up this way falls back to gh.
func readTokenFile(file string) string {
	if file == "" || folderRuleProblem(file) != "" {
		return ""
	}
	file = expandHome(file)
	data, err := os.ReadFile(file)
	if err != nil {
		return ""
	}
	return strings.Map(func(r rune) rune {
		if unicode.IsSpace(r) {
			return -1
		}
		return r
	}, string(data))
}

// tokenSource is where a token came from, which decides whether we already know
// whose it is. gh's own store answered for an account by name; a file did not.
type tokenSource int

const (
	tokenNone tokenSource = iota
	tokenFromGh
	tokenFromFile
)

// accountToken finds a token for the account we resolved, and says where it came
// from. gh's own store first - it is the one that stays current, so a rotated
// login is never shadowed by a stale copy on disk - then the file the config
// names, then the older git-config key. Nothing found is not an error anywhere.
func (a *app) accountToken(host string) (string, tokenSource, string) {
	// A named GitHub login is one way to have an account, not the definition of
	// having one: a Gitea account names a host and a token file and no ghAccount at
	// all, and testing the GitHub field to decide the record exists gave it nothing.
	if a.acct.ghWho == "" && a.acct.name == "" {
		return "", tokenNone, ""
	}
	// gh's own store, only for a host gh serves. Asking it about a Gitea account is
	// asking after a login that was never going to be there.
	if isGitHubHost(host) {
		if token := a.ghTokenFor(a.acct.ghWho); token != "" {
			return token, tokenFromGh, ""
		}
	}
	if file := a.cfg.value(a.acct.name, "tokenFile"); file != "" {
		if token := readTokenFile(file); token != "" {
			return token, tokenFromFile, file
		}
	}
	// The older git config key is GitHub's, so it answers only for a run that named a
	// GitHub login, and only once the account's own file gave nothing.
	if a.acct.ghWho != "" {
		file := a.git.ownTokenFile.get(func() string { return configOwnScope("gitsby.ghTokenFile") })
		if token := readTokenFile(file); token != "" {
			return token, tokenFromFile, file
		}
	}
	return "", tokenNone, ""
}

// worldReadable names a token file other users on this machine can read, or
// nothing. ssh and gh both refuse or complain about one; loading it without a word
// is how a token ends up shared with everyone who has an account here. Windows
// has no mode bits worth reading, so it is left out of this.
func worldReadable(file string) string {
	if file == "" || isWindows() {
		return ""
	}
	file = expandHome(file)
	fi, err := os.Stat(file)
	if err != nil || fi.Mode().Perm()&0o077 == 0 {
		return ""
	}
	return file
}

// configOwnScope reads a git config key from your own config only, never the repo's. For
// the token file: it names any file, whose contents go to every child, and a repo can
// come from a stranger.
func configOwnScope(key string) string {
	value := ""
	for _, line := range runLines("git", "config", "--show-scope", "--get-all", key) {
		scope, rest, found := strings.Cut(line, "\t")
		if !found {
			continue
		}
		if scope == "global" || scope == "system" {
			value = rest // last one wins, the same way git settles a scalar
		}
	}
	return value
}

// setEnv fails only on a name no process can hold, so a failure here means
// something is wrong in this program rather than out there. It still has to stop
// the run: every variable set through here decides which account the commands
// after it act as, and half an account applied is how you push as the wrong one.
func setEnv(key, value string) error {
	if err := os.Setenv(key, value); err != nil {
		return usageWrapf(err, "Couldn't set %s for this run", key)
	}
	return nil
}

// gitConfigEnv adds one config key to the environment git reads, numbered on from the
// caller's GIT_CONFIG_COUNT. A count that isn't a number stops the run.
func gitConfigEnv(key, value string) error {
	n := 0
	if raw := os.Getenv("GIT_CONFIG_COUNT"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 0 {
			return usagef("GIT_CONFIG_COUNT is '%s', which isn't a count - unset it, or set it to the number of GIT_CONFIG_KEY_n entries you meant.", raw)
		}
		n = parsed
	}
	if err := setEnv("GIT_CONFIG_KEY_"+strconv.Itoa(n), key); err != nil {
		return err
	}
	if err := setEnv("GIT_CONFIG_VALUE_"+strconv.Itoa(n), value); err != nil {
		return err
	}
	return setEnv("GIT_CONFIG_COUNT", strconv.Itoa(n+1))
}

// selectAccount points this run and its children at this folder's account. GH_TOKEN
// scopes gh to this process, where 'gh auth switch' is global. skipGhProbe: no identity
// block prints.
func (a *app) selectAccount(skipGhProbe bool) error {
	if a.opt.anyIdentity {
		// Nothing is selected at all - not the token, not the key, not the commit
		// identity. Recorded so the block below says that, rather than naming the
		// account we resolved as though it had been applied.
		a.acct.bypassed = true
		return nil
	}
	// Applying twice would number a second set of GIT_CONFIG_* entries on top of
	// the first.
	if a.acct.applied {
		return nil
	}
	a.acct.applied = true
	// Where this run is about to authenticate, which is what decides whether the
	// account's token is any use at all and which host the helper gets written for.
	credHost := a.authHost()
	a.acct.credHost = credHost
	token, source, tokenFile := "", tokenNone, ""
	if a.accountServesHost(credHost) {
		token, source, tokenFile = a.accountToken(credHost)
	}
	a.acct.looseTokenFile = worldReadable(tokenFile)
	onGitHubHost := isGitHubHost(credHost)
	switch {
	case token != "":
		// Asked before the token is exported, or the API answers with that token's
		// login. Display only, so skipped when no block prints. '?' means gh held no
		// account.
		if onGitHubHost && !skipGhProbe {
			if active := a.ghActiveLogin(credHost); active != a.acct.ghWho && active != "?" {
				a.acct.switchedFrom = active
			}
		}
		// Export whenever a token was found, not only when it replaces a different
		// active account: the helper below reads GH_TOKEN when git runs it, and the
		// reset that precedes it has already evicted any credential manager.
		envVar := tokenEnvVar(credHost)
		a.acct.tokenEnv = envVar
		if err := setEnv(envVar, token); err != nil {
			return err
		}
		switch {
		case source == tokenFromGh:
			// gh's own store was asked for this account by name, so there is nothing
			// left to ask.
			a.remote.login.set(a.acct.ghWho)
		case onGitHubHost:
			// A token file says nothing about whose token is in it, so ask GitHub with
			// it. Only when a block prints it, and started now so it runs beside the
			// fetch.
			a.remote.login.forget()
			if !skipGhProbe {
				a.askGhLoginAhead()
				a.acct.checkTokenWho = true
			}
		}
		// The token also lets git push over https. The empty value clears other helpers
		// first. Token and login go through the environment, since git hands this to a
		// shell.
		if err := setEnv(userEnvVar, a.accountLogin()); err != nil {
			return err
		}
		helperKey := "credential.https://" + credHost + ".helper"
		if err := gitConfigEnv(helperKey, ""); err != nil {
			return err
		}
		if err := gitConfigEnv(helperKey,
			`!f(){ test "$1" = get && { echo "username=${`+userEnvVar+`}"; echo "password=${`+envVar+`}"; }; }; f`); err != nil {
			return err
		}
		a.acct.usedHTTPSAuth = true
	case (a.acct.explicit || a.acct.name != "") && !a.accountServesHost(credHost):
		// The account we resolved banks somewhere else, so none of its credentials
		// apply here. Said plainly rather than reported as a missing token: the fix is
		// a host key or a different account, not hunting for a token that would be the
		// wrong one anyway.
		a.acct.otherHost = true
	case a.accountWho(a.accountHost()) != "" && (a.acct.explicit || a.acct.name != ""):
		// An account we resolved but can't act as, so the identity block mustn't call it
		// applied. Only for a configured or asked-for one, and asked of its own host,
		// not 'ghAccount'.
		a.acct.noToken = true
	}
	// The ssh key stays supported as the way that needs no token at all. Only when
	// nothing already says which key to use: an explicit GIT_SSH_COMMAND, or one
	// set on the repo, was chosen more deliberately than a folder rule was.
	if sshKey := a.cfg.value(a.acct.name, "sshKey"); sshKey != "" &&
		os.Getenv("GIT_SSH_COMMAND") == "" && a.coreSSHCommand() == "" {
		if err := setEnv("GIT_SSH_COMMAND", sshKeyCommand(sshKey)); err != nil {
			return err
		}
		a.acct.usedSSHKey = sshKey
	}
	// Commit identity, unless the repo sets its own. Asked per key, since these reach
	// git as '-c' does, which outranks the repo's own.
	acctEmail := a.cfg.value(a.acct.name, "email")
	acctUser := a.cfg.value(a.acct.name, "name")
	if acctEmail != "" || acctUser != "" {
		pinned := localIdentityKeys()
		if acctUser != "" && !pinned["user.name"] {
			if err := gitConfigEnv("user.name", acctUser); err != nil {
				return err
			}
			a.acct.usedIdentity = true
		}
		if acctEmail != "" && !pinned["user.email"] {
			if err := gitConfigEnv("user.email", acctEmail); err != nil {
				return err
			}
			a.acct.usedIdentity = true
		}
	}
	return nil
}

// localIdentityKeys names which of the two identity keys THIS repo sets for
// itself, ignoring the global and system files an account rule is entitled to
// fill in. Both in one call: asking twice would cost a second git for an answer
// that arrives in the same listing.
func localIdentityKeys() map[string]bool {
	pinned := map[string]bool{}
	for _, line := range runLines("git", "config", "--local", "--name-only", "--get-regexp", `^user\.(name|email)$`) {
		pinned[strings.ToLower(strings.TrimSpace(line))] = true
	}
	return pinned
}

// ghLogin names the account gh's token belongs to. gh talks to the API over https
// and never consults ssh config, so this is who every gh-backed command acts as -
// regardless of which key git pushes with. '?' when gh can't say.
func (a *app) ghLogin() string {
	return a.remote.login.get(func() string {
		if pending := a.remote.loginAhead; pending != nil {
			a.remote.loginAhead = nil
			return pending.wait()
		}
		return probeGhLogin(context.Background(), os.Environ())
	})
}

// askGhLoginAhead starts the ghLogin probe without waiting for it. The
// environment is taken now, on this goroutine: the token just exported is the one
// being asked about.
func (a *app) askGhLoginAhead() {
	if a.remote.login.known || a.remote.loginAhead != nil {
		return
	}
	ctx, env := a.probeContext(), os.Environ()
	a.remote.loginAhead = startAhead(func() string { return probeGhLogin(ctx, env) })
}

func probeGhLogin(ctx context.Context, env []string) string {
	if !inPath("gh") {
		return "?"
	}
	cmd := toolCmdContext(ctx, "gh", "api", "user", "--jq", ".login")
	cmd.Env = append(env, "GH_PROMPT_DISABLED=1")
	out, err := cmd.Output()
	if err != nil {
		return "?"
	}
	if login := strings.TrimRight(string(out), "\r\n"); login != "" {
		return login
	}
	return "?"
}

// ghActiveLogin names the account gh is logged in to a host as, from gh's own
// config: no network. A token in the environment outranks that login, and only
// the API can say whose it is.
func (a *app) ghActiveLogin(host string) string {
	for _, name := range []string{"GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"} {
		if os.Getenv(name) != "" {
			return a.ghLogin()
		}
	}
	if !inPath("gh") {
		return "?"
	}
	if who := runOut("gh", "config", "get", "-h", host, "user"); who != "" {
		return who
	}
	return "?"
}

// tokenFileWho is who a file-sourced token authenticates as, or nothing when this
// run did not ask.
func (a *app) tokenFileWho() string {
	if !a.acct.checkTokenWho {
		return ""
	}
	return a.ghLogin()
}
