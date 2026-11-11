// Which host a remote lives on, and which tool speaks to it. Everything that
// used to assume github.com asks here instead: git does the work wherever it can,
// and a host-specific CLI is reached for only once the host has been identified as
// one that CLI serves.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"os"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

// remoteRef is a remote URL taken apart: where it lives and what it is called.
// Every field empty is the ordinary answer for a local path - a directory is a
// perfectly good remote, it has no host to ask anything about.
type remoteRef struct {
	host  string // canonical hostname, after any ssh_config alias is resolved
	owner string
	name  string
}

// target is 'owner/name', or nothing when the URL had only a host.
func (r remoteRef) target() string {
	if r.owner == "" || r.name == "" {
		return ""
	}
	return r.owner + "/" + r.name
}

// parseRemote splits a remote URL into host, owner and name, for every caller. An
// ssh_config alias is resolved for the ssh spellings only.
func parseRemote(url string) remoteRef {
	ref, viaSSH := parseRemoteText(url)
	// A host gh already serves is a real hostname, not an alias, so asking ssh about
	// it spends a process to be told what we started with. That skip is why the
	// ordinary 'git@github.com:owner/name' remote costs no ssh call at all - dropping
	// it put one into the spawn count of every command on every GitHub repo.
	if viaSSH && !isGitHubHost(ref.host) {
		ref.host = resolveSSHHost(ref.host, sshConnectTarget(url))
	}
	return ref
}

// parseRemoteText is parseRemote with the host as written, for callers that want
// only the owner and name. It resolves no alias, so it starts no process.
func parseRemoteText(url string) (ref remoteRef, viaSSH bool) {
	host, path, viaSSH := splitRemoteURL(url)
	if host == "" {
		return remoteRef{}, false
	}
	ref.host = host
	path = strings.TrimSuffix(strings.TrimSuffix(path, "/"), ".git")
	// Everything before the last segment is the owner: a Gitea instance served
	// under a subpath, and GitHub's own 'owner/name', both come out right here.
	if slash := strings.LastIndex(path, "/"); slash > 0 {
		ref.owner, ref.name = path[:slash], path[slash+1:]
		// Only the segment immediately above the repo names the owner; anything
		// deeper is instance routing that says nothing about who owns this.
		if deeper := strings.LastIndex(ref.owner, "/"); deeper >= 0 {
			ref.owner = ref.owner[deeper+1:]
		}
	}
	return ref, viaSSH
}

// splitRemoteURL is the pure text half: the host as written, the path after it,
// and whether the spelling was one ssh would resolve an alias for. Kept apart from
// parseRemote so the alias lookup - the only part that costs a process - has one
// place it can be skipped.
func splitRemoteURL(url string) (host, path string, viaSSH bool) {
	switch {
	case strings.HasPrefix(url, "ssh://"):
		host, path, viaSSH = url[len("ssh://"):], "", true
	case isDrivePath(url):
		return "", "", false // a Windows drive path, not 'host:path'
	case len(url) > 0 && isLetter(url[0]) && strings.Contains(url, "://"):
		host = url[strings.Index(url, "://")+3:]
	default:
		// scp-like '[user@]host:path'. A colon at position zero is not a host.
		colon := strings.Index(url, ":")
		if colon < 1 {
			return "", "", false
		}
		host, path, viaSSH = url[:colon], url[colon+1:], true
		if at := strings.LastIndex(host, "@"); at >= 0 {
			host = host[at+1:]
		}
		return hostOrNothing(host, strings.TrimPrefix(path, "/"), viaSSH)
	}
	// The two '://' forms both have the path after the first slash.
	if slash := strings.Index(host, "/"); slash >= 0 {
		host, path = host[:slash], host[slash+1:]
	}
	if at := strings.LastIndex(host, "@"); at >= 0 {
		host = host[at+1:]
	}
	if colon := strings.Index(host, ":"); colon >= 0 { // a port is not part of the name
		host = host[:colon]
	}
	return hostOrNothing(host, strings.TrimPrefix(path, "/"), viaSSH)
}

