// Host detection and the host CLIs' vocabulary. What these cover is the seam
// where a GitHub-only program learned there are other hosts: getting it wrong
// means running a GitHub client against somebody else's git host, or refusing work
// that never needed a host-specific client at all.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// Only spellings that need no ssh_config lookup: an alias would send this to a
// real ssh, and what the box outside answers is not this test's business.
func TestParseRemote(t *testing.T) { // [dbg5z]
	tests := []struct {
		url, host, owner, name string
	}{
		{"https://github.com/octocat/hello.git", "github.com", "octocat", "hello"},
		{"https://github.com/octocat/hello", "github.com", "octocat", "hello"},
		{"https://user:token@github.com/octocat/hello.git", "github.com", "octocat", "hello"},
		{"git@github.com:octocat/hello.git", "github.com", "octocat", "hello"},
		{"https://git.example.com/octocat/hello.git", "git.example.com", "octocat", "hello"},
		{"https://git.example.com:3000/octocat/hello.git", "git.example.com", "octocat", "hello"},
		// A Gitea served under a subpath: the owner is the segment above the repo,
		// and the instance routing above that says nothing about who owns it.
		{"https://git.example.com/gitea/octocat/hello.git", "git.example.com", "octocat", "hello"},
		// A host with no repo under it still names the host - which is what decides
		// whether a git host CLI is the right tool, independently of the repo.
		{"https://git.example.com/octocat", "git.example.com", "", ""},
		{"/srv/local/repo.git", "", "", ""},
		{`C:\srv\repo`, "", "", ""},
		{"C:/srv/repo", "", "", ""},
		{"", "", "", ""},
	}
	for _, tc := range tests {
		got := parseRemote(tc.url)
		if got.host != tc.host || got.owner != tc.owner || got.name != tc.name {
			t.Errorf("parseRemote(%q) = {%q %q %q}, want {%q %q %q}",
				tc.url, got.host, got.owner, got.name, tc.host, tc.owner, tc.name)
		}
	}
}

// GH_HOST is how gh itself is pointed at an Enterprise instance. Reading it here
// is what keeps an Enterprise user out of the "not GitHub, so no pull requests"
// path they don't belong in.
func TestIsGitHubHost(t *testing.T) { // [dbg60]
	tests := []struct {
		host, ghHost string
		want         bool
	}{
		{"github.com", "", true},
		{"GitHub.com", "", true}, // hostnames don't care about case
		{"git.example.com", "", false},
		{"", "", false},
		{"github.example.com", "github.example.com", true},
		{"github.com", "github.example.com", true}, // GH_HOST adds a host, never removes one
		{"git.example.com", "github.example.com", false},
	}
	for _, tc := range tests {
		t.Setenv("GH_HOST", tc.ghHost)
		if got := isGitHubHost(tc.host); got != tc.want {
			t.Errorf("isGitHubHost(%q) with GH_HOST=%q = %v, want %v", tc.host, tc.ghHost, got, tc.want)
		}
	}
}

func TestHostURL(t *testing.T) { // [dcpv1]
	tests := []struct{ host, target, proto, want string }{
		{"github.com", "octocat/hello", "https", "https://github.com/octocat/hello.git"},
		{"github.com", "octocat/hello", "ssh", "git@github.com:octocat/hello.git"},
		{"git.example.com", "octocat/hello", "https", "https://git.example.com/octocat/hello.git"},
		{"git.example.com", "octocat/hello", "ssh", "git@git.example.com:octocat/hello.git"},
		{"", "octocat/hello", "https", ""},
		{"github.com", "", "https", ""},
	}
	for _, tc := range tests {
		if got := hostURL(tc.host, tc.target, tc.proto); got != tc.want {
			t.Errorf("hostURL(%q, %q, %q) = %q, want %q", tc.host, tc.target, tc.proto, got, tc.want)
		}
	}
}

// tea's tsv writer quotes every cell, header names included. Left quoted, every
// lookup misses and every value takes the quotes into whatever it is compared
// against - which reads as "no such pull request" rather than as a parse problem.
func TestParseTeaTable(t *testing.T) { // [dcpv2]
	out := "\"index\"\t\"head\"\t\"state\"\n\"7\"\t\"feature-x\"\t\"open\"\n\"9\"\t\"acct:forked\"\t\"closed\"\n"
	records := parseTeaTable(out)
	if len(records) != 2 {
		t.Fatalf("parseTeaTable gave %d records, want 2", len(records))
	}
	if records[0]["index"] != "7" || records[0]["head"] != "feature-x" || records[0]["state"] != "open" {
		t.Errorf("first record = %v", records[0])
	}
	if records[1]["state"] != "closed" {
		t.Errorf("second record state = %q, want \"closed\"", records[1]["state"])
	}
	// A header with no rows under it is not a record, and neither is nothing at all.
	// Both have to read as "couldn't tell" rather than as "no such thing".
	for _, empty := range []string{"", "\"index\"\t\"head\"\n", "\n"} {
		if got := parseTeaTable(empty); len(got) != 0 {
			t.Errorf("parseTeaTable(%q) = %v, want none", empty, got)
		}
	}
}

// A head branch on a fork is spelled 'owner:branch'. What we compare against, and
// later hand to git, is the branch on its own.
func TestHeadBranchName(t *testing.T) { // [dbg61]
	tests := []struct{ head, want string }{
		{"feature-x", "feature-x"},
		{"acct:feature-x", "feature-x"},
		{"acct:feature/x", "feature/x"},
		{"", ""},
	}
	for _, tc := range tests {
		if got := headBranchName(tc.head); got != tc.want {
			t.Errorf("headBranchName(%q) = %q, want %q", tc.head, got, tc.want)
		}
	}
}

