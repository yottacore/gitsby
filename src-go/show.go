// The state display: the status block, the identity block, and the capped lists
// under them. What these print is what the user reads before saying yes, so every
// line either states something verified or says "unknown" - never a guess.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
)

var lastListCount = 0 // set by cappedList; callers that need "was it empty?" read this

// cappedList indents and prints a command's output, truncated to the terminal so
// nothing wraps and capped so a huge working tree can't scroll the prompt
// off-screen - the 'less -FX' idea without a pager.
func cappedList(name string, args ...string) {
	var outLines []string
	if out, _ := exec.Command(name, args...).Output(); len(out) > 0 {
		outLines = strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	}
	cappedLines(outLines)
}

// cappedLines is the same treatment for lines we already hold.
func cappedLines(outLines []string) {
	const maxLines = 25
	termWidth := 100
	if isTTY(os.Stdout) {
		if _, err := exec.LookPath("tput"); err == nil {
			if w, err := strconv.Atoi(runOut("tput", "cols")); err == nil && w >= 40 {
				termWidth = w
			}
		}
	}
	shown := 0
	for _, line := range outLines {
		if shown >= maxLines {
			break
		}
		if r := []rune(line); len(r) > termWidth-4 {
			line = string(r[:termWidth-7]) + "..."
		}
		echoClean("    " + line)
		shown++
	}
	if len(outLines) > shown {
		echoClean("    ... and " + strconv.Itoa(len(outLines)-shown) + " more")
	}
	lastListCount = len(outLines)
}

// showChanges: short form on purpose - git status's long form buries the file
// list under paragraphs of hints.
func showChanges() {
	echoClean("Local changes:")
	cappedList("git", "status", "--short")
	if lastListCount == 0 {
		echoClean("    (working tree clean)")
	}
}

// showIncoming is the other half of "what's going to change": what a pull would
// bring down on top of your work.
func showIncoming() {
	if !hasUpstream() {
		return
	}
	behind, _ := strconv.Atoi(runOut("git", "rev-list", "--count", "HEAD..@{u}"))
	if behind == 0 {
		return
	}
	echoClean("")
	echoClean("Incoming (" + strconv.Itoa(behind) + " commit(s) to pull):")
	cappedList("git", "diff", "--name-status", "HEAD..@{u}")
}

