// The account commands: 'list' shows what is configured and which rule this
// folder matches - the command you run when a push went out as the wrong person
// and you want to know why - and 'apply' teaches plain git the same folder
// rules, so a bare 'git push' in one of these folders behaves the same as it
// does through us.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

// accountNames: every account the config file defines, in the order it defines
// them. An account can be declared by its keys alone, with no folder rule - it is
// then only reachable by name, through GITSBY_ACCOUNT, which is a legitimate way
// to use one.
func accountNames() []string {
	var seen []string
	have := func(name string) bool {
		for _, s := range seen {
			if s == name {
				return true
			}
		}
		return false
	}
	for _, r := range cfgPaths {
		if !have(r.acct) {
			seen = append(seen, r.acct)
		}
	}
	for _, r := range cfgSegments {
		if !have(r.acct) {
			seen = append(seen, r.acct)
		}
	}
	for _, name := range cfgAcctOrder {
		if !have(name) {
			seen = append(seen, name)
		}
	}
	return seen
}

// accountFoldersOf: the folder rules belonging to one account, as canonical paths.
func accountFoldersOf(name string) []string {
	var out []string
	for _, r := range cfgPaths {
		if r.acct == name && r.match != "" {
			out = append(out, r.match)
		}
	}
	return out
}

// accountSegmentsOf: the 'pathContains' rules belonging to one account. Kept
// apart from the folder rules because they are a different claim: those name a
// tree on this machine, these name a run of folder names on any machine, which
// is what lets one config file be synced between them.
func accountSegmentsOf(name string) []string {
	var out []string
	for _, r := range cfgSegments {
		if r.acct == name && r.match != "" {
			out = append(out, r.match)
		}
	}
	return out
}

// accountIncludeDir: where the per-account git config fragments live - beside
// the config file that describes them, so the two travel together and 'account
// apply' has an unambiguous set of files it owns.
func accountIncludeDir() string {
	if configFileUsed == "" {
		return ""
	}
	dir := configFileUsed
	if i := strings.LastIndex(dir, "/"); i >= 0 {
		dir = dir[:i]
	}
	return dir + "/accounts"
}

type includeRule struct{ cond, target string }

// sortRuleLines orders "<n>\t<match>\t<name>" lines the way the scripts' sort
// does: numeric on the first field, text on the second, whole line settling an
// exact tie.
func sortRuleLines(lines []string) {
	sort.Slice(lines, func(i, j int) bool {
		fi, fj := strings.SplitN(lines[i], "\t", 3), strings.SplitN(lines[j], "\t", 3)
		ni, _ := strconv.Atoi(fi[0])
		nj, _ := strconv.Atoi(fj[0])
		if ni != nj {
			return ni < nj
		}
		if fi[1] != fj[1] {
			return fi[1] < fj[1]
		}
		return lines[i] < lines[j]
	})
}

// accountApplyPlan: the includeIf conditions 'account apply' would write.
// gitdir/i, not gitdir: a path compares case-insensitively on Windows and macOS,
// and a rule that silently misses because of a capital letter is worse than no
// rule. 'pathContains' maps straight onto git's own gitdir globbing, so plain
// git gets the same rule rather than an approximation of it. Fewest folder names
// first, and all of them ahead of the absolute rules - git takes the LAST match,
// and gitsby takes the most specific, so the two only agree if the order runs
// least specific to most; within the absolute rules, shortest path first for the
// same reason (a tree nested inside another account's tree must land last).
func accountApplyPlan() []includeRule {
	dir := accountIncludeDir()
	if dir == "" {
		return nil
	}
	var rules, segRules []string
	for _, name := range accountNames() {
		for _, folder := range accountFoldersOf(name) {
			rules = append(rules, strconv.Itoa(len(folder))+"\t"+folder+"\t"+name)
		}
		for _, folder := range accountSegmentsOf(name) {
			segs := strings.Count(folder, "/") + 1
			segRules = append(segRules, strconv.Itoa(segs)+"\t**/"+folder+"/**\t"+name)
		}
	}
	if len(rules)+len(segRules) == 0 {
		return nil
	}
	sortRuleLines(segRules)
	sortRuleLines(rules)
	var plan []includeRule
	for _, line := range segRules {
		f := strings.SplitN(line, "\t", 3)
		plan = append(plan, includeRule{"includeIf.gitdir/i:" + f[1] + ".path", dir + "/" + f[2] + ".gitconfig"})
	}
	for _, line := range rules {
		f := strings.SplitN(line, "\t", 3)
		// The trailing slash is what makes git apply it to everything below the
		// folder too.
		plan = append(plan, includeRule{"includeIf.gitdir/i:" + f[1] + "/.path", dir + "/" + f[2] + ".gitconfig"})
	}
	return plan
}