// hostOrNothing refuses a "host" no host could be: whitespace means some other
// colon-bearing string ended up in the split, and "couldn't tell" (empty) is the
// true answer rather than a name for rules to match against.
func hostOrNothing(host, path string, viaSSH bool) (string, string, bool) {
	if strings.ContainsFunc(host, unicode.IsSpace) {
		return "", "", false
	}
	return host, path, viaSSH
}

// isGitHubHost says whether gh is the right tool for host. GH_HOST is how gh itself
// is pointed at an Enterprise instance, so a remote on that host is gh territory
// just as much as github.com is - and reading it here is what keeps Enterprise
// users out of the "not GitHub, so no pull requests" path they don't belong in.
func isGitHubHost(host string) bool {
	if host == "" {
		return false
	}
	if strings.EqualFold(host, "github.com") {
		return true
	}
	enterprise := os.Getenv("GH_HOST")
	return enterprise != "" && strings.EqualFold(host, enterprise)
}

// originRef is origin taken apart, asked once. The parse is cheap but the alias
// resolution behind it is a process, and half a dozen callers want the answer.
func (a *app) originRef() remoteRef {
	return a.git.originRef.get(func() remoteRef { return parseRemote(a.originURL()) })
}

// originHost is where origin lives, or nothing for a local path or no remote at all.
func (a *app) originHost() string { return a.originRef().host }

// onGitHub: this repo's origin is one gh serves. The single question every gh call
// site now asks - a gh that is installed and logged in still has no business being
// run against somebody else's git host, where at best it errors in its own vocabulary
// about a repo it was never looking at.
func (a *app) onGitHub() bool { return isGitHubHost(a.originHost()) }

// hostName is how a host is referred to in a message. 'origin' when there is no
// host to name, so a sentence about it still reads.
func (a *app) hostName() string {
	if host := a.originHost(); host != "" {
		return host
	}
	return "origin"
}

// teaNames: upstream installs Gitea's CLI as 'tea', and Debian packages the same
// program as 'tea-cli' because the name was already taken there. Looking for one
// spelling finds it on the machines that happen to use that one.
var teaNames = []string{"tea", "tea-cli"}

// teaCommand is Gitea's CLI as this machine spells it, or nothing when it isn't
// installed. Asked once: two LookPath calls per pr command, for an answer that
// cannot change mid-run.
func (a *app) teaCommand() string {
	return a.host.tea.get(func() string {
		for _, name := range teaNames {
			if inPath(name) {
				return name
			}
		}
		return ""
	})
}

// hostTokenEnv hands the account's token for this run's host to a git host CLI
// other than gh, in the variables that CLI reads, with the host beside it. tea keeps
// the token on that host; glab doesn't, so it goes through glabTokenEnv. A GitHub
// token is never handed over:
// that one is gh's, already in GH_TOKEN. Says whether there was a token to give.
func (a *app) hostTokenEnv(tokenVar, hostVar string) (bool, error) {
	if a.acct.tokenEnv == "" || isGitHubHost(a.acct.credHost) {
		return false, nil
	}
	if err := setEnv(tokenVar, os.Getenv(a.acct.tokenEnv)); err != nil {
		return false, err
	}
	return true, setEnv(hostVar, "https://"+a.acct.credHost)
}

// glabTokenEnv is hostTokenEnv for glab, which sends GITLAB_TOKEN to every host it
// talks to. GITLAB_API_HOST wins over any host glab is told, so pinning it keeps the
// token on the account's host. A run pointed at some other host gets nothing and
// runs as plain glab would; that host comes back so the caller can say so.
func (a *app) glabTokenEnv(args []string) (gave bool, elsewhere string, err error) {
	if a.acct.tokenEnv == "" || isGitHubHost(a.acct.credHost) {
		return false, "", nil
	}
	host := a.acct.credHost
	named := glabNamedHosts(args)
	if api := os.Getenv("GITLAB_API_HOST"); api != "" {
		named = append(named, api)
	}
	for _, x := range named {
		if !strings.EqualFold(glabHostName(x), serviceHost(host)) {
			return false, x, nil
		}
	}
	if gave, err = a.hostTokenEnv("GITLAB_TOKEN", "GITLAB_HOST"); !gave || err != nil {
		return gave, "", err
	}
	return true, "", setEnv("GITLAB_API_HOST", host)
}

