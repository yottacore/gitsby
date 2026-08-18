// gitsby, compiled. Built out against cicd/test.bash from the first commit; commands land
// slice by slice, so anything not here yet says so and exits nonzero rather than guessing.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"
	"strings"
)

const meName = "gitsby"

// For help text, before we know we're in a repo.
const mergeTargetLabel = "dev/main"

// Ported pieces whose only callers land with a later slice. The unused check has
// no ignore directive, and turning the whole check off would hide real rot, so
// this anchor marks them used until then.
var _ = []any{repoVisibility}

// Set at build time: -ldflags "-X main.version=x.y.z". The bare default marks a
// hand-run 'go build' apart from a pipeline build.
var version = "0.0.0-dev"

const (
	copyrightYear = "2014-2026"
	author        = "Jim Collier"
)

func printCopyright() {
	if quiet {
		return
	}
	echoClean("")
	echoClean(fmt.Sprintf("%s v%s, Copyright © %s %s.", meName, version, copyrightYear, author))
	echoClean("Licensed under The MIT License (MIT). Full text at:")
	echoClean("  https://mit-license.org/")
	echoClean("No Warranty.")
	echoClean("")
}

func printAbout() {
	if quiet {
		return
	}
	echoClean("")
	echoClean("Safer, state-checked wrappers for everyday git. Every command verifies the")
	echoClean("repo state before acting (commit only if dirty, pull only with an upstream,")
	echoClean("push only if ahead), so each is idempotent and safe to re-run.")
	echoClean("")
}

func printSyntax() {
	if quiet {
		return
	}
	echoClean("")
	echoClean("Common commands:")
	echoClean("  update [msg] .......: Pull updates, then commit all local changes. Do frequently!")
	echoClean("  br create <branch> .: Create a new branch off " + mergeTargetLabel + " (current work is carried or parked).")
	echoClean("  br switch [branch] .: Switch to a branch (parks current work first). No arg: back to " + mergeTargetLabel + ".")
	echoClean("  br [list] ..........: Fetch and list branches.")
	echoClean("  status .............: Fetch and show current status.")
	echoClean("One-time setup commands:")
	echoClean("  repo clone <url> ...: Clone a repo you don't have yet, into [dir] (checks out dev if it has one).")
	echoClean("  repo create <o/n> ..: Create GitHub repo 'owner/name' via gh, then connect this directory and push.")
	echoClean("  repo connect [url] .: Connect this directory to an existing empty remote, and push.")
	echoClean("  repo url [https|ssh]: Show how origin authenticates, or switch it between the two.")
	echoClean("  account [list] .....: Show your configured GitHub accounts, and which one this folder uses.")
	echoClean("  account apply ......: Teach plain git the same folder rules, so 'git' outside gitsby matches.")
	echoClean("Less common commands:")
	echoClean("  sync [msg] .........: Pull, commit, and push. Do infrequently.")
	echoClean("Admin commands, e.g. for small solo projects:")
	echoClean("  br land [msg] ......: Merge current branch into " + mergeTargetLabel + " (--no-ff), push, delete it local + remote.")
	echoClean("  br prune ...........: Delete branches already merged into " + mergeTargetLabel + ", local + remote.")
	echoClean("  br hotfix <name> ...: Branch off the default branch, to correct what's already published.")
	echoClean("  pr [create|n|ok n] .: Create, list, review, or accept a pull request (needs gh).")
	echoClean("  release [ver] ......: Cut a release: merge dev into main, tag, push. No ver: next after latest tag.")
	echoClean("For scripts:")
	echoClean("  raw git <args> .....: Run git as the account this folder belongs to. Everything after 'git' is git's.")
	echoClean("  raw gh <args> ......: The same, for gh.")
	echoClean("Options:")
	echoClean("  -m, --message MSG ....: Commit or merge message (or give it positionally).")
	echoClean("  -q, --quiet, -y ......: Assume yes - no prompts; if committing with no message, one is generated.")
	echoClean("  --public / --private .: Visibility for the repo 'repo create' makes (default: private).")
	echoClean("  --any-identity .......: Act as gh's active account, and proceed when it differs from the remote's ssh key.")
	echoClean("  --no-fetch ...........: Skip the pre-command fetch, and the pull. (Pushes still go out.)")
	echoClean("  --config FILE ........: Read accounts from FILE instead of the usual config location.")
	echoClean("  -h, --help  /  -v, --version")
	echoClean("")
}

func printHelp() {
	printCopyright()
	printAbout()
	printSyntax()
}

