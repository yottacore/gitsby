// The remote's side of things: ssh host and identity probing, the pre-command
// fetch, and which transport a remote should use. Offline is a STATE the fetch
// discovers, never a flag.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"regexp"
	"strings"
)

var (
	remoteReachable = true // cleared when the pre-command fetch can't reach origin
	sshLoginCache   = ""   // per-run; the probe costs a live round trip
	ghProtocolCache = ""
)

// sshTarget is the host to ask ssh about, pulled out of a remote URL. Empty for
// https and local-path remotes - and for a Windows drive path, which is not
// 'host:path' however much it looks like one.
func sshTarget(url string) string {
	switch {
	case strings.HasPrefix(url, "ssh://"):
		host := url[len("ssh://"):]
		if i := strings.Index(host, "/"); i >= 0 {
			host = host[:i]
		}
		if at := strings.LastIndex(host, "@"); at >= 0 {
			host = host[at+1:]
		}
		if c := strings.Index(host, ":"); c >= 0 {
			host = host[:c]
		}
		return host
	case strings.Contains(url, "://"): // https/git/file: no ssh identity involved
		return ""
	case isDrivePath(url):
		return ""
	}
	// scp-like: [user@]host:path.
	c := strings.Index(url, ":")
	if c < 1 {
		return ""
	}
	host := url[:c]
	if at := strings.LastIndex(host, "@"); at >= 0 {
		host = host[at+1:]
	}
	return host
}

// sshConnectTarget is the '[user@]host' to actually connect to, so an explicit
// user in the remote URL is honored. sshTarget returns the bare host, which is
// the alias to name in the display.
func sshConnectTarget(url string) string {
	host := sshTarget(url)
	if host == "" {
		return ""
	}
	user := ""
	switch {
	case strings.HasPrefix(url, "ssh://") && strings.Contains(url, "@"):
		user = url[len("ssh://"):]
		user = user[:strings.Index(user, "@")]
	case strings.Contains(url, "://"):
	default:
		if at := strings.Index(url, "@"); at >= 0 && strings.Contains(url[at:], ":") {
			user = url[:at]
		}
	}
	if user != "" {
		return user + "@" + host
	}
	return host
}

// gitSshCommand is the ssh command git itself would run, so probes ask as the key
// git actually pushes with. Without this a per-repo 'core.sshCommand' (the usual
// way to hold two GitHub accounts on one box) is invisible: the probe answers
// with the default key's account while git pushes as someone else - and two wrong
// halves that happen to agree read as a clean bill of health. Precedence is git's
// own: GIT_SSH_COMMAND beats core.sshCommand. Split, never shelled - a config
// value is not a place to run shell - so a quoted path degrades to a plain 'ssh'
// probe (which answers for the default key, and a wrong '?' is safer than a wrong
// name) rather than misparse.
func gitSshCommand() string {
	cmd := os.Getenv("GIT_SSH_COMMAND")
	if cmd == "" {
		cmd = runOut("git", "config", "--get", "core.sshCommand")
	}
	if cmd == "" || strings.ContainsAny(cmd, `"'`) {
		return "ssh"
	}
	return cmd
}

var sshGreetingRE = regexp.MustCompile(`^Hi ([A-Za-z0-9_.:/-]+)!`)

// sshLogin names the account this remote's ssh key authenticates as. GitHub
// answers 'Hi <user>!' and always exits 1, so parse the greeting, not the status.
// BatchMode + a connect timeout: never prompt, never hang. '?' for https/local
// remotes, no agent, or anything else unresolvable - and a deploy key answers
// with a repo name, which simply won't match any login. Unknown is not wrong.
func sshLogin(url string) string {
	if sshLoginCache == "" {
		sshLoginCache = "?"
		target := sshConnectTarget(url)
		if _, err := exec.LookPath("ssh"); err == nil && target != "" {
			sshCmd := strings.Fields(gitSshCommand())
			args := append(sshCmd[1:], "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", "--", target)
			// Both streams: ssh writes host-key and missing-identity warnings ahead
			// of the greeting, so it is not reliably the first line - anchoring to
			// the whole output answered '?' for exactly the multi-key setups this
			// exists for.
			out, _ := exec.Command(sshCmd[0], args...).CombinedOutput()
			for _, line := range strings.Split(string(out), "\n") {
				if m := sshGreetingRE.FindStringSubmatch(line); m != nil {
					sshLoginCache = m[1]
					break
				}
			}
		}
	}
	return sshLoginCache
}