// glabNamedHosts is every host a glab command line names: --hostname, a -R that
// starts with a host, a URL anywhere (api takes one as the endpoint, issue view
// takes one as the issue), and a repo command's 'host/group/name'. glab reads a
// dotted first part as a host only when it knows that host, which we can't see, so
// it always counts here. Too many means no token, never a token sent astray.
func glabNamedHosts(args []string) []string {
	var hosts []string
	repoCmd := len(args) > 0 && args[0] == "repo"
	for i := 0; i < len(args); i++ {
		x := args[i]
		name, val, hasVal := x, x, false
		if strings.HasPrefix(x, "--") {
			if n, v, ok := strings.Cut(x, "="); ok {
				name, val, hasVal = n, v, true
			}
		} else if len(x) > 2 && (strings.HasPrefix(x, "-R") || strings.HasPrefix(x, "-h")) {
			name, val, hasVal = x[:2], strings.TrimPrefix(x[2:], "="), true
		}
		hostFlag := name == "--hostname" || name == "-h"
		repoFlag := name == "--repo" || name == "-R"
		if (hostFlag || repoFlag) && !hasVal {
			if i+1 == len(args) {
				break
			}
			i++
			val = args[i]
		}
		h := ""
		switch {
		case hostFlag:
			hosts = append(hosts, val)
		case repoFlag || (repoCmd && !strings.HasPrefix(x, "-")):
			h = glabRepoHost(val)
		default:
			h = glabURLHost(val)
		}
		if h != "" {
			hosts = append(hosts, h)
		}
	}
	return hosts
}

// glabRepoHost is the host in a repo as glab takes it: a URL, or 'host/group/name'.
func glabRepoHost(repo string) string {
	if h := glabURLHost(repo); h != "" {
		return h
	}
	parts := strings.Split(repo, "/")
	if first := parts[0]; len(parts) >= 3 && strings.Contains(first, ".") && strings.Trim(first, ".") == first {
		return first
	}
	return ""
}

// glabURLRE: an argument that is a URL or 'user@host:path' from its first byte. Not a
// bare 'a:b', which a label such as 'priority:high' would be, nor an api field
// such as 'url=https://...', which is a value for the host to store.
var glabURLRE = regexp.MustCompile(`^(?:[A-Za-z][A-Za-z0-9+.-]*://|[A-Za-z0-9._-]+@[^:/\s]+:)`)

func glabURLHost(s string) string {
	if !glabURLRE.MatchString(s) {
		return ""
	}
	host, _, _ := splitRemoteURL(s)
	return host
}

// glabHostName is a host as glab compares them, so a URL, a trailing slash, 'www.'
// and the ssh. endpoint all match the account's host.
func glabHostName(host string) string {
	if strings.Contains(host, "://") {
		host, _, _ = splitRemoteURL(host)
	}
	return serviceHost(strings.TrimPrefix(strings.ToLower(strings.TrimSuffix(host, "/")), "www."))
}

// glabScopeAuth pins 'glab auth status' to the account's host. Left alone it
// checks every host glab knows, gitlab.com included, with the one token we set.
func glabScopeAuth(args []string, host string) []string {
	if len(args) < 2 || args[0] != "auth" || args[1] != "status" {
		return args
	}
	for _, x := range args[2:] {
		if x == "-h" || x == "--hostname" || strings.HasPrefix(x, "--hostname=") {
			return args
		}
	}
	return append(append([]string{}, args...), "--hostname", host)
}

