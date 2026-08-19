// Account resolution and selection. Resolved once per run, applied through the
// environment only (GIT_CONFIG_COUNT and friends) - nothing is written to a file,
// so a killed run leaves no trace.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
	"unicode"
)

// resolveAccount works out who 'dir' says to act as. Most specific first:
// GITSBY_ACCOUNT, then 'gitsby.ghAccount' in git config (an includeIf already
// selects that by repo path), then the config file's folder rules, then whoever
// owns 'url' - which needs no configuration whatsoever. Finding none of them is
// the ordinary single-account case: gh's own account is left alone.
//
// 'dir' is where we are standing for every command but clone, which resolves for
// the folder its new repo lands in instead. An empty 'url' declines the last step.
func (a *app) resolveAccount(dir, url string) error {
	if err := a.cfg.load(a.opt); err != nil {
		return err
	}
	a.acct.name, a.acct.ghWho, a.acct.source, a.acct.explicit = "", "", "", false
	if who := os.Getenv("GITSBY_ACCOUNT"); who != "" {
		// Either the name of a configured account or a bare login - accept both; a
		// script setting this knows one of the two and shouldn't have to know which.
		if v := a.cfg.value(who, "ghAccount"); v != "" {
			a.acct.name, a.acct.ghWho = who, v
		} else {
			a.acct.ghWho = who
		}
		a.acct.source, a.acct.explicit = "GITSBY_ACCOUNT", true
		return nil
	}
	// git config answers for the repo we are standing in, which is the repo in
	// question only when that is the folder being asked about. A clone's destination
	// has no config of its own yet, and an includeIf keyed on gitdir cannot be asked
	// about a repo that does not exist - so asking here would answer for a different
	// repo entirely. The config file's folder rules below have no such limit: gitsby
	// matches those itself, against any path.
	if dir == a.contextDir() {
		if fromGit := runOut("git", "config", "--get", "gitsby.ghAccount"); fromGit != "" {
			a.acct.ghWho, a.acct.source, a.acct.explicit = fromGit, "git config", true
			// Name the config account too when one claims this folder, so its key and
			// commit identity still apply - the git key says who, not that the rest of
			// the account is off.
			a.acct.name = a.cfg.accountForDir(dir)
			if a.cfg.value(a.acct.name, "ghAccount") != a.acct.ghWho {
				a.acct.name = ""
			}
			return nil
		}
	}
	a.acct.name = a.cfg.accountForDir(dir)
	if a.acct.name != "" {
		// A folder rule with no account named still carries a key and a commit
		// identity, worth applying on their own - it just says nothing about gh.
		a.acct.ghWho = a.cfg.value(a.acct.name, "ghAccount")
		a.acct.source = "config '" + a.acct.name + "'"
		return nil
	}
	if fromRemote := remoteOwner(url); fromRemote != "" {
		a.acct.ghWho, a.acct.source = fromRemote, "the remote"
	}
	return nil
}

// remoteOwner names the GitHub account a remote belongs to, or nothing when that
// cannot be said. Only github.com counts, and an alias is resolved first. Nothing
// for other forges, local paths, or anything that doesn't parse: the caller treats
// empty as "no opinion", so a remote we don't understand can never trigger a refusal.
func remoteOwner(url string) string {
	host, path := "", ""
	colon := strings.Index(url, ":")
	switch {
	case strings.HasPrefix(url, "ssh://"):
		path = url[len("ssh://"):]
	case isDrivePath(url):
		return "" // a Windows drive path, not 'host:path'
	case len(url) > 0 && isLetter(url[0]) && strings.Contains(url, "://"):
		path = url[strings.Index(url, "://")+3:]
	case colon > 0:
		host = url[:colon]
		if at := strings.LastIndex(host, "@"); at >= 0 {
			host = host[at+1:]
		}
		path = url[colon+1:]
	default:
		return ""
	}
	if host == "" {
		host = path
		if slash := strings.Index(host, "/"); slash >= 0 {
			host = host[:slash]
			path = path[slash+1:]
		} else {
			path = ""
		}
		if at := strings.LastIndex(host, "@"); at >= 0 {
			host = host[at+1:]
		}
		if c := strings.Index(host, ":"); c >= 0 {
			host = host[:c]
		}
	}
	path = strings.TrimPrefix(path, "/")
	if host == "" || !strings.Contains(path, "/") {
		return ""
	}
	if host != "github.com" {
		host = resolveSSHHost(host)
	}
	if host != "github.com" {
		return ""
	}
	return path[:strings.Index(path, "/")]
}

