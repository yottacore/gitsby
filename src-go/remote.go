// The remote's side of things: ssh host and identity probing, the pre-command
// fetch, and which transport a remote should use. Offline is a STATE the fetch
// discovers, never a flag.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"context"
	"os"
	"regexp"
	"strings"
)

// origin's url, asked once. A preview alone wanted it half a dozen times, and it
// can only change through a step, which forgets it - so the after-shot still
// reads what the step left behind. Not for another repo: '-C <dir>' asks about a
// different origin and must go direct.
func (a *app) originURL() string {
	return a.git.originURL.get(func() string { return runOut("git", "remote", "get-url", "origin") })
}

// hasOrigin: there is a remote called origin. get-url printing nothing and
// get-url failing are the same answer.
func (a *app) hasOrigin() bool { return a.originURL() != "" }

// coreSSHCommand: git's configured ssh command, read once - the account selector
// and every ssh probe ask for the same value.
func (a *app) coreSSHCommand() string {
	return a.git.coreSSHCommand.get(func() string { return runOut("git", "config", "--get", "core.sshCommand") })
}

// identityMismatchText says why the 2 identities disagree, or nothing. '?' on either
// side is unknown, not wrong. The tool is named, since it may be tea.
func identityMismatchText(cli, cliWho, sshWho string) string {
	if cli == "" {
		cli = "the host's CLI"
	}
	if cliWho == "" {
		cliWho = "?"
	}
	if sshWho == "" {
		sshWho = "?"
	}
	if cliWho == "?" || sshWho == "?" || cliWho == sshWho {
		return ""
	}
	return cli + " acts as '" + cliWho + "', but this remote's key authenticates as '" + sshWho + "'."
}

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
	case strings.HasPrefix(url, "ssh://"):
		// The user part ends at the authority; an '@' in the path is part of the path.
		authority := url[len("ssh://"):]
		if slash := strings.IndexByte(authority, '/'); slash >= 0 {
			authority = authority[:slash]
		}
		if at := strings.LastIndexByte(authority, '@'); at >= 0 {
			user = authority[:at]
		}
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

// gitSSHCommand is the ssh command git would run, so probes ask as the key git pushes
// with. GIT_SSH_COMMAND beats core.sshCommand. Split, never shelled, so a quoted path
// gives plain 'ssh'.
func (a *app) gitSSHCommand() string {
	cmd := a.rawSSHCommand()
	// Blank is as good as unset. A lone space split into nothing, and reading the
	// command's first word killed every push compared against an account.
	if strings.TrimSpace(cmd) == "" || strings.ContainsAny(cmd, `"'`) {
		return "ssh"
	}
	return cmd
}

func (a *app) rawSSHCommand() string {
	if cmd := os.Getenv("GIT_SSH_COMMAND"); cmd != "" {
		return cmd
	}
	return a.coreSSHCommand()
}

// remoteEnv is the environment every command that reaches origin runs under: no auth
// prompts, and an ssh connect timeout added to whatever ssh command git would use. A
// GIT_SSH_COMMAND the caller chose is left alone, and so is a quoted one.
func (a *app) remoteEnv() []string {
	env := append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	if !a.userSSHCommand && !strings.ContainsAny(a.rawSSHCommand(), `"'`) {
		env = append(env, "GIT_SSH_COMMAND="+a.gitSSHCommand()+" -o ConnectTimeout=3")
	}
	return env
}

// The greeting each git host answers an ssh -T with. GitHub says 'Hi <user>!';
// Gitea (and Forgejo, which kept the wording) says 'Hi there, <user>!' - close
// enough to look handled by the first pattern and different enough not to be, so
// the identity line read 'unknown' on every Gitea remote while looking correct.
var sshGreetingREs = []*regexp.Regexp{
	regexp.MustCompile(`^Hi ([A-Za-z0-9_.:/-]+)!`),
	regexp.MustCompile(`^Hi there, ([A-Za-z0-9_.-]+)!`),
}

// sshLogin names the account this remote's ssh key authenticates as, from GitHub's
// greeting, since it always exits 1. '?' for anything unresolvable. Unknown isn't wrong.
func (a *app) sshLogin(url string) string {
	if who, asked := a.remote.sshLogins[url]; asked {
		return who
	}
	var who string
	if pending := a.remote.sshAhead[url]; pending != nil {
		delete(a.remote.sshAhead, url)
		who = pending.wait()
	} else {
		who = probeSSHLogin(context.Background(), os.Environ(), url, a.gitSSHCommand())
	}
	if a.remote.sshLogins == nil {
		a.remote.sshLogins = map[string]string{}
	}
	a.remote.sshLogins[url] = who
	return who
}

// askSSHLoginAhead starts the sshLogin probe without waiting for it. Everything
// it reads from the run is read here, on this goroutine.
func (a *app) askSSHLoginAhead(url string) {
	if _, asked := a.remote.sshLogins[url]; asked || a.remote.sshAhead[url] != nil {
		return
	}
	ctx, env, sshCommand := a.probeContext(), os.Environ(), a.gitSSHCommand()
	if a.remote.sshAhead == nil {
		a.remote.sshAhead = map[string]*ahead[string]{}
	}
	a.remote.sshAhead[url] = startAhead(func() string { return probeSSHLogin(ctx, env, url, sshCommand) })
}

