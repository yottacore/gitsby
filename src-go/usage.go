// What each command takes, in one table. The Syntax refusals and the help screen's
// command list both read it, so a placeholder has 1 name everywhere.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"slices"
	"strings"
)

type cmdUsage struct {
	cmd   string // as typed, such as "br create"
	args  string // its placeholders, such as "<branch>"
	group string // the help screen heading it goes under
	help  string // its line on the help screen
	defs  []placeholder
	lines func() []string // a whole block, for the account commands that list their keys
}

const (
	grpCommon = "Common commands:"
	grpSetup  = "One-time setup commands:"
	grpLess   = "Less common commands:"
	grpAdmin  = "Admin commands, e.g. for small solo projects:"
	grpScript = "For scripts:"
)

var (
	messageDef   = placeholder{"[message]", "The commit message. Without it, git's editor opens, or under -q one is made up."}
	urlDef       = placeholder{"<url>", "The repo's https or ssh address, e.g. https://github.com/pat/app.git."}
	ownerNameDef = placeholder{"<owner/name>", "A GitHub account or organization, a slash, and the repo's name, e.g. pat/app."}
	prNumberDef  = placeholder{"<number>", "The pull request's number, e.g. 42. A bare 'pr' lists them."}
)

// usages is in help screen order.
var usages = []cmdUsage{
	{cmd: "pullcom", args: "[message]", group: grpCommon, help: "Pull updates, then commit all local changes. Do frequently!", defs: []placeholder{messageDef}},
	{cmd: "br create", args: "<branch>", group: grpCommon, help: "Create a new branch off " + mergeTargetLabel + " (current work is carried or parked).",
		defs: []placeholder{{"<branch>", "The branch to create off " + mergeTargetLabel + ", e.g. login-form."}}},
	{cmd: "br switch", args: "[branch]", group: grpCommon, help: "Switch to a branch (parks current work first). No arg: back to " + mergeTargetLabel + ".",
		defs: []placeholder{{"[branch]", "The branch to switch to. Without it, " + mergeTargetLabel + "."}}},
	{cmd: "br", args: "[list]", group: grpCommon, help: "Fetch and list branches."},
	{cmd: "status", group: grpCommon, help: "Fetch and show current status."},

	{cmd: "repo clone", args: "<url> [directory]", group: grpSetup, help: "Clone a repo you don't have yet (checks out dev if it has one).",
		defs: []placeholder{urlDef, {"[directory]", "The folder to clone into. Without it, a folder named after the repo."}}},
	{cmd: "repo create", args: "<owner/name>", group: grpSetup, help: "Create the GitHub repo via gh, then connect this directory and push.", defs: []placeholder{ownerNameDef}},
	{cmd: "repo connect", args: "[<url> | <owner/name>]", group: grpSetup, help: "Connect this directory to an existing empty remote, and push. Without either, origin.",
		defs: []placeholder{urlDef, ownerNameDef}},
	{cmd: "repo url", args: "[https|ssh]", group: grpSetup, help: "Show how origin authenticates, or switch it between the two.",
		defs: []placeholder{{"[https|ssh]", "Switches origin to that kind of address. Without it, 'repo url' shows which one origin uses."}}},
	{cmd: "account", args: "[list]", group: grpSetup, help: "Show your configured accounts, and which one this folder uses."},
	{cmd: "account set", args: "<account> <key> <value>", group: grpSetup, help: "Set one key of one account, e.g. 'account set gitea.com_my-login host gitea.com'.", lines: accountSetLines},
	{cmd: "account unset", args: "<account> <key>", group: grpSetup, help: "Remove one key from one account, e.g. 'account unset gitea.com_my-login host'.", lines: accountUnsetLines},
	{cmd: "account apply", group: grpSetup, help: "Teach plain git the same folder rules, so 'git' outside gitsby matches."},

	{cmd: "sync", args: "[message]", group: grpLess, help: "Pull, commit, and push (pullcom, plus the push). Do infrequently.", defs: []placeholder{messageDef}},
	{cmd: "whoami", group: grpLess, help: "Show account, ssh key, commit author, git host login."},

	{cmd: "br merge", args: "[message]", group: grpAdmin, help: "Merge current branch into " + mergeTargetLabel + " (--no-ff), push, delete it local + remote.",
		defs: []placeholder{{"[message]", "The merge commit's message. Without it, git's editor opens, or under -q one is made up."}}},
	{cmd: "br prune", group: grpAdmin, help: "Delete branches already merged into " + mergeTargetLabel + ", local + remote."},
	{cmd: "br hotfix", args: "<name>", group: grpAdmin, help: "Branch off the default branch, to correct what's already published.",
		defs: []placeholder{{"<name>", "The fix's branch name, e.g. crash-on-start. It is created as hotfix/<name>, off the default branch."}}},
	{cmd: "pr", args: "[list]", group: grpAdmin, help: "List pull requests (gh on GitHub, glab on GitLab, tea on Gitea)."},
	{cmd: "pr", args: "<number>", group: grpAdmin, help: "View a pull request and its diff.", defs: []placeholder{prNumberDef}},
	{cmd: "pr create", args: "[title]", group: grpAdmin, help: "Push this branch and open a pull request against " + mergeTargetLabel + ".",
		defs: []placeholder{{"[title]", "The new pull request's title. Without it, the last commit's subject."}}},
	{cmd: "pr ok", args: "<number>", group: grpAdmin, help: "Approve and merge a pull request.", defs: []placeholder{prNumberDef}},
	{cmd: "release", args: "[version]", group: grpAdmin, help: "Cut a release: merge dev into main, tag, push. No version: next after latest tag.",
		defs: []placeholder{{"[version]", "X.Y.Z, with an optional -suffix such as 1.4.0-beta.1, and an optional leading v. Without it, the next patch version after the latest tag."}}},

	{cmd: "raw", args: "<tool> <arguments ...>", group: grpScript, help: "Run git, gh, tea, glab, lazygit or tig as the account this folder belongs to.",
		defs: []placeholder{{"<tool>", "One of " + strings.Join(rawTools, ", ") + ", run as the account this folder belongs to."}, {"<arguments ...>", "Handed to that tool unchanged."}}},
}

