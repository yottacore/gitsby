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

// State written by the ported shared layer whose readers land with the command
// slice. The unused check has no ignore directive, and turning the whole check
// off would hide real rot, so this anchor marks them used until then.
var _ = []any{commitMessage, doFetch, repoVisibility, configFileUsed,
	accountNoToken, accountUsedHttpsAuth, accountUsedSSHKey, accountUsedIdentity, ghSwitchedFrom}

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

func main() {
	args := os.Args[1:]

	// Only the command slot counts for help and the version - scanning the whole
	// argv would make a message like "add -v flag" silently short-circuit.
	if len(args) == 0 {
		notYet()
	}
	switch strings.ToLower(args[0]) {
	case "-h", "--help", "help":
		notYet()
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

	mustBeInPath("git")
	if parseArgs(args) {
		notYet() // help asked mid-line; the help text lands with the command slice
	}
	// Both visibilities given is a contradiction, not a precedence question - and
	// silently picking one would publish a repo the caller believes is the other.
	if sawPublic && sawPrivate {
		throwUsage("--public and --private are mutually exclusive; pick one.")
	}
	collapseCommand()
	// The scripts resolve the account - and so validate --config - before any
	// command runs; keep that contract while the commands themselves are pending.
	loadConfig()

	notYet()
}
