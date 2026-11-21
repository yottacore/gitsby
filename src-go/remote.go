// The remote's side of things: ssh host and identity probing, the pre-command
// fetch, and which transport a remote should use. Offline is a STATE the fetch
// discovers, never a flag.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"context"
	"io"
	"os"
	"regexp"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"time"
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

// sshURLHostPort splits an ssh:// URL's authority into host and port text. A
// bracketed IPv6 host keeps its colons and loses the brackets, as ssh wants it, and
// only a ':' after the ']' starts the port. An '@' in the path is part of the path.
func sshURLHostPort(url string) (host, port string) {
	authority := strings.TrimPrefix(url, "ssh://")
	if slash := strings.IndexByte(authority, '/'); slash >= 0 {
		authority = authority[:slash]
	}
	authority = authority[strings.LastIndexByte(authority, '@')+1:]
	if strings.HasPrefix(authority, "[") {
		if end := strings.IndexByte(authority, ']'); end > 0 {
			host = authority[1:end]
			port = strings.TrimPrefix(authority[end+1:], ":")
			return host, port
		}
	}
	host, port, _ = strings.Cut(authority, ":")
	return host, port
}

// sshTarget is the host to ask ssh about, pulled out of a remote URL. Empty for
// https and local-path remotes - and for a Windows drive path, which is not
// 'host:path' however much it looks like one.
func sshTarget(url string) string {
	switch {
	case strings.HasPrefix(url, "ssh://"):
		host, _ := sshURLHostPort(url)
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

// sshPort is the port an ssh:// remote names, or nothing. git hands it to ssh as
// '-p', after the ssh command's own words, and so does every ssh gitsby runs about
// that remote. Digits only, since git can't connect with anything else either.
func sshPort(url string) string {
	if !strings.HasPrefix(url, "ssh://") {
		return ""
	}
	_, port := sshURLHostPort(url)
	if port == "" || strings.Trim(port, "0123456789") != "" {
		return ""
	}
	return port
}

// sshDest ends every ssh call about a remote: the port, if the URL names one, then
// '--' and the connect target. Nothing for a remote that isn't ssh. One helper, so
// the login probe and the ssh -G read can't disagree about where they connect.
func sshDest(url string) []string {
	target := sshConnectTarget(url)
	if target == "" {
		return nil
	}
	if port := sshPort(url); port != "" {
		return []string{"-p", port, "--", target}
	}
	return []string{"--", target}
}

// gitSSHCommand is the ssh command git would run, so probes ask as the key git pushes
// with. GIT_SSH_COMMAND beats core.sshCommand. Split, never shelled, so one only a
// shell could read gives plain 'ssh'.
func (a *app) gitSSHCommand() string {
	cmd := a.rawSSHCommand()
	// Blank is as good as unset. A lone space split into nothing, and reading the
	// command's first word killed every push compared against an account.
	if _, ok := sshWords(cmd); !ok {
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

// sshArgv is the program and leading arguments a probe runs. With neither command
// set, git runs GIT_SSH, one program named by its path, spaces and all.
func (a *app) sshArgv() []string {
	if strings.TrimSpace(a.rawSSHCommand()) == "" {
		if program := os.Getenv("GIT_SSH"); program != "" {
			return []string{program}
		}
	}
	words, _ := sshWords(a.gitSSHCommand())
	return words
}

// sshWords is an ssh command split the way git's shell would split it, or false
// when that shell would do more than split it on blanks: a quote, a variable, a
// backtick, '~user'. A leading '~/' stays, since ssh expands that in a key path
// itself, and gitsby's own sshkey command is spelled that way.
func sshWords(cmd string) ([]string, bool) {
	if strings.ContainsAny(cmd, "\"'\\$`;&|<>()\n") {
		return nil, false
	}
	words := strings.Fields(cmd)
	for _, word := range words {
		if strings.HasPrefix(word, "#") || (strings.HasPrefix(word, "~") && word != "~" && !strings.HasPrefix(word, "~/")) {
			return nil, false
		}
	}
	return words, len(words) > 0
}

// sshTakesOptions: the program takes OpenSSH's '-o' options, by git's own reading of
// it. GIT_SSH_VARIANT says outright; otherwise PuTTY's programs are known by name.
// plink takes no '-o', and won't connect at all when handed one.
func sshTakesOptions(program string) bool {
	switch strings.ToLower(os.Getenv("GIT_SSH_VARIANT")) {
	case "ssh":
		return true
	case "plink", "putty", "tortoiseplink", "simple":
		return false
	}
	base := strings.ToLower(program[strings.LastIndexAny(program, `/\`)+1:])
	base = strings.TrimSuffix(base, ".exe")
	return base != "plink" && base != "tortoiseplink"
}

// remoteEnv is the environment every command that reaches origin runs under: no auth
// prompts, an http low-speed limit, and ssh's time limits added to whatever ssh
// command git would use. Whatever can't take them is left for git to run as it
// stands: a GIT_SSH_COMMAND the caller chose, one only a shell can read, PuTTY's,
// and GIT_SSH, which any GIT_SSH_COMMAND would outrank.
func (a *app) remoteEnv() []string {
	env := append(toolEnv("git"), "GIT_TERMINAL_PROMPT=0")
	env = append(env, httpStallEnv()...)
	if a.userSSHCommand {
		return env
	}
	cmd := a.rawSSHCommand()
	if strings.TrimSpace(cmd) == "" {
		if os.Getenv("GIT_SSH") != "" {
			return env
		}
		cmd = "ssh"
	}
	if words, ok := sshWords(cmd); !ok || !sshTakesOptions(words[0]) {
		return env
	}
	return append(env, "GIT_SSH_COMMAND="+cmd+" "+strings.Join(sshStallOptions(), " "))
}

// A remote that takes the connection and then goes quiet holds git with no limit of
// its own, since git sets none, over http or ssh. This long without an answer gives
// up. A server busy packing sends a keepalive every 5 s over http, and sshd answers
// ssh's own keepalives while git packs, so this only trips on one that has gone
// quiet. A var only so a test can wait less.
var stallSeconds = 30

// httpStallEnv is the low-speed limit for the commands that reach origin unseen:
// under a byte a second for stallSeconds. Either variable set by the caller leaves
// both as they are. git reads them over http.lowSpeedLimit and http.lowSpeedTime,
// so a config value is outranked, the way ssh's options below outrank ssh_config.
// curl's own 300 s connect limit is all that bounds a TLS handshake that never
// finishes: the low-speed check starts after it.
func httpStallEnv() []string {
	if os.Getenv("GIT_HTTP_LOW_SPEED_LIMIT") != "" || os.Getenv("GIT_HTTP_LOW_SPEED_TIME") != "" {
		return nil
	}
	return []string{"GIT_HTTP_LOW_SPEED_LIMIT=1", "GIT_HTTP_LOW_SPEED_TIME=" + strconv.Itoa(stallSeconds)}
}

// ssh's ConnectTimeout, which the login probe's own limit counts in too.
const sshConnectSeconds = 3

// sshStallOptions are ssh's time limits for the fetch and the probes. ConnectTimeout
// bounds only the connect and the server's banner. A server that stops after its
// banner held the fetch until killed: the ServerAlive pair bounds every read after
// it, the key exchange included, at their product, and after login ends a session
// whose keepalives go unanswered. They go after the command's own words, since ssh
// keeps the first value it reads for each option, so a command's own -o wins.
func sshStallOptions() []string {
	return []string{"-o", "ConnectTimeout=" + strconv.Itoa(sshConnectSeconds), "-o", "ServerAliveInterval=" + strconv.Itoa(max(1, stallSeconds/3)), "-o", "ServerAliveCountMax=3"}
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
		who = probeSSHLogin(context.Background(), os.Environ(), url, a.sshArgv(), sshStallOptions(), sshProbeWait())
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
	ctx, env, sshCmd, limits, wait := a.probeContext(), os.Environ(), a.sshArgv(), sshStallOptions(), sshProbeWait()
	if a.remote.sshAhead == nil {
		a.remote.sshAhead = map[string]*ahead[string]{}
	}
	a.remote.sshAhead[url] = startAhead(func() string { return probeSSHLogin(ctx, env, url, sshCmd, limits, wait) })
}

// sshProbeWait is all the time the login probe gets. Windows' own OpenSSH (9.5p2)
// never exits once it has written to a stderr that is a pipe, which errSink keeps
// it from. Any ssh that ignores its limits some other way, the probe ends itself,
// a little past ssh's own limits, and an ssh that keeps them ends first.
func sshProbeWait() time.Duration {
	return time.Duration(sshConnectSeconds+stallSeconds+5) * time.Second
}

func probeSSHLogin(ctx context.Context, env []string, url string, sshCmd, limits []string, wait time.Duration) string {
	dest := sshDest(url)
	// PuTTY's programs take none of the options below, so the answer stays unknown.
	// Asking plain ssh instead could name an account git never pushes as.
	if len(dest) == 0 || !inPath("ssh") || len(sshCmd) == 0 || !sshTakesOptions(sshCmd[0]) {
		return "?"
	}
	// A copy, since this runs on a look-ahead goroutine and append could write into the caller's array.
	args := slices.Concat(sshCmd[1:], []string{"-T", "-o", "BatchMode=yes"}, limits, dest)
	ctx, stop := context.WithTimeout(ctx, wait)
	defer stop()
	// Both streams: ssh writes host-key and missing-identity warnings ahead of the
	// greeting, so it is not reliably the first line - anchoring to the whole output
	// answered '?' for exactly the multi-key setups this exists for.
	probe := toolCmdContext(ctx, sshCmd[0], args...)
	probe.Env = env
	// What the ssh command started, such as a ProxyCommand, can hold the output open past the kill.
	probe.WaitDelay = time.Second
	said := newErrSink()
	defer said.close()
	probe.Stdout, probe.Stderr = said.writer(), said.writer()
	// No exit code to read: github.com says hello and then exits 1.
	_ = probe.Run()
	for _, line := range splitLines(said.text()) {
		for _, greeting := range sshGreetingREs {
			if m := greeting.FindStringSubmatch(line); m != nil {
				return m[1]
			}
		}
	}
	return "?"
}

// Windows' own OpenSSH (9.5p2) never exits once it has written a line to a stderr
// that is a pipe, whatever the server does next: Win32-OpenSSH#1427, an async write
// that never completes. To NUL or a file it exits as it should. git hands ssh its
// own stderr, so where gitsby reads what a remote reach said, on Windows it reads it
// back from a temp file rather than a pipe. One gitsby passes its own stderr to gets
// what git would get run by hand.
// A var so a test can take the file path anywhere.
var errToFile = runtime.GOOS == "windows"

// errSink is where a command that reaches a remote writes what it says.
type errSink struct {
	buf  bytes.Buffer
	file *os.File
}

// newErrSink makes the temp file under errToFile. Without one it falls back to the pipe.
func newErrSink() *errSink {
	sink := &errSink{}
	if errToFile {
		sink.file, _ = os.CreateTemp("", "gitsby-said-*.txt")
	}
	return sink
}

// newErrFile is an errSink that is a temp file on every system, for the
// pre-command fetch, whose stderr was NUL before it was read. A pipe would make
// the run wait on anything the fetch left running that holds it open, such as a
// ProxyCommand, and NUL never did.
func newErrFile() *errSink {
	sink := &errSink{}
	sink.file, _ = os.CreateTemp("", "gitsby-said-*.txt") // without one it falls back to the pipe
	return sink
}

func (sink *errSink) writer() io.Writer {
	if sink.file != nil {
		return sink.file
	}
	return &sink.buf
}

// text is what the command said, read once it has ended.
func (sink *errSink) text() string {
	if sink.file == nil {
		return sink.buf.String()
	}
	if _, err := sink.file.Seek(0, io.SeekStart); err != nil {
		return ""
	}
	said, _ := io.ReadAll(sink.file) // what was read so far is all there is to go on
	return string(said)
}

func (sink *errSink) close() {
	if sink.file != nil {
		_ = sink.file.Close()
		_ = os.Remove(sink.file.Name()) // a child the kill missed can hold it on Windows; the temp folder keeps it then
	}
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
	// LC_ALL=C so submoduleFetchFailed can read what it said.
	fetch.Env = append(slices.Clip(env), "LC_ALL=C")
	said := newErrFile()
	defer said.close()
	fetch.Stderr = said.writer()
	if fetch.Run() != nil {
		// fetch.recurseSubmodules defaults to on-demand, so a submodule whose own
		// remote is gone fails the fetch after origin's refs are in. git fetches
		// submodules only once origin's fetch has worked, so that failure isn't
		// offline, and the pull still has what it needs.
		if !submoduleFetchFailed(said.text()) {
			a.remote.offline = true
			a.out.status("WARNING: git fetch failed (offline?); remote info may be stale.")
			return
		}
		a.out.status("WARNING: origin was fetched, but fetching a submodule failed, so it may lack the commits origin's branches point at. 'git submodule update' fetches them once its remote answers.")
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

// submoduleFetchFailed: whether a failed fetch got as far as the submodules, from
// the heading git prints, under LC_ALL=C, over the ones whose fetch failed.
func submoduleFetchFailed(said string) bool {
	return slices.Contains(splitLines(said), "Errors during submodule fetch:")
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