// usageOf is a command's first entry. Asking for one that isn't there is a bug here,
// so it panics rather than print an empty Syntax line.
func usageOf(cmd string) cmdUsage {
	for _, u := range usages {
		if u.cmd == cmd {
			return u
		}
	}
	panic("no usage for " + cmd)
}

func (u cmdUsage) syntax() string { return strings.TrimSpace(u.cmd + " " + u.args) }

// refuse is the Syntax refusal for a command typed wrong, under an optional lead.
func (u cmdUsage) refuse(lead string) error {
	if u.lines != nil {
		return &usageError{msg: strings.Join(u.lines(), "\n")}
	}
	return syntaxUsage(lead, u.syntax(), u.defs...)
}

// nounRefusal is the Syntax block for a noun as a whole: each verb with its
// placeholders, and each placeholder defined once. A noun with a bare form, like
// 'pr', shows its verbs as optional.
func nounRefusal(noun string) error {
	var alts []string
	var defs []placeholder
	seen := map[string]bool{}
	optional := false
	for _, u := range usages {
		verb, ok := strings.CutPrefix(u.cmd, noun)
		if !ok || (verb != "" && verb[0] != ' ') {
			continue
		}
		alt := strings.TrimSpace(strings.TrimSpace(verb) + " " + u.args)
		switch alt {
		case "":
			optional = true
			continue
		case "[list]": // the noun alone lists, so 'list' is one more verb
			optional, alt = true, "list"
		}
		alts = append(alts, alt)
		for _, d := range u.defs {
			if !seen[d.name] {
				seen[d.name] = true
				defs = append(defs, d)
			}
		}
	}
	open, shut := "<", ">"
	if optional {
		open, shut = "[", "]"
	}
	return syntaxUsage("", noun+" "+open+strings.Join(alts, " | ")+shut, defs...)
}

// helpLine is a command's line on the help screen, its syntax padded with dots so the
// descriptions line up. A syntax too long for the column moves into the description.
func (u cmdUsage) helpLine() string {
	const col = 20
	label, text := u.syntax(), u.help
	if len(label) > col {
		label, text = u.cmd, u.args+". "+text
	}
	switch pad := col - len(label); pad {
	case 0:
	case 1:
		label += " "
	default:
		label += " " + strings.Repeat(".", pad-1)
	}
	return "  " + label + ": " + text
}

// helpFor is the block '<command> --help' prints. Nil means the whole help screen:
// no command was typed, or one the parser doesn't know.
func helpFor(argv []string) []string {
	var words []string
	var pending *optSpec
	endOpts := false
	for _, arg := range argv {
		switch {
		case pending != nil:
			pending = nil
		case arg == "--" && !endOpts:
			endOpts = true
		case !endOpts && switchRegex.MatchString(arg):
			if spec, joined := lookupOption(stripDashes(strings.ToLower(arg))); spec != nil && spec.value && !joined {
				pending = spec
			}
		default:
			words = append(words, arg)
		}
	}
	if len(words) == 0 {
		return nil
	}
	if len(words) == 1 {
		switch strings.ToLower(words[0]) {
		case "repo", "repository":
			return nounHelp("repo")
		case "br", "branch":
			return nounHelp("br")
		case "account", "acct":
			return nounHelp("account")
		case "pr":
			return nounHelp("pr")
		}
	}
	cmd := command{name: words[0]}
	if len(words) > 1 {
		cmd.arg = words[1]
	}
	cmd, err := collapseCommand(cmd)
	if err != nil {
		return nil
	}
	name := typedName(cmd)
	switch {
	case cmd.name == "pr" && cmd.arg != "" && prNumRE.MatchString(cmd.arg):
		return usages[slices.IndexFunc(usages, func(u cmdUsage) bool { return u.cmd == "pr" && u.args == "<number>" })].helpBlock()
	case name == "br list" || name == "account list":
		name = strings.TrimSuffix(name, " list")
	}
	for _, u := range usages {
		if u.cmd == name {
			return u.helpBlock()
		}
	}
	return nil
}

// helpBlock is the Syntax block, what the command does, and the options it takes.
func (u cmdUsage) helpBlock() []string {
	var lines []string
	if u.lines != nil {
		lines = u.lines()
	} else {
		lines = strings.Split(u.refuse("").Error(), "\n")
		var what []string
		for _, l := range wrapWords(u.help, noteWidth+16) {
			what = append(what, "  "+l)
		}
		lines = slices.Insert(lines, 1, what...)
	}
	var opts []string
	for _, spec := range optSpecs {
		if spec.cmds == nil || slices.Contains(spec.cmds, u.cmd) {
			opts = append(opts, spec.shown)
		}
	}
	return append(lines, "  Options: "+strings.Join(opts, ", ")+".")
}

// nounHelp is a noun's block, with each verb's own '--help' named under it.
func nounHelp(noun string) []string {
	lines := strings.Split(nounRefusal(noun).Error(), "\n")
	return append(lines, "  Each verb has its own, as '"+meName+" "+noun+" <verb> --help'.")
}