// fetchRemote fetches with --prune (stale origin/* refs would fool the existence
// checks) and heals origin/HEAD (missing on git < 2.47, stale after an upstream
// default-branch rename). ssh gets a connect timeout so a dead remote can't hang
// every command for minutes; https relies on git's own timeouts. Never clobbers a
// user-set GIT_SSH_COMMAND, and never prompts for auth - this runs before any of
// our own checks, so an https remote we can't authenticate to would stop and ask
// for a username mid-command.
func fetchRemote() {
	env := append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	if os.Getenv("GIT_SSH_COMMAND") == "" {
		env = append(env, "GIT_SSH_COMMAND="+gitSshCommand()+" -o ConnectTimeout=3")
	}
	fetch := exec.Command("git", "fetch", "--quiet", "--prune")
	fetch.Env = env
	if fetch.Run() == nil {
		// Healing queries the remote again, so only when there is nothing to read:
		// git < 2.47 never wrote one. A ref left stale by an upstream rename
		// survives, and main already refuses naming the fix.
		if !runOK("git", "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD") {
			setHead := exec.Command("git", "remote", "set-head", "origin", "--auto")
			setHead.Env = env
			_ = setHead.Run()
		}
	} else {
		remoteReachable = false
		echoStatus("WARNING: git fetch failed (offline?); remote info may be stale.")
	}
}

// isOffline: set by the pre-command fetch, which is the only thing that actually
// asks origin. --no-fetch is NOT offline: it declines the incoming round trip,
// and pushes still go out.
func isOffline() bool { return !remoteReachable }

// ghProtocol: which transport gh hands to git for github.com ('ssh' or 'https').
// Host-specific, not the global default - they can disagree, and the host one is
// what github.com operations use.
func ghProtocol() string {
	if ghProtocolCache == "" {
		ghProtocolCache = "https"
		if _, err := exec.LookPath("gh"); err == nil {
			if runOut("gh", "config", "get", "-h", "github.com", "git_protocol") == "ssh" {
				ghProtocolCache = "ssh"
			}
		}
	}
	return ghProtocolCache
}

// preferredProtocol: which transport a remote we set should use. The config file
// wins because that is where the accounts live, and choosing https there is what
// makes a second account work with no ssh key at all; gh's own setting is the
// answer when nothing says otherwise, so an unconfigured machine behaves exactly
// as it did before any of this existed.
func preferredProtocol() string {
	proto := accountValue(acctName, "protocol")
	if proto == "" {
		proto = cfg["protocol"]
	}
	switch strings.ToLower(proto) {
	case "https", "ssh":
		return strings.ToLower(proto)
	}
	return ghProtocol()
}

// remoteTarget: 'owner/name' out of any github.com remote URL, or nothing. Used
// to re-spell a remote in the other transport without asking the network.
func remoteTarget(url string) string {
	owner := remoteOwner(url)
	if owner == "" {
		return ""
	}
	name := strings.TrimSuffix(url, ".git")
	name = strings.TrimSuffix(name, "/")
	name = name[strings.LastIndex(name, "/")+1:]
	if name == "" || name == owner {
		return ""
	}
	return owner + "/" + name
}

// convertibleToHttps is true when this repo is on ssh but the account it belongs
// to could authenticate with a token instead - the one case where saying so is
// worth a line. Someone who set 'protocol = ssh' has answered the question
// already, and hears nothing.
func convertibleToHttps() bool {
	if acctName == "" || preferredProtocol() != "https" {
		return false
	}
	url := runOut("git", "remote", "get-url", "origin")
	if sshTarget(url) == "" || remoteTarget(url) == "" {
		return false
	}
	return accountToken() != ""
}