func isLetter(b byte) bool { return (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') }

func isDrivePath(p string) bool {
	return len(p) >= 3 && isLetter(p[0]) && p[1] == ':' && (p[2] == '/' || p[2] == '\\')
}

// resolveSSHHost finds the real hostname behind an ssh_config alias
// ('github_work' -> 'github.com'), so an aliased remote can still be recognized
// as GitHub. The alias itself when ssh can't say.
func resolveSSHHost(alias string) string {
	if alias == "" || !inPath("ssh") {
		return alias
	}
	// '--': an option-shaped host must not parse as an ssh option.
	for _, line := range strings.Split(runOut("ssh", "-G", "--", alias), "\n") {
		key, value, found := strings.Cut(line, " ")
		if found && key == "hostname" && value != "" {
			return value
		}
	}
	return alias
}

// ghTokenFor reads the stored token for an account gh already holds, or nothing.
// gh's own credential store - no network, no prompt - so it doubles as the
// "does gh have this account" test.
func ghTokenFor(who string) string {
	if who == "" || !inPath("gh") {
		return ""
	}
	return runOut("gh", "auth", "token", "--user", who)
}

// readTokenFile pulls a token out of a file. Unset, missing, unreadable and empty
// are all simply "no token": a machine never set up this way has to fall back to
// gh's own account, never fail because a path is absent.
func readTokenFile(file string) string {
	if file == "" {
		return ""
	}
	file = expandTilde(file)
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
func (a *app) accountToken() (string, tokenSource, string) {
	if a.acct.ghWho == "" {
		return "", tokenNone, ""
	}
	if token := ghTokenFor(a.acct.ghWho); token != "" {
		return token, tokenFromGh, ""
	}
	for _, file := range []string{a.cfg.value(a.acct.name, "tokenFile"), configOwnScope("gitsby.ghTokenFile")} {
		if token := readTokenFile(file); token != "" {
			return token, tokenFromFile, file
		}
	}
	return "", tokenNone, ""
}

// worldReadable names a token file other users on this machine can read, or
// nothing. ssh and gh both refuse or complain about one; loading it without a word
// is how a token ends up shared with everyone who has an account here. Windows
// carries no mode bits worth reading, so it is left out of this.
func worldReadable(file string) string {
	if file == "" || isWindows() {
		return ""
	}
	file = expandTilde(file)
	fi, err := os.Stat(file)
	if err != nil || fi.Mode().Perm()&0o077 == 0 {
		return ""
	}
	return file
}

// configOwnScope reads a git config key from your own configuration only, leaving
// out anything the repo itself set. 'gitsby.ghAccount' is deliberately not read
// this way - naming a login repo-locally is an ordinary thing to do, and the
// account still has to be one you hold. A token FILE is different: it names any
// readable file on the machine, whose contents then go into the environment of
// every child process - and a repo is a thing you clone from a stranger. 'global'
// covers the includeIf fragments 'account apply' writes, which is where this key
// legitimately comes from.
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
		return usagef("Couldn't set %s for this run: %s", key, err)
	}
	return nil
}

// gitConfigEnv adds one config key to the environment git reads, without
// disturbing any the caller already set: GIT_CONFIG_COUNT is a count, so entries
// have to be numbered on from where it stands. A count that isn't one stops the
// run: treating it as zero numbers our entries over the caller's first few and
// leaves the rest applying, which is half a config each and nobody's intent.
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

// selectAccount points this run at the account this folder belongs to - gh, git's
// credentials, its ssh key and its commit identity - for this process and its
// children only. GH_TOKEN outranks gh's stored credentials for this process alone,
// which is exactly the scope wanted; 'gh auth switch' would be global state a
// killed run leaves the machine on.
// skipGhProbe: this run prints no identity block, so skip the probe that only
// feeds one.
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
	token, source, tokenFile := a.accountToken()
	a.acct.looseTokenFile = worldReadable(tokenFile)
	switch {
	case token != "":
		// Asked BEFORE the token lands, or the probe answers as the token we are about
		// to export and the line can only ever say what it already knows. Naming the
		// account this one replaces is display only, and asking is a live API round
		// trip. '?' means gh held no account at all.
		if !skipGhProbe {
			if active := a.ghLogin(); active != a.acct.ghWho && active != "?" {
				a.acct.switchedFrom = active
			}
		}
		// Export whenever a token was found, not only when it replaces a different
		// active account: the helper below reads GH_TOKEN when git runs it, and the
		// reset that precedes it has already evicted any credential manager.
		if err := setEnv("GH_TOKEN", token); err != nil {
			return err
		}
		switch source {
		case tokenFromGh:
			// gh's own store was asked for this account by name, so there is nothing
			// left to ask.
			a.gh.login.set(a.acct.ghWho)
		default:
			// A file says nothing about whose token is in it - the name came from a
			// config key beside it, and a stale file reports that name and pushes as
			// somebody else. Drop the pre-token answer so the probe below runs with the
			// token, and ask GitHub who it really belongs to. Only when a block will
			// print it: this is a live round trip.
			a.gh.login.forget()
			if !skipGhProbe {
				a.acct.tokenWho = a.ghLogin()
			}
		}
		// The same token is what lets git itself push as this account over https,
		// with no ssh key anywhere. An empty value first resets the helper list, so
		// a credential manager configured for another account cannot answer ahead of
		// us. The token is read from the environment when the helper runs, never
		// stored in the config value itself.
		if err := gitConfigEnv("credential.https://github.com.helper", ""); err != nil {
			return err
		}
		if err := gitConfigEnv("credential.https://github.com.helper",
			`!f(){ test "$1" = get && { echo username=x; echo "password=${GH_TOKEN}"; }; }; f`); err != nil {
			return err
		}
		a.acct.usedHTTPSAuth = true
	case a.acct.ghWho != "" && (a.acct.explicit || a.acct.name != ""):
		// An account we resolved but cannot act as. gh goes on using whichever
		// account it is logged in as, and the identity block must say so rather than
		// name what was RESOLVED as if it were APPLIED. Only for an account that was
		// configured or asked for: one guessed from the remote owner is not a claim
		// that we can act as it.
		a.acct.noToken = true
	}
	// The ssh key stays supported as the way that needs no token at all. Only when
	// nothing already says which key to use: an explicit GIT_SSH_COMMAND, or one
	// set on the repo, was chosen more deliberately than a folder rule was.
	if sshKey := a.cfg.value(a.acct.name, "sshKey"); sshKey != "" &&
		os.Getenv("GIT_SSH_COMMAND") == "" && a.coreSSHCommand() == "" {
		// IdentitiesOnly, or ssh offers every key the agent holds and the server
		// picks the first that authenticates - on a two-account machine a coin toss.
		if err := setEnv("GIT_SSH_COMMAND", "ssh -i "+sshKey+" -o IdentitiesOnly=yes"); err != nil {
			return err
		}
		a.acct.usedSSHKey = sshKey
	}
	// Commit identity, unless the repo sets its own - a local value was typed for
	// this repo specifically, and a folder rule should not quietly outrank it.
	acctEmail := a.cfg.value(a.acct.name, "email")
	acctUser := a.cfg.value(a.acct.name, "name")
	if (acctEmail != "" || acctUser != "") && runOut("git", "config", "--local", "--get", "user.email") == "" {
		if acctUser != "" {
			if err := gitConfigEnv("user.name", acctUser); err != nil {
				return err
			}
		}
		if acctEmail != "" {
			if err := gitConfigEnv("user.email", acctEmail); err != nil {
				return err
			}
		}
		a.acct.usedIdentity = true
	}
	return nil
}

// ghLogin names the account gh's token belongs to. gh talks to the API over https
// and never consults ssh config, so this is who every gh-backed command acts as -
// regardless of which key git pushes with. '?' when gh can't say.
func (a *app) ghLogin() string {
	return a.gh.login.get(func() string {
		if !inPath("gh") {
			return "?"
		}
		cmd := exec.Command("gh", "api", "user", "--jq", ".login")
		cmd.Env = append(os.Environ(), "GH_PROMPT_DISABLED=1")
		out, err := cmd.Output()
		if err != nil {
			return "?"
		}
		if login := strings.TrimRight(string(out), "\r\n"); login != "" {
			return login
		}
		return "?"
	})
}