// An account's credentials are only credentials where that account banks. A config
// that never mentions a host means github.com, because that is all there was when
// every such config was written.
func TestAccountServesHost(t *testing.T) { // [dbg62]
	tests := []struct {
		name, configured, host string
		want                   bool
	}{
		{"unstated host is github.com", "", "github.com", true},
		{"unstated host is not somebody else's", "", "git.example.com", false},
		{"stated host matches", "git.example.com", "git.example.com", true},
		{"stated host is not github.com", "git.example.com", "github.com", false},
		{"hostnames don't care about case", "Git.Example.com", "git.example.com", true},
		{"no host at all serves nothing", "", "", false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			a := newApp(newPrinter())
			a.acct.name = "work"
			a.cfg.values = map[string]string{}
			if tc.configured != "" {
				a.cfg.values["account.work.host"] = tc.configured
			}
			if got := a.accountServesHost(tc.host); got != tc.want {
				t.Errorf("accountServesHost(%q) with host=%q = %v, want %v",
					tc.host, tc.configured, got, tc.want)
			}
		})
	}
}

// The variable a token is exported under. A Gitea token must never end up in
// GH_TOKEN: gh reads that one, and every child process would inherit a credential
// for a host gh will happily try to use it on.
func TestTokenEnvVar(t *testing.T) { // [dbg63]
	if got := tokenEnvVar("github.com"); got != "GH_TOKEN" {
		t.Errorf("tokenEnvVar(github.com) = %q, want GH_TOKEN", got)
	}
	if got := tokenEnvVar("git.example.com"); got == "GH_TOKEN" {
		t.Errorf("tokenEnvVar(git.example.com) = %q, which gh would pick up", got)
	}
}

// gh reads only GH_ENTERPRISE_TOKEN for an Enterprise Server host, and only GH_TOKEN
// for github.com and a *.ghe.com tenant, so the token has to go where gh looks for
// the host it's pointed at. Reproduced against gh 2.96 with GH_HOST set to each.
func TestTokenEnvVarFollowsGhHost(t *testing.T) { // [dfgvm]
	for _, tc := range []struct{ ghHost, host, want string }{
		{"", "github.com", "GH_TOKEN"},
		{"ghe.example.test", "github.com", "GH_TOKEN"},
		{"ghe.example.test", "ghe.example.test", "GH_ENTERPRISE_TOKEN"},
		{"GHE.Example.Test", "ghe.example.test", "GH_ENTERPRISE_TOKEN"},
		{"acme.ghe.com", "acme.ghe.com", "GH_TOKEN"},
		{"github.localhost", "github.localhost", "GH_TOKEN"},
		{"ghe.example.test", "git.example.test", "GITSBY_HOST_TOKEN"},
		{"", "ghe.example.test", "GITSBY_HOST_TOKEN"},
	} {
		t.Setenv("GH_HOST", tc.ghHost)
		if got := tokenEnvVar(tc.host); got != tc.want {
			t.Errorf("GH_HOST=%q: tokenEnvVar(%q) = %q, want %q", tc.ghHost, tc.host, got, tc.want)
		}
	}
}

// The pull-request vocabulary per tool. These are what both the preview and the
// command read, so a disagreement here is a plan promising something else.
func TestPrArgsPerTool(t *testing.T) { // [dbg64]
	for _, tc := range []struct {
		tool  hostTool
		first string
	}{
		{toolGh, "pr"},
		{toolTea, "pulls"},
	} {
		a := newApp(newPrinter())
		a.pr.tool, a.pr.num = tc.tool, "7"
		for label, args := range map[string][]string{
			"list":    a.prListArgs(),
			"approve": a.prApproveArgs(),
			"merge":   a.prMergeArgs(),
		} {
			if len(args) == 0 || args[0] != tc.first {
				t.Errorf("%v %s args = %v, want first word %q", tc.tool, label, args, tc.first)
			}
		}
	}
	// gh deletes the merged branch as part of its own merge; tea does not, so the
	// sweep is a separate call there and must not be invented for gh.
	gh := newApp(newPrinter())
	gh.pr.tool, gh.pr.num = toolGh, "7"
	if got := gh.prCleanArgs(); got != nil {
		t.Errorf("gh prCleanArgs = %v, want none - its merge already deletes the branch", got)
	}
	tea := newApp(newPrinter())
	tea.pr.tool, tea.pr.num = toolTea, "7"
	if got := tea.prCleanArgs(); len(got) == 0 {
		t.Error("tea prCleanArgs is empty, so 'pr ok' would merge and leave the branch standing")
	}
}

// The plan's create line is the run's call with some flags left out, never with
// a flag of its own: every option it names is in the call, with the same value
// after it. glab's base is --target-branch, which a shared --base hid.
func TestPrCreateDispFlags(t *testing.T) { // [dfnbg]
	t.Chdir(t.TempDir()) // glab's -R reads origin, and this repo's isn't the test's
	for _, tool := range []hostTool{toolGh, toolTea, toolGlab} {
		a := newApp(newPrinter())
		a.pr.tool, a.pr.cli, a.pr.sub, a.pr.headBranch, a.pr.title = tool, "cli", "create", "feat", "My title"
		a.git.mergeTarget.set("dev")
		args := a.prCreateArgs()
		// The title is last, and quoted, so it's split off whole.
		front, title, _ := strings.Cut(strings.TrimPrefix(a.prCreateDisp(), "cli "), " --title ")
		disp := append(strings.Fields(front), "--title", title)
		if verb := strings.Fields(a.prCreateVerb()); !slices.Equal(args[:len(verb)], verb) || !slices.Equal(disp[:len(verb)], verb) {
			t.Errorf("tool %d: verb %q, args %q, plan %q", tool, verb, args, disp)
		}
		named := 0
		for i, word := range disp {
			if !strings.HasPrefix(word, "--") || i+1 >= len(disp) {
				continue
			}
			named++
			at := slices.Index(args, word)
			if at < 0 || at+1 >= len(args) || shellWord(args[at+1], word == "--title") != disp[i+1] {
				t.Errorf("tool %d: the plan names %s %s, the call is %q", tool, word, disp[i+1], args)
			}
		}
		if named != 2 {
			t.Errorf("tool %d: plan %q names %d options, want the base and the title", tool, disp, named)
		}
	}
}

