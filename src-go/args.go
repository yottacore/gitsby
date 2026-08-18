// Argument parsing: the option vocabulary, the positional slots, the grouped-noun
// collapse, and the 'raw' passthrough prescan. Options are lowercased FIRST, then
// the dashes stripped, so no two entry points can accept different spellings of
// the same option.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strconv"
	"strings"
)

var (
	cmdName               = "" // positional 1: flat command, or the noun of a grouped one
	cmdArg                = "" // positional 2: subcommand for a grouped noun, else message/branch/version/PR number
	cmdArg2               = "" // positional 3
	cmdArg3               = "" // positional 4: only 'repo clone <url> [dir]' goes this deep
	sawPublic, sawPrivate bool // to catch both being given
	anyIdentity           bool // --any-identity: a gh/ssh account mismatch here is intended
	configFileArg         = ""
	configFileGiven       bool // whether it was typed at all: '--config ""' is a mistake, not a fallback
)

// Option state the commands read once they land; the parser has to take the whole
// vocabulary from day one so no spelling is refused now and accepted later.
var (
	commitMessage  = ""
	doFetch        = true // cleared by --no-fetch
	repoVisibility = "private"
)

var switchRegex = regexp.MustCompile(`^--?[^ -]`)

func stripDashes(s string) string {
	for strings.HasPrefix(s, "-") {
		s = s[1:]
	}
	return s
}

// afterEq is the value of a joined option, from the argument as typed - the
// normalized copy is for matching only, a file name or message keeps its case.
func afterEq(arg string) string { return arg[strings.Index(arg, "=")+1:] }

// parseArgs fills the option and positional state. Returns true when help was
// asked for - from any position: '<noun> <verb> --help' is the reflex every git
// user has, and slot 1 always holds a real command, so nothing can be shadowed.
// -v is deliberately not an option here - it must not turn a mutating command
// into a silent no-op.
func parseArgs(args []string) bool {
	const maxPositional = 4
	lastSwitch, lastSwitchAsPassed := "", ""
	expectingValue := false
	positional := 0
	for _, arg := range args {
		if expectingValue {
			// A value we are already waiting for wins over the option test:
			// '-m -Wall added' is a commit message, and there is no other way to
			// write one starting with '-'.
			switch lastSwitch {
			case "m", "message", "msg":
				commitMessage = arg
			case "config":
				configFileArg, configFileGiven = arg, true
			default:
				throwUsage("Unknown option: '" + lastSwitchAsPassed + "', current parameter: '" + arg + "'.")
			}
			expectingValue = false
		} else if switchRegex.MatchString(arg) {
			lastSwitchAsPassed = arg
			t := stripDashes(strings.ToLower(arg))
			lastSwitch = t
			switch {
			case t == "h" || t == "help":
				return true
			case t == "q" || t == "quiet" || t == "y" || t == "yes":
				quiet = true
			case t == "no-fetch" || t == "nofetch" || t == "offline":
				doFetch = false
			case t == "public":
				repoVisibility, sawPublic = "public", true
			case t == "private":
				repoVisibility, sawPrivate = "private", true
			case t == "any-identity" || t == "anyidentity":
				anyIdentity = true
			case strings.HasPrefix(t, "m=") || strings.HasPrefix(t, "message=") || strings.HasPrefix(t, "msg="):
				commitMessage = afterEq(arg)
			case strings.HasPrefix(t, "config="):
				configFileArg, configFileGiven = afterEq(arg), true
			case t == "m" || t == "message" || t == "msg":
				expectingValue = true
			case t == "config":
				expectingValue = true
			default:
				throwUsage("Unexpected option in this context: '" + arg + "'.")
			}
		} else {
			positional++
			if positional > maxPositional {
				throwUsage("Too many positional arguments: " + strconv.Itoa(positional) + ", for max of " + strconv.Itoa(maxPositional) + ".")
			}
			switch positional {
			case 1:
				cmdName = arg
			case 2:
				cmdArg = arg
			case 3:
				cmdArg2 = arg
			case 4:
				cmdArg3 = arg
			}
		}
	}
	if expectingValue {
		throwUsage("Never received a parameter for switch '--" + lastSwitch + "'.")
	}
	return false
}

