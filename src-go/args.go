// Argument parsing. Options are lowercased first, then the dashes stripped, so no 2
// entry points take different spellings. Nothing here touches the repo.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"slices"
	"strings"
)

func defaultOptions() options {
	return options{fetch: true, visibility: "private"}
}

// optSpec is one of gitsby's own options. parseArgs and scanPassthrough both read
// optSpecs, so they can't take different ones. An option with cmds is refused on any
// other command rather than dropped. Without cmds it means something everywhere, or
// asks for nothing a command could fail to do, like --no-fetch where nothing fetches.
type optSpec struct {
	shown     string   // as messages print it
	spellings []string // lowercased, dashes stripped
	value     bool     // takes a value, joined by '=' or as the next argument
	cmds      []string // the commands that read it, as typed
	set       func(o *options, v string)
}

// stagedCmds commit before they move, so --staged has something to narrow.
var stagedCmds = []string{"pullcom", "sync", "br create", "br hotfix", "br switch", "br merge", "pr create", "release"}

var optSpecs = []optSpec{
	{shown: "-q", spellings: []string{"q", "quiet", "y", "yes"}, set: func(o *options, _ string) { o.quiet = true }},
	{shown: "--no-fetch", spellings: []string{"no-fetch", "nofetch"}, set: func(o *options, _ string) { o.fetch = false }},
	{shown: "--any-identity", spellings: []string{"any-identity", "anyidentity"}, set: func(o *options, _ string) { o.anyIdentity = true }},
	{shown: "--config", spellings: []string{"config"}, value: true, set: func(o *options, v string) { o.configFile, o.configGiven = v, true }},
	{shown: "--public", spellings: []string{"public"}, cmds: []string{"repo create"}, set: func(o *options, _ string) { o.visibility, o.sawPublic = "public", true }},
	{shown: "--private", spellings: []string{"private"}, cmds: []string{"repo create"}, set: func(o *options, _ string) { o.visibility, o.sawPrivate = "private", true }},
	{shown: "--direct", spellings: []string{"direct"}, cmds: []string{"sync"}, set: func(o *options, _ string) { o.direct = true }},
	{shown: "--staged", spellings: []string{"staged"}, cmds: stagedCmds, set: func(o *options, _ string) { o.staged = true }},
	// The commands that commit, which is the --staged list plus the 2 that publish a
	// directory.
	{shown: "-m", spellings: []string{"m", "message", "msg"}, value: true, cmds: append(slices.Clone(stagedCmds), "repo create", "repo connect"),
		set: func(o *options, v string) { o.message = v }},
}

// lookupOption finds the option a lowercased, dash-stripped argument names, and
// whether its value was joined on with '='.
func lookupOption(t string) (spec *optSpec, joined bool) {
	for i := range optSpecs {
		for _, s := range optSpecs[i].spellings {
			if t == s {
				return &optSpecs[i], false
			}
			if optSpecs[i].value && strings.HasPrefix(t, s+"=") {
				return &optSpecs[i], true
			}
		}
	}
	return nil, false
}

func (o *options) apply(spec *optSpec, v string) {
	spec.set(o, v)
	if o.typed == nil {
		o.typed = map[string]bool{}
	}
	o.typed[spec.shown] = true
}

// checkOptionsUsed refuses an option typed for a command that doesn't read it.
// Dropping it would make a typo look like it did what was meant, and for --staged it
// would sweep in the edits it was typed to keep out. 'cmd' is as typed, such as
// "br create" or "raw".
func checkOptionsUsed(cmd string, opt options) error {
	for _, spec := range optSpecs {
		if spec.cmds == nil || !opt.typed[spec.shown] || slices.Contains(spec.cmds, cmd) {
			continue
		}
		return usagef("%s works with %s.", spec.shown, andList(spec.cmds))
	}
	return nil
}

// andList joins words as a sentence does: "a, b and c".
func andList(words []string) string {
	if len(words) < 2 {
		return strings.Join(words, "")
	}
	return strings.Join(words[:len(words)-1], ", ") + " and " + words[len(words)-1]
}