// glab's merge deletes only the git host's copy of the branch, so pr ok deletes
// ours after it. gh's merge and tea's clean already take both.
func TestPrLocalCleanArgs(t *testing.T) { // [dfnbh]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "feat")
	runGit(t, clone, "push", "-q", "-u", "origin", "feat")
	runGit(t, clone, "push", "-q", "origin", "feat:other")
	t.Chdir(clone)
	try := func(name string, tool hostTool, head string, want []string) {
		t.Run(name, func(t *testing.T) {
			a := newApp(newPrinter())
			a.pr.tool, a.pr.sub, a.pr.headBranch, a.pr.baseBranch = tool, "ok", head, "main"
			if got := a.prLocalCleanArgs(); !slices.Equal(got, want) {
				t.Errorf("prLocalCleanArgs() = %q, want %q", got, want)
			}
		})
	}
	try("glab, standing on it", toolGlab, "feat", []string{"branch", "-D", "feat"})
	try("gh", toolGh, "feat", nil)
	try("tea", toolTea, "feat", nil)
	try("glab, no local copy", toolGlab, "gone", nil)
	runGit(t, clone, "checkout", "-q", "main")
	try("glab, from elsewhere", toolGlab, "feat", []string{"branch", "-D", "feat"})
	// Standing on it while it tracks another branch, pr ok stays and pulls, so
	// git couldn't delete it.
	runGit(t, clone, "checkout", "-q", "feat")
	runGit(t, clone, "branch", "-q", "--set-upstream-to", "origin/other")
	try("glab, staying on it", toolGlab, "feat", nil)
}

// A fork's PR proposes the fork's branch, which shares at most a name with ours,
// so no tool's merge or clean deletes a branch for it. gh's --delete-branch would
// still take ours. Origin's own branch still goes.
func TestPrForkDeletesNothing(t *testing.T) { // [dfq0v]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "branch", "-q", "feat")
	t.Chdir(clone)
	deletes := map[string]bool{"--delete-branch": true, "--remove-source-branch": true}
	for _, tool := range []hostTool{toolGh, toolTea, toolGlab} {
		for _, fork := range []bool{false, true} {
			a := newApp(newPrinter())
			a.pr.tool, a.pr.num, a.pr.sub, a.pr.headBranch, a.pr.baseBranch, a.pr.fork = tool, "7", "ok", "feat", "main", fork
			merge := a.prMergeArgs()
			deleted := slices.ContainsFunc(merge, func(arg string) bool { return deletes[arg] }) || a.prCleanArgs() != nil || a.prLocalCleanArgs() != nil
			if deleted == fork {
				t.Errorf("tool %d, fork %v: merge %q, clean %q, local clean %q", tool, fork, merge, a.prCleanArgs(), a.prLocalCleanArgs())
			}
			if len(merge) < 3 || merge[2] != "7" {
				t.Errorf("tool %d, fork %v: merge %q doesn't name the PR", tool, fork, merge)
			}
		}
	}
}

// 'pr <n>' is the PR and its diff. gh takes a call for each; tea's detail view
// has the diff in one.
func TestPrViewArgsPerTool(t *testing.T) { // [dd5ga]
	for _, tc := range []struct {
		name string
		tool hostTool
		want [][]string
	}{
		{"gh", toolGh, [][]string{{"pr", "view", "7"}, {"pr", "diff", "7"}}},
		{"tea", toolTea, [][]string{{"pulls", "7", "--fields", teaDetailFields}}},
	} {
		a := newApp(newPrinter())
		a.pr.tool, a.pr.num = tc.tool, "7"
		if got := a.prViewArgs(); !slices.EqualFunc(got, tc.want, slices.Equal) {
			t.Errorf("%s prViewArgs = %q, want %q", tc.name, got, tc.want)
		}
	}
	if !strings.Contains(teaDetailFields, "diff") {
		t.Errorf("tea's detail fields %q leave out the diff", teaDetailFields)
	}
}

// And the command runs every call, not just the first.
func TestCmdPrViewRunsEachCall(t *testing.T) { // [dd5gb]
	if !inPath("true") {
		t.Skip("no 'true' to stand in for gh")
	}
	p, out, _ := testPrinter()
	a := newApp(p)
	a.pr.tool, a.pr.num, a.pr.cli = toolGh, "7", "true"
	if err := a.cmdPrView(); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"true pr view 7 ...", "true pr diff 7 ..."} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("%q never ran %q", out, want)
		}
	}
}

// Which login the identity gate compares against. 'ghAccount' is a GitHub login and
// says nothing about who you are anywhere else, so keying the gate on it alone left
// every non-GitHub account uncompared - which is a gate that quietly stopped
// guarding rather than one that said it could not.
func TestAccountWho(t *testing.T) { // [dbg6d]
	tests := []struct {
		name, ghAccount, user, host, want string
	}{
		{"ghAccount answers for GitHub", "alice", "", "github.com", "alice"},
		{"and for nowhere else", "alice", "", "git.example.test", ""},
		{"user answers for any host", "", "gitfriend", "git.example.test", "gitfriend"},
		{"user wins where both are given", "alice", "gitfriend", "github.com", "gitfriend"},
		{"nothing named is no claim to check", "", "", "git.example.test", ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			a := newApp(newPrinter())
			a.acct.name, a.acct.ghWho = "work", tc.ghAccount
			a.cfg.values = map[string]string{}
			if tc.user != "" {
				a.cfg.values["account.work.user"] = tc.user
			}
			if got := a.accountWho(tc.host); got != tc.want {
				t.Errorf("accountWho(%q) = %q, want %q", tc.host, got, tc.want)
			}
		})
	}
}