// collapseCommand folds '<noun> <verb>' to one internal token and shifts the
// positionals down, so everything downstream deals with a single flat name. No
// real command has a hyphen, so rejecting one keeps the tokens untypeable.
func collapseCommand() {
	cmdName = strings.ToLower(cmdName)
	if strings.Contains(cmdName, "-") {
		throwUsage("Unknown command '" + cmdName + "'. Run '" + meName + "' with no arguments for a list.")
	}
	shift := true
	switch cmdName {
	case "repo", "repository":
		switch strings.ToLower(cmdArg) {
		case "clone":
			cmdName = "repo-clone"
		case "create", "new":
			cmdName = "repo-create"
		case "connect":
			cmdName = "repo-connect"
		case "url":
			cmdName = "repo-url"
		case "":
			throwUsage("Syntax: " + meName + " repo <clone <url> [dir] | create <owner/name> | connect [url] | url [https|ssh]>")
		default:
			throwUsage("Unknown 'repo' subcommand '" + cmdArg + "'. One of: clone, create, connect, url.")
		}
	case "account", "acct":
		switch strings.ToLower(cmdArg) {
		case "", "list", "show":
			cmdName = "account-list"
		case "apply":
			cmdName = "account-apply"
		default:
			throwUsage("Unknown 'account' subcommand '" + cmdArg + "'. One of: list, apply.")
		}
	case "br", "branch":
		switch strings.ToLower(cmdArg) {
		case "", "list":
			cmdName = "br-list"
		case "create", "new":
			cmdName = "br-create"
		case "hotfix":
			cmdName = "br-hotfix"
		case "switch", "go":
			cmdName = "br-switch"
		case "land":
			cmdName = "br-land"
		case "prune", "clean":
			cmdName = "br-prune"
		default:
			throwUsage("Unknown 'br' subcommand '" + cmdArg + "'. One of: list, create, hotfix, switch, land, prune.")
		}
	default:
		shift = false
	}
	if shift {
		cmdArg, cmdArg2, cmdArg3 = cmdArg2, cmdArg3, ""
	}
}

// scanPassthrough spots 'raw <git|gh>' ahead of the main parser, because past the
// tool name the arguments belong to the tool: a '-q' there is its own flag, not
// ours. Ours come first. The whole option vocabulary is taken here, spelled and
// normalized the same way as the main parser; the ones with nothing to act on in
// a passthrough are inert. -h and -v fall through on purpose - they mean show
// help or the version, which is the main parser's job.
func scanPassthrough(argv []string) (string, []string) {
	tool := ""
	var ptArgs []string
	wantConfig, wantTool, wantValue := false, false, false
scan:
	for _, arg := range argv {
		switch {
		case tool != "":
			ptArgs = append(ptArgs, arg)
		case wantConfig:
			configFileArg, configFileGiven = arg, true
			wantConfig = false
		case wantValue:
			wantValue = false
		case wantTool:
			if arg != "git" && arg != "gh" {
				throwUsage("Unknown 'raw' subcommand '" + arg + "'. One of: git, gh.")
			}
			tool, wantTool = arg, false
		case arg == "raw":
			wantTool = true
		case !strings.HasPrefix(arg, "-"):
			break scan
		default:
			opt := stripDashes(strings.ToLower(arg))
			switch {
			case opt == "q" || opt == "quiet" || opt == "y" || opt == "yes":
				quiet = true
			case opt == "config":
				wantConfig = true
			case strings.HasPrefix(opt, "config="):
				configFileArg, configFileGiven = afterEq(arg), true
			case opt == "no-fetch" || opt == "nofetch" || opt == "offline":
			case opt == "any-identity" || opt == "anyidentity":
			case opt == "public" || opt == "private":
			case opt == "m" || opt == "message" || opt == "msg":
				wantValue = true
			case strings.HasPrefix(opt, "m=") || strings.HasPrefix(opt, "message=") || strings.HasPrefix(opt, "msg="):
			default:
				break scan
			}
		}
	}
	if wantTool {
		throwUsage("Syntax: " + meName + " raw <git|gh> <arguments ...>")
	}
	return tool, ptArgs
}
