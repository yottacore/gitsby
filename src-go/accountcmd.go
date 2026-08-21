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
// anyHostStated: whether any account in this config names a forge. What makes the
// host worth a line in the listing - with one forge configured there is nothing to
// compare, and a machine that only ever talks to github.com should not have the
// key advertised at it.
func (c *config) anyHostStated() bool {
	for key, value := range c.values {
		if strings.HasSuffix(key, ".host") && value != "" {
			return true
		}
	}
	return false
}

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

// git's exit status for "the key you asked me to unset isn't there".
const gitConfigNothingToUnset = 5

type includeRule struct{ cond, target string }

// includeCandidate is one folder rule on its way to becoming an includeIf: how
// specific it is, where it was declared, the pattern git will match on, and the
// account it selects.
type includeCandidate struct {
	weight  int // path length, or folder-name count
	order   int // position in the config file, which is how gitsby breaks a tie
	pattern string
	account string
}

// sortIncludes orders candidates the way the two matchers have to agree: git takes
// the LAST rule that matches and gitsby the most specific, so least specific comes
// first. Equal specificity is the case that used to disagree - gitsby keeps the
// FIRST rule declared, so that one has to be written LAST for git to keep it too,
// which is why the order runs backwards here.
func sortIncludes(list []includeCandidate) {
	slices.SortFunc(list, func(x, y includeCandidate) int {
		return cmp.Or(
			cmp.Compare(x.weight, y.weight),
			cmp.Compare(y.order, x.order),
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
	// Straight off the rule lists, so the index IS the declaration order that
	// accountForDir breaks its own ties by.
	var paths, segments []includeCandidate
	for i, r := range c.paths {
		if r.match == "" {
			continue
		}
		// The trailing slash is what makes git apply it to everything below the
		// folder too.
		paths = append(paths, includeCandidate{len(r.match), i, r.match + "/", r.acct})
	}
	for i, r := range c.segments {
		if r.match == "" {
			continue
		}
		segments = append(segments, includeCandidate{strings.Count(r.match, "/") + 1, i, "**/" + r.match + "/**", r.acct})
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
		// --unset-all takes every entry under a key at once, so a key listed twice
		// (two accounts claiming one folder produce the same one) is removed by the
		// first pass and absent for the second.
		if !slices.Contains(keys, key) {
			keys = append(keys, key)
		}
	}
	return keys
}

func (a *app) cmdAccountList() {
	a.out.clean("")
	configDisp := displayPath(a.cfg.file)
	if configDisp == "" {
		configDisp = "(none found)"
	}
	a.out.clean("Config file ..: " + configDisp)
	a.out.clean(dirLabel + nativePath(a.contextDir()))
	hereAccount := a.cfg.accountForDir(a.contextDir())
	// An account that resolved and simply names no login is not the same as no
	// account at all - reported as "nothing configured" it contradicted the source
	// printed in the same sentence. Named as "(no login named)" it said nothing
	// anybody could act on either: the account is what the reader has to go and
	// edit, so name that instead.
	resolvedLine := a.accountWho(a.accountHost())
	switch {
	case resolvedLine != "":
		if a.acct.source != "" {
			resolvedLine += " (from " + a.accountSourceText(false) + ")"
		}
	case a.acct.name != "":
		resolvedLine = "'" + a.acct.name + "' - it names no login" + a.accountFallbackNote()
	default:
		// Nothing beyond that: this says what gitsby is configured to do here, and
		// whatever git and the forge CLI fall back to is their own business.
		resolvedLine = "(nothing configured)"
	}
	// Status's label for the same answer. "Resolves to" named no actor, so the first
	// question it raised was who was doing the resolving.
	a.out.clean(acctLabel + resolvedLine)
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
	for _, contested := range a.cfg.contestedRules() {
		a.out.clean("")
		a.out.clean("WARNING: more than one account claims " + contested + " - only the first is used.")
	}
}

// contestedRules names the folder rules more than one account claims. There is no
// right answer to one: gitsby keeps the first declared, git keeps the last written,
// and 'account apply' can only make them agree about which mistake to make.
func (c *config) contestedRules() []string {
	var out []string
	for _, rules := range [][]acctRule{c.paths, c.segments} {
		byMatch := map[string][]string{}
		var order []string
		for _, r := range rules {
			if r.match == "" || slices.Contains(byMatch[r.match], r.acct) {
				continue
			}
			if len(byMatch[r.match]) == 0 {
				order = append(order, r.match)
			}
			byMatch[r.match] = append(byMatch[r.match], r.acct)
		}
		for _, match := range order {
			if len(byMatch[match]) > 1 {
				out = append(out, match+": "+strings.Join(byMatch[match], ", "))
			}
		}
	}
	return out
}

func (a *app) showAccount(name string, isHere bool) {
	marker := "  "
	if isHere {
		marker = "->"
	}
	a.out.clean(marker + " " + name)
	// The host leads, because it decides whether anything under it applies at all.
	// Leaving the deciding field off the listing made 'account list' - the command
	// that always says - silent about the one key that had refused an account.
	// Shown only once some account names a forge, and then for every account,
	// including the ones that never said: it is the comparison that answers "why did
	// this one apply and that one not", and it is meaningless where every account is
	// on the same host. A config with one forge in it reads exactly as it always did.
	if host := a.cfg.value(name, "host"); host != "" {
		a.out.clean("     host ....: " + host)
	} else if a.cfg.anyHostStated() {
		a.out.clean("     host ....: github.com  (default)")
	}
	ghWho := a.cfg.value(name, "ghAccount")
	ghDisp := ghWho
	if ghDisp == "" {
		ghDisp = "(none)"
	}
	a.out.clean("     github ..: " + ghDisp)
	// The host-neutral login, and on a non-GitHub account the only one there is.
	if user := a.cfg.value(name, "user"); user != "" {
		a.out.clean("     login ...: " + user)
	}
	// Say where a token would come from, never what it is.
	tokenFrom := "none"
	if ghWho != "" && ghTokenFor(ghWho) != "" {
		tokenFrom = "gh's own store"
	} else if readTokenFile(a.cfg.value(name, "tokenFile")) != "" {
		tokenFrom = nativePath(a.cfg.value(name, "tokenFile"))
	}
	a.out.clean("     token ...: " + tokenFrom)
	if sshKey := a.cfg.value(name, "sshKey"); sshKey != "" {
		a.out.clean("     ssh key .: " + nativePath(sshKey))
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
			a.out.clean("     folder ..: " + nativePath(folder))
		} else {
			a.out.clean("     folder ..: " + nativePath(folder) + "  (no such directory - this rule can never match)")
		}
	}
	// No existence check on these: naming no machine in particular is the point.
	for _, seg := range a.cfg.segmentsOf(name) {
		a.out.clean("     anywhere : " + nativePath(".../"+seg+"/..."))
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
	// 0700, not 0777-and-hope-for-umask: these fragments name your accounts and
	// point at your token file, and they sit under your own config directory.
	if err := os.MkdirAll(dir, 0o700); err != nil {
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
		// git exits 5 for "there was nothing to remove", which is the end state this
		// loop is asking for. Only a real failure is one - reading 5 as one left the
		// config with no rules at all and the command reporting an error.
		if rc := a.inheritRC("git", "config", "--global", "--unset-all", key); rc != 0 && rc != gitConfigNothingToUnset {
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
	if err := os.WriteFile(fragment, nil, 0o600); err != nil {
		return usagef("Couldn't write '%s'. Check permissions on '%s'.", fragment, dir)
	}
	// WriteFile only applies its mode when it creates the file, so a fragment left
	// world-readable by an earlier run - or by a umask - stays that way through
	// every re-apply. It names the account and points at the token file.
	if err := os.Chmod(fragment, 0o600); err != nil && !isWindows() {
		return usagef("Couldn't set permissions on '%s'; it names your account and points at your token file.", fragment)
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

// accountSetFields: the per-account keys 'account set' will write, spelled the way
// the file and the docs spell them. The loader lowercases every key on the way in,
// so the file takes any casing - but a line this command WROTE has to read back
// looking like the ones a person wrote by hand.
var accountSetFields = []string{"path", "pathContains", "ghAccount", "tokenFile", "sshKey", "name", "email", "protocol", "host", "user"}

// canonAccountField maps whatever casing was typed onto the documented spelling,
// or empty for a key nothing reads. Refusing an unknown key is the point: the
// loader only lists one as ignored, which is a warning nobody reads until the
// account silently fails to apply.
func canonAccountField(field string) string {
	for _, known := range accountSetFields {
		if strings.EqualFold(known, field) {
			return known
		}
	}
	return ""
}

// The byte-order mark a Windows editor writes at the top of a file it saves.
const utf8BOM = "\ufeff"

// accountSetTarget is what 'account set' would write, and where. Everything the
// write needs is settled here, off ONE read of the file, so the plan on screen and
// the edit that follows cannot describe two different files.
type accountSetTarget struct {
	file    string
	key     string
	value   string
	lines   []string
	bom     string
	crlf    bool
	lineNum int // 1-based line being replaced; 0 to append
	old     string
	creates bool // the file itself does not exist yet
}

// newLine spells the line to be written, in the file's own line ending.
func (t accountSetTarget) newLine() string {
	line := t.key + " = " + quoteConfigValue(t.value)
	if t.crlf {
		line += "\r"
	}
	return line
}

// accountSetPlan resolves what 'account set' would do without doing any of it.
// The value is validated here rather than at write time, so a refusal happens
// before the plan is shown rather than after it has been agreed to.
func (a *app) accountSetPlan() (accountSetTarget, error) {
	var t accountSetTarget
	name := strings.ToLower(a.cmd.arg)
	if !acctNameOK.MatchString(name) {
		return t, usagef("'%s' isn't a usable account name; letters, digits, '.', '_' and '-' only.", a.cmd.arg)
	}
	field := canonAccountField(a.cmd.arg2)
	if field == "" {
		return t, usagef("'%s' isn't an account key %s reads. One of: %s.", a.cmd.arg2, meName, strings.Join(accountSetFields, ", "))
	}
	t.key, t.value = "account."+name+"."+field, a.cmd.arg3
	// The same two checks the loader makes, made here where they can still be
	// answered. Written past them the line lands in the file and is then dropped on
	// every read, so the file says one thing and every command does another.
	if field == "sshKey" && strings.ContainsAny(t.value, sshKeyShellChars) {
		return t, usagef("git hands a key path to a shell, so one carrying whitespace or a shell character is re-parsed rather than used. Move the key somewhere plainer.")
	}
	if (field == "host" || field == "user") && !forgeWordOK.MatchString(t.value) {
		return t, usagef("'%s' isn't a plain %s name; letters, digits, '.', '_' and '-' only.", t.value, strings.ToLower(field))
	}
	if t.file = a.cfg.file; t.file == "" {
		if t.file = defaultConfigFile(); t.file == "" {
			return t, usagef("There is nowhere to put an accounts file: this machine names no home directory. Set HOME, or name a file with --config.")
		}
		t.creates = true
		return t, nil
	}
	data, err := os.ReadFile(t.file)
	if err != nil {
		return t, usagef("Couldn't read '%s'.", displayPath(t.file))
	}
	// Read apart, written back byte for byte. This file is hand-written and
	// hand-commented, and a command that reformatted it on the way past - dropping
	// the mark a Windows editor put there, or rewriting every line ending - would
	// cost more than it saved. Split on '\n' alone for the same reason.
	text := string(data)
	if strings.HasPrefix(text, utf8BOM) {
		text, t.bom = strings.TrimPrefix(text, utf8BOM), utf8BOM
	}
	t.crlf = strings.Contains(text, "\r\n")
	t.lines = strings.Split(text, "\n")
	// 'path' and 'pathContains' are repeatable by design, and any key at all can be
	// in there twice by accident. Replacing the first and leaving the rest would
	// look like it worked and change nothing, so say so rather than guess.
	var found []int
	for i, line := range t.lines {
		key, _, ok := strings.Cut(strings.TrimLeft(line, " \t"), "=")
		if ok && strings.EqualFold(strings.TrimRight(key, " \t"), t.key) {
			found = append(found, i+1)
			t.old = strings.TrimRight(line, "\r")
		}
	}
	if len(found) > 1 {
		return t, usagef("'%s' is in %s %d times. Edit it by hand - there is no telling which one you meant.", t.key, displayPath(t.file), len(found))
	}
	if len(found) == 1 {
		t.lineNum = found[0]
	}
	return t, nil
}

// quoteConfigValue wraps a value the reader would otherwise take apart. ' #' starts
// a comment mid-line and a leading quote is stripped as one, so a value carrying
// either has to go back in quoted or it will not read back as itself.
func quoteConfigValue(value string) string {
	switch {
	case value == "":
		return `""`
	case strings.Contains(value, " #"), strings.Contains(value, "\t#"),
		value[0] == '"', value[0] == '\'', value[0] == '#',
		strings.HasSuffix(value, " "), strings.HasSuffix(value, "\t"):
		return `"` + strings.ReplaceAll(value, `"`, "") + `"`
	}
	return value
}

// cmdAccountSet writes one 'account.<name>.<key> = <value>' line into the accounts
// file, replacing that key's existing line where it has one. Every other line is
// copied through untouched.
func (a *app) cmdAccountSet() error {
	t, err := a.accountSetPlan()
	if err != nil {
		return err
	}
	line := t.newLine()
	switch {
	case t.creates:
		dir := t.file
		if i := strings.LastIndexAny(dir, `/\\`); i > 0 {
			dir = dir[:i]
		}
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return usagef("Couldn't create '%s' to put the accounts file in.", displayPath(dir))
		}
		t.lines = []string{"# " + meName + " accounts: one 'key = value' per line.", "", line, ""}
	case t.lineNum > 0:
		t.lines[t.lineNum-1] = line
	case len(t.lines) > 0 && strings.TrimRight(t.lines[len(t.lines)-1], "\r") == "":
		// A file ending in a newline splits to a trailing empty element. Writing over
		// it and adding a fresh one keeps that final newline where it was, instead of
		// leaving a blank line in the middle of the file.
		t.lines[len(t.lines)-1] = line
		t.lines = append(t.lines, "")
	default:
		t.lines = append(t.lines, line)
	}
	// 0600 on create: this file names your accounts and points at your token files.
	// WriteFile only applies a mode when it creates one, so an existing file keeps
	// the permissions it has - which is the caller's business and not ours.
	if err := os.WriteFile(t.file, []byte(t.bom+strings.Join(t.lines, "\n")), 0o600); err != nil {
		return usagef("Couldn't write '%s'. Check permissions on it.", displayPath(t.file))
	}
	a.out.status("Wrote " + displayPath(t.file))
	return nil
}