// The write gate reads whichever CLI this run goes through. Unknown must stay
// unknown: a tea with no login for the host has said nothing about who you are, and
// refusing on that would refuse every machine that never configured one.
func TestHostCLIWho(t *testing.T) { // [dcpv3]
	none := newApp(newPrinter())
	none.remote.tool = toolNone
	if got := none.hostCLIWho(); got != "?" {
		t.Errorf("hostCLIWho with no tool = %q, want ?", got)
	}
	// A tea that answers nothing is '?', not the empty string - the mismatch test
	// reads '?' as "couldn't tell" and an empty name would too, but only one of them
	// survives being concatenated into a message.
	tea := newApp(newPrinter())
	tea.remote.tool, tea.remote.cli = toolTea, "tea"
	tea.host.login.set(hostAnswer{})
	if got := tea.hostCLIWho(); got != "?" {
		t.Errorf("hostCLIWho with no tea login = %q, want ?", got)
	}
	tea.host.login.set(hostAnswer{failure: "tea config is unreadable"})
	if got := tea.hostCLIWho(); got != "?" {
		t.Errorf("hostCLIWho when tea failed = %q, want ?", got)
	}
	tea.host.login.set(hostAnswer{user: "gitfriend"})
	if got := tea.hostCLIWho(); got != "gitfriend" {
		t.Errorf("hostCLIWho = %q, want gitfriend", got)
	}
}

// A tea that failed is not a tea with no login, and only a login tea named is
// compared with the ssh key's account. "No login" is not a login called that.
// Every unknown is "(unknown - why)", the SSH line's form.
func TestShowHostLine(t *testing.T) { // [dcpv4]
	tests := []struct {
		name    string
		answer  hostAnswer
		offline bool
		has     string
		lacks   []string
	}{
		{"a login", hostAnswer{user: "gitfriend"}, false, "(tea): gitfriend  <-- NOT the ssh key's account ('alice')", nil},
		{"no login", hostAnswer{}, false, "(tea): (unknown - 'tea login add' has no login for this host)\n", []string{"NOT the ssh key"}},
		{"tea failed", hostAnswer{failure: "tea config is unreadable"}, false, "(tea): (unknown - couldn't ask tea: tea config is unreadable)\n", []string{"login add", "NOT the ssh key"}},
		{"offline", hostAnswer{user: "gitfriend"}, true, "(tea): (unknown - offline, so tea wasn't asked)\n", []string{"gitfriend"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			p, out, _ := testPrinter()
			a := newApp(p)
			a.git.originRef.set(remoteRef{host: "git.example.test", owner: "acme", name: "proj"})
			a.host.tea.set("tea")
			a.host.login.set(tc.answer)
			a.remote.isWrite, a.remote.probeURL = true, "git@git.example.test:acme/proj.git"
			a.remote.sshLogins = map[string]string{a.remote.probeURL: "alice"}
			a.remote.offline = tc.offline
			a.showHostLine()
			if !strings.Contains(out.String(), tc.has) {
				t.Errorf("%q does not say %q", out, tc.has)
			}
			for _, s := range tc.lacks {
				if strings.Contains(out.String(), s) {
					t.Errorf("%q says %q", out, s)
				}
			}
		})
	}
}

// tea bolds the number, and a build with no version stamped says 'development',
// which is also what Debian's 0.9.2 says.
func TestTeaVersionReadsEnv(t *testing.T) { // [ddk62]
	tests := []struct {
		text string
		want bool
	}{
		{"Version: \x1b[1m0.11.0\x1b[0m\tgolang: 1.24.4", true},
		{"Version: \x1b[1mv0.16.0\x1b[0m\tgolang: 1.26.1", true},
		{"Version: 1.0.0\tgolang: 1.26.1", true},
		{"Version: \x1b[1m0.10.1\x1b[0m\tgolang: 1.23.0", false},
		{"Version: \x1b[1mdevelopment\x1b[0m\tgolang: 1.24.4", false},
		{"", false},
	}
	for _, tc := range tests {
		if got := teaVersionReadsEnv(tc.text); got != tc.want {
			t.Errorf("teaVersionReadsEnv(%q) = %v, want %v", tc.text, got, tc.want)
		}
	}
}

// tea falls back to GH_TOKEN and glab sends its token to whatever host it is
// told, so a GitHub token handed on would go to somebody else's server.
func TestHostTokenEnvKeepsGitHubTokens(t *testing.T) { // [ddk63]
	testGrant(t, "github.com", "tok_gh")
	if gave := hostTokenEnv("tea", "GITEA_TOKEN", "GITEA_INSTANCE_URL"); gave || grantVar("tea", "GITEA_TOKEN") != "" {
		t.Fatalf("a GitHub token was handed on: gave=%v", gave)
	}
	testGrant(t, "git.example.test", "tok_gitea")
	if gave := hostTokenEnv("tea", "GITEA_TOKEN", "GITEA_INSTANCE_URL"); !gave {
		t.Fatal("a Gitea token was not handed on")
	}
	if grantVar("tea", "GITEA_TOKEN") != "tok_gitea" || grantVar("tea", "GITEA_INSTANCE_URL") != "https://git.example.test" {
		t.Errorf("got GITEA_TOKEN=%q GITEA_INSTANCE_URL=%q", grantVar("tea", "GITEA_TOKEN"), grantVar("tea", "GITEA_INSTANCE_URL"))
	}
}

// testGrant gives this test a grant, and takes it back after.
func testGrant(t *testing.T, host, token string) {
	t.Helper()
	setGrant(host, token)
	t.Cleanup(func() { setGrant("", "") })
}

// grantVar is the value tool gets for key from the grant, the last one given.
func grantVar(tool, key string) string {
	value := ""
	for _, kv := range grantEnv(tool) {
		if k, v, _ := strings.Cut(kv, "="); k == key {
			value = v
		}
	}
	return value
}

// 'glab auth status' with no host walks every host glab knows, and gitlab.com
// would see a token that belongs to another server.
func TestGlabScopeAuth(t *testing.T) { // [de9ja]
	h := "gitlab.example.test"
	for _, c := range []struct{ in, want string }{
		{"auth status", "auth status --hostname gitlab.example.test"},
		{"auth status --hostname other.test", "auth status --hostname other.test"},
		{"auth status -h other.test", "auth status -h other.test"},
		{"auth status --hostname=other.test", "auth status --hostname=other.test"},
		{"mr list", "mr list"},
		{"auth", "auth"},
	} {
		if got := strings.Join(glabScopeAuth(strings.Fields(c.in), h), " "); got != c.want {
			t.Errorf("%q -> %q, want %q", c.in, got, c.want)
		}
	}
}