// notYet is the whole answer for anything this build has not grown into. It names
// no command on purpose: anything an error message names must be one the parser
// accepts.
func notYet() {
	fmt.Fprintln(os.Stderr, meName+": this build does not do that yet")
	os.Exit(2)
}

// cmdPassthrough runs the real tool as the account this folder belongs to, then
// gets out of its way entirely. No preview, no confirmation, no fetch: this is
// somebody else's command run under the right identity, and a script piping its
// output must get that output and nothing else.
func cmdPassthrough(tool string, args []string) {
	mustBeInPath(tool)
	resolveAccount(runOut("git", "remote", "get-url", "origin"))
	selectAccount(true)
	// One line, on stderr, so a pipeline reading stdout sees only the tool.
	// Silence is what '-q' is for.
	if !quiet && acctGhWho != "" && acctSource != "" {
		fmt.Fprintln(os.Stderr, meName+": acting as "+acctGhWho+" (from "+acctSource+")")
	}
	runHandover(tool, args)
}

func cmdBrList() {
	dflt := defaultBranch()
	if dflt == "" {
		dflt = "unknown"
	}
	echoClean("")
	echoClean("Default branch: " + dflt)
	echoStatus("git branch -a -vv")
	runInherit("git", "branch", "-a", "-vv")
	echoResetBlank()
}