// glabRemoteHost points glab at origin when origin is on the account host's ssh
// name (ssh.gitlab.gnome.org). glab takes a repo only from a remote whose host is
// GITLAB_HOST, so GITLAB_HOST names origin's host and GITLAB_API_HOST sends the API
// calls to the account's. 'pr' needs none of this, since it passes -R.
func (a *app) glabRemoteHost() error {
	remote, host := a.originHost(), a.acct.credHost
	if strings.EqualFold(remote, host) || !strings.EqualFold(serviceHost(remote), host) {
		return nil
	}
	if err := setEnv("GITLAB_HOST", "https://"+remote); err != nil {
		return err
	}
	return setEnv("GITLAB_API_HOST", host)
}

// teaVersionRE reads 'tea --version', once ansiRE has taken the bold off the number.
var (
	teaVersionRE = regexp.MustCompile(`^Version:\s*v?(\d+)\.(\d+)`)
	ansiRE       = regexp.MustCompile(`\x1b\[[0-9;]*m`)
)

// teaReadsEnv: tea 0.11 was the first to take its login from GITEA_TOKEN and
// GITEA_INSTANCE_URL. A build that says 'development' counts as older, since
// that is what Debian's 0.9.2 says.
func teaReadsEnv(cli string) bool { return teaVersionReadsEnv(runOut(cli, "--version")) }

func teaVersionReadsEnv(text string) bool {
	m := teaVersionRE.FindStringSubmatch(ansiRE.ReplaceAllString(text, ""))
	if m == nil {
		return false
	}
	// Digits only, from the pattern; Atoi clamps on overflow, which still compares right.
	major, _ := strconv.Atoi(m[1])
	minor, _ := strconv.Atoi(m[2])
	return major > 0 || minor >= 11
}

// teaAsAccount points 'raw tea' at the account. A tea too old for the env login
// uses the first login it has for the host, the same one 'logins list' puts
// first, so only that one being somebody else is a problem. -q can't warn, so it
// refuses. Couldn't tell is not somebody else. Says whether it warned.
func (a *app) teaAsAccount(cli string) (bool, error) {
	// Read before we set it, so this is the caller's own env login.
	callerEnvLogin := os.Getenv("GITEA_INSTANCE_URL") != ""
	gave, err := a.hostTokenEnv("GITEA_TOKEN", "GITEA_INSTANCE_URL")
	if err != nil {
		return false, err
	}
	want := a.accountWho(a.acct.credHost)
	if want == "" || !a.accountDecidedSomething() || (!gave && callerEnvLogin) || (gave && teaReadsEnv(cli)) {
		return false, nil
	}
	got, failure := a.hostLogin(cli, a.acct.credHost)
	if failure != "" || got == "" || strings.EqualFold(got, want) {
		return false, nil
	}
	why := "This tea is older than 0.11 and ignores the account's token."
	fix := noteLines("Fix", "Update tea, or run it anyway with --any-identity.")
	if !gave {
		why = "The account has no token for " + a.acct.credHost + "."
		fix = noteLines("Fix", "Point the account at a file holding a "+a.acct.credHost+" token, or run it anyway with --any-identity:",
			"  "+meName+" account set "+a.acct.name+" tokenfile <file>")
	}
	if a.opt.quiet {
		return false, refusalBlock("tea would act as '"+printable(got)+"', its own login for "+a.acct.credHost+", not as '"+printable(want)+"'.", [][]string{noteLines("Why", why), fix}, nil)
	}
	a.out.warn("WARNING: tea acts as '" + got + "', its own login for " + a.acct.credHost + ", not as '" + want + "'.")
	a.out.notes(append(noteLines("Why", why), fix...))
	return true, nil
}

// hostURL is the canonical URL for 'owner/name' on a host, in one of the two
// transports. The github.com-only version of this is what made 'repo url' - which
// only ever rewrites text - refuse to work on any other host.
func hostURL(host, target, proto string) string {
	if host == "" || target == "" {
		return ""
	}
	if proto == "ssh" {
		return "git@" + host + ":" + target + ".git"
	}
	return "https://" + host + "/" + target + ".git"
}

// githubURL: the canonical github.com URL, for the commands that are about GitHub
// specifically rather than about whatever host this repo happens to use.
func githubURL(target, proto string) string { return hostURL("github.com", target, proto) }

