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

// showList indents and prints a command's output, truncated to the terminal so
// nothing wraps and capped so a huge working tree can't scroll the prompt
// off-screen - the 'less -FX' idea without a pager.
func (a *app) showList(name string, args ...string) {
	var outLines []string
	if out, _ := exec.Command(name, args...).Output(); len(out) > 0 {
		outLines = strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	}
	a.showLines(outLines)
}

// terminalWidth: asked once. Every capped list was spawning its own tput, and
// measuring twice in one run would only let the plan and the after-shot wrap
// differently.
func (a *app) terminalWidth() int {
	return a.termWidth.get(func() int {
		const fallback = 100
		if !isTTY(os.Stdout) || !inPath("tput") {
			return fallback
		}
		if w, err := strconv.Atoi(runOut("tput", "cols")); err == nil && w >= 40 {
			return w
		}
		return fallback
	})
}

// showLines is the same treatment for lines we already hold.
func (a *app) showLines(outLines []string) {
	const maxLines = 25
	termWidth := a.terminalWidth()
	shown := 0
	for _, line := range outLines {
		if shown >= maxLines {
			break
		}
		if r := []rune(line); len(r) > termWidth-4 {
			line = string(r[:termWidth-7]) + "..."
		}
		a.out.clean("    " + line)
		shown++
	}
	if len(outLines) > shown {
		a.out.cleanf("    ... and %d more", len(outLines)-shown)
	}
	a.lastListCount = len(outLines)
}

// showChanges: short form on purpose - git status's long form buries the file
// list under paragraphs of hints.
func (a *app) showChanges() {
	a.out.clean("Local changes:")
	a.showList("git", "status", "--short")
	if a.lastListCount == 0 {
		a.out.clean("    (working tree clean)")
	}
}

// showIncoming is the other half of "what's going to change": what a pull would
// bring down on top of your work.
func (a *app) showIncoming() {
	if !a.hasUpstream() {
		return
	}
	_, behind := a.aheadBehind()
	if behind == 0 {
		return
	}
	a.out.clean("")
	a.out.cleanf("Incoming (%d commit(s) to pull):", behind)
	a.showList("git", "diff", "--name-status", "HEAD..@{u}")
}

// identityWillPrint: whether this run reaches showIdentity at all. Every mutating
// command previews the block, bar 'account apply', which shows the account list
// instead; among the read-only ones only status and identity do. It gates the live
// probes that feed the block and nothing else, so being over-broad costs a round
// trip and never an answer.
func (a *app) identityWillPrint() bool {
	if a.cmd.name == "account-apply" {
		return false
	}
	if a.cmd.mutating {
		return true
	}
	return a.cmd.name == "status" || a.cmd.name == "identity"
}

// showIdentity: who a remote-touching command will act as. Host aliases in
// ~/.ssh/config hide this, and with more than one account configured it is easy
// to push as the wrong person.
func (a *app) showIdentity(remoteURL string) {
	a.showAccountLine()
	// A key nothing reads is how you end up acting as the wrong account while
	// believing you configured it, so say so - once, here, rather than failing or
	// staying quiet.
	if len(a.cfg.unknown) > 0 {
		a.out.clean("Config .......: " + a.cfg.file + " - ignored: " + strings.Join(a.cfg.unknown, ", "))
	}
	a.showSSHLine(remoteURL)
	a.out.clean("Author .......: " + commitIdentity())
	a.showGhLine()
}

// accountDecidedSomething: whether the account resolution actually changed how
// this run behaves - asked for or configured, not merely inferred. A single-account
// machine must never learn the feature exists.
func (a *app) accountDecidedSomething() bool {
	return a.acct.explicit || a.acct.name != "" || a.acct.switchedFrom != "" ||
		a.acct.usedHTTPSAuth || a.acct.usedSSHKey != "" || a.acct.usedIdentity
}

// showAccountLine leads the block, because it explains the lines under it: the key
// on the SSH line and the name on the Author line can both be its doing.
func (a *app) showAccountLine() {
	if !a.accountDecidedSomething() {
		return
	}
	line := a.acct.ghWho
	if line == "" {
		line = "(no GitHub account named)"
	}
	if a.acct.source != "" {
		line += " (from " + a.acct.source + ")"
	}
	// The one thing the lines below can't show: an https push authenticating with
	// the token rather than with a key, which is what makes a second account work
	// with no ssh setup.
	if a.acct.usedHTTPSAuth {
		line += ", git over https"
	}
	// Say plainly when the name above is only what we resolved. Without this the
	// block named an account nothing was actually acting as.
	if a.acct.noToken {
		line += " - NOT applied: no token for it here, so gh acts as its own account"
	}
	a.out.clean("Account ......: " + line)
	// This repo could authenticate with the account's token instead of a key, and
	// doesn't. Worth one line, because it is the whole point of configuring accounts
	// this way - and setting 'protocol = ssh' answers the question, so nobody hears
	// it twice.
	if a.convertibleToHTTPS() {
		a.out.clean("              : origin still uses ssh; '" + meName + " repo url https' switches it to this account's token.")
	}
}

// sshConfig is what 'ssh -G' says about a target: who it would connect as, where,
// and with which key.
type sshConfig struct {
	user, host, keyFile string
}