// Each spelling glab takes a host in, checked against glab 1.53.
func TestGlabNamedHosts(t *testing.T) { // [df4w4]
	for _, c := range []struct{ in, want string }{
		{"api --hostname gitlab.com user", "gitlab.com"},
		{"api user --hostname=gitlab.com", "gitlab.com"},
		{"auth status -h gitlab.com", "gitlab.com"},
		{"mr list -R gitlab.com/someone/else", "gitlab.com"},
		{"mr list -Rgitlab.com/a/b", "gitlab.com"},
		{"mr list -R=gitlab.com/a/b", "gitlab.com"},
		{"mr list --repo https://gitlab.com/a/b", "gitlab.com"},
		{"mr list --repo=git@gitlab.com:a/b.git", "gitlab.com"},
		{"issue view https://gitlab.com/a/b/-/issues/1", "gitlab.com"},
		{"api https://gitlab.com/api/v4/user", "gitlab.com"},
		{"repo clone gitlab.com/a/b", "gitlab.com"},
		{"repo clone git@ssh.gitlab.gnome.org:a/b.git ./my.dir/x/y", "ssh.gitlab.gnome.org"},
		{"mr list -R a.b/c/d", "a.b"},
		{"mr list -R grp/sub/proj", ""},
		{"mr list -R someone/else", ""},
		{"mr list", ""},
		{"mr list -R", ""},
		{"mr create --label priority:high --title a.b/c/d", ""},
		{"release upload v1 out.d/x/y.tgz", ""},
		{"api projects/:id/merge_requests", ""},
		{"api projects/:id/hooks -f url=https://ci.other.test/hook", ""},
		{"mr create --description https://other.test/x", "other.test"},
		{"mr note 1 -m see:https://other.test", ""},
	} {
		if got := strings.Join(glabNamedHosts(strings.Fields(c.in)), " "); got != c.want {
			t.Errorf("%q -> %q, want %q", c.in, got, c.want)
		}
	}
}

// glab sends GITLAB_TOKEN to whatever host it's pointed at, so the token goes only
// with the API pinned to the account's host, and not at all when pointed elsewhere.
func TestGlabTokenEnvStaysHome(t *testing.T) { // [df4w5]
	host := "gitlab.example.test"
	for _, c := range []struct {
		args, callerAPI string
		gave            bool
		elsewhere       string
	}{
		{"api user", "", true, ""},
		{"mr list -R gitlab.example.test/a/b", "", true, ""},
		{"mr list -R https://www.GitLab.example.test/a/b", "", true, ""},
		{"repo clone git@ssh.gitlab.example.test:a/b.git", "", true, ""},
		{"api user", "https://gitlab.example.test/", true, ""},
		{"api --hostname gitlab.com user", "", false, "gitlab.com"},
		{"mr list -R gitlab.com/someone/else", "", false, "gitlab.com"},
		{"repo clone https://other.test/a/b", "", false, "other.test"},
		{"api user", "gitlab.com", false, "gitlab.com"},
	} {
		t.Setenv("GITLAB_API_HOST", c.callerAPI)
		testGrant(t, host, "tok_gl")
		a := newApp(newPrinter())
		a.acct.credHost = host
		gave, elsewhere := a.glabTokenEnv(strings.Fields(c.args))
		if gave != c.gave || elsewhere != c.elsewhere {
			t.Errorf("%q api=%q: gave=%v elsewhere=%q, want %v %q", c.args, c.callerAPI, gave, elsewhere, c.gave, c.elsewhere)
			continue
		}
		tok, gl, api := grantVar("glab", "GITLAB_TOKEN"), grantVar("glab", "GITLAB_HOST"), grantVar("glab", "GITLAB_API_HOST")
		if gave && (tok != "tok_gl" || gl != "https://"+host || api != host) {
			t.Errorf("%q: GITLAB_TOKEN=%q GITLAB_HOST=%q GITLAB_API_HOST=%q", c.args, tok, gl, api)
		}
		if !gave && (tok != "" || gl != "" || api != "") {
			t.Errorf("%q: glab granted variables with no token given: %q %q %q", c.args, tok, gl, api)
		}
		if os.Getenv("GITLAB_TOKEN") == "tok_gl" {
			t.Errorf("%q: GITLAB_TOKEN went into the process's own environment", c.args)
		}
	}
}

// gh takes a host the ways glab does, but reads any 3-part -R as one, and a bare
// argument only where it's a repo. Checked against gh 2.96.
func TestGhNamedHosts(t *testing.T) { // [dfh5v]
	for _, c := range []struct{ in, want string }{
		{"auth token --hostname evil.example", "evil.example"},
		{"auth token -h evil.example", "evil.example"},
		{"api --hostname=evil.example user", "evil.example"},
		{"pr list -R evil.example/a/b", "evil.example"},
		{"pr list -R ghe/a/b", "ghe"},
		{"pr list --repo https://evil.example/a/b", "evil.example"},
		{"pr view https://evil.example/a/b/pull/1", "evil.example"},
		{"repo clone evil.example/a/b", "evil.example"},
		{"repo clone git@evil.example:a/b.git", "evil.example"},
		{"issue transfer 1 evil.example/a/b", "evil.example"},
		{"repo clone a/b ./x/y", ""},
		{"repo clone a/b some/deep/dir", ""},
		{"pr list -R a/b", ""},
		{"pr list", ""},
		{"release upload v1 out.d/x/y.tgz", ""},
		{"api repos/a/b/hooks -f url=https://ci.other.test/hook", ""},
	} {
		if got := strings.Join(ghNamedHosts(strings.Fields(c.in)), " "); got != c.want {
			t.Errorf("%q -> %q, want %q", c.in, got, c.want)
		}
	}
}