func probeSSHLogin(ctx context.Context, env []string, url, sshCommand string) string {
	target := sshConnectTarget(url)
	if target == "" || !inPath("ssh") {
		return "?"
	}
	sshCmd := strings.Fields(sshCommand)
	if len(sshCmd) == 0 {
		sshCmd = []string{"ssh"}
	}
	args := append(sshCmd[1:], "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", "--", target)
	// Both streams: ssh writes host-key and missing-identity warnings ahead of the
	// greeting, so it is not reliably the first line - anchoring to the whole output
	// answered '?' for exactly the multi-key setups this exists for.
	probe := toolCmdContext(ctx, sshCmd[0], args...)
	probe.Env = env
	out, _ := probe.CombinedOutput()
	for _, line := range splitLines(string(out)) {
		for _, greeting := range sshGreetingREs {
			if m := greeting.FindStringSubmatch(line); m != nil {
				return m[1]
			}
		}
	}
	return "?"
}

// fetchRemote fetches with --prune and heals origin/HEAD, missing on git < 2.47 or stale
// after a rename. Runs under remoteEnv, so no auth prompt and no hang.
func (a *app) fetchRemote() {
	// The one thing that moves a ref without being a step, so the runners' own
	// invalidation never covers it. Only what reads origin/*: ahead-behind, the
	// branch list and origin/HEAD. Everything else the run has settled stays where
	// it was.
	a.git.aheadBehind.forget()
	a.git.branches.forget()
	a.git.originHead.forget()
	env := a.remoteEnv()
	// Named, not implied: a bare 'git fetch' follows the current branch's own
	// tracking remote, and every existence check afterwards reads origin.
	fetch := toolCmd("git", "fetch", "--quiet", "--prune", "origin")
	fetch.Env = env
	if fetch.Run() != nil {
		a.remote.offline = true
		a.out.status("WARNING: git fetch failed (offline?); remote info may be stale.")
		return
	}
	// Healing queries the remote again, so only when there is nothing to read:
	// git < 2.47 never wrote one. A ref left stale by an upstream rename survives,
	// and main already refuses naming the fix.
	// The answer is kept: the default branch is read from it next.
	if a.originHead() == "" {
		setHead := toolCmd("git", "remote", "set-head", "origin", "--auto")
		setHead.Env = env
		_ = setHead.Run() // best effort: with nothing written, the default branch reads as unknown
		a.git.originHead.forget()
	}
}

// askOriginHeads asks origin where its branches point, for br prune's delete check. One
// answer for all, since a pattern list can pass Windows' command-line limit. false: not
// asked.
func (a *app) askOriginHeads() (map[string]string, bool) {
	ask := toolCmd("git", "ls-remote", "--heads", "origin")
	ask.Env = a.remoteEnv()
	ask.Stderr = os.Stderr
	out, err := ask.Output()
	if err != nil {
		return nil, false
	}
	return parseOriginHeads(string(out)), true
}

// isOffline: set by the pre-command fetch, which is the only thing that decides
// offline. br prune's delete-time ask of origin reports its own failure without
// changing it. --no-fetch is NOT offline: it declines the incoming round trip,
// and pushes still go out.
func (a *app) isOffline() bool { return a.remote.offline }

// ghProtocol: the transport gh hands git for this host, from the host setting, not the
// global one. Only for a host gh serves.
func (a *app) ghProtocol(host string) string {
	if !isGitHubHost(host) {
		return "https"
	}
	return a.remote.protocol.get(func() string {
		if inPath("gh") && runOut("gh", "config", "get", "-h", host, "git_protocol") == "ssh" {
			return "ssh"
		}
		return "https"
	})
}

// preferredProtocol: which transport a remote we set should use. The config file wins,
// then gh's own setting.
func (a *app) preferredProtocol() string {
	return a.protocolFor(a.originHost())
}

// protocolFor is the same question about a named host, for the commands settling a
// remote they do not have yet - a clone's URL and a connect's target name their own
// host, and it need not be the one the current directory sits on.
func (a *app) protocolFor(host string) string {
	proto := a.cfg.value(a.acct.name, "protocol")
	if proto == "" {
		proto = a.cfg.values["protocol"]
	}
	switch strings.ToLower(proto) {
	case "https", "ssh":
		return strings.ToLower(proto)
	}
	return a.ghProtocol(host)
}

// remoteTarget: 'owner/name' out of any remote URL, or nothing. Used to re-spell
// a remote in the other transport without asking the network - which is pure text
// work on any host, and was refused everywhere but github.com for no better reason
// than that the parser behind it only knew the one.
func remoteTarget(url string) string {
	ref, _ := parseRemoteText(url)
	return ref.target()
}

// convertibleToHTTPS is true when this repo is on ssh but the account it belongs
// to could authenticate with a token instead - the one case where saying so is
// worth a line. Someone who set 'protocol = ssh' has answered the question
// already, and hears nothing.
func (a *app) convertibleToHTTPS() bool {
	if a.acct.name == "" {
		return false
	}
	// The text test first: it is free, and on an https origin it already says no
	// before gh is asked for its protocol.
	url := a.originURL()
	if sshTarget(url) == "" || remoteTarget(url) == "" || a.preferredProtocol() != "https" {
		return false
	}
	// The token has to be one THIS host would accept. Offering to re-spell a Gitea
	// remote so it authenticates with a GitHub token is an invitation to break a
	// working repo, and the line reads as advice either way.
	if !a.accountServesHost(a.originHost()) {
		return false
	}
	// Only whether a token exists matters here; its source and any load complaint
	// belong to the identity block, which reports them itself.
	token, _, _ := a.accountToken(a.originHost())
	return token != ""
}