// typedName is the command as a person types it, for messages and the option check.
func typedName(cmd command) string {
	if cmd.name == "pr" {
		if sub := strings.ToLower(cmd.arg); sub == "create" || sub == "new" || sub == "ok" {
			return "pr " + strings.Replace(sub, "new", "create", 1)
		}
		return "pr"
	}
	return strings.Replace(cmd.name, "-", " ", 1)
}

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

// parseArgs fills the option and positional state. 'info' is help, version, about or
// donate, from any position. -v is no option here, so it can't make a mutating command a
// no-op.
func parseArgs(argv []string) (opt options, cmd command, info string, err error) {
	const maxPositional = 5
	opt = defaultOptions()
	cmd = command{mutating: true}
	lastSwitch := ""
	var pending *optSpec // an option still waiting for its value
	positional := 0
	for _, arg := range argv {
		switch {
		case pending != nil:
			// A value we are already waiting for wins over the option test:
			// '-m -Wall added' is a commit message.
			opt.apply(pending, arg)
			pending = nil
		case switchRegex.MatchString(arg):
			t := stripDashes(strings.ToLower(arg))
			lastSwitch = t
			switch t {
			case "h", "help":
				return opt, cmd, "help", nil
			case "version", "ver":
				return opt, cmd, "version", nil
			case "about", "donate":
				return opt, cmd, t, nil
			case "offline":
				// Old spelling of --no-fetch, and a lie: it never stopped a push.
				return opt, cmd, "", usagef("There is no --offline option. Offline is a state gitsby finds by trying, not one you declare; use --no-fetch to skip the pre-command fetch (pushes still go out).")
			}
			spec, joined := lookupOption(t)
			switch {
			case spec == nil:
				return opt, cmd, "", usagef("Unexpected option in this context: '%s'.", arg)
			case spec.value && !joined:
				pending = spec
			default:
				opt.apply(spec, afterEq(arg))
			}
		default:
			positional++
			if positional > maxPositional {
				return opt, cmd, "", usagef("Too many positional arguments: %d, for max of %d. If that was a message or title, quote it.", positional, maxPositional)
			}
			switch positional {
			case 1:
				cmd.name = arg
			case 2:
				cmd.arg = arg
			case 3:
				cmd.arg2 = arg
			case 4:
				cmd.arg3 = arg
			case 5:
				cmd.arg4 = arg
			}
		}
	}
	if pending != nil {
		return opt, cmd, "", usagef("Never received a parameter for switch '--%s'.", lastSwitch)
	}
	return opt, cmd, "", nil
}

