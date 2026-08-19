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
	"cmp"
	"os"
	"slices"
	"strings"
)

// accountNames: every account the config file defines, in the order it defines
// them. An account can be declared by its keys alone, with no folder rule - it is
// then only reachable by name, through GITSBY_ACCOUNT, which is a legitimate way
// to use one.
func (c *config) accountNames() []string {
	var seen []string
	add := func(name string) {
		if !slices.Contains(seen, name) {
			seen = append(seen, name)
		}
	}
	for _, r := range c.paths {
		add(r.acct)
	}
	for _, r := range c.segments {
		add(r.acct)
	}
	for _, name := range c.order {
		add(name)
	}
	return seen
}

// foldersOf: the folder rules belonging to one account, as canonical paths.
func (c *config) foldersOf(name string) []string {
	return matchesOf(c.paths, name)
}

// segmentsOf: the 'pathContains' rules belonging to one account. Kept apart from
// the folder rules because they are a different claim: those name a tree on this
// machine, these name a run of folder names on any machine, which is what lets one
// config file be synced between them.
func (c *config) segmentsOf(name string) []string {
	return matchesOf(c.segments, name)
}

func matchesOf(rules []acctRule, name string) []string {
	var out []string
	for _, r := range rules {
		if r.acct == name && r.match != "" {
			out = append(out, r.match)
		}
	}
	return out
}

// includeDir: where the per-account git config fragments live - beside the config
// file that describes them, so the two travel together and 'account apply' has an
// unambiguous set of files it owns.
func (c *config) includeDir() string {
	if c.file == "" {
		return ""
	}
	dir := c.file
	if i := strings.LastIndex(dir, "/"); i >= 0 {
		dir = dir[:i]
	}
	return dir + "/accounts"
}

type includeRule struct{ cond, target string }

// includeCandidate is one folder rule on its way to becoming an includeIf: how
// specific it is, the pattern git will match on, and the account it selects.
type includeCandidate struct {
	weight  int // path length, or folder-name count
	pattern string
	account string
}

// sortIncludes orders candidates the way the two matchers have to agree: git
// takes the LAST match and gitsby the most specific, so least specific comes
// first. The pattern breaks a tie in weight, and the account name settles an
// exact one.
func sortIncludes(list []includeCandidate) {
	slices.SortFunc(list, func(x, y includeCandidate) int {
		return cmp.Or(
			cmp.Compare(x.weight, y.weight),
			cmp.Compare(x.pattern, y.pattern),
			cmp.Compare(x.account, y.account),
		)
	})
}

// accountApplyPlan: the includeIf conditions 'account apply' would write.
// gitdir/i, not gitdir: a path compares case-insensitively on Windows and macOS,
// and a rule that silently misses because of a capital letter is worse than no
// rule. 'pathContains' maps straight onto git's own gitdir globbing, so plain
// git gets the same rule rather than an approximation of it. Fewest folder names
// first, and all of them ahead of the absolute rules; within the absolute rules,
// shortest path first, so a tree nested inside another account's tree lands last.
func (c *config) accountApplyPlan() []includeRule {
	dir := c.includeDir()
	if dir == "" {
		return nil
	}
	var paths, segments []includeCandidate
	for _, name := range c.accountNames() {
		for _, folder := range c.foldersOf(name) {
			// The trailing slash is what makes git apply it to everything below the
			// folder too.
			paths = append(paths, includeCandidate{len(folder), folder + "/", name})
		}
		for _, folder := range c.segmentsOf(name) {
			segments = append(segments, includeCandidate{strings.Count(folder, "/") + 1, "**/" + folder + "/**", name})
		}
	}
	if len(paths)+len(segments) == 0 {
		return nil
	}
	sortIncludes(segments)
	sortIncludes(paths)
	plan := make([]includeRule, 0, len(segments)+len(paths))
	for _, cand := range slices.Concat(segments, paths) {
		plan = append(plan, includeRule{"includeIf.gitdir/i:" + cand.pattern + ".path", dir + "/" + cand.account + ".gitconfig"})
	}
	return plan
}

