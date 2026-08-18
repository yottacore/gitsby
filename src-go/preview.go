// The plan display. A static per-command recipe; the command functions do the
// real state checks at run time, which is what the '*' marks. 'commit' and 'pull'
// are not commands of their own - they stay here as the fragments the real ones
// compose their plans from.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

const pad = "    "

func preview(what string) {
	msgDisp := "git commit"
	if commitMessage != "" {
		msgDisp = `git commit -m "` + commitMessage + `"`
	}
	switch what {
	case "commit":
		echoClean(pad + "git add --all")
		echoClean(pad + msgDisp + " *")
	case "pull":
		echoClean(pad + "git pull --ff-only --autostash *")
	case "update":
		preview("pull")
		preview("commit")
	case "sync":
		preview("update")
		echoClean(pad + "git push (branch '" + currentBranch() + "') *")
	case "br-prune":
		prunePreview()
	}
	// The recipes for the branch, pr, release, repo and account writers land with
	// those commands.
}