// gh hands GH_TOKEN or GH_ENTERPRISE_TOKEN to any host its rule covers, so gh gets the
// token only while every host it's pointed at is the one the token is for.
func TestGhTokenStaysHome(t *testing.T) { // [dfh5w]
	for _, c := range []struct{ cred, args, ghHost, ghRepo, elsewhere string }{
		{"ghe.example.test", "auth token", "ghe.example.test", "", ""},
		{"ghe.example.test", "auth token --hostname evil.example", "ghe.example.test", "", "evil.example"},
		{"ghe.example.test", "pr list -R evil.example/a/b", "ghe.example.test", "", "evil.example"},
		{"ghe.example.test", "pr list -R GHE.example.test/a/b", "ghe.example.test", "", ""},
		{"ghe.example.test", "pr list", "ghe.example.test", "evil.example/a/b", "evil.example"},
		{"ghe.example.test", "pr list", "ghe.example.test", "a/b", ""},
		{"github.com", "api user", "", "", ""},
		{"github.com", "auth token --hostname acme.ghe.com", "", "", "acme.ghe.com"},
		{"github.com", "auth token --hostname github.localhost", "", "", "github.localhost"},
		{"github.com", "api user", "acme.ghe.com", "", "acme.ghe.com"},
	} {
		t.Setenv("GH_HOST", c.ghHost)
		t.Setenv("GH_REPO", c.ghRepo)
		a := newApp(newPrinter())
		a.acct.credHost, a.acct.toolHosts = c.cred, ghNamedHosts(strings.Fields(c.args))
		if got := a.tokenElsewhere(a.ghPointedAt()); got != c.elsewhere {
			t.Errorf("%s: %q GH_HOST=%q GH_REPO=%q -> %q, want %q", c.cred, c.args, c.ghHost, c.ghRepo, got, c.elsewhere)
		}
	}
}