// collapseCommand folds '<noun> <verb>' to one internal token and shifts the
// positionals down, so everything downstream deals with a single flat name. No
// real command has a hyphen, so rejecting one keeps the tokens untypeable.
func collapseCommand(cmd command) (command, error) {
	cmd.name = strings.ToLower(cmd.name)
	if strings.Contains(cmd.name, "-") {
		return cmd, usagef("Unknown command '%s'. Run '%s' with no arguments for a list.", cmd.name, meName)
	}
	// The one prefix ladder in the tool, since this is the command typed all day. Don't
	// spread it. 'update' is the 2.1.0 name; 'pull' is safe, since the bare pull is
	// gone.
	switch cmd.name {
	case "update", "pull", "pullc", "pullco", "pullcom", "pullcomm", "pullcommi", "pullcommit":
		cmd.name = "pullcom"
	// 'identity' is the name this command was born with, and 'who' is the question
	// shortened. Both permanent: a spelling that ever worked has to keep working.
	case "who", "identity":
		cmd.name = "whoami"
	}
	shift := true
	switch cmd.name {
	case "repo", "repository":
		switch strings.ToLower(cmd.arg) {
		case "clone":
			cmd.name = "repo-clone"
		case "create", "new":
			cmd.name = "repo-create"
		case "connect":
			cmd.name = "repo-connect"
		case "url":
			cmd.name = "repo-url"
		case "":
			return cmd, nounRefusal("repo")
		default:
			return cmd, usagef("Unknown 'repo' subcommand '%s'. One of: clone, create, connect, url.", cmd.arg)
		}
	case "pr":
		// The flat name stays 'pr', since the rest reads the verb from pr.sub. Only the
		// word is settled here, so an unknown one is refused the way the other nouns'
		// are.
		shift = false
		switch sub := strings.ToLower(cmd.arg); {
		case sub == "" || sub == "list":
			cmd.arg = ""
		case sub == "create" || sub == "new":
			cmd.arg = "create"
		case sub == "ok":
			cmd.arg = "ok"
		case prNumRE.MatchString(sub):
		default:
			return cmd, usagef("Unknown 'pr' subcommand '%s'. One of: list, create, ok, or a pull request number.", cmd.arg)
		}
	case "account", "acct":
		switch strings.ToLower(cmd.arg) {
		case "", "list", "show":
			cmd.name = "account-list"
		case "apply":
			cmd.name = "account-apply"
		case "set":
			cmd.name = "account-set"
		case "unset":
			cmd.name = "account-unset"
		default:
			return cmd, usagef("Unknown 'account' subcommand '%s'. One of: list, set, unset, apply.", cmd.arg)
		}
	case "br", "branch":
		switch strings.ToLower(cmd.arg) {
		case "", "list":
			cmd.name = "br-list"
		case "create", "new":
			cmd.name = "br-create"
		case "hotfix":
			cmd.name = "br-hotfix"
		case "switch", "go":
			cmd.name = "br-switch"
		case "merge", "land":
			cmd.name = "br-merge"
		case "prune", "clean":
			cmd.name = "br-prune"
		default:
			return cmd, usagef("Unknown 'br' subcommand '%s'. One of: list, create, hotfix, switch, merge, prune.", cmd.arg)
		}
	default:
		shift = false
	}
	if shift {
		cmd.arg, cmd.arg2, cmd.arg3, cmd.arg4 = cmd.arg2, cmd.arg3, cmd.arg4, ""
	}
	return cmd, nil
}