func main() {
	args := os.Args[1:]

	// Only the command slot counts for help and the version - scanning the whole
	// argv would make a message like "add -v flag" silently short-circuit.
	if len(args) == 0 {
		printHelp()
		// The scripts' exit trap adds one more blank on any nonzero path.
		echoCleanForce("")
		os.Exit(1)
	}
	switch strings.ToLower(args[0]) {
	case "-h", "--help", "help":
		printHelp()
		return
	case "-v", "--ver", "--version", "version":
		printCopyright()
		return
	}

	// 'raw git|gh' hands everything after the tool to the real thing, verbatim, as
	// the account this folder belongs to. Scanned ahead of the main parser and of
	// the git PATH check - 'raw gh' must work without git installed.
	if tool, ptArgs := scanPassthrough(args); tool != "" {
		cmdPassthrough(tool, ptArgs)
	}

	// Breathing room after the shell prompt (the matching trailing blank is at each
	// exit path). After the passthrough, which owns its own output.
	echoClean("")

	mustBeInPath("git")
	if parseArgs(args) {
		// Help works from any position: '<noun> <verb> --help' is the reflex every
		// git user has, and slot 1 always holds a real command, so nothing can be
		// shadowed.
		printHelp()
		echoClean("")
		return
	}
	// Both visibilities given is a contradiction, not a precedence question - and
	// silently picking one would publish a repo the caller believes is the other.
	if sawPublic && sawPrivate {
		throwUsage("--public and --private are mutually exclusive; pick one.")
	}
	collapseCommand()
	sortCommand()

	// No tty = nobody to answer a prompt. Read-only commands just go quiet;
	// mutating ones fail closed (require an explicit -q) so piped/cron input can't
	// silently auto-confirm.
	if !isTTY(os.Stdin) {
		if isMutating && !quiet {
			throwUsage("No terminal to confirm on; re-run with -q to proceed without prompts.")
		}
		quiet = true
	}

	// pr's own shape, ahead of the repo gate like the scripts: a malformed pr call
	// is wrong anywhere, in a repo or not.
	if cmdName == "pr" {
		sortPr()
	}

	// Every command needs a repo - except the repo ones: clone works anywhere, and
	// create/connect exist precisely to turn a plain directory into one.
	inRepo := runOK("git", "rev-parse", "--is-inside-work-tree")
	if !inRepo && !strings.HasPrefix(cmdName, "repo-") && !strings.HasPrefix(cmdName, "account-") {
		throwUsage("Not inside a git repository. Change to a git project directory first.")
	}

	// Point this run at the account whose folder this is, before anything reaches
	// the network: the fetch below authenticates, so getting this wrong here gets
	// it wrong for the whole command. This also validates --config/GITSBY_CONFIG,
	// so it stays ahead of the not-yet refusal - same contract the scripts keep.
	resolveAccount(runOut("git", "remote", "get-url", "origin"))
	selectAccount(false)

	switch cmdName {
	case "status", "br-list", "br-prune", "update", "sync",
		"br-create", "br-hotfix", "br-switch", "br-land", "pr", "release":
	default:
		notYet()
	}

	// Freshen remote refs so status/ahead-behind info is current. Never fatal -
	// offline still works locally.
	if doFetch && runOK("git", "remote", "get-url", "origin") {
		echoStatus("git fetch ...")
		fetchRemote()
	}
	// These can't change mid-command, so resolve them once (post-fetch, so
	// origin/HEAD is fresh). status and br list run without a resolvable default
	// branch on purpose: they mutate nothing and are the commands you run to see
	// what is wrong, so they report "unknown" instead of refusing.
	if inRepo {
		defaultBranchCache = defaultBranch()
		mergeTargetCache = mergeTarget()
		// Every branch command checks this out, protects it, or merges into it, so a
		// name we can't confirm has to stop things here - before a preview promises
		// it. 'status' and 'br list' are exempt on purpose: they mutate nothing and
		// are the commands you run to see what is wrong, so they report "unknown"
		// instead of refusing.
		if cmdName != "status" && cmdName != "br-list" && !strings.HasPrefix(cmdName, "repo-") && !strings.HasPrefix(cmdName, "account-") && runOK("git", "rev-parse", "-q", "--verify", "HEAD") {
			if defaultBranchCache == "" {
				throwUsage("Can't tell this repo's default branch. Set it with 'git remote set-head origin --auto', or create a main/master.")
			}
			if !branchExistsLocal(defaultBranchCache) && !branchExistsRemote(defaultBranchCache) {
				throwUsage("This repo's default branch resolves to '" + defaultBranchCache + "', which exists neither here nor on origin. Fix it with 'git remote set-head origin --auto'.")
			}
		}
	}

	// Commands that exist to publish, refused here rather than halfway through on
	// raw git text - and far better than "succeeding" having sent nothing. The rest
	// degrade instead: they mean something locally, so they run and say what they
	// skipped.
	switch cmdName {
	case "sync":
		requireOnline("sync", "Commit locally with '"+meName+" update', then '"+meName+" sync' when you are back online.")
	case "release":
		requireOnline("release", "A release nobody can fetch isn't one.")
	case "pr":
		if prSub != "" {
			requireOnline("pr "+prSub, "The pull request lives on GitHub; there is no local half to do first.")
		}
	}

	// The release version resolves up front so the preview and the command agree,
	// and so bad input dies early.
	if cmdName == "release" {
		resolveRelease()
		releasePreflight()
	}
	// The mutating pr subcommands check here too, so nothing can fail after the plan
	// was confirmed.
	if prSub != "" {
		prPreflight()
	}

	// Branch arguments validate up front too, so a bad name can't survive to a
	// nonsense preview.
	switch cmdName {
	case "br-create":
		if cmdArg == "" {
			throwUsage("No branch name given. Syntax: " + meName + " br create <new branch name>")
		}
		checkNewBranchName()
	case "br-hotfix":
		if cmdArg == "" {
			throwUsage("No name given. Syntax: " + meName + " br hotfix <name>")
		}
		// The prefix is the marker, so put it on ourselves - and accept it if the user
		// typed it.
		cmdArg = "hotfix/" + strings.TrimPrefix(cmdArg, "hotfix/")
		checkNewBranchName()
	case "br-land":
		// Landing ends in 'git branch -d', so a leftover main/master must be refused
		// here for the same reason br prune never lists one - and up front, not after a
		// destructive plan was shown.
		if isProtectedBranch("") {
			throwUsage("'" + currentBranch() + "' is a protected branch; landing it would delete it. Run this from a work branch instead.")
		}
	case "br-switch":
		if cmdArg != "" && !branchExistsLocal(cmdArg) && !branchExistsRemote(cmdArg) {
			throwUsage("No branch '" + cmdArg + "' locally or on origin. To create it: " + meName + " br create " + cmdArg)
		}
		// Refusing a dirty protected branch belongs here too, before the plan is shown
		// and confirmed.
		switchTarget := cmdArg
		if switchTarget == "" {
			switchTarget = mergeTarget()
		}
		if currentBranch() != switchTarget && isProtectedBranch("") && runOut("git", "status", "--porcelain") != "" {
			throwUsage("Working tree has changes on '" + currentBranch() + "'; won't auto-commit to a protected branch. Carry them to a new branch (" + meName + " br create <name>), or commit them here deliberately (" + meName + " update) first.")
		}
	}

	// br prune: work out what goes before anything is shown, so the plan names
	// every branch by name. An empty plan is a plain read-only answer.
	if cmdName == "br-prune" {
		if currentBranch() == "" {
			throwUsage("Detached HEAD (no current branch); resolve that manually first.")
		}
		resolvePrune()
		if len(pruneLocal) == 0 && len(pruneRemote) == 0 {
			pruneNothingToDo()
			echoClean("")
			return
		}
	}

	// Which commands go through gh, and where the ssh identity should be read from.
	// For pr that's the origin we already have; repo create/connect have no origin
	// yet and settle their own probe url, so they join this with their slice.
	if cmdName == "pr" {
		isGhCommand = true
		if prSub != "" {
			isGhWrite = true
			identityProbeUrl = runOut("git", "remote", "get-url", "origin")
		}
	}
	// Prime the probe caches here, like the scripts prime them in-shell: every later
	// use would otherwise repeat the round trip.
	if isGhCommand {
		_ = ghLogin()
	}
	if isGhWrite {
		_ = sshLogin(identityProbeUrl)
	}

	// A gh write acting as a different account than the key git pushes with is a
	// wrong-account mistake waiting to happen, and it is outward-facing. Refuse it
	// unattended (nobody is there to read a warning); warn interactively, right
	// before the prompt. --any-identity means the difference is intended.
	identityMismatch := ""
	if isGhWrite && !anyIdentity {
		identityMismatch = identityMismatchText(ghLogin(), sshLogin(identityProbeUrl))
		// Up front, like every other refusal: don't show a plan we won't run.
		if identityMismatch != "" && quiet {
			throwUsage(identityMismatch + " Nothing was done. Re-run with --any-identity if that is intended.")
		}
	}
	// The same question for the commands that push with git rather than write
	// through gh - 'sync' above all, which sends your work to a remote and compared
	// nothing at all. Only for an account that was CONFIGURED or asked for: one
	// inferred from the remote's owner says nothing about who you are, and would
	// fire for every single-account user cloning somebody else's repo.
	if isMutating && !anyIdentity && identityMismatch == "" && acctGhWho != "" && (acctExplicit || acctName != "") {
		pushLogin := sshLogin(runOut("git", "remote", "get-url", "origin"))
		if pushLogin != "" && pushLogin != "?" && pushLogin != acctGhWho {
			identityMismatch = "This folder's account is '" + acctGhWho + "', but origin's key authenticates as '" + pushLogin + "'."
			if quiet {
				throwUsage(identityMismatch + " Nothing was done. Re-run with --any-identity if that is intended.")
			}
		}
	}

	// Read-only commands
	if !isMutating {
		switch cmdName {
		case "status":
			showStatus(true)
		case "br-list":
			cmdBrList()
		case "pr":
			cmdPrView()
		}
		echoClean("")
		return
	}

	// Mutating commands: show state and plan, confirm, execute, show state again.
	// The smaller headers - clone, and create/connect from a plain directory, which
	// have no repo state to show - land with those commands.
	if currentBranch() == "" {
		throwUsage("Detached HEAD (no current branch); resolve that manually first.")
	}
	showStatus(true)
	echoClean("")
	echoClean("Going to do (steps marked * only if needed, based on repo state):")
	preview(cmdName)
	// Said once here, where you can still say no, and again by each step as it
	// skips. repo-* has no park push to skip - it probes its own remote and fails
	// on its own terms.
	if !strings.HasPrefix(cmdName, "repo-") && isOffline() {
		echoClean("")
		echoClean("WARNING: remote unreachable - nothing will be pushed; the work stays local.")
	}
	// Last thing before the prompt, so it can't scroll away above the plan.
	if identityMismatch != "" {
		echoClean("")
		echoStatus("*** WRONG ACCOUNT? ***")
		echoClean("  " + identityMismatch)
		echoClean("  gh does the pull request work, so it happens as '" + ghLogin() + "'.")
		echoClean("  Continue only if that is what you mean. (--any-identity silences this.)")
	}
	if !quiet {
		echoClean("")
		if !promptYN("Continue? (y|n): ") {
			echoStatus("User aborted.")
			echoClean("")
			os.Exit(1)
		}
	}

	switch cmdName {
	case "update":
		cmdCommitPull()
	case "sync":
		cmdPush()
	case "br-create":
		cmdNewBranch(cmdArg, mergeTarget())
	case "br-hotfix":
		cmdNewBranch(cmdArg, defaultBranch())
	case "br-switch":
		cmdGoBranch(cmdArg)
	case "br-land":
		cmdLand()
	case "br-prune":
		cmdPrune()
	case "pr":
		if prSub == "create" {
			cmdPrCreate()
		} else {
			cmdPrAccept()
		}
	case "release":
		cmdRelease()
	}

	echoClean("")
	showStatus(false)
	echoStatus("")
	echoStatus("Done.")
	echoClean("")
}