// The helper account apply writes checks the host in sh, since git runs it without
// us. It has to agree with sameService on every host as git hands it over.
func TestFragmentHelperHostCheck(t *testing.T) { // [dfh5x]
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("no sh")
	}
	fakeTool(t, "git", `case "$*" in
"config --global --includes --get gitsby.host") echo "$FAKE_TOKEN_HOST" ;;
"config --global --includes --get gitsby.ghTokenFile") echo "$FAKE_TOKEN_FILE" ;;
esac`)
	file := filepath.ToSlash(filepath.Join(t.TempDir(), "tok"))
	if err := os.WriteFile(file, []byte("tok_helper\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("FAKE_TOKEN_FILE", file)
	helper := strings.TrimPrefix(fragmentHelper(false), "!")
	for _, c := range []struct{ asked, tokenHost string }{
		{"gitea.example.test", "gitea.example.test"},
		{"Gitea.Example.TEST", "gitea.example.test"},
		{"github.com", "gitea.example.test"},
		{"gitea.example.test", "github.com"},
		{"git.example.test:3000", "git.example.test:3000"},
		{"git.example.test:3000", "git.example.test"},
		{"git.example.test", ""},
		{"", "git.example.test"},
	} {
		t.Setenv("FAKE_TOKEN_HOST", c.tokenHost)
		cmd := exec.Command(sh, "-c", helper+` "$@"`, "helper", "get")
		cmd.Stdin = strings.NewReader("protocol=https\nhost=" + c.asked + "\n\n")
		out, err := cmd.Output()
		if err != nil {
			t.Fatalf("%q: %v", c.asked, err)
		}
		gave, want := strings.Contains(string(out), "password=tok_helper"), sameService(c.asked, c.tokenHost)
		if gave != want {
			t.Errorf("asked for %q with gitsby.host %q: gave a token %v, sameService says %v", c.asked, c.tokenHost, gave, want)
		}
	}
}

func TestServiceHost(t *testing.T) { // [de9k6]
	for in, want := range map[string]string{
		"ssh.gitlab.gnome.org": "gitlab.gnome.org",
		"ssh.github.com":       "github.com",
		"gitlab.gnome.org":     "gitlab.gnome.org",
		"ssh.local":            "ssh.local",
		"ssh":                  "ssh",
		"":                     "",
	} {
		if got := serviceHost(in); got != want {
			t.Errorf("%q -> %q, want %q", in, got, want)
		}
	}
}

// glab finds the repo only through a remote on GITLAB_HOST, so a remote on the
// account host's ssh name gets that name there, and the API keeps the account host.
func TestGlabRemoteHost(t *testing.T) { // [dea3n]
	for _, c := range []struct{ remote, host, wantHost, wantAPI string }{
		{"ssh.gitlab.example.test", "gitlab.example.test", "https://ssh.gitlab.example.test", "gitlab.example.test"},
		{"gitlab.example.test", "gitlab.example.test", "", ""},
		{"GitLab.example.test", "gitlab.example.test", "", ""},
		{"ssh.other.test", "gitlab.example.test", "", ""},
		{"", "gitlab.example.test", "", ""},
	} {
		testGrant(t, c.host, "tok_gl")
		a := newApp(newPrinter())
		a.acct.credHost = c.host
		a.git.originRef.set(remoteRef{host: c.remote, owner: "grp", name: "proj"})
		a.glabRemoteHost()
		if got, api := grantVar("glab", "GITLAB_HOST"), grantVar("glab", "GITLAB_API_HOST"); got != c.wantHost || api != c.wantAPI {
			t.Errorf("%q: GITLAB_HOST=%q GITLAB_API_HOST=%q, want %q %q", c.remote, got, api, c.wantHost, c.wantAPI)
		}
	}
}

func TestIsGitLabHost(t *testing.T) { // [dea1b]
	t.Setenv("GITLAB_HOST", "https://code.example.test/")
	for host, want := range map[string]bool{
		"gitlab.com":           true,
		"gitlab.gnome.org":     true,
		"ssh.gitlab.gnome.org": true,
		"GitLab.example.test":  true,
		"code.example.test":    true,
		"github.com":           false,
		"git.example.test":     false,
		"mygitlab.test":        false,
		"":                     false,
	} {
		if got := isGitLabHost(host); got != want {
			t.Errorf("%q: got %v, want %v", host, got, want)
		}
	}
}

// glab's JSON is read by hand, so key order, spacing, escapes and nesting are
// all the reader's to get right. A nested "state" is the author's, not the MR's.
func TestReadGlabMR(t *testing.T) { // [df04m]
	for _, c := range []struct {
		in   string
		list bool
		ok   bool
		want glabMR
	}{
		{`{"iid":7,"state":"opened","source_branch":"feat"}`, false, true, glabMR{"7", "opened", "feat", "", "", ""}},
		{"\n {\n\t\"source_branch\" : \"feat\" ,\r\n \"state\":\"merged\", \"iid\" : 12 }\n", false, true, glabMR{"12", "merged", "feat", "", "", ""}},
		{`{"author":{"state":"active","id":3},"labels":["a","b"],"state":"opened","source_branch":"feat"}`, false, true, glabMR{"", "opened", "feat", "", "", ""}},
		{`{"title":"a \"quoted\", title}","source_branch":"x\"y,z","state":"opened"}`, false, true, glabMR{"", "opened", `x"y,z`, "", "", ""}},
		{`{"source_branch":"café\/\\ 😀","state":"opened"}`, false, true, glabMR{"", "opened", "café/\\ \U0001F600", "", "", ""}},
		{`{"draft":false,"merged_at":null,"x":-1.5e3,"state":"closed","source_branch":"b"}`, false, true, glabMR{"", "closed", "b", "", "", ""}},
		{`[{"iid":3,"source_branch":"a"},{"iid":4}]`, true, true, glabMR{"3", "", "a", "", "", ""}},
		{`{"source_branch":"hotfix/x","author":{"target_branch":"no"},"target_branch":"dev","state":"opened"}`, false, true, glabMR{"", "opened", "hotfix/x", "dev", "", ""}},
		{`{"target_branch":null}`, false, false, glabMR{}},
		{`[]`, true, false, glabMR{}},
		{` [ ] `, true, false, glabMR{}},
		{`{}`, false, true, glabMR{}},
		{``, false, false, glabMR{}},
		{`[{"iid":3}]`, false, false, glabMR{}},
		{`{"iid":3}`, true, false, glabMR{}},
		{`{"iid":3,}`, false, false, glabMR{}},
		{`{"iid":3}x`, false, false, glabMR{}},
		{`{"iid":"3"}`, false, false, glabMR{}},
		{`{"iid":3.5}`, false, false, glabMR{}},
		{`{"state":null}`, false, false, glabMR{}},
		{`{"x":tru,"state":"opened"}`, false, false, glabMR{}},
		{`{"x":[1,],"state":"opened"}`, false, false, glabMR{}},
		{`{"source_branch":"a` + "\n" + `b"}`, false, false, glabMR{}},
		{`{"source_branch":"a\qb"}`, false, false, glabMR{}},
		{`{"source_branch":"a\u00"}`, false, false, glabMR{}},
		{`{"source_branch":"a`, false, false, glabMR{}},
		{`{"x":` + strings.Repeat("[", 2000) + strings.Repeat("]", 2000) + `}`, false, false, glabMR{}},
		{`{"iid":9,"source_project_id":41,"target_project_id":7,"author":{"source_project_id":7},"source_branch":"main","target_branch":"dev"}`, false, true, glabMR{"9", "", "main", "dev", "41", "7"}},
		{`{"source_project_id":7,"target_project_id":7}`, false, true, glabMR{"", "", "", "", "7", "7"}},
		{`{"source_project_id":"41"}`, false, false, glabMR{}},
		{`{"source_project_id":-4}`, false, false, glabMR{}},
		{`{"target_project_id":null}`, false, false, glabMR{}},
	} {
		got, ok := readGlabMR(c.in, c.list)
		if ok != c.ok || got != c.want {
			t.Errorf("readGlabMR(%q, %v) = %+v, %v; want %+v, %v", c.in, c.list, got, ok, c.want, c.ok)
		}
	}
}

// A Fix that names an account key spells it the way 'account set' and the file
// take it. tokenFile came back in 3 notes after the key went lower case.
func TestFixKeysAreSetFields(t *testing.T) { // [df366]
	files, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatal(err)
	}
	keyRE := regexp.MustCompile(`account set "\s*\+[^+]+\+\s*" (\w+)`)
	seen := 0
	for _, f := range files {
		if strings.HasSuffix(f, "_test.go") {
			continue
		}
		body, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		for _, m := range keyRE.FindAllStringSubmatch(string(body), -1) {
			seen++
			if !slices.Contains(accountSetFields, m[1]) {
				t.Errorf("%s: 'account set <name> %s' isn't a key 'account set' takes", f, m[1])
			}
		}
	}
	if seen == 0 {
		t.Fatal("no 'account set <name> <key>' literal found; the pattern no longer matches the source")
	}
}

// One grant per run: each host CLI gets its own variable in its own environment,
// the tools that run git get the helper's, and nothing goes into the process's own.
// gh's variable in git's environment went on to any Enterprise host through the
// helper 'gh auth setup-git' writes (2026112017135870).
func TestGrantGoesOnlyToItsTool(t *testing.T) { // [dfjxb]
	testGrant(t, "ghe.example.test", "tok_grant")
	grantFor("gh", "GH_ENTERPRISE_TOKEN=tok_grant")
	grantFor("glab", "GITLAB_TOKEN=tok_grant")
	grantFor("tea", "GITEA_TOKEN=tok_grant")
	own := map[string]string{"gh": "GH_ENTERPRISE_TOKEN", "glab": "GITLAB_TOKEN", "tea": "GITEA_TOKEN"}
	for _, tool := range []string{"git", "tig", "lazygit", "gh", "glab", "tea", "tea-cli", "/usr/bin/git", `C:\Git\cmd\GIT.EXE`, "ssh", "sh", "tput"} {
		key := toolKey(tool)
		for _, v := range []string{"GH_TOKEN", "GH_ENTERPRISE_TOKEN", "GITLAB_TOKEN", "GITEA_TOKEN", hostTokenVar} {
			want := own[key] == v || (v == hostTokenVar && gitRunners[key])
			if got := grantVar(tool, v) == "tok_grant"; got != want {
				t.Errorf("%s gets %s: %v, want %v", tool, v, got, want)
			}
		}
	}
	for _, kv := range os.Environ() {
		if strings.Contains(kv, "tok_grant") {
			t.Errorf("the grant is in the process's own environment: %s", kv)
		}
	}
}

