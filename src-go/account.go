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

var (
	acctName       = "" // configured account claiming this folder, if any
	acctGhWho      = "" // the GitHub account this run acts as
	acctSource     = "" // how we decided that, for the identity line
	acctExplicit   = false
	accountApplied = false
	ghLoginCache   = ""
)

// What the selection actually applied, read back by the identity block.
var (
	accountNoToken       = false
	accountUsedHttpsAuth = false
	accountUsedSSHKey    = ""
	accountUsedIdentity  = false
	ghSwitchedFrom       = ""
)

// resolveAccount works out who this folder says to act as. Most specific first:
// GITSBY_ACCOUNT, then 'gitsby.ghAccount' in git config (an includeIf already
// selects that by repo path), then the config file's folder rules, then whoever
// owns origin - which needs no configuration whatsoever. Finding none of them is
// the ordinary single-account case: gh's own account is left alone.
func resolveAccount(url string) {
	loadConfig()
	acctName, acctGhWho, acctSource, acctExplicit = "", "", "", false
	if who := os.Getenv("GITSBY_ACCOUNT"); who != "" {
		// Either the name of a configured account or a bare login - accept both; a
		// script setting this knows one of the two and shouldn't have to know which.
		if v := accountValue(who, "ghAccount"); v != "" {
			acctName, acctGhWho = who, v
		} else {
			acctGhWho = who
		}
		acctSource, acctExplicit = "GITSBY_ACCOUNT", true
		return
	}
	if fromGit := runOut("git", "config", "--get", "gitsby.ghAccount"); fromGit != "" {
		acctGhWho, acctSource, acctExplicit = fromGit, "git config", true
		// Name the config account too when one claims this folder, so its key and
		// commit identity still apply - the git key says who, not that the rest of
		// the account is off.
		acctName = accountForDir(contextDir())
		if accountValue(acctName, "ghAccount") != acctGhWho {
			acctName = ""
		}
		return
	}
	acctName = accountForDir(contextDir())
	if acctName != "" {
		// A folder rule with no account named still carries a key and a commit
		// identity, worth applying on their own - it just says nothing about gh.
		acctGhWho = accountValue(acctName, "ghAccount")
		acctSource = "config '" + acctName + "'"
		return
	}
	if fromRemote := remoteOwner(url); fromRemote != "" {
		acctGhWho, acctSource = fromRemote, "the remote"
	}
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
// ('github_work' -> 'github.com'), so an aliased remote can still be recognised
// as GitHub. The alias itself when ssh can't say.
func resolveSSHHost(alias string) string {
	if alias == "" {
		return alias
	}
	if _, err := exec.LookPath("ssh"); err != nil {
		return alias
	}
	// '--': an option-shaped host must not parse as an ssh option.
	out := runOut("ssh", "-G", "--", alias)
	for _, line := range strings.Split(out, "\n") {
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
	if who == "" {
		return ""
	}
	if _, err := exec.LookPath("gh"); err != nil {
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
	if file == "~" || strings.HasPrefix(file, "~/") {
		file = os.Getenv("HOME") + file[1:]
	}
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

// accountToken finds a token for the account we resolved. gh's own store first -
// it is the one that stays current, so a rotated login is never shadowed by a
// stale copy on disk - then the file the config names, then the older git-config
// key. Nothing found is not an error anywhere.
func accountToken() string {
	if acctGhWho == "" {
		return ""
	}
	if token := ghTokenFor(acctGhWho); token != "" {
		return token
	}
	if token := readTokenFile(accountValue(acctName, "tokenFile")); token != "" {
		return token
	}
	return readTokenFile(runOut("git", "config", "--get", "gitsby.ghTokenFile"))
}

// gitConfigEnv adds one config key to the environment git reads, without
// disturbing any the caller already set: GIT_CONFIG_COUNT is a count, so entries
// have to be numbered on from where it stands.
func gitConfigEnv(key, value string) {
	n, _ := strconv.Atoi(os.Getenv("GIT_CONFIG_COUNT"))
	os.Setenv("GIT_CONFIG_KEY_"+strconv.Itoa(n), key)
	os.Setenv("GIT_CONFIG_VALUE_"+strconv.Itoa(n), value)
	os.Setenv("GIT_CONFIG_COUNT", strconv.Itoa(n+1))
}

// selectAccount points this run at the account this folder belongs to - gh, git's
// credentials, its ssh key and its commit identity - for this process and its
// children only. GH_TOKEN outranks gh's stored credentials for this process alone,
// which is exactly the scope wanted; 'gh auth switch' would be global state a
// killed run leaves the machine on.
// skipGhProbe: this run prints no identity block, so skip the probe that only
// feeds one.
func selectAccount(skipGhProbe bool) {
	if anyIdentity {
		return
	}
	// Applying twice would number a second set of GIT_CONFIG_* entries on top of
	// the first.
	if accountApplied {
		return
	}
	accountApplied = true
	token := accountToken()
	if token != "" {
		// Export whenever a token was found, not only when it replaces a different
		// active account: the helper below reads GH_TOKEN when git runs it, and the
		// reset that precedes it has already evicted any credential manager.
		os.Setenv("GH_TOKEN", token)
		if !skipGhProbe {
			// Naming the account this one replaced is display only, and asking is a
			// live API round trip. '?' means gh held no account at all.
			if active := ghLogin(); active != acctGhWho && active != "?" {
				ghSwitchedFrom = active
			}
		}
		ghLoginCache = acctGhWho
		// The same token is what lets git itself push as this account over https,
		// with no ssh key anywhere. An empty value first resets the helper list, so
		// a credential manager configured for another account cannot answer ahead of
		// us. The token is read from the environment when the helper runs, never
		// stored in the config value itself.
		gitConfigEnv("credential.https://github.com.helper", "")
		gitConfigEnv("credential.https://github.com.helper",
			`!f(){ test "$1" = get && { echo username=x; echo "password=${GH_TOKEN}"; }; }; f`)
		accountUsedHttpsAuth = true
	} else if acctGhWho != "" && (acctExplicit || acctName != "") {
		// An account we resolved but cannot act as. gh goes on using whichever
		// account it is logged in as, and the identity block must say so rather than
		// name what was RESOLVED as if it were APPLIED. Only for an account that was
		// configured or asked for: one guessed from the remote owner is not a claim
		// that we can act as it.
		accountNoToken = true
	}
	// The ssh key stays supported as the way that needs no token at all. Only when
	// nothing already says which key to use: an explicit GIT_SSH_COMMAND, or one
	// set on the repo, was chosen more deliberately than a folder rule was.
	if sshKey := accountValue(acctName, "sshKey"); sshKey != "" &&
		os.Getenv("GIT_SSH_COMMAND") == "" && coreSshCommand() == "" {
		// IdentitiesOnly, or ssh offers every key the agent holds and the server
		// picks the first that authenticates - on a two-account machine a coin toss.
		os.Setenv("GIT_SSH_COMMAND", "ssh -i "+sshKey+" -o IdentitiesOnly=yes")
		accountUsedSSHKey = sshKey
	}
	// Commit identity, unless the repo sets its own - a local value was typed for
	// this repo specifically, and a folder rule should not quietly outrank it.
	acctEmail := accountValue(acctName, "email")
	acctUser := accountValue(acctName, "name")
	if (acctEmail != "" || acctUser != "") && runOut("git", "config", "--local", "--get", "user.email") == "" {
		if acctUser != "" {
			gitConfigEnv("user.name", acctUser)
		}
		if acctEmail != "" {
			gitConfigEnv("user.email", acctEmail)
		}
		accountUsedIdentity = true
	}
}

// ghLogin names the account gh's token belongs to. gh talks to the API over https
// and never consults ssh config, so this is who every gh-backed command acts as -
// regardless of which key git pushes with. '?' when gh can't say.
func ghLogin() string {
	if ghLoginCache == "" {
		ghLoginCache = "?"
		if _, err := exec.LookPath("gh"); err == nil {
			cmd := exec.Command("gh", "api", "user", "--jq", ".login")
			cmd.Env = append(os.Environ(), "GH_PROMPT_DISABLED=1")
			if out, err := cmd.Output(); err == nil {
				if login := strings.TrimRight(string(out), "\r\n"); login != "" {
					ghLoginCache = login
				}
			}
		}
	}
	return ghLoginCache
}
