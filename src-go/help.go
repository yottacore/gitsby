// The help text: what gitsby is, and one line per command. Written out rather than
// generated from a table, because the grouping and the dotted leaders are the point -
// this is the first thing anyone reads.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

func (a *app) printCopyright() {
	a.out.clean("")
	a.out.cleanf("%s %s", meName, versionText())
	a.out.cleanf("Copyright © %s %s.", copyrightYear, author)
	a.out.clean("Licensed under The MIT License (MIT). Full text at:")
	a.out.clean("  https://mit-license.org/")
	a.out.clean("No Warranty.")
	a.out.clean("")
}

// printVersion is the whole of --version: one line, for a script to read back.
func (a *app) printVersion() {
	a.out.cleanf("%s %s", meName, versionText())
}

func (a *app) printBlurb() {
	a.out.clean("")
	a.out.clean("Safer, state-checked wrappers for everyday git. Every command verifies the")
	a.out.clean("repo state before acting (commit only if dirty, pull only with an upstream,")
	a.out.clean("push only if ahead), so each is idempotent and safe to re-run.")
	a.out.clean("")
}

func (a *app) printAbout() {
	a.printCopyright()
	a.printBlurb()
	a.out.clean("  " + homeURL)
	a.out.clean("")
}

func (a *app) printDonate() {
	a.out.clean("")
	a.printBanner()
	a.out.clean("Gitsby is free, and built and maintained in spare time. A star or a mention")
	a.out.clean("helps other people find it. If it is saving you real time, sponsorship is")
	a.out.clean("welcome, and never expected.")
	a.out.clean("")
	a.out.clean("  " + donateURL)
	a.out.clean("  " + kofiURL)
	a.out.clean("")
}

func (a *app) printSyntax() {
	a.out.clean("")
	group := ""
	for _, u := range usages {
		if u.group != group {
			group = u.group
			a.out.clean(group)
		}
		a.out.clean(u.helpLine())
	}
	a.out.clean("Options:")
	a.out.clean("  -m, --message MSG ....: Commit or merge message (or give it positionally).")
	a.out.clean("  -q, -y, --quiet, --yes: Assume yes - no prompts; if committing with no message, one is generated.")
	a.out.clean("  --public / --private .: Visibility for the repo 'repo create' makes (default: private).")
	a.out.clean("  --any-identity .......: Act as the git host CLI's active account, and proceed when it differs from the remote's ssh key.")
	a.out.clean("  --direct .............: Let sync push straight to main, dev or the default branch, with no warning.")
	a.out.clean("  --no-fetch ...........: Skip the pre-command fetch, and the pull. (Pushes still go out.)")
	a.out.clean("  --staged .............: Commit only what is staged, and leave the rest of the tree as it is.")
	a.out.clean("  --config FILE ........: Read accounts from FILE instead of the usual config location.")
	a.out.clean("  -- ...................: End of options. What follows is positional, so a message can start with '-'.")
	a.out.clean("  -h, --help  /  -v, --version  /  --about  /  --donate")
	a.out.clean("")
}

// printCmdHelp prints one command's help block under the build line.
func (a *app) printCmdHelp(block []string) {
	a.out.clean("")
	a.printBanner()
	for _, l := range block {
		a.out.clean(l)
	}
}

func (a *app) printHelp() {
	a.printCopyright()
	a.printBlurb()
	a.printSyntax()
}

// printBanner names the build every command's output came from, so a bug report
// can say which one. Skipped under -q, the unattended mode, and never reached by
// 'raw' - that hands stdout straight back to the caller.
func (a *app) printBanner() {
	if a.opt.sawQuiet {
		return
	}
	a.out.cleanf("%s %s", meName, versionText())
	a.out.clean("")
}
