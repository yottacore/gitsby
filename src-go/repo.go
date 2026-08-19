// The repo lifecycle commands: clone, create, connect, url. Everything they need
// settles before the plan is shown - which remote, which directory, which mode -
// so a bad argument or an unreachable target refuses up front, and the preview
// promises only what will actually run.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

var (
	cloneUrl    = ""
	cloneDir    = ""
	connectMode = "" // "create" | "add" | "push"; what create and connect disagree about
	connectUrl  = ""
	ghTarget    = "" // 'owner/name' when gh is the one doing the creating or answering
)

var ownerNameRE = regexp.MustCompile(`^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)

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

// sameRemote: whether two remote URLs name the same place. Text settles it for a
// real URL, but git rewrites a local path into the platform's own spelling when
// it stores one - hand it '/c/tmp/x' on Windows and it gives back 'C:/tmp/x' -
// so comparing our own argument against git's copy said "different" for the same
// directory, and a re-run of 'repo clone' refused itself.
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

// githubUrl: the canonical github.com URL for 'owner/name' in one of the two
// transports.
func githubUrl(target, proto string) string {
	if target == "" {
		return ""
	}
	if proto == "ssh" {
		return "git@github.com:" + target + ".git"
	}
	return "https://github.com/" + target + ".git"
}

// probeRemote is one network round-trip: does the remote exist, and does it have
// history? No auth prompts - a bad https URL would otherwise stop and ask for
// credentials mid-run - and the timeout composes onto git's own ssh command, so
// a per-repo core.sshCommand still probes as the key git actually pushes with.
func probeRemote(url string) string {
	env := append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	if os.Getenv("GIT_SSH_COMMAND") == "" {
		env = append(env, "GIT_SSH_COMMAND="+gitSshCommand()+" -o ConnectTimeout=3")
	}
	probe := exec.Command("git", "ls-remote", url)
	probe.Env = env
	out, err := probe.Output()
	if err != nil {
		return "missing"
	}
	if strings.TrimRight(string(out), "\r\n") != "" {
		return "nonempty"
	}
	return "empty"
}

// ghRepoState asks gh what exists at 'owner/name': "empty", "nonempty",
// "missing", or "" plus the reason gh gave. A failed call is NOT absence - gh
// exits nonzero for a name that resolves to nothing and for a network that is
// down alike, and these two commands skip the pre-command fetch (they have no
// origin yet), so this is the only place either can be discovered. Stating
// "doesn't exist" for an unreachable API sent you off to create a repo you
// already have.
func ghRepoState(target string) (state, reason string) {
	cmd := exec.Command("gh", "repo", "view", target, "--json", "isEmpty", "--jq", ".isEmpty")
	var errText bytes.Buffer
	cmd.Stderr = &errText
	out, err := cmd.Output()
	if err == nil {
		if strings.TrimRight(string(out), "\r\n") == "true" {
			return "empty", ""
		}
		return "nonempty", ""
	}
	said := errText.String()
	// What gh says, and only what gh says, when the name resolves to nothing.
	if strings.Contains(said, "Could not resolve to a Repository") || strings.Contains(said, "404") {
		return "missing", ""
	}
	for _, line := range strings.Split(said, "\n") {
		if line = strings.TrimRight(line, "\r"); line != "" {
			return "", line
		}
	}
	return "", "gh gave no reason"
}

// settleRepoUrl refuses a bad argument or an unconvertible remote before a plan
// promises anything. True means the answer was "nothing to do" and main is done.
func settleRepoUrl() bool {
	cmdArg = strings.ToLower(cmdArg)
	if cmdArg != "" && cmdArg != "https" && cmdArg != "ssh" {
		throwUsage("Syntax: " + meName + " repo url [https|ssh]")
	}
	// Exempt from the repo gate with its 'repo-' siblings, but unlike them it has
	// nothing to say outside one - it re-spells a remote a repo has to already have.
	if !inRepo {
		throwUsage("Not inside a git repository. Change to a git project directory first.")
	}
	current := originUrl()
	if current == "" {
		throwUsage("No origin to re-spell. Connect one first: " + meName + " repo connect <url | owner/name>")
	}
	if cmdArg != "" {
		if remoteTarget(current) == "" {
			throwUsage("origin isn't a github.com remote, so there is no other spelling of it to switch to.")
		}
		if githubUrl(remoteTarget(current), cmdArg) == current {
			echoStatus("origin already uses " + cmdArg + "; nothing to do.")
			echoClean("")
			return true
		}
	}
	return false
}

// cloneDestDir names where a clone will land, from the arguments alone. Asked
// before the account is resolved as well as when the clone is settled: the folder
// rules that pick the account are the destination's, and nothing has touched the
// disk by then. Empty means the URL carried no name to derive one from.
func cloneDestDir() string {
	if cmdArg2 != "" {
		return cmdArg2
	}
	d := strings.TrimSuffix(cmdArg, "/")
	d = strings.TrimSuffix(d, ".git")
	d = d[strings.LastIndex(d, "/")+1:]
	return d[strings.LastIndex(d, ":")+1:]
}

// settleRepoClone derives the target dir, and makes re-runs a no-op instead of
// an error. True means main is done.
func settleRepoClone() bool {
	if cmdArg == "" {
		throwUsage("No URL given. Syntax: " + meName + " repo clone <url> [directory]")
	}
	// 'owner/name' is what create and connect take; refusing it here only after
	// the plan was confirmed is the surprise.
	if ownerNameRE.MatchString(cmdArg) && !pathExists(cmdArg) {
		cmdArg = githubUrl(cmdArg, preferredProtocol())
	}
	cloneUrl, cloneDir = cmdArg, cloneDestDir()
	if cloneDir == "" {
		throwUsage("Can't derive a directory name from '" + maskUrl(cloneUrl) + "'; give one explicitly.")
	}
	if pathExists(cloneDir) {
		existingUrl := runOut("git", "-C", cloneDir, "remote", "get-url", "origin")
		if pathExists(cloneDir+"/.git") && sameRemote(existingUrl, cloneUrl) {
			echoStatus("'" + cloneDir + "' is already a clone of that URL; nothing to do.")
			echoClean("")
			return true
		}
		// An empty dir is fine (git allows it); anything else would clobber.
		if !isDir(cloneDir) || !dirEmpty(cloneDir) {
			throwUsage("'" + cloneDir + "' already exists and isn't a clone of that URL.")
		}
	}
	return false
}

// settleRepoConnect resolves what create/connect are publishing to before the
// preview, so the plan is real. Same machinery, one difference - only 'create'
// will bring a remote into existence.
func settleRepoConnect() {
	wantCreate := cmdName == "repo-create"
	hasWork := false
	if inRepo {
		if runOK("git", "rev-parse", "-q", "--verify", "HEAD") || runOut("git", "status", "--porcelain") != "" {
			hasWork = true
		}
	} else if !dirEmpty(".") {
		hasWork = true
	}
	if !hasWork {
		throwUsage("Nothing to publish here: no commits and no files.")
	}
	existingOrigin := ""
	if inRepo {
		existingOrigin = originUrl()
	}
	if existingOrigin != "" {
		if wantCreate {
			throwUsage("origin is already set to '" + maskUrl(existingOrigin) + "', so there is no repo left to create. Push what you have with: " + meName + " repo connect")
		}
		if cmdArg != "" && !sameRemote(cmdArg, existingOrigin) {
			throwUsage("origin is already set to '" + maskUrl(existingOrigin) + "'; changing remotes is raw-git territory.")
		}
		connectMode, connectUrl = "push", existingOrigin
	} else if wantCreate {
		if cmdArg == "" {
			throwUsage("No target given. Syntax: " + meName + " repo create <owner/name>")
		}
		if !ownerNameRE.MatchString(cmdArg) || pathExists(cmdArg) {
			throwUsage("'" + cmdArg + "' isn't a GitHub 'owner/name'; only GitHub repos can be created from here. For a remote that already exists: " + meName + " repo connect " + cmdArg)
		}
		mustBeInPath("gh")
		ghTarget = cmdArg
		switch state, reason := ghRepoState(ghTarget); state {
		case "":
			throwUsage("Couldn't ask GitHub about " + ghTarget + ", so there is no telling whether it exists: " + reason)
		case "missing":
			connectMode = "create"
		case "empty":
			throwUsage("github.com/" + ghTarget + " already exists and is empty; connect to it instead: " + meName + " repo connect " + ghTarget)
		default:
			throwUsage("github.com/" + ghTarget + " already has commits; clone it instead (" + meName + " repo clone), or reconcile with raw git.")
		}
	} else {
		if cmdArg == "" {
			throwUsage("No remote configured and no target given. Syntax: " + meName + " repo connect <url | owner/name>")
		}
		if ownerNameRE.MatchString(cmdArg) && !pathExists(cmdArg) {
			// owner/name shorthand: gh can say whether it exists and whether it's empty.
			mustBeInPath("gh")
			ghTarget = cmdArg
			switch state, reason := ghRepoState(ghTarget); state {
			case "":
				throwUsage("Couldn't ask GitHub about " + ghTarget + ", so there is no telling whether it exists: " + reason)
			case "missing":
				throwUsage("github.com/" + ghTarget + " doesn't exist, or you can't see it. To create it: " + meName + " repo create " + ghTarget)
			case "empty":
				// gh never uses a host alias, so this is the canonical url. We build
				// this one ourselves, so the config's transport applies - unlike 'repo
				// create', where gh adds the remote and only gh's own git_protocol
				// decides.
				connectUrl = githubUrl(ghTarget, preferredProtocol())
				connectMode = "add"
			default:
				throwUsage("github.com/" + ghTarget + " already has commits; clone it instead (" + meName + " repo clone), or reconcile with raw git.")
			}
		} else {
			switch probeRemote(cmdArg) {
			case "missing":
				throwUsage("Can't reach '" + maskUrl(cmdArg) + "' (doesn't exist, or no access). Create it first, or on GitHub: " + meName + " repo create <owner/name>")
			case "nonempty":
				throwUsage("'" + maskUrl(cmdArg) + "' already has history; clone it instead (" + meName + " repo clone " + maskUrl(cmdArg) + "), or reconcile with raw git.")
			case "empty":
				connectMode, connectUrl = "add", cmdArg
			}
		}
	}
}

func cmdClone() {
	runStep("git", "clone", cloneUrl, cloneDir)
	// Opinionated: if the repo works dev-first, start there.
	if runOK("git", "-C", cloneDir, "show-ref", "--verify", "--quiet", "refs/remotes/origin/dev") {
		runStep("git", "-C", cloneDir, "checkout", "dev")
	}
}

// cmdConnect serves both 'repo create' and 'repo connect'; connectMode is what
// they disagree about.
func cmdConnect() {
	if !inRepo {
		runStep("git", "init", "-b", "main")
	}
	cmdCommit() // publish everything as-is; no-op when clean
	switch connectMode {
	case "create":
		runStep("gh", "repo", "create", ghTarget, "--"+repoVisibility, "--source", ".", "--push", "--remote", "origin")
	case "add":
		runStep("git", "remote", "add", "origin", connectUrl)
		runStep("git", "push", "-u", "origin", "HEAD")
	case "push":
		// origin already set - just make sure everything is published
		if !hasUpstream() {
			runStep("git", "push", "-u", "origin", "HEAD")
		} else if isAhead() {
			runStep("git", "push")
		} else {
			echoStatus("Nothing to push; already connected and current.")
		}
	}
}

// cmdRepoUrl re-spells origin in the other transport. Nothing else about the
// repo changes: same remote, same history, same name - only how git
// authenticates to it.
func cmdRepoUrl() {
	url := originUrl()
	runStep("git", "remote", "set-url", "origin", githubUrl(remoteTarget(url), cmdArg))
}

// cmdRepoUrlShow is the bare, read-only form: what origin is now, and its other
// spelling if it has one.
func cmdRepoUrlShow() {
	urlNow := originUrl()
	urlTarget := remoteTarget(urlNow)
	echoClean("")
	echoClean("origin .......: " + maskUrl(urlNow))
	if urlTarget != "" {
		echoClean("as https .....: " + githubUrl(urlTarget, "https"))
		echoClean("as ssh .......: " + githubUrl(urlTarget, "ssh"))
		echoClean("Switch with '" + meName + " repo url <https|ssh>'.")
	} else {
		echoClean("Not a github.com remote, so there is no other spelling of it.")
	}
}

// showFilesToPublish: every in-repo command shows what it is about to touch; this
// is the one that publishes a whole directory for the first time, possibly to a
// public repo, so it owes the same. Asked through a throwaway git dir OUTSIDE the
// work tree: that way .gitignore and core.excludesFile are honored exactly as the
// real 'git add --all' will honor them (listing files git would skip is its own
// kind of wrong), and answering 'n' leaves the directory as it was found.
func showFilesToPublish() {
	probeDir, err := os.MkdirTemp("", "")
	if err != nil {
		return
	}
	defer os.RemoveAll(probeDir)
	wd, _ := os.Getwd()
	env := append(os.Environ(), "GIT_DIR="+probeDir, "GIT_WORK_TREE="+wd)
	initCmd := exec.Command("git", "init", "--quiet")
	initCmd.Env = env
	_ = initCmd.Run()
	echoClean("")
	echoClean("Files to publish:")
	ls := exec.Command("git", "ls-files", "--others", "--exclude-standard")
	ls.Env = env
	var outLines []string
	if out, _ := ls.Output(); len(out) > 0 {
		outLines = strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	}
	cappedLines(outLines)
	if lastListCount == 0 {
		echoClean("    (nothing - the directory is empty, or everything in it is ignored)")
	}
}