// readSSHConfig probes the connect target, not the bare host. Without a user,
// 'ssh -G' answers with the local login name - neither who we connect as nor the
// account we act as, and on a personal box it looks plausible enough to be
// believed. '--': an option-shaped host must not parse as an option.
func readSSHConfig(target string) sshConfig {
	var cfg sshConfig
	out, _ := exec.Command("ssh", "-G", "--", target).Output()
	for _, line := range strings.Split(string(out), "\n") {
		key, value, found := strings.Cut(line, " ")
		if !found || value == "" {
			continue
		}
		switch key {
		case "user":
			if cfg.user == "" {
				cfg.user = value
			}
		case "hostname":
			if cfg.host == "" {
				cfg.host = value
			}
		case "identityfile":
			if cfg.keyFile == "" {
				expanded := value
				if expanded == "~" || strings.HasPrefix(expanded, "~/") {
					expanded = os.Getenv("HOME") + expanded[1:]
				}
				if isReadableFile(expanded) {
					cfg.keyFile = value
				}
			}
		}
	}
	return cfg
}

func (a *app) showSSHLine(remoteURL string) {
	hostAlias := sshTarget(remoteURL)
	if hostAlias == "" || !inPath("ssh") {
		return
	}
	ssh := readSSHConfig(sshConnectTarget(remoteURL))
	// An '-i' in git's own ssh command outranks whatever ssh -G nominated: that is
	// the key git hands ssh, and with IdentitiesOnly set ssh_config's candidates
	// never get a look in. Without this the line can name the right account beside
	// the wrong key file, which is worse than either alone - it invites you to
	// trust the half that happens to be wrong.
	fields := strings.Fields(a.gitSSHCommand())
	for i, arg := range fields {
		if arg == "-i" && i+1 < len(fields) {
			ssh.keyFile = fields[i+1]
		}
	}
	if ssh.host == "" {
		return
	}
	if ssh.user == "" {
		ssh.user = "?"
	}
	line := ssh.user + "@" + ssh.host
	if hostAlias != ssh.host {
		line += " via alias '" + hostAlias + "'"
	}
	if ssh.keyFile != "" {
		line += ", key " + ssh.keyFile
	}
	// Neither half above answers the question this line exists for: the connect
	// user is 'git' for every GitHub account, and the key is only ssh's first
	// readable candidate, not necessarily the one that authenticates. So ask the
	// host who we actually are. Offline it stays unknown - the fetch already said why.
	account := "unknown"
	if !a.isOffline() {
		if resolved := a.sshLogin(remoteURL); resolved != "?" {
			account = resolved
		}
	}
	a.out.clean("SSH ..........: " + account + " (" + line + ")")
}

// showGhLine: gh-backed commands act as gh's account, not the ssh key's - so name
// it where it applies.
func (a *app) showGhLine() {
	if !a.gh.isCommand {
		return
	}
	ghWho := a.ghLogin()
	line := ghWho
	if ghWho == "?" {
		line = "(unknown - gh not logged in, or offline)"
	}
	// An account we picked for this remote is still a change of who you act as.
	// Say it here, in the block you read before confirming, rather than let it look
	// like it was already active.
	if a.acct.switchedFrom != "" {
		line += " (selected here; gh's active account is '" + a.acct.switchedFrom + "')"
	}
	// Only a write can act as the wrong account, so only a write gets the
	// comparison. The round trip behind it is the one the SSH line above already
	// made.
	if a.gh.isWrite {
		keyWho := a.sshLogin(a.gh.probeURL)
		if identityMismatchText(ghWho, keyWho) != "" {
			line += "  <-- NOT the ssh key's account ('" + keyWho + "')"
		} else if keyWho == "?" {
			line += " (no ssh identity to compare)"
		}
	}
	a.out.clean("GitHub (gh) ..: " + line)
}

// cmdIdentity is the identity block on its own - the same lines 'status' prints,
// without the branch and working-tree state, for when the only question is who
// the next command acts as. Directory and remote lead it because they are what
// decides the answer.
func (a *app) cmdIdentity() {
	remoteURL := a.originURL()
	remoteDisp := maskURL(remoteURL)
	if remoteDisp == "" {
		remoteDisp = "(none)"
	}
	wd, _ := os.Getwd()
	a.out.clean("")
	a.out.clean("Directory ....: " + wd)
	a.out.clean("Remote .......: " + remoteDisp)
	a.showIdentity(remoteURL)
	a.out.resetBlank()
}

// showStatus prints the state block. withIdentity: also show who we'll be on the
// remote - pre-flight and 'status', but not the after-shot.
func (a *app) showStatus(withIdentity bool) {
	remoteURL := a.originURL()
	remoteDisp := maskURL(remoteURL)
	if remoteDisp == "" {
		remoteDisp = "(none)"
	}
	a.out.clean("")
	wd, _ := os.Getwd()
	a.out.clean("Directory ....: " + wd)
	a.out.clean("Remote .......: " + remoteDisp)
	if withIdentity {
		a.showIdentity(remoteURL)
	}
	// Say "unknown" rather than assert a name we couldn't resolve - this is the one
	// command that still runs when the default branch can't be told, so it must not
	// fabricate one.
	dflt := a.defaultBranch()
	if dflt == "" {
		dflt = "unknown"
	}
	a.out.clean("Default branch: " + dflt)
	a.out.clean("Current branch: " + strings.TrimRight(a.branchDisp("")+" "+a.branchSync(), " "))
	// Pre-flight only, and only for the two commands that make a branch: the line
	// above is where you ARE, which is exactly what misled here - it says 'dev'
	// while the plan checks out main.
	if withIdentity {
		switch a.cmd.name {
		case "br-create":
			a.out.clean("New branch ...: " + a.mergeTarget() + " :: " + a.cmd.arg)
		case "br-hotfix":
			a.out.clean("New branch ...: " + a.defaultBranch() + " :: " + a.cmd.arg)
		}
	}
	a.out.clean("")
	a.showChanges()
	if withIdentity {
		a.showIncoming()
	}
	a.out.resetBlank()
}