// accountManagedIncludes: every includeIf already in the global config that
// points into the directory we own. Those are ours to replace; anything else in
// there was written by hand and is left alone.
func accountManagedIncludes() []string {
	dir := accountIncludeDir()
	if dir == "" {
		return nil
	}
	canonDir := canonPath(dir)
	var keys []string
	// --null, not the plain form: that one separates the key from the value with a
	// space, and the key holds a folder path which can contain one. Every such rule
	// came back truncated, so it was never recognised as ours - which made each
	// re-run append a duplicate, and left a rule dropped from the config file
	// applying forever. -z ends each record with a NUL and the key with a newline.
	for _, record := range strings.Split(runOut("git", "config", "--global", "--get-regexp", "--null", `^includeIf\..*\.path$`), "\x00") {
		key, value, found := strings.Cut(record, "\n")
		if !found {
			continue
		}
		// git prints the section and variable lower-cased and the subsection
		// verbatim, so match the key that way and hand it straight back to
		// --unset-all.
		lower := strings.ToLower(key)
		if !strings.HasPrefix(lower, "includeif.") || !strings.HasSuffix(lower, ".path") {
			continue
		}
		// Canonical, not textual: git stores a path in the platform's own spelling,
		// so ours comes back as 'C:/...' where we wrote '/c/...' - and a prefix test
		// on the raw text never fires, which quietly turns every re-run into a
		// duplicate rather than a refresh.
		if !strings.HasPrefix(canonPath(value), canonDir+"/") {
			continue
		}
		keys = append(keys, key)
	}
	return keys
}

func cmdAccountList() {
	echoClean("")
	configDisp := configFileUsed
	if configDisp == "" {
		configDisp = "(none found)"
	}
	echoClean("Config file ..: " + configDisp)
	echoClean("Here .........: " + contextDir())
	hereAccount := accountForDir(contextDir())
	resolvedLine := acctGhWho
	if resolvedLine == "" {
		resolvedLine = "(nothing configured - gh's own account)"
	}
	if acctSource != "" {
		resolvedLine += " (from " + acctSource + ")"
	}
	echoClean("Resolves to ..: " + resolvedLine)
	if len(cfgUnknown) > 0 {
		echoClean("Ignored keys .: " + strings.Join(cfgUnknown, ", "))
	}
	names := accountNames()
	if len(names) == 0 {
		echoClean("")
		echoClean("No accounts defined. See the Multiple accounts section of the README for the file format.")
		return
	}
	echoClean("")
	echoClean("Accounts:")
	for _, name := range names {
		marker := "  "
		if name == hereAccount {
			marker = "->"
		}
		echoClean(marker + " " + name)
		ghWho := accountValue(name, "ghAccount")
		ghDisp := ghWho
		if ghDisp == "" {
			ghDisp = "(none)"
		}
		echoClean("     github ..: " + ghDisp)
		// Say where a token would come from, never what it is.
		tokenFrom := "none"
		if ghWho != "" && ghTokenFor(ghWho) != "" {
			tokenFrom = "gh's own store"
		} else if readTokenFile(accountValue(name, "tokenFile")) != "" {
			tokenFrom = accountValue(name, "tokenFile")
		}
		echoClean("     token ...: " + tokenFrom)
		if sshKey := accountValue(name, "sshKey"); sshKey != "" {
			echoClean("     ssh key .: " + sshKey)
		}
		acctUser := accountValue(name, "name")
		acctEmail := accountValue(name, "email")
		if acctUser+acctEmail != "" {
			if acctUser == "" {
				acctUser = "?"
			}
			if acctEmail == "" {
				acctEmail = "?"
			}
			echoClean("     commits .: " + acctUser + " <" + acctEmail + ">")
		}
		if proto := accountValue(name, "protocol"); proto != "" {
			echoClean("     protocol : " + proto)
		}
		for _, folder := range accountFoldersOf(name) {
			// A rule pointing at nothing matches nothing, and reads exactly like no
			// rule at all - which is how you end up acting as the wrong account while
			// believing you configured it. Usually a typo; on Windows it is also how
			// a shell-only path spelling such as '/tmp/...' looks, since only the
			// shell build can resolve one.
			if isDir(folder) {
				echoClean("     folder ..: " + folder)
			} else {
				echoClean("     folder ..: " + folder + "  (no such directory - this rule can never match)")
			}
		}
		// No existence check on these: naming no machine in particular is the point.
		for _, seg := range accountSegmentsOf(name) {
			echoClean("     anywhere : .../" + seg + "/...")
		}
	}
}

