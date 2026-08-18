// pr's argument shape and the read-only views. The parse takes the whole
// vocabulary so a malformed call refuses the same way whichever half is built;
// create and ok land with the other writers.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strings"
)

var (
	prSub = "" // "create" or "ok"; empty for the bare list and the numeric view
	prNum = ""
)

var prNumRE = regexp.MustCompile(`^[0-9]+$`)

// sortPr validates pr's own arguments - before the repo gate, same as the
// scripts: a malformed pr call is wrong anywhere, in a repo or not. The title
// for create is settled by the creating half; refusing bad shapes is all that
// belongs here.
func sortPr() {
	mustBeInPath("gh")
	switch strings.ToLower(cmdArg) {
	case "ok":
		prSub = "ok"
		prNum = cmdArg2
		if !prNumRE.MatchString(prNum) {
			throwUsage("Syntax: " + meName + " pr ok <number>")
		}
	case "create", "new":
		prSub = "create"
	case "":
	default:
		prNum = cmdArg
		if !prNumRE.MatchString(prNum) {
			throwUsage("Syntax: " + meName + " pr [create [title] | <number> | ok <number>]")
		}
	}
}

// cmdPrView: bare lists open PRs; a number views one plus its diff.
func cmdPrView() {
	if prNum == "" {
		runStep("gh", "pr", "list")
	} else {
		runStep("gh", "pr", "view", prNum)
		runStep("gh", "pr", "diff", prNum)
	}
}
