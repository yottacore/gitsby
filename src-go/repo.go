// The repo lifecycle commands: clone, create, connect, url. Everything they need
// settles before the plan is shown - which remote, which directory, which mode -
// so a bad argument or an unreachable target refuses up front, and the preview
// promises only what will actually run.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// repoTarget is what create, connect, clone and url settled about the remote
// before their plan was printed.
type repoTarget struct {
	cloneURL    string
	cloneDir    string
	connectMode string // "create" | "add" | "push"; what create and connect disagree about
	connectURL  string
	ghTarget    string // 'owner/name' when gh is the one doing the creating or answering
}

// repoExistence is what we could establish about a remote. Unknown is its own
// answer, not a synonym for missing: gh exits nonzero for a name that resolves to
// nothing and for a network that is down alike, and stating the first when it was
// the second sends you off to create something you already have.
type repoExistence int

const (
	repoUnknown repoExistence = iota
	repoMissing
	repoEmpty
	repoNonEmpty
)

var ownerNameRE = regexp.MustCompile(`^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)

// lsRemoteAbsentRE is git's wording for a host that was reached and said no. A
// credential prompt counts, since git asks only after a 401, as GitHub and Gitea give
// for no repo.
var lsRemoteAbsentRE = regexp.MustCompile(`does not appear to be a git repository|Repository not found\.|(?m:^fatal: repository '.*' not found$)|could not read (?:Username|Password) for '|Authentication failed for '`)

// isLocalPath: a remote that is a directory on this machine, rather than
// something to connect to.
func isLocalPath(url string) bool {
	if url == "" {
		return false
	}
	if isDrivePath(url) { // a Windows drive path is not 'host:path'
		return true
	}
	if strings.Contains(url, "://") {
		return false
	}
	if strings.Index(url, ":") >= 1 { // scp-like host:path, with or without a user
		return false
	}
	return true
}

// sameRemote: whether 2 remote URLs name the same place. git stores a local path in the
// platform's spelling, '/c/tmp/x' as 'C:/tmp/x' on Windows.
func sameRemote(a, b string) bool {
	if a == "" || b == "" {
		return false
	}
	if a == b {
		return true
	}
	if !isLocalPath(a) || !isLocalPath(b) {
		return false
	}
	return canonPath(a) == canonPath(b)
}

// probeRemote is one round trip: does the remote exist, and does it have history? Under
// remoteEnv. Missing only when git's words say the host said no; else unknown, with
// git's reason.
func (a *app) probeRemote(url string) (repoExistence, string) {
	probe := toolCmd("git", "ls-remote", url)
	probe.Env = a.remoteEnv()
	var errText bytes.Buffer
	probe.Stderr = &errText
	out, err := probe.Output()
	if err != nil {
		return lsRemoteFailure(errText.String(), err)
	}
	if strings.TrimRight(string(out), "\r\n") != "" {
		return repoNonEmpty, ""
	}
	return repoEmpty, ""
}

// lsRemoteFailure reads why ls-remote failed. Only git's wording for a host that
// answered no counts as missing: a network that is down, a host key ssh refused
// and a git that never started are all "couldn't tell", and the reason goes back
// to the reader.
func lsRemoteFailure(said string, err error) (repoExistence, string) {
	// Joined after splitLines, so a CRLF answer still meets the '$' anchor.
	lines := splitLines(said)
	if lsRemoteAbsentRE.MatchString(strings.Join(lines, "\n")) {
		return repoMissing, ""
	}
	// ssh puts its warnings ahead of the line that says what went wrong.
	for _, line := range lines {
		line = strings.TrimSpace(line)
		lower := strings.ToLower(line)
		if line == "" || strings.HasPrefix(lower, "warning:") || strings.HasPrefix(lower, "hint:") {
			continue
		}
		return repoUnknown, line
	}
	if err != nil {
		return repoUnknown, err.Error()
	}
	return repoUnknown, "git gave no reason"
}

// probedConnect turns what the probe established into create/connect's answer.
// Only an empty remote is connected to; every other answer, including one the
// probe could not get, refuses before the plan.
func probedConnect(url string, state repoExistence, reason string) error {
	switch state {
	case repoEmpty:
		return nil
	case repoMissing:
		return usagef("'%s' doesn't exist, or you have no access to it. Create it first, or on GitHub: %s repo create <owner/name>", maskURL(url), meName)
	case repoNonEmpty:
		return usagef("'%s' already has history; clone it instead (%s repo clone %s), or reconcile with raw git.", maskURL(url), meName, maskURL(url))
	default:
		// Nothing but reaching the host settles it, so no command is offered.
		return usagef("Couldn't get an answer from '%s', so there is no telling whether it exists: %s", maskURL(url), reason)
	}
}

// ghRepoState asks gh what exists at 'owner/name', plus the reason gh gave when
// it could not say. These two commands skip the pre-command fetch (they have no
// origin yet), so this is the only place either can discover a network that is down.
func ghRepoState(target string) (repoExistence, string) {
	cmd := toolCmd("gh", "repo", "view", target, "--json", "isEmpty", "--jq", ".isEmpty")
	var errText bytes.Buffer
	cmd.Stderr = &errText
	out, err := cmd.Output()
	if err == nil {
		if strings.TrimRight(string(out), "\r\n") == "true" {
			return repoEmpty, ""
		}
		return repoNonEmpty, ""
	}
	said := errText.String()
	// What gh says, and only what gh says, when the name resolves to nothing.
	if strings.Contains(said, "Could not resolve to a Repository") || strings.Contains(said, "404") {
		return repoMissing, ""
	}
	for _, line := range splitLines(said) {
		if line != "" {
			return repoUnknown, line
		}
	}
	return repoUnknown, "gh gave no reason"
}

// settleRepoURL refuses a bad argument or an unconvertible remote before a plan
// promises anything. True means the answer was "nothing to do" and main is done.
func (a *app) settleRepoURL() (bool, error) {
	a.cmd.arg = strings.ToLower(a.cmd.arg)
	if a.cmd.arg != "" && a.cmd.arg != "https" && a.cmd.arg != "ssh" {
		return false, syntaxUsage("", "repo url [https|ssh]",
			placeholder{"[https|ssh]", "Switches origin to that kind of address. Without it, shows which one origin uses."})
	}
	// Exempt from the repo gate with its 'repo-' siblings, but unlike them it has
	// nothing to say outside one - it re-spells a remote a repo has to already have.
	if !a.inRepo {
		return false, usagef("Not inside a git repository. Change to a git project directory first.")
	}
	current := a.originURL()
	if current == "" {
		return false, usagef("No origin to re-spell. Connect one first: %s repo connect <url | owner/name>", meName)
	}
	if a.cmd.arg != "" {
		// Any host, not just github.com: re-spelling a remote is text work that the
		// host never hears about, and refusing it anywhere else was the parser's limit
		// showing through as a rule. A local path still has nothing to re-spell.
		if remoteTarget(current) == "" || a.originHost() == "" {
			where := noteLines("URL", maskURL(current))
			if isLocalPath(current) {
				where = noteLines("File", nativePath(current))
			}
			return false, refusalBlock("origin has no host and 'owner/name' to re-spell, so there is no other spelling of it to switch to.", [][]string{where}, nil)
		}
		if hostURL(a.originHost(), remoteTarget(current), a.cmd.arg) == current {
			a.out.status("origin already uses " + a.cmd.arg + "; nothing to do.")
			a.out.clean("")
			return true, nil
		}
	}
	return false, nil
}

// cloneDestDir names where a clone will go, from the arguments alone. Asked
// before the account is resolved as well as when the clone is settled: the folder
// rules that pick the account are the destination's, and nothing has touched the
// disk by then. Empty means the URL had no name to derive one from.
func cloneDestDir(url, dir string) string {
	if dir != "" {
		return dir
	}
	d := strings.TrimSuffix(url, "/")
	d = strings.TrimSuffix(d, ".git")
	d = d[strings.LastIndex(d, "/")+1:]
	return d[strings.LastIndex(d, ":")+1:]
}

func (a *app) cloneDestDir() string { return cloneDestDir(a.cmd.arg, a.cmd.arg2) }

// cloneDirShown is the clone's folder in full. The git commands keep it as typed,
// but the line that says where the repo goes names the folder gitsby worked out,
// which a relative spelling leaves to the reader.
func (a *app) cloneDirShown() string {
	if full, err := filepath.Abs(a.tgt.cloneDir); err == nil {
		return nativePath(filepath.ToSlash(full))
	}
	return a.tgt.cloneDir
}

// settleRepoClone derives the target dir, and makes re-runs a no-op instead of
// an error. True means main is done.
func (a *app) settleRepoClone() (bool, error) {
	if a.cmd.arg == "" {
		return false, syntaxUsage("No URL given.", "repo clone <url> [directory]", repoURLDef("<url>"), repoDirDef())
	}
	// 'owner/name' is refused before the plan, not after. It has only ever meant
	// github.com, so the transport is asked of github.com too.
	if ownerNameRE.MatchString(a.cmd.arg) && !pathExists(a.cmd.arg) {
		a.cmd.arg = githubURL(a.cmd.arg, a.protocolFor("github.com"))
	}
	a.tgt.cloneURL, a.tgt.cloneDir = a.cmd.arg, a.cloneDestDir()
	if a.tgt.cloneDir == "" {
		return false, usagef("Can't derive a directory name from '%s'; give one explicitly.", maskURL(a.tgt.cloneURL))
	}
	if pathExists(a.tgt.cloneDir) {
		existingURL := runOut("git", "-C", a.tgt.cloneDir, "remote", "get-url", "origin")
		if pathExists(a.tgt.cloneDir+"/.git") && sameRemote(existingURL, a.tgt.cloneURL) {
			a.out.statusNotes("Already a clone of that URL; nothing to do.", noteLines("File", a.cloneDirShown()))
			a.out.clean("")
			return true, nil
		}
		// An empty dir is fine (git allows it); anything else would clobber.
		if !isDir(a.tgt.cloneDir) || !dirEmpty(a.tgt.cloneDir) {
			return false, refusalBlock("The clone's folder already exists and isn't a clone of that URL.",
				[][]string{noteLines("File", a.cloneDirShown())}, nil)
		}
	}
	return false, nil
}

// settleRepoConnect resolves what create/connect are publishing to before the
// preview, so the plan is real. Same machinery, one difference - only 'create'
// will bring a remote into existence.
func (a *app) settleRepoConnect() error {
	wantCreate := a.cmd.name == "repo-create"
	hasWork := false
	if a.inRepo {
		hasWork = runOK("git", "rev-parse", "-q", "--verify", "HEAD") || runOut("git", "status", "--porcelain") != ""
	} else {
		hasWork = !dirEmpty(".")
	}
	if !hasWork {
		return usagef("Nothing to publish here: no commits and no files.")
	}
	existingOrigin := ""
	if a.inRepo {
		existingOrigin = a.originURL()
	}
	switch {
	case existingOrigin != "":
		if wantCreate {
			return usagef("origin is already set to '%s', so there is no repo left to create. Push what you have with: %s repo connect", maskURL(existingOrigin), meName)
		}
		if a.cmd.arg != "" && !sameRemote(a.cmd.arg, existingOrigin) {
			return usagef("origin is already set to '%s'; changing remotes is raw-git territory.", maskURL(existingOrigin))
		}
		a.tgt.connectMode, a.tgt.connectURL = "push", existingOrigin
		return nil
	case wantCreate:
		return a.settleRepoCreate()
	default:
		return a.settleRepoConnectTo()
	}
}

func (a *app) settleRepoCreate() error {
	if a.cmd.arg == "" {
		return syntaxUsage("No target given.", "repo create <owner/name>", repoOwnerNameDef())
	}
	if !ownerNameRE.MatchString(a.cmd.arg) || pathExists(a.cmd.arg) {
		return usagef("'%s' isn't a GitHub 'owner/name'; only GitHub repos can be created from here. For a remote that already exists: %s repo connect %s", a.cmd.arg, meName, a.cmd.arg)
	}
	if err := mustBeInPath("gh"); err != nil {
		return err
	}
	state, err := a.askGhTarget()
	if err != nil {
		return err
	}
	if state == repoEmpty {
		return usagef("github.com/%s already exists and is empty; connect to it instead: %s repo connect %s", a.tgt.ghTarget, meName, a.tgt.ghTarget)
	}
	a.tgt.connectMode = "create"
	return nil
}

func (a *app) settleRepoConnectTo() error {
	if a.cmd.arg == "" {
		return syntaxUsage("No remote configured and no target given.", "repo connect <url | owner/name>", repoURLDef("<url>"), repoOwnerNameDef())
	}
	if !ownerNameRE.MatchString(a.cmd.arg) || pathExists(a.cmd.arg) {
		state, reason := a.probeRemote(a.cmd.arg)
		if err := probedConnect(a.cmd.arg, state, reason); err != nil {
			return err
		}
		a.tgt.connectMode, a.tgt.connectURL = "add", a.cmd.arg
		return nil
	}
	// owner/name shorthand: gh can say whether it exists and whether it's empty.
	if err := mustBeInPath("gh"); err != nil {
		return err
	}
	state, err := a.askGhTarget()
	if err != nil {
		return err
	}
	if state == repoMissing {
		return usagef("github.com/%s doesn't exist, or you can't see it. To create it: %s repo create %s", a.tgt.ghTarget, meName, a.tgt.ghTarget)
	}
	// gh never uses a host alias, so this is the canonical url. We build this one
	// ourselves, so the config's transport applies - unlike 'repo create', where gh
	// adds the remote and only gh's own git_protocol decides.
	a.tgt.connectURL = githubURL(a.tgt.ghTarget, a.protocolFor("github.com"))
	a.tgt.connectMode = "add"
	return nil
}

// askGhTarget asks gh about the owner/name given, for repo create and connect.
// It refuses the 2 answers both refuse, so only missing and empty come back.
func (a *app) askGhTarget() (repoExistence, error) {
	a.tgt.ghTarget = a.cmd.arg
	state, reason := ghRepoState(a.tgt.ghTarget)
	switch state {
	case repoUnknown:
		return state, usagef("Couldn't ask GitHub about %s, so there is no telling whether it exists: %s", a.tgt.ghTarget, reason)
	case repoMissing, repoEmpty:
		return state, nil
	}
	return state, usagef("github.com/%s already has commits; clone it instead (%s repo clone), or reconcile with raw git.", a.tgt.ghTarget, meName)
}

func (a *app) cmdClone() error {
	// The folder can come from the URL's last part, so it may start with a dash, and
	// git would read it as an option of its own.
	if err := a.step("git", "clone", "--", a.tgt.cloneURL, a.tgt.cloneDir); err != nil {
		return err
	}
	// Opinionated: if the repo works dev-first, start there.
	if runOK("git", "-C", a.tgt.cloneDir, "show-ref", "--verify", "--quiet", "refs/remotes/origin/dev") {
		return a.step("git", "-C", a.tgt.cloneDir, "checkout", "dev")
	}
	return nil
}

// cmdConnect serves both 'repo create' and 'repo connect'; connectMode is what
// they disagree about.
func (a *app) cmdConnect() error {
	if !a.inRepo {
		if err := a.step("git", "init", "-b", "main"); err != nil {
			return err
		}
	}
	if err := a.cmdCommit(); err != nil { // publish everything as-is; no-op when clean
		return err
	}
	switch a.tgt.connectMode {
	case "create":
		return a.step("gh", "repo", "create", a.tgt.ghTarget, "--"+a.opt.visibility, "--source", ".", "--push", "--remote", "origin")
	case "add":
		if err := a.step("git", "remote", "add", "origin", a.tgt.connectURL); err != nil {
			return err
		}
		return a.step("git", "push", "-u", "origin", "HEAD")
	case "push":
		// origin already set - make sure everything is published
		switch {
		case !a.hasUpstream() || isAhead():
			return a.step("git", a.pushArgs()...)
		default:
			a.out.status("Nothing to push; already connected and current.")
		}
	}
	return nil
}

// cmdRepoURL re-spells origin in the other transport. Nothing else about the
// repo changes: same remote, same history, same name - only how git
// authenticates to it.
func (a *app) cmdRepoURL() error {
	url := a.originURL()
	return a.step("git", "remote", "set-url", "origin", hostURL(a.originHost(), remoteTarget(url), a.cmd.arg))
}

// cmdRepoURLShow is the bare, read-only form: what origin is now, and its other
// spelling if it has one.
func (a *app) cmdRepoURLShow() {
	urlNow := a.originURL()
	urlTarget := remoteTarget(urlNow)
	host := a.originHost()
	a.out.clean("")
	a.out.clean("origin .......: " + maskURL(urlNow))
	if urlTarget == "" || host == "" {
		a.out.clean("No host and 'owner/name' to re-spell, so there is no other spelling of it.")
		return
	}
	a.out.clean("as https .....: " + hostURL(host, urlTarget, "https"))
	a.out.clean("as ssh .......: " + hostURL(host, urlTarget, "ssh"))
	a.out.clean("Switch with '" + meName + " repo url <https|ssh>'.")
}

// showFilesToPublish lists what a first publish would add, through a throwaway git dir
// outside the tree, so the excludes apply as 'git add --all' will and 'n' changes
// nothing.
func (a *app) showFilesToPublish() {
	probeDir, err := os.MkdirTemp("", "")
	if err != nil {
		return
	}
	// Ours, made two lines up, and nothing outside this function ever names it.
	defer func() { _ = os.RemoveAll(probeDir) }()
	// A cwd nothing can name makes the probe list nothing; the confirm then shows an
	// empty list instead of dying, on a machine already in deeper trouble.
	wd, _ := os.Getwd()
	env := append(os.Environ(), "GIT_DIR="+probeDir, "GIT_WORK_TREE="+wd)
	initCmd := toolCmd("git", "init", "--quiet")
	initCmd.Env = env
	_ = initCmd.Run()
	a.out.clean("")
	a.out.clean("Files to publish:")
	ls := toolCmd("git", "ls-files", "--others", "--exclude-standard")
	ls.Env = env
	var outLines []string
	if out, _ := ls.Output(); len(out) > 0 {
		outLines = strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	}
	a.showLines(outLines)
	if a.lastListCount == 0 {
		a.out.clean("    (nothing - the directory is empty, or everything in it is ignored)")
	}
}

// The placeholders more than one 'repo' refusal defines, worded once.
func repoURLDef(name string) placeholder {
	return placeholder{name, "The repo's https or ssh address, e.g. https://github.com/pat/app.git."}
}

func repoDirDef() placeholder {
	return placeholder{"[directory]", "The folder to clone into. Without it, a folder named after the repo."}
}

func repoOwnerNameDef() placeholder {
	return placeholder{"<owner/name>", "A GitHub account or organization, a slash, and the repo's name, e.g. pat/app."}
}