// showIdentity: who a remote-touching command will act as. Host aliases in
// ~/.ssh/config hide this, and with more than one account configured it is easy
// to push as the wrong person.
func showIdentity(remoteUrl string) {
	// The Account line leads the block, because it explains the lines under it: the
	// key on the SSH line and the name on the Author line can both be its doing.
	// Shown only when something was actually decided by it - asked for or
	// configured, not merely inferred, so a single-account machine never learns the
	// feature exists.
	if acctExplicit || acctName != "" || ghSwitchedFrom != "" || accountUsedHttpsAuth || accountUsedSSHKey != "" || accountUsedIdentity {
		acctLine := acctGhWho
		if acctLine == "" {
			acctLine = "(no GitHub account named)"
		}
		if acctSource != "" {
			acctLine += " (from " + acctSource + ")"
		}
		// The one thing the lines below can't show: an https push authenticating
		// with the token rather than with a key, which is what makes a second
		// account work with no ssh setup.
		if accountUsedHttpsAuth {
			acctLine += ", git over https"
		}
		// Say plainly when the name above is only what we resolved. Without this the
		// block named an account nothing was actually acting as.
		if accountNoToken {
			acctLine += " - NOT applied: no token for it here, so gh acts as its own account"
		}
		echoClean("Account ......: " + acctLine)
		// This repo could authenticate with the account's token instead of a key,
		// and doesn't. Worth one line, because it is the whole point of configuring
		// accounts this way - and setting 'protocol = ssh' answers the question, so
		// nobody hears it twice.
		if convertibleToHttps() {
			echoClean("              : origin still uses ssh; '" + meName + " repo url https' switches it to this account's token.")
		}
	}
	// A key nothing reads is how you end up acting as the wrong account while
	// believing you configured it, so say so - once, here, rather than failing or
	// staying quiet.
	if len(cfgUnknown) > 0 {
		echoClean("Config .......: " + configFileUsed + " - ignored: " + strings.Join(cfgUnknown, ", "))
	}
	sshHostAlias := sshTarget(remoteUrl)
	if sshHostAlias != "" {
		if _, err := exec.LookPath("ssh"); err == nil {
			// Probe the connect target, not the bare host. Without a user, 'ssh -G'
			// answers with the local login name - neither who we connect as nor the
			// account we act as, and on a personal box it looks plausible enough to
			// be believed. '--': an option-shaped host must not parse as an option.
			sshUser, sshHost, keyFile := "", "", ""
			out, _ := exec.Command("ssh", "-G", "--", sshConnectTarget(remoteUrl)).Output()
			for _, line := range strings.Split(string(out), "\n") {
				key, value, found := strings.Cut(line, " ")
				if !found || value == "" {
					continue
				}
				switch key {
				case "user":
					if sshUser == "" {
						sshUser = value
					}
				case "hostname":
					if sshHost == "" {
						sshHost = value
					}
				case "identityfile":
					if keyFile == "" {
						expanded := value
						if expanded == "~" || strings.HasPrefix(expanded, "~/") {
							expanded = os.Getenv("HOME") + expanded[1:]
						}
						if isReadableFile(expanded) {
							keyFile = value
						}
					}
				}
			}
			// An '-i' in git's own ssh command outranks whatever ssh -G nominated:
			// that is the key git hands ssh, and with IdentitiesOnly set ssh_config's
			// candidates never get a look in. Without this the line can name the
			// right account beside the wrong key file, which is worse than either
			// alone - it invites you to trust the half that happens to be wrong.
			fields := strings.Fields(gitSshCommand())
			for i, arg := range fields {
				if arg == "-i" && i+1 < len(fields) {
					keyFile = fields[i+1]
				}
			}
			if sshHost != "" {
				if sshUser == "" {
					sshUser = "?"
				}
				sshLine := sshUser + "@" + sshHost
				if sshHostAlias != sshHost {
					sshLine += " via alias '" + sshHostAlias + "'"
				}
				if keyFile != "" {
					sshLine += ", key " + keyFile
				}
				// Neither half above answers the question this line exists for: the
				// connect user is 'git' for every GitHub account, and the key is only
				// ssh's first readable candidate, not necessarily the one that
				// authenticates. So ask the host who we actually are. Offline it
				// stays unknown - the fetch already said why.
				sshAccount := "unknown"
				if !isOffline() {
					if resolved := sshLogin(remoteUrl); resolved != "?" {
						sshAccount = resolved
					}
				}
				echoClean("SSH ..........: " + sshAccount + " (" + sshLine + ")")
			}
		}
	}
	echoClean("Author .......: " + commitIdentity())
	// gh-backed commands act as gh's account, not the ssh key's - so name it where
	// it applies.
	if isGhCommand {
		ghWho := ghLogin()
		ghLine := ghWho
		if ghWho == "?" {
			ghLine = "(unknown - gh not logged in, or offline)"
		}
		// An account we picked for this remote is still a change of who you act as.
		// Say it here, in the block you read before confirming, rather than let it
		// look like it was already active.
		if ghSwitchedFrom != "" {
			ghLine += " (selected here; gh's active account is '" + ghSwitchedFrom + "')"
		}
		// Only a write can act as the wrong account, so only a write gets the
		// comparison. The round trip behind it is the one the SSH line above already
		// made.
		if isGhWrite {
			keyWho := sshLogin(identityProbeUrl)
			if identityMismatchText(ghWho, keyWho) != "" {
				ghLine += "  <-- NOT the ssh key's account ('" + keyWho + "')"
			} else if keyWho == "?" {
				ghLine += " (no ssh identity to compare)"
			}
		}
		echoClean("GitHub (gh) ..: " + ghLine)
	}
}

// cmdIdentity is the identity block on its own - the same lines 'status' prints,
// without the branch and working-tree state, for when the only question is who
// the next command acts as. Directory and remote lead it because they are what
// decides the answer.
func cmdIdentity() {
	remoteUrl := runOut("git", "remote", "get-url", "origin")
	remoteDisp := maskUrl(remoteUrl)
	if remoteDisp == "" {
		remoteDisp = "(none)"
	}
	wd, _ := os.Getwd()
	echoClean("")
	echoClean("Directory ....: " + wd)
	echoClean("Remote .......: " + remoteDisp)
	showIdentity(remoteUrl)
	echoResetBlank()
}

// showStatus prints the state block. withIdentity: also show who we'll be on the
// remote - pre-flight and 'status', but not the after-shot.
func showStatus(withIdentity bool) {
	remoteUrl := runOut("git", "remote", "get-url", "origin")
	remoteDisp := maskUrl(remoteUrl)
	if remoteDisp == "" {
		remoteDisp = "(none)"
	}
	echoClean("")
	wd, _ := os.Getwd()
	echoClean("Directory ....: " + wd)
	echoClean("Remote .......: " + remoteDisp)
	if withIdentity {
		showIdentity(remoteUrl)
	}
	// Say "unknown" rather than assert a name we couldn't resolve - this is the one
	// command that still runs when the default branch can't be told, so it must not
	// fabricate one.
	dflt := defaultBranch()
	if dflt == "" {
		dflt = "unknown"
	}
	echoClean("Default branch: " + dflt)
	echoClean("Current branch: " + strings.TrimRight(branchDisp("")+" "+branchSync(), " "))
	// Pre-flight only, and only for the two commands that make a branch: the line
	// above is where you ARE, which is exactly what misled here - it says 'dev'
	// while the plan checks out main.
	if withIdentity {
		switch cmdName {
		case "br-create":
			echoClean("New branch ...: " + mergeTarget() + " :: " + cmdArg)
		case "br-hotfix":
			echoClean("New branch ...: " + defaultBranch() + " :: " + cmdArg)
		}
	}
	echoClean("")
	showChanges()
	if withIdentity {
		showIncoming()
	}
	echoResetBlank()
}