// sortCommand validates each command's argument shape and settles whether it
// mutates. Trailing arguments are rejected everywhere, so silently ignoring one
// anywhere would make a typo look like it did what you meant.
func sortCommand(cmd command, opt *options) (command, error) {
	switch cmd.name {
	case "status", "whoami", "br-list":
		// br list's extra goes in cmd.arg too, after the noun shift, so one test
		// covers both.
		cmd.mutating = false
		if cmd.arg != "" {
			return cmd, usagef("'%s %s' takes no arguments (got '%s').", meName, strings.Replace(cmd.name, "br-list", "br list", 1), cmd.arg)
		}
	case "account-list":
		cmd.mutating = false
		if cmd.arg != "" {
			return cmd, usagef("'%s account list' takes no arguments (got '%s').", meName, cmd.arg)
		}
	case "account-apply":
		if cmd.arg != "" {
			return cmd, usagef("'%s account apply' takes no arguments (got '%s').", meName, cmd.arg)
		}
	case "account-set":
		// Three words exactly. A missing value would otherwise read as a request to
		// set the key empty, which is a different thing from what anybody typed.
		if cmd.arg == "" || cmd.arg2 == "" || cmd.arg3 == "" {
			return cmd, accountSetUsage()
		}
		// Returns here rather than falling through: this is the one command whose
		// third positional is a value it wants, and the tail below rejects one.
		return cmd, nil
	case "account-unset":
		if cmd.arg == "" || cmd.arg2 == "" {
			return cmd, accountUnsetUsage()
		}
		// A value typed after the key reads like a request to remove only that one,
		// and this removes them all, so it is refused rather than dropped.
		if cmd.arg3 != "" {
			return cmd, usagef("'%s account unset' takes an account and a key, and removes every '%s' line in that block (got '%s' too).", meName, cmd.arg2, cmd.arg3)
		}
		return cmd, nil
	case "pr":
		switch strings.ToLower(cmd.arg) {
		case "create", "new":
			if cmd.arg3 != "" {
				return cmd, usagef("Unexpected extra argument '%s'; quote your title.", cmd.arg3)
			}
		case "ok":
		default:
			// A number, or nothing. Either way there is no third word.
			cmd.mutating = false
			if cmd.arg2 != "" {
				return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg2)
			}
		}
	case "pullcom", "sync", "br-merge":
		if opt.message == "" {
			opt.message = cmd.arg
		}
		if cmd.arg2 != "" {
			return cmd, usagef("Unexpected extra argument '%s'; quote your commit message.", cmd.arg2)
		}
	case "repo-clone": // the only one with a second argument of its own (the target directory)
	case "br-prune":
		// Takes nothing: what it deletes is decided by repo state, never by a name
		// on the command line.
		if cmd.arg != "" {
			return cmd, usagef("'%s br prune' takes no arguments (got '%s'); it prunes every branch already merged.", meName, cmd.arg)
		}
	case "br-create", "br-hotfix", "br-switch", "release", "repo-create", "repo-connect":
		if cmd.arg2 != "" {
			return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg2)
		}
	case "repo-url":
		// Bare is the read-only "what is it now"; naming a transport is what makes
		// it mutate.
		if cmd.arg2 != "" {
			return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg2)
		}
		if cmd.arg == "" {
			cmd.mutating = false
		}
	default:
		return cmd, usagef("Unknown command '%s'. Run '%s' with no arguments for a list.", cmd.name, meName)
	}
	if cmd.arg4 != "" {
		return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg4)
	}
	if cmd.arg3 != "" {
		return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg3)
	}
	return cmd, nil
}

// scanPassthrough spots 'raw <tool>' ahead of the main parser, since past the tool name
// the arguments are the tool's. -h and -v fall through to the main parser.
func scanPassthrough(argv []string, opt *options) (string, []string, error) {
	tool := ""
	var ptArgs []string
	var pending *optSpec
	wantTool := false
scan:
	for _, arg := range argv {
		switch {
		case tool != "":
			ptArgs = append(ptArgs, arg)
		case pending != nil:
			opt.apply(pending, arg)
			pending = nil
		case wantTool:
			// Past the tool name every option is the tool's, so one typed here is
			// ours arriving too late - not a subcommand nobody has heard of.
			if strings.HasPrefix(arg, "-") {
				return "", nil, usageOf("raw").refuse("'" + arg + "' is an option, and " + meName + "'s own options come before 'raw'.")
			}
			if !slices.Contains(rawTools, arg) && arg != "tea-cli" {
				return "", nil, usagef("Unknown 'raw' subcommand '%s'. One of: %s.", arg, strings.Join(rawTools, ", "))
			}
			tool, wantTool = arg, false
		case arg == "raw":
			wantTool = true
		case !strings.HasPrefix(arg, "-"):
			break scan
		default:
			// Anything not in the table, -h and -v among them, is the main parser's.
			spec, joined := lookupOption(stripDashes(strings.ToLower(arg)))
			switch {
			case spec == nil:
				break scan
			case spec.value && !joined:
				pending = spec
			default:
				opt.apply(spec, afterEq(arg))
			}
		}
	}
	if wantTool {
		return "", nil, usageOf("raw").refuse("")
	}
	if tool != "" {
		if err := checkOptionsUsed("raw", *opt); err != nil {
			return "", nil, err
		}
	}
	return tool, ptArgs, nil
}

// rawTools are what 'raw' fronts: git, the git host CLIs, and the front ends
// that run git underneath. gitui is missing on purpose - it goes through libgit2,
// which never reads the GIT_CONFIG_* the account is applied through. tea is also
// taken as 'tea-cli', Debian's name for it.
var rawTools = []string{"git", "gh", "tea", "glab", "lazygit", "tig"}