// hostTool is which CLI, if any, speaks the API of the host origin lives on.
// Having none is not a failure in itself - it only becomes one for a command that
// needed it, which is where the message explaining it belongs.
type hostTool int

const (
	toolNone hostTool = iota
	toolGh
	toolTea
	toolGlab
)

// isGitLabHost says whether glab is the right tool for host: gitlab.com, any name
// that starts with a 'gitlab' label (gitlab.gnome.org), or GITLAB_HOST, which is how
// glab itself is pointed at a self-hosted instance. A leading 'ssh.' is not part of
// the name.
func isGitLabHost(host string) bool {
	host = serviceHost(host)
	if host == "" {
		return false
	}
	if strings.HasPrefix(strings.ToLower(host), "gitlab.") {
		return true
	}
	env := os.Getenv("GITLAB_HOST")
	env = strings.TrimPrefix(strings.TrimPrefix(env, "https://"), "http://")
	return env != "" && strings.EqualFold(host, strings.TrimSuffix(env, "/"))
}

// glabRepoArg is the repo path glab is told with -R, taken from origin's URL. Its own
// lookup matches remote host names to GITLAB_HOST, which fails for a remote on
// ssh.<host>, and reads a nested group's path wrong.
func (a *app) glabRepoArg() string {
	_, path, _ := splitRemoteURL(a.originURL())
	return strings.TrimSuffix(strings.TrimSuffix(strings.TrimPrefix(path, "/"), "/"), ".git")
}

// hostToolFor picks the CLI for a host: gh for GitHub and nothing else, tea for any
// other host that has it installed.
func (a *app) hostToolFor(host string) (hostTool, string) {
	switch {
	case isGitHubHost(host):
		if inPath("gh") {
			return toolGh, "gh"
		}
	case isGitLabHost(host):
		if inPath("glab") {
			return toolGlab, "glab"
		}
	case host != "":
		if tea := a.teaCommand(); tea != "" {
			return toolTea, tea
		}
	}
	return toolNone, ""
}

// originTool is the same question about this repo, which is what every caller
// actually wants to know.
func (a *app) originTool() (hostTool, string) { return a.hostToolFor(a.originHost()) }

// hostCLIHint names the tool a host needs and how to get it pointed at one, for
// the refusal that has to explain itself. Kept beside the picker so the two cannot
// drift into recommending different things.
func (a *app) hostCLIHint() string {
	if isGitHubHost(a.originHost()) {
		return "Install gh (https://cli.github.com) and run 'gh auth login'."
	}
	if isGitLabHost(a.originHost()) {
		return "Install glab (https://gitlab.com/gitlab-org/cli) and run 'glab auth login'."
	}
	return "Install Gitea's CLI (https://gitea.com/gitea/tea) and run 'tea login add'." +
		" Some distributions install it as 'tea-cli'; either name is found."
}

// hostAnswer is what tea said about a host: the login it has, or why it could
// not be asked. Both empty means it was asked and has none there.
type hostAnswer struct {
	user    string
	failure string
}

// hostLogin names the account tea has for a host, or nothing, plus tea's reason when it
// failed. From the login list, since 'tea whoami' gives the default login and exits 0
// with none.
func (a *app) hostLogin(cli, host string) (user, failure string) {
	answer := a.host.login.get(func() hostAnswer {
		if cli == "" || host == "" {
			return hostAnswer{}
		}
		list := toolCmd(cli, "logins", "list", "--output", "tsv")
		var errText bytes.Buffer
		list.Stderr = &errText
		out, err := list.Output()
		if err != nil {
			for _, line := range splitLines(errText.String()) {
				if line = strings.TrimSpace(line); line != "" {
					return hostAnswer{failure: line}
				}
			}
			return hostAnswer{failure: err.Error()}
		}
		for _, record := range parseTeaTable(strings.TrimRight(string(out), "\r\n")) {
			if strings.EqualFold(parseRemote(record["url"]).host, host) {
				return hostAnswer{user: record["user"]}
			}
		}
		return hostAnswer{}
	})
	return answer.user, answer.failure
}