// accountManagedIncludes: every includeIf already in the global config that
// points into the directory we own. Those are ours to replace; anything else in
// there was written by hand and is left alone.
func (c *config) accountManagedIncludes() []string {
	dir := c.includeDir()
	if dir == "" {
		return nil
	}
	canonDir := canonPath(dir)
	var keys []string
	// --null, not the plain form: that one separates the key from the value with a
	// space, and the key holds a folder path which can contain one. Every such rule
	// came back truncated, so it was never recognized as ours - which made each
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

func (a *app) cmdAccountList() {
	a.out.clean("")
	configDisp := a.cfg.file
	if configDisp == "" {
		configDisp = "(none found)"
	}
	a.out.clean("Config file ..: " + configDisp)
	a.out.clean("Here .........: " + a.contextDir())
	hereAccount := a.cfg.accountForDir(a.contextDir())
	resolvedLine := a.acct.ghWho
	if resolvedLine == "" {
		resolvedLine = "(nothing configured - gh's own account)"
	}
	if a.acct.source != "" {
		resolvedLine += " (from " + a.acct.source + ")"
	}
	a.out.clean("Resolves to ..: " + resolvedLine)
	if len(a.cfg.unknown) > 0 {
		a.out.clean("Ignored keys .: " + strings.Join(a.cfg.unknown, ", "))
	}
	names := a.cfg.accountNames()
	if len(names) == 0 {
		a.out.clean("")
		a.out.clean("No accounts defined. See the Multiple accounts section of the README for the file format.")
		return
	}
	a.out.clean("")
	a.out.clean("Accounts:")
	for _, name := range names {
		a.showAccount(name, name == hereAccount)
	}
}

func (a *app) showAccount(name string, isHere bool) {
	marker := "  "
	if isHere {
		marker = "->"
	}
	a.out.clean(marker + " " + name)
	ghWho := a.cfg.value(name, "ghAccount")
	ghDisp := ghWho
	if ghDisp == "" {
		ghDisp = "(none)"
	}
	a.out.clean("     github ..: " + ghDisp)
	// Say where a token would come from, never what it is.
	tokenFrom := "none"
	if ghWho != "" && ghTokenFor(ghWho) != "" {
		tokenFrom = "gh's own store"
	} else if readTokenFile(a.cfg.value(name, "tokenFile")) != "" {
		tokenFrom = a.cfg.value(name, "tokenFile")
	}
	a.out.clean("     token ...: " + tokenFrom)
	if sshKey := a.cfg.value(name, "sshKey"); sshKey != "" {
		a.out.clean("     ssh key .: " + sshKey)
	}
	acctUser := a.cfg.value(name, "name")
	acctEmail := a.cfg.value(name, "email")
	if acctUser+acctEmail != "" {
		if acctUser == "" {
			acctUser = "?"
		}
		if acctEmail == "" {
			acctEmail = "?"
		}
		a.out.clean("     commits .: " + acctUser + " <" + acctEmail + ">")
	}
	if proto := a.cfg.value(name, "protocol"); proto != "" {
		a.out.clean("     protocol : " + proto)
	}
	for _, folder := range a.cfg.foldersOf(name) {
		// A rule pointing at nothing matches nothing, and reads exactly like no rule
		// at all - which is how you end up acting as the wrong account while believing
		// you configured it. Usually a typo; on Windows it is also how a shell-only
		// path spelling such as '/tmp/...' looks, since only the shell build can
		// resolve one.
		if isDir(folder) {
			a.out.clean("     folder ..: " + folder)
		} else {
			a.out.clean("     folder ..: " + folder + "  (no such directory - this rule can never match)")
		}
	}
	// No existence check on these: naming no machine in particular is the point.
	for _, seg := range a.cfg.segmentsOf(name) {
		a.out.clean("     anywhere : .../" + seg + "/...")
	}
}

// cmdAccountApply writes one fragment per account, and an includeIf per folder
// rule pointing at it - with 'git config', never by editing the file ourselves,
// so git's own parser decides what a valid entry looks like. The directory is
// checked BEFORE writing anything: left to mkdir and the redirect, a blocked
// path surfaced as a raw tooling error part way through the run, which reads as
// a crash rather than as something you can act on.
func (a *app) cmdAccountApply() error {
	dir := a.cfg.includeDir()
	if dir == "" {
		return usagef("No config file, so there is nowhere to write the account fragments.")
	}
	if pathExists(dir) && !isDir(dir) {
		return usagef("'%s' is where the account fragments go, and it isn't a directory. Move or remove it, then re-run.", dir)
	}
	if err := os.MkdirAll(dir, 0o777); err != nil {
		parent := dir
		if i := strings.LastIndex(parent, "/"); i >= 0 {
			parent = parent[:i]
		}
		return usagef("Couldn't create '%s' for the account fragments. Check permissions on '%s'.", dir, parent)
	}
	for _, name := range a.cfg.accountNames() {
		if err := a.writeAccountFragment(dir, name); err != nil {
			return err
		}
	}
	// Drop ours before adding, so a folder rule that was removed from the config
	// file stops applying. Each key was just listed out of the config, so a failure
	// to remove one is real - and leaving it means the old rule keeps applying
	// beside the new one.
	for _, key := range a.cfg.accountManagedIncludes() {
		if !a.inheritOK("git", "config", "--global", "--unset-all", key) {
			return usagef("Couldn't remove the old rule '%s' from your global git config; nothing further was applied.", key)
		}
	}
	for _, rule := range a.cfg.accountApplyPlan() {
		if !a.inheritOK("git", "config", "--global", "--add", rule.cond, rule.target) {
			return usagef("Couldn't add '%s' to your global git config.", rule.cond)
		}
		a.out.status("git config --global --add " + rule.cond)
	}
	return nil
}

// writeAccountFragment writes one account's git config fragment. Every write is
// checked and every failure stops the run: this is the one command that writes
// outside the repo you are standing in, so it is the one place where a discarded
// exit code turns into a silent no-op - it said "Wrote" and exited 0 whatever
// happened.
func (a *app) writeAccountFragment(dir, name string) error {
	fragment := dir + "/" + name + ".gitconfig"
	if err := os.WriteFile(fragment, nil, 0o644); err != nil {
		return usagef("Couldn't write '%s'. Check permissions on '%s'.", fragment, dir)
	}
	write := func(key, value string) error {
		if !a.inheritOK("git", "config", "--file", fragment, key, value) {
			return usagef("Couldn't write %s into '%s'; it is incomplete, and nothing further was applied.", key, fragment)
		}
		return nil
	}
	entries := []struct{ key, value string }{
		{"user.name", a.cfg.value(name, "name")},
		{"user.email", a.cfg.value(name, "email")},
		{"gitsby.ghAccount", a.cfg.value(name, "ghAccount")},
		// Which account plain git should ASK for over https. Without it the fragment
		// covered the ssh half and left the https half to whichever credential the
		// helper happened to hold first - so a bare 'git push' in a configured folder
		// could still go out as someone else, which is the gap 'apply' exists to close.
		// Naming the user is what makes a credential manager look up that account's
		// entry rather than any entry for the host.
		{"credential.https://github.com.username", a.cfg.value(name, "ghAccount")},
		{"gitsby.ghTokenFile", a.cfg.value(name, "tokenFile")},
	}
	for _, e := range entries {
		if e.value == "" {
			continue
		}
		if err := write(e.key, e.value); err != nil {
			return err
		}
	}
	if sshKey := a.cfg.value(name, "sshKey"); sshKey != "" {
		if err := write("core.sshCommand", "ssh -i "+sshKey+" -o IdentitiesOnly=yes"); err != nil {
			return err
		}
	}
	a.out.status("Wrote " + fragment)
	return nil
}