// cmdAccountApply writes one fragment per account, and an includeIf per folder
// rule pointing at it - with 'git config', never by editing the file ourselves,
// so git's own parser decides what a valid entry looks like. The directory is
// checked BEFORE writing anything: left to mkdir and the redirect, a blocked
// path surfaced as a raw tooling error part way through the run, which reads as
// a crash rather than as something you can act on.
func cmdAccountApply() {
	dir := accountIncludeDir()
	if dir == "" {
		throwUsage("No config file, so there is nowhere to write the account fragments.")
	}
	if pathExists(dir) && !isDir(dir) {
		throwUsage("'" + dir + "' is where the account fragments go, and it isn't a directory. Move or remove it, then re-run.")
	}
	if err := os.MkdirAll(dir, 0o777); err != nil {
		parent := dir
		if i := strings.LastIndex(parent, "/"); i >= 0 {
			parent = parent[:i]
		}
		throwUsage("Couldn't create '" + dir + "' for the account fragments. Check permissions on '" + parent + "'.")
	}
	for _, name := range accountNames() {
		fragment := dir + "/" + name + ".gitconfig"
		// Every write is checked and every failure stops the run. This is the one
		// command that writes outside the repo you are standing in, so it is the one
		// place where a discarded exit code turns into a silent no-op: it said "Wrote"
		// and exited 0 whatever happened.
		if err := os.WriteFile(fragment, nil, 0o644); err != nil {
			throwUsage("Couldn't write '" + fragment + "'. Check permissions on '" + dir + "'.")
		}
		write := func(key, value string) {
			if !runInheritOK("git", "config", "--file", fragment, key, value) {
				throwUsage("Couldn't write " + key + " into '" + fragment + "'; it is incomplete, and nothing further was applied.")
			}
		}
		if acctUser := accountValue(name, "name"); acctUser != "" {
			write("user.name", acctUser)
		}
		if acctEmail := accountValue(name, "email"); acctEmail != "" {
			write("user.email", acctEmail)
		}
		ghWho := accountValue(name, "ghAccount")
		if ghWho != "" {
			write("gitsby.ghAccount", ghWho)
			// Which account plain git should ASK for over https. Without it the
			// fragment covered the ssh half and left the https half to whichever
			// credential the helper happened to hold first - so a bare 'git push' in a
			// configured folder could still go out as someone else, which is the gap
			// 'apply' exists to close. Naming the user is what makes a credential
			// manager look up that account's entry rather than any entry for the host.
			write("credential.https://github.com.username", ghWho)
		}
		if tokenFile := accountValue(name, "tokenFile"); tokenFile != "" {
			write("gitsby.ghTokenFile", tokenFile)
		}
		if sshKey := accountValue(name, "sshKey"); sshKey != "" {
			write("core.sshCommand", "ssh -i "+sshKey+" -o IdentitiesOnly=yes")
		}
		echoStatus("Wrote " + fragment)
	}
	// Drop ours before adding, so a folder rule that was removed from the config
	// file stops applying. Each key was just listed out of the config, so a failure
	// to remove one is real - and leaving it means the old rule keeps applying
	// beside the new one.
	for _, key := range accountManagedIncludes() {
		if !runInheritOK("git", "config", "--global", "--unset-all", key) {
			throwUsage("Couldn't remove the old rule '" + key + "' from your global git config; nothing further was applied.")
		}
	}
	for _, rule := range accountApplyPlan() {
		if !runInheritOK("git", "config", "--global", "--add", rule.cond, rule.target) {
			throwUsage("Couldn't add '" + rule.cond + "' to your global git config.")
		}
		echoStatus("git config --global --add " + rule.cond)
	}
}