// The spawn sites, run: git gets the helper's variable and none of gh's or glab's,
// also under remoteEnv, and gh gets its own.
func TestGrantReachesChildren(t *testing.T) { // [dfjxc]
	show := `echo "ghe=${GH_ENTERPRISE_TOKEN:-} gl=${GITLAB_TOKEN:-} host=${GITSBY_HOST_TOKEN:-}"`
	fakeTool(t, "git", show)
	fakeTool(t, "gh", show)
	testGrant(t, "ghe.example.test", "tok_grant")
	grantFor("gh", "GH_ENTERPRISE_TOKEN=tok_grant")
	grantFor("glab", "GITLAB_TOKEN=tok_grant")
	if got := runOut("git"); got != "ghe= gl= host=tok_grant" {
		t.Errorf("git got %q", got)
	}
	cmd := toolCmd("git")
	cmd.Env = newApp(newPrinter()).remoteEnv()
	if out, _ := cmd.Output(); strings.TrimSpace(string(out)) != "ghe= gl= host=tok_grant" {
		t.Errorf("git under remoteEnv got %q", out)
	}
	if got := runOut("gh"); got != "ghe=tok_grant gl= host=tok_grant" {
		t.Errorf("gh got %q", got)
	}
	if got := probeGhLogin(context.Background(), toolEnv("gh")); got != "ghe=tok_grant gl= host=tok_grant" {
		t.Errorf("the gh login probe got %q", got)
	}
}

// The host ends at the first '/', '?' or '#', as net/url and git read it, so a '?@'
// or '#@' can't put the account's host where the token check reads it
// (2026112017135807).
func TestSplitRemoteURLHostEnds(t *testing.T) { // [dfjxd]
	for _, c := range []struct{ in, host, path string }{
		{"http://127.0.0.1:8080?@ghe.example.test/x", "127.0.0.1", ""},
		{"http://127.0.0.1:8080#@ghe.example.test/x", "127.0.0.1", ""},
		{"https://evil.test?@github.com/acme/proj.git", "evil.test", ""},
		{"https://evil.test/?@github.com/acme/proj.git", "evil.test", ""},
		{"https://user@github.com/acme/proj.git", "github.com", "acme/proj.git"},
		{"https://a@b@github.com/acme/proj", "github.com", "acme/proj"},
		{"https://github.com/acme/proj.git?x=1#y", "github.com", "acme/proj.git"},
		{"ssh://git@[::1]:22/acme/proj.git", "::1", "acme/proj.git"},
		{"ssh://git@host.test:owner/proj.git", "host.test", "proj.git"},
		{"ssh://git@host.test?@github.com/acme/proj.git", "host.test", ""},
		{"git@github.com:acme/proj.git", "github.com", "acme/proj.git"},
	} {
		if host, path, _ := splitRemoteURL(c.in); host != c.host || path != c.path {
			t.Errorf("%q -> %q %q, want %q %q", c.in, host, path, c.host, c.path)
		}
	}
	a := newApp(newPrinter())
	a.acct.credHost = "ghe.example.test"
	for _, arg := range []string{"http://127.0.0.1:9?@ghe.example.test/x", "http://127.0.0.1:9#@ghe.example.test/x"} {
		if x := a.tokenElsewhere(ghNamedHosts([]string{"api", arg})); x != "127.0.0.1" {
			t.Errorf("gh api %q: elsewhere %q, want 127.0.0.1", arg, x)
		}
		if x := a.tokenElsewhere(glabNamedHosts([]string{"api", arg})); x != "127.0.0.1" {
			t.Errorf("glab api %q: elsewhere %q, want 127.0.0.1", arg, x)
		}
	}
}

// An account whose host was ignored names no host its token is for, so it gets no
// token and no helper anywhere, rather than github.com's (2026112017135838).
func TestIgnoredHostBanksNowhere(t *testing.T) { // [dfjxe]
	file := filepath.ToSlash(filepath.Join(t.TempDir(), "gt.tok"))
	for _, host := range []string{"https://gitea.example.test", "gitea.example.test:3000"} {
		a := newApp(newPrinter())
		a.cfg = writeConfig(t, "account: bad\n\thost: "+host+"\n\tuser: gtuser\n\ttokenfile: "+file+"\n\naccount: good\n\ttokenfile: "+file+"\n")
		if got := a.cfg.hostOf("bad"); got != "" {
			t.Errorf("%s: hostOf = %q, want nothing", host, got)
		}
		if got := a.cfg.hostOf("good"); got != "github.com" {
			t.Errorf("%s: an account with no host is %q, want github.com", host, got)
		}
		a.acct.name = "bad"
		if a.accountServesHost("github.com") {
			t.Errorf("%s: the account serves github.com", host)
		}
		for _, k := range a.fragmentKeys("bad") {
			if k.value != "" && (strings.HasPrefix(k.key, "credential.") || strings.HasPrefix(k.key, "gitsby.")) {
				t.Errorf("%s: the fragment sets %s = %q", host, k.key, k.value)
			}
		}
	}
}

// gh answers 'auth token --user' for GH_HOST's host when none is named, so a
// github.com account took the token gh holds for the same login on Enterprise
// (2026112017135855).
func TestGhTokenAskedForItsHost(t *testing.T) { // [dfjxf]
	fakeTool(t, "gh", `echo "$*"`)
	if got := probeGhToken("github.com", "jim"); got != "auth token --user jim --hostname github.com" {
		t.Errorf("asked %q", got)
	}
	if got := probeGhToken("", "jim"); got != "" {
		t.Errorf("asked with no host: %q", got)
	}
	if !strings.Contains(fragmentHelper(true), `gh auth token --user "$u" --hostname "$h"`) {
		t.Error("the fragment helper asks gh with no host")
	}
}
