// The account commands: 'list' shows what is configured and which rule this folder
// matches, and 'apply' gives plain git the same folder rules.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"cmp"
	"errors"
	"fmt"
	"io/fs"
	"maps"
	"math/rand/v2"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"time"
	"unicode"

	shcl "github.com/yottacore/shcl/source/go/v3"
)

// anyHostStated: whether any account in this config names a git host. What makes the
// host worth a line in the listing - with one git host configured there is nothing to
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

// rulesOf: the rules in one list that belong to one account.
func rulesOf(rules []acctRule, name string) []acctRule {
	var out []acctRule
	for _, r := range rules {
		if r.acct == name && r.match != "" {
			out = append(out, r)
		}
	}
	return out
}

// includeDir: where the per-account fragments live, beside the config file. Absolute,
// since git reads a relative include from its own config's folder.
func (c *config) includeDir() string {
	if c.file == "" {
		return ""
	}
	dir, err := filepath.Abs(filepath.Dir(c.file))
	if err != nil {
		dir = filepath.Dir(c.file)
	}
	// A root comes back with its slash on, 'C:/' or '/'.
	return strings.TrimSuffix(filepath.ToSlash(dir), "/") + "/accounts"
}

// fragmentNames maps each account to its fragment's file name: host, then login, or the
// account's own name with no login. 2 accounts sharing both add their names.
func (c *config) fragmentNames() map[string]string {
	names := c.accountNames()
	base := make(map[string]string, len(names))
	count := map[string]int{}
	for _, name := range names {
		who := c.loginOf(name)
		if who == "" {
			who = name
		}
		base[name] = fileSafe(c.hostOf(name)) + "_" + fileSafe(who)
		count[base[name]]++
	}
	files := make(map[string]string, len(names))
	for _, name := range names {
		file := base[name]
		if count[file] > 1 {
			file += "_" + name
		}
		files[name] = file + ".gitconfig"
	}
	return files
}

// fileSafe holds a host or login to what the account name itself may use, so it
// can't climb out of the include folder. 'host' and 'user' are checked on load,
// but 'ghaccount' is not. Lower case, so two spellings of one login don't make
// two files.
func fileSafe(s string) string {
	return strings.Map(func(r rune) rune {
		if r < 0x80 && (r == '.' || r == '_' || r == '-' || unicode.IsLetter(r) || unicode.IsDigit(r)) {
			return r
		}
		return '-'
	}, strings.ToLower(s))
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

// sortIncludes puts least specific first: git takes the last rule that matches, gitsby
// the most specific. On a tie gitsby keeps the first declared, so it goes last.
func sortIncludes(list []includeCandidate) {
	slices.SortFunc(list, func(x, y includeCandidate) int {
		return cmp.Or(
			cmp.Compare(x.weight, y.weight),
			cmp.Compare(y.order, x.order),
		)
	})
}

// accountApplyPlan: the includeIf conditions 'account apply' would write. gitdir/i,
// since a path ignores case on Windows and macOS.
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
		// folder too. A root has one already, and a second matches nothing.
		pattern := globLiteral(r.match)
		if !strings.HasSuffix(pattern, "/") {
			pattern += "/"
		}
		paths = append(paths, includeCandidate{len(r.match), i, pattern, r.acct})
	}
	for i, r := range c.segments {
		if r.match == "" {
			continue
		}
		segments = append(segments, includeCandidate{strings.Count(r.match, "/") + 1, i, "**/" + globLiteral(r.match) + "/**", r.acct})
	}
	if len(paths)+len(segments) == 0 {
		return nil
	}
	sortIncludes(segments)
	sortIncludes(paths)
	files := c.fragmentNames()
	plan := make([]includeRule, 0, len(segments)+len(paths))
	for _, cand := range slices.Concat(segments, paths) {
		plan = append(plan, includeRule{"includeIf.gitdir/i:" + cand.pattern + ".path", dir + "/" + files[cand.account]})
	}
	return plan
}

// globLiteral escapes what git's gitdir match reads as a pattern. gitsby matches a
// rule as plain text, so 'path: ~/d*' bound '~/dev' in plain git and nothing in
// gitsby, and 'pathcontains: **' bound every repo on the disk.
func globLiteral(s string) string {
	var b strings.Builder
	for _, r := range s {
		if strings.ContainsRune(`*?[\`, r) {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	return b.String()
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
	// --null, since the key holds a folder path that can have a space, where the plain
	// form splits key from value.
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
		if value := canonPath(value); value == canonDir || !pathUnder(value, canonDir) {
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
	configDisp := nativePath(a.cfg.file)
	if configDisp == "" {
		configDisp = "(none)"
	}
	a.out.clean("Config file ..: " + configDisp)
	a.out.clean(dirLabel + nativePath(a.contextDir()))
	hereAccount := a.cfg.accountForDir(a.contextDir())
	// An account with no login is still an account. Name it, since it's what the reader
	// has to edit.
	resolvedLine := a.accountWho(a.accountHost())
	switch {
	case resolvedLine != "":
		if a.acct.source != "" {
			resolvedLine += " (from " + a.acct.source + ")"
		}
	case a.acct.name != "":
		resolvedLine = "'" + a.acct.name + "' - it names no login" + a.accountFallbackNote()
	default:
		// Nothing beyond that: this says what gitsby is configured to do here, and
		// whatever git and the git host CLI fall back to is their own business.
		resolvedLine = "(nothing configured)"
	}
	// Status's label for the same answer. "Resolves to" named no actor, so the first
	// question it raised was who was doing the resolving.
	a.out.clean(acctLabel + resolvedLine)
	if len(a.cfg.unknown) > 0 {
		a.out.clean("Ignored keys .: " + strings.Join(a.cfg.unknown, ", "))
	}
	// Here and nowhere else: this is the command the docs send you to when something
	// went out as the wrong person, and asking git costs every other command a process.
	stale := a.cfg.relativeManagedIncludes()
	warnStale := func() {
		for _, pattern := range stale {
			a.out.clean("")
			a.out.clean("WARNING: your global git config still has the rule 'gitdir/i:" + pattern + "' from an earlier 'account apply'. " +
				"Its folder isn't absolute, so plain git can apply that account far from where it was typed. Run '" + meName + " account apply' to remove it.")
		}
	}
	names := a.cfg.accountNames()
	if len(names) == 0 {
		a.out.clean("")
		a.out.clean("No accounts defined. '" + meName + " account set' adds one; run it with no arguments for the keys it takes.")
		warnStale()
		return
	}
	a.out.clean("")
	a.out.clean("Accounts:")
	logins := make([]string, 0, len(names))
	for _, name := range names {
		logins = append(logins, a.cfg.value(name, "ghAccount"))
	}
	a.askGhTokens(logins)
	for _, name := range names {
		a.showAccount(name, name == hereAccount)
	}
	for _, contested := range a.cfg.contestedRules() {
		a.out.clean("")
		a.out.clean("WARNING: more than one account claims " + contested + " - only the first is used.")
	}
	warnStale()
}

// contestedRules names the folder rules more than one account claims. There is no
// right answer to one: gitsby keeps the first declared, git keeps the last written,
// and 'account apply' can only make them agree about which mistake to make.
func (c *config) contestedRules() []string {
	var out []string
	for _, rules := range [][]acctRule{c.paths, c.segments} {
		byMatch := map[string][]string{}
		written := map[string]string{}
		var order []string
		for _, r := range rules {
			if r.match == "" || slices.Contains(byMatch[r.match], r.acct) {
				continue
			}
			if len(byMatch[r.match]) == 0 {
				order = append(order, r.match)
				// The first spelling, since two that match alike can be written apart.
				written[r.match] = r.written
			}
			byMatch[r.match] = append(byMatch[r.match], r.acct)
		}
		for _, match := range order {
			if len(byMatch[match]) > 1 {
				out = append(out, written[match]+": "+strings.Join(byMatch[match], ", "))
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
	// The host leads, since it decides whether the rest applies. Shown for every account
	// once any names a git host, so the list says why one applied and another didn't.
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
	tokenFrom := "(none)"
	if ghWho != "" && a.ghTokenFor(ghWho) != "" {
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
	// Each rule as the file writes it. The canonical form is lower case on Windows
	// with every link resolved, so printing that named a folder nobody had typed.
	for _, r := range rulesOf(a.cfg.paths, name) {
		// A rule pointing at no folder matches nothing. Usually a typo; on Windows also
		// a shell-only spelling such as '/tmp/...'.
		if isDir(r.match) {
			a.out.clean("     folder ..: " + r.written)
		} else {
			a.out.clean("     folder ..: " + r.written + "  (no such directory - this rule can never match)")
		}
	}
	// No existence check on these: naming no machine in particular is the point.
	for _, r := range rulesOf(a.cfg.segments, name) {
		a.out.clean("     anywhere : .../" + strings.Trim(r.written, `/\`) + "/...")
	}
}

// cmdAccountApply writes one fragment per account and an includeIf per folder rule,
// through 'git config' so git decides what's valid. The folder is checked first.
func (a *app) cmdAccountApply() error {
	dir := a.cfg.includeDir()
	if dir == "" {
		return usagef("No config file, so there is nowhere to write the account fragments.")
	}
	if pathExists(dir) && !isDir(dir) {
		return refusalBlock("Something that isn't a folder is where the account fragments go.", [][]string{
			noteLines("File", nativePath(dir)),
			noteLines("Fix", "Move or remove it, then run this again."),
		}, nil)
	}
	// 0700, not 0777-and-hope-for-umask: these fragments name your accounts and
	// point at your token file, and they sit under your own config directory.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return writeRefusal("Couldn't create the folder the account fragments go in.", "Creating it", err,
			"Nothing was written.", "Make the folder it goes in writable, then run this again.",
			noteLines("File", nativePath(failedAt(err, dir))))
	}
	files := a.cfg.fragmentNames()
	for _, name := range a.cfg.accountNames() {
		if err := a.writeAccountFragment(dir, files[name], name); err != nil {
			return err
		}
	}
	// A fragment left from an account since renamed or dropped, or from before
	// fragments were named by host. Named rather than removed, since nothing says
	// gitsby put it there.
	if entries, err := os.ReadDir(dir); err == nil {
		written := slices.Collect(maps.Values(files))
		for _, e := range entries {
			if strings.HasSuffix(e.Name(), ".gitconfig") && !slices.Contains(written, e.Name()) {
				a.out.statusNotes("Not used any more, safe to remove.", noteLines("File", nativePath(dir+"/"+e.Name())))
			}
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

// writeAccountFragment writes one account's git config fragment. Every write is checked,
// since this is the one command that writes outside the repo.
func (a *app) writeAccountFragment(dir, file, name string) (err error) {
	fragment := dir + "/" + file
	// Nothing goes into the global config until every fragment is written, and the
	// global config may already include this one. So the keys go into a new file
	// that replaces it only once all of them are in.
	const fragmentKept = "This one is as it was, and fragments written before it stay. Your global git config was not changed."
	// The replace would take a read-only fragment, or another user's, without a
	// word, so those are refused here, with nothing changed.
	if f, err := os.OpenFile(fragment, os.O_WRONLY, 0); err == nil {
		_ = f.Close() // opened only to ask; nothing went through it
	} else if !errors.Is(err, fs.ErrNotExist) {
		return writeRefusal("Couldn't write an account fragment.", "Writing it", err,
			fragmentKept, "Check permissions on it and on the folder it is in, then run this again.",
			noteLines("File", nativePath(fragment)))
	}
	// CreateTemp makes it 0600, which git keeps through its own writes. Its name
	// doesn't end in .gitconfig, so a crash's leftover isn't offered as a fragment.
	tmp, err := os.CreateTemp(dir, file+".*.tmp")
	if err != nil {
		return writeRefusal("Couldn't write an account fragment.", "Creating its replacement", err,
			fragmentKept, "Check permissions on the folder it is in, then run this again.",
			noteLines("File", nativePath(fragment)))
	}
	newFragment := filepath.ToSlash(tmp.Name())
	_ = tmp.Close() // git writes it, not this handle
	defer func() {
		if err != nil {
			_ = os.Remove(newFragment) // the refusal is the error to report; a leftover is never read
		}
	}()
	write := func(key, value string) error {
		if !a.inheritOK("git", "config", "--file", newFragment, key, value) {
			return refusalBlock("Couldn't write "+key+" into an account fragment; it was left as it was, and nothing further was applied.",
				[][]string{noteLines("File", nativePath(fragment))}, nil)
		}
		return nil
	}
	entries := []struct{ key, value string }{
		{"user.name", a.cfg.value(name, "name")},
		{"user.email", a.cfg.value(name, "email")},
		{"gitsby.ghAccount", a.cfg.value(name, "ghAccount")},
		// Which account plain git asks for over https, so a credential manager looks up
		// that account's entry and not any for the host.
		{"credential.https://" + a.cfg.hostOf(name) + ".username", a.cfg.loginOf(name)},
		// Expanded, since git knows none of the home spellings the accounts file takes.
		{"gitsby.ghTokenFile", expandHome(a.cfg.value(name, "tokenFile"))},
		// gh's own helper answers only for its active account, so plain git over
		// https had nothing to push with in another account's folder. Added after
		// any helper the global config already lists, so a credential manager set
		// up there is still asked first.
		{"credential.https://" + a.cfg.hostOf(name) + ".helper", a.fragmentHelperFor(name)},
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
		if err := write("core.sshCommand", sshKeyCommand(sshKey)); err != nil {
			return err
		}
	}
	if err := os.Rename(newFragment, fragment); err != nil {
		return writeRefusal("Couldn't write an account fragment.", "Replacing it", err,
			fragmentKept, "Check permissions on it and on the folder it is in, then run this again.",
			noteLines("File", nativePath(fragment)))
	}
	a.out.statusNotes("Wrote an account fragment.", noteLines("File", nativePath(fragment)))
	return nil
}

// fragmentHelperFor is an account's helper, or nothing for one with no way to a
// token on its own host, such as an ssh-only account: a helper that can never
// answer only costs every https request a few processes.
func (a *app) fragmentHelperFor(name string) string {
	onGitHub := isGitHubHost(a.cfg.hostOf(name))
	if a.cfg.value(name, "tokenFile") == "" && (!onGitHub || a.cfg.value(name, "ghAccount") == "") {
		return ""
	}
	return fragmentHelper(onGitHub)
}

// fragmentHelper is the credential helper a fragment gives plain git. It reads the login
// and token file from git config when it runs, so nothing from the accounts file goes
// into a shell line. Detail: backlog 2026110810100400.
func fragmentHelper(onGitHub bool) string {
	steps := []string{
		`test "$1" = get || return 0`,
		`n= t=`,
		`while IFS= read -r l && test -n "$l"; do case $l in username=*) n=1 ;; esac; done`,
	}
	if onGitHub {
		steps = append(steps,
			`u=$(git config --get gitsby.ghAccount)`,
			`test -z "$u" || t=$(gh auth token --user "$u" 2>/dev/null)`)
	}
	steps = append(steps,
		`if test -z "$t"; then f=$(git config --global --includes --get gitsby.ghTokenFile); case $f in /*|?:*) ;; *) f= ;; esac; test -r "$f" && t=$(tr -d '[:space:]' < "$f"); fi`,
		`test -n "$t" || return 0`,
		`test -n "$n" || echo username=x`,
		`echo "password=$t"`)
	return "!f(){ " + strings.Join(steps, "; ") + "; }; f"
}

// accountSetFields: the per-account keys 'account set' will write, spelled the way
// the file spells them. The format folds key names to lower case on every
// rewrite, so lower case is the one spelling a file ever settles on, and the help
// and the docs say it that way too rather than teach one the file won't keep.
var accountSetFields = []string{"path", "pathcontains", "ghaccount", "tokenfile", "sshkey", "name", "email", "protocol", "host", "user"}

// The block nests by indent rather than lining up under the 'gitsby: ' prefix: the
// prefix is on one line only, so hanging everything off its width buries the
// structure. Placeholders sit two levels in, with a description column past the
// widest of them, and the examples one level deeper again.
const (
	accountSetIndent = "  "
	accountSetPad    = accountSetIndent + accountSetIndent
	accountSetCont   = "               "
)

// accountSetUsage spells out the 3 words 'account set' takes, with the closed list of
// keys. No '*' in the examples, since 'pathContains' is folder names, not a glob.
func accountSetUsage() error { return usageOf("account set").refuse("") }

func accountSetLines() []string {
	lines := []string{
		"Syntax: " + meName + " account set <account> <key> <value>",
		accountSetIndent + "Writes '<key>: <value>' into the <account> block of the accounts file.",
		accountSetPad + "<account>  A string you define for one login; e.g. 'work', 'personal'.",
	}
	lines = appendKeyDef(lines, "The setting to change. One of: "+strings.Join(accountSetFields, ", ")+".")
	lines = append(lines,
		accountSetPad+"<value>    What to set it to. Quote it if it has spaces.",
		accountSetIndent+"Examples:",
		accountSetPad+"Bind an account to one folder, and the login to use there:",
		accountSetPad+accountSetIndent+meName+" account set github.com_my-work-login path ~/dev/work",
		accountSetPad+accountSetIndent+meName+" account set github.com_my-work-login ghaccount my-work-login",
		accountSetPad+"Or by a run of folder names the project's path contains:",
		accountSetPad+accountSetIndent+meName+" account set github.com_my-work-login pathcontains my-employer/github")
	return lines
}

// accountUnsetUsage is the same layout for the two words 'account unset' takes. A
// key nothing reads can go too, where the block has one: that is the line the
// listing calls ignored, and this is the way to be rid of it.
func accountUnsetUsage() error { return usageOf("account unset").refuse("") }

func accountUnsetLines() []string {
	lines := []string{
		"Syntax: " + meName + " account unset <account> <key>",
		accountSetIndent + "Removes '<key>' from the <account> block of the accounts file, every line of it.",
		accountSetPad + "<account>  The account to change; e.g. 'work', 'personal'.",
	}
	lines = appendKeyDef(lines, "The setting to remove. One of: "+strings.Join(accountSetFields, ", ")+", or any other key the block has.")
	lines = append(lines,
		accountSetIndent+"Example:",
		accountSetPad+"Go back to the default host for an account:",
		accountSetPad+accountSetIndent+meName+" account unset gitea.com_my-login host")
	return lines
}

// appendKeyDef adds the '<key>' line of either usage, wrapped under its column.
func appendKeyDef(lines []string, def string) []string {
	key := wrapWords(def, 57)
	lines = append(lines, accountSetPad+"<key>      "+key[0])
	for _, rest := range key[1:] {
		lines = append(lines, accountSetCont+rest)
	}
	return lines
}

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

// absPathValue is the 'path', 'tokenfile' or 'sshkey' value 'account set' writes,
// absolute since the file can't say where it was typed. Forward slashes, since a
// backslash in a bare value is an escape. One starting at home stays as typed.
func absPathValue(value, what string) (string, error) {
	// filepath.Abs("") is the current directory, which nobody typed.
	if value == "" {
		return value, nil
	}
	switch folderRuleProblem(value) {
	case "":
		return value, nil
	case ruleNoHome:
		return "", usagef("'%s' starts at the home folder, and this machine names none. Give the full path.", value)
	case ruleOtherHome:
		return "", usagef("'%s' names another user's home folder, and only a bare '~' is expanded. Give the full path.", value)
	case ruleOtherVar:
		return "", usagef("'%s' starts with a variable %s doesn't expand. Only '~', '${HOME}' and '%%USERPROFILE%%' are, or give the full path.", value, meName)
	}
	abs, err := filepath.Abs(value)
	if err != nil {
		return "", usagef("Couldn't work out which %s '%s' is from here, since finding the current folder failed with: %s. Give the full path.", what, value, causeText(err))
	}
	abs = filepath.ToSlash(abs)
	if folderRuleProblem(abs) != "" {
		return "", usagef("Couldn't work out which %s '%s' is from here. Give the full path.", what, value)
	}
	return abs, nil
}

// managedIncludePattern takes the folder pattern back out of an includeIf key as
// accountManagedIncludes lists it: 'includeIf.gitdir/i:./.path' gives './'. git
// hands the section and variable back lower-cased and the pattern as written.
func managedIncludePattern(key string) (string, bool) {
	const suffix = ".path"
	for _, prefix := range []string{"includeif.gitdir/i:", "includeif.gitdir:"} {
		if len(key) < len(prefix)+len(suffix) {
			continue
		}
		if strings.EqualFold(key[:len(prefix)], prefix) && strings.EqualFold(key[len(key)-len(suffix):], suffix) {
			return key[len(prefix) : len(key)-len(suffix)], true
		}
	}
	return "", false
}

// relativeManagedIncludes names our includeIf patterns in the global git config with a
// relative folder, left by an older apply. A '**/' one is a pathcontains rule.
func (c *config) relativeManagedIncludes() []string {
	var out []string
	for _, key := range c.accountManagedIncludes() {
		pattern, ok := managedIncludePattern(key)
		if !ok || strings.HasPrefix(pattern, "**/") || slices.Contains(out, pattern) {
			continue
		}
		// A root keeps its slash: 'C:' alone is not a folder.
		folder := pattern
		if folder != "/" && !driveRootRE.MatchString(folder) {
			folder = strings.TrimSuffix(folder, "/")
		}
		if folderRuleProblem(folder) != "" {
			out = append(out, pattern)
		}
	}
	return out
}

// accountSetTarget is what 'account set' would write, and where. Everything the
// write needs is settled here, off ONE read of the file, so the plan on screen and
// the edit that follows cannot describe two different files.
type accountSetTarget struct {
	file     string
	doc      *shcl.Document
	base     string // the account block's lookup path
	disp     string // the block as the plan names it: account[work]
	field    string
	value    string
	exists   bool   // the key is in the block already
	lineNum  int    // the line it is on now, where the file keeps its shape
	old      string // its value now, as typed
	creates  bool   // the file itself does not exist yet
	converts bool   // the file is in the old flat layout, and comes out in the current one
	reshapes bool   // the save changes more of the file than the key: spacing, key case, line ends
	read     string // the file as the plan read it; the save refuses once it has anything else
	unset    bool   // 'account unset': the key comes out rather than going in
	gone     []goneLine
}

// goneLine is one line 'account unset' takes out: where it is now, and what it says.
type goneLine struct {
	num  int
	text string
}

func (t accountSetTarget) path() string { return t.base + "." + t.field }

// configInTheWay refuses a create while anything is at a place an accounts file
// can live. Reads pass over such a file as if it were not there, and a create
// taking that at its word would replace it, or go in ahead of it and hide it from
// every later command. Every candidate counts, not only the one written.
func (a *app) configInTheWay() error {
	for _, c := range configCandidates() {
		if state, fi, err := probeConfigCandidate(c); state != candidateAbsent {
			return configRefusal(c, state, fi, err)
		}
	}
	return nil
}

// configRefusal says why a create was refused, by what is at the path. The fix
// differs for each, so they don't share one message. Absent and usable both mean
// a file arrived after the load: absent is reached only when the exclusive open
// said something was there, and it has gone again since.
func configRefusal(file string, state candidateState, fi os.FileInfo, cause error) error {
	kept := noteLines("Kept", "Nothing was written.")
	var head string
	var notes [][]string
	switch state {
	case candidateUnreadable:
		head = "An accounts file is already there, and it can't be read."
		notes = [][]string{
			noteLines("File", nativePath(file)),
			noteLines("Why", "A new file here would replace it. Opening it failed with: "+causeText(cause)+"."),
			kept,
			noteLines("Fix", unreadableFix(runtime.GOOS, file, cause)...),
		}
	case candidateBrokenLink:
		head = "The accounts file is a link to something that isn't there."
		notes = [][]string{noteLines("File", nativePath(file))}
		if target, err := os.Readlink(file); err == nil {
			notes = append(notes, noteLines("Link", target))
		}
		notes = append(notes,
			noteLines("Why", "Writing through it would create a new file where it points, and whatever belongs there is missing right now."),
			kept,
			noteLines("Fix", "Put back what the link points to, or remove the link, then run this again."),
		)
	case candidateNotFile:
		kind := "special file"
		if fi != nil && fi.IsDir() {
			kind = "folder"
		}
		head = "Something that isn't a file is where the accounts file goes."
		notes = [][]string{
			noteLines("File", nativePath(file)),
			noteLines("Why", "It is a "+kind+", and the accounts file has to go in its place."),
			kept,
			noteLines("Fix", "Move it out of the way, then run this again."),
		}
	case candidateUnknown:
		head = "Couldn't look for an accounts file where one can be."
		why := "Looking there failed with: " + causeText(cause) + ", so there is no telling whether one is there."
		if file != defaultConfigFile() {
			why += " A new file would go in ahead of it and hide it."
		}
		notes = [][]string{
			noteLines("File", nativePath(file)),
			noteLines("Why", why),
			kept,
			noteLines("Fix", lookupFix(runtime.GOOS, file, cause)...),
		}
	default:
		head = "An accounts file turned up while this ran."
		notes = [][]string{
			noteLines("File", nativePath(file)),
			noteLines("Why", "This command read the accounts before the file was there, so its edit would replace what the file holds now."),
			kept,
			noteLines("Fix", "Run this again. It will edit the file that is there now."),
		}
	}
	return refusalBlock(head, notes, cause)
}

// refusalBlock is a refusal laid out by refusalText.
func refusalBlock(head string, notes [][]string, cause error) error {
	return &usageError{msg: refusalText(head, notes), cause: cause}
}

// refusalText lays a refusal out as its first line with the labeled notes under it.
// Each line is escaped here, since a head often quotes a value as typed.
func refusalText(head string, notes [][]string) string {
	lines := []string{printable(head)}
	for _, note := range notes {
		for _, l := range note {
			lines = append(lines, "  "+printable(l))
		}
	}
	return strings.Join(lines, "\n")
}

// writeRefusal says a step that writes was turned down, with the reason the OS
// gave. The permissions fix is offered only for a permissions error. A full disk,
// a read-only filesystem or a folder where a file goes names itself in Why, and a
// hint about permissions there sends the reader the wrong way.
func writeRefusal(head, doing string, cause error, kept, permFix string, where ...[]string) error {
	fix := "Run this again once that is fixed."
	if errors.Is(cause, fs.ErrPermission) {
		fix = permFix
	}
	return refusalBlock(head, append(where,
		noteLines("Why", doing+" failed with: "+causeText(cause)+"."),
		noteLines("Kept", kept),
		noteLines("Fix", fix),
	), cause)
}

// failedAt is the path an OS error names, else want. A MkdirAll that fails
// partway names the folder it stopped at, which can be above the one asked for.
func failedAt(err error, want string) string {
	var pe *fs.PathError
	if errors.As(err, &pe) && pe.Path != "" {
		return pe.Path
	}
	return want
}

// causeText is the OS's reason alone. The path is already on its own line, and a
// PathError repeats it.
func causeText(err error) string {
	if err == nil {
		return "no reason given"
	}
	var pe *fs.PathError
	text := err.Error()
	if errors.As(err, &pe) {
		text = pe.Err.Error()
	}
	return strings.TrimSuffix(text, ".")
}

// unreadableFix is the Fix for a file that can't be read: chmod off Windows, where
// gitsby made it 0600, and no one command on Windows. Takes goos, so both are testable.
func unreadableFix(goos, file string, cause error) []string {
	switch {
	case !errors.Is(cause, fs.ErrPermission):
		return []string{"Run this again once it can be read."}
	case goos == "windows":
		return []string{"Give your account read access to it, then run this again."}
	}
	// A leading space makes it a literal line: indented, never wrapped.
	return []string{"Make it readable, then run this again:", "  chmod u+r " + shellQuote(file)}
}

// lookupFix is the Fix for a place that couldn't be looked in. The command is given
// only when the folder the file sits in is the one that can't be searched, which
// looking up that folder itself proves. A folder further up is left to the reader.
func lookupFix(goos, file string, cause error) []string {
	dir := filepath.Dir(file)
	switch {
	case !errors.Is(cause, fs.ErrPermission):
		return []string{"Run this again once it can be looked up."}
	case goos == "windows":
		return []string{"Give your account access to the folder it is in, then run this again."}
	}
	if _, err := os.Lstat(dir); err != nil {
		return []string{"Make the folders above it searchable, then run this again."}
	}
	// A leading space makes it a literal line: indented, never wrapped.
	return []string{"Make the folder it is in searchable, then run this again:", "  chmod u+x " + shellQuote(dir)}
}

// createNew makes a file that must not exist yet, a link included, and writes it through
// the same handle at its mode, so no empty file is ever there to load. opened says this
// call made it. A failed write leaves it, since another run may own the name by then.
func createNew(file, text string, mode fs.FileMode) (opened bool, err error) {
	f, err := os.OpenFile(file, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return false, err
	}
	_, err = f.WriteString(text)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	return true, err
}

// A run holds the lock only from its re-read to its save, which is milliseconds.
const accountLockWait = 3 * time.Second

// lockAccountsFile keeps 2 runs from saving over each other, by an exclusive create
// beside the file, since the save renames over the name. The unlock checks a random
// token in it, not the inode, which UFS hands straight to the next file.
func lockAccountsFile(file string, wait time.Duration) (func(), error) {
	// The save writes through a link, so two names for one file take one lock.
	target := file
	if resolved, err := filepath.EvalSymlinks(file); err == nil {
		target = resolved
	}
	lock := target + ".lock"
	// math/rand, seeded by the runtime from the OS: the token only tells our lock
	// from a later run's, and crypto/rand costs 32 MiB of BSS for the FIPS module.
	token := fmt.Sprintf("%016x%016x", rand.Uint64(), rand.Uint64())
	deadline := time.Now().Add(wait)
	for {
		opened, err := createNew(lock, token, 0o600)
		if opened {
			if err != nil {
				_ = os.Remove(lock) // the write's error is the one to report; a leftover reads as held next run
				return nil, writeRefusal("Couldn't make the lock beside the accounts file.", "Writing it", err,
					"Nothing was written.", "Make the folder it is in writable, then run this again.",
					noteLines("File", nativePath(file)), noteLines("Lock", nativePath(lock)))
			}
			return func() {
				if now, err := os.ReadFile(lock); err == nil && string(now) == token {
					_ = os.Remove(lock) // the edit is saved; a lock that stays times out as held next run
				}
			}, nil
		}
		// Windows refuses a create over a file whose delete is still pending, which is
		// what another run's lock is for a moment after it lets go.
		held := errors.Is(err, fs.ErrExist)
		pending := isWindows() && errors.Is(err, fs.ErrPermission)
		switch {
		case !held && (!pending || time.Now().After(deadline)):
			return nil, writeRefusal("Couldn't make the lock beside the accounts file.", "Creating it", err,
				"Nothing was written.", "Make the folder it is in writable, then run this again.",
				noteLines("File", nativePath(file)), noteLines("Lock", nativePath(lock)))
		case time.Now().After(deadline):
			return nil, refusalBlock("Another run is editing the accounts file.", [][]string{
				noteLines("File", nativePath(file)),
				noteLines("Lock", nativePath(lock)),
				noteLines("Why", "Edits go in one at a time, and the lock beside the file was still there after waiting for it."),
				noteLines("Kept", "Nothing was written."),
				noteLines("Fix", lockFix(runtime.GOOS, lock)...),
			}, nil)
		}
		time.Sleep(25 * time.Millisecond)
	}
}

// lockFix is the Fix for a lock that stayed put. Takes the platform, so both are
// testable from either.
func lockFix(goos, lock string) []string {
	const stale = "If no other " + meName + " is running, a run that was stopped left it behind. Remove it, then run this again"
	if goos == "windows" {
		return []string{stale + "."}
	}
	// A leading space makes it a literal line: indented, never wrapped.
	return []string{stale + ":", "  rm " + shellQuote(lock)}
}

// changedRefusal: the file no longer has what the plan read. Saving would put
// back what it held then, and drop whatever went in since.
func changedRefusal(file string, cause error) error {
	why := "Something wrote it after this command read it, and saving now would undo that."
	if cause != nil {
		why = "Reading it again before the save failed with: " + causeText(cause) + "."
	}
	return refusalBlock("The accounts file changed while this ran.", [][]string{
		noteLines("File", nativePath(file)),
		noteLines("Why", why),
		noteLines("Kept", "Nothing was written."),
		noteLines("Fix", "Run this again. It will edit the file as it is now."),
	}, cause)
}

// accountNameArg is the account the set and unset commands were given, folded
// to the case the file keeps.
func (a *app) accountNameArg() (string, error) {
	name := strings.ToLower(a.cmd.arg)
	if !acctNameOK.MatchString(name) {
		return "", usagef("'%s' isn't a usable account name; letters, digits, '.', '_' and '-' only.", a.cmd.arg)
	}
	return name, nil
}

// accountSetPlan resolves what 'account set' would do without doing any of it.
// The value is validated here rather than at write time, so a refusal happens
// before the plan is shown rather than after it has been agreed to.
func (a *app) accountSetPlan() (accountSetTarget, error) {
	var t accountSetTarget
	name, err := a.accountNameArg()
	if err != nil {
		return t, err
	}
	t.field = canonAccountField(a.cmd.arg2)
	if t.field == "" {
		return t, usagef("'%s' isn't an account key %s reads. One of: %s.", a.cmd.arg2, meName, strings.Join(accountSetFields, ", "))
	}
	t.value, t.disp = a.cmd.arg3, "account["+name+"]"
	switch t.field {
	case "path":
		t.value, err = absPathValue(t.value, "folder")
	case "tokenfile", "sshkey":
		t.value, err = absPathValue(t.value, "file")
	}
	if err != nil {
		return t, err
	}
	// The loader's checks, made where they can still be answered, or the line is written
	// and then dropped on every read. The key is checked as it will be written.
	if t.field == "sshkey" && strings.ContainsAny(sshKeyArg(t.value), sshKeyShellChars) {
		return t, usagef("git hands a key path to a shell, so one with whitespace or a shell character is re-parsed rather than used. Move the key somewhere plainer.")
	}
	if (t.field == "host" || t.field == "user") && !hostWordOK.MatchString(t.value) {
		return t, usagef("'%s' isn't a plain %s name; letters, digits, '.', '_' and '-' only.", t.value, t.field)
	}
	if t.field == "protocol" {
		if !protocolOK(t.value) {
			return t, usagef("'%s' isn't a protocol %s uses. One of: https, ssh.", t.value, meName)
		}
		t.value = strings.ToLower(t.value)
	}
	if a.cfg.file == "" {
		if t.file = defaultConfigFile(); t.file == "" {
			return t, usagef("There is nowhere to put an accounts file: this machine names no home directory. Set HOME, or name a file with --config.")
		}
		if err := a.configInTheWay(); err != nil {
			return t, err
		}
		t.creates = true
		// The block goes in as text, ahead of the key: a header comment attaches to
		// the first setting after it, and with nothing there yet it would trail the
		// file as a footer instead.
		t.doc = shcl.Parse(configHeader + "\naccount: " + name + "\n\n" + shcl.GenBanner)
	} else if err := a.loadForEdit(&t); err != nil {
		return t, err
	}
	// Taken before the edit, so only what the save changes besides the key counts.
	tidy := t.doc.ToCanonical() == t.read
	// One account can be in pieces: blocks whose names differ only in case, or
	// dotted lines beside a block. The key is edited in whichever piece has it,
	// and added to the first when none does. Editing the first regardless left a
	// later piece's value as the one read.
	blocks, _ := acctBlocks(t.doc)
	n := 0
	for _, b := range blocks {
		if b.name != name {
			continue
		}
		if t.base == "" {
			t.base = b.path
		}
		if held := t.doc.Count(b.path + "." + shcl.QuoteSegment(t.field)); held > 0 {
			t.base, n = b.path, n+held
		}
	}
	if t.base == "" {
		// Quoted, so a name that happens to be a number is not read as an index.
		t.base = `account("` + name + `")`
	}
	// 'path' and 'pathcontains' are repeatable by design, and any key at all can be
	// in there twice by accident. Replacing the first and leaving the rest would
	// look like it worked and change nothing, so say so rather than guess.
	if n > 1 {
		return t, refusalBlock(fmt.Sprintf("'%s' is in the accounts file %d times.", printable(t.disp+"."+t.field), n), [][]string{
			noteLines("File", nativePath(t.file)),
			noteLines("Fix", "Edit it by hand - there is no telling which one you meant."),
		}, nil)
	}
	if read := t.doc.ReadString(t.path()); read.Status != shcl.NotFound {
		t.exists, t.lineNum = true, read.Line
		if read.Raw != nil {
			t.old = *read.Raw
		}
	}
	// Made here rather than at the save, so a key the file can't hold is refused
	// before the plan, and the plan knows whether the rest of the file comes back
	// as written. A few edits can't keep it, such as a key added under a dotted
	// line; those save the whole file in the module's own layout.
	if status := t.doc.SetString(t.path(), t.value); status != shcl.SetOk {
		return t, usagef("'%s' isn't a setting the file can hold (%s).", t.disp+"."+t.field, status)
	}
	_, kept := t.doc.ToTextKeepLines()
	if err := lostRefusal(t, kept); err != nil {
		return t, err
	}
	if !kept && !tidy && !t.creates && !t.converts {
		t.reshapes = true
	}
	return t, nil
}

// loadForEdit points t at the accounts file the run loaded, and at the document an
// edit is made to.
func (a *app) loadForEdit(t *accountSetTarget) error {
	if a.cfg.flat {
		// Converted whole, comments and all, rather than refused: the file was
		// written for the scripted builds, and this is the command that moves it on.
		data, err := os.ReadFile(a.cfg.file)
		if err != nil {
			return refusalBlock("Couldn't read the accounts file again to convert it.", [][]string{
				noteLines("File", nativePath(a.cfg.file)),
				noteLines("Why", "Reading it failed with: "+causeText(err)+"."),
				noteLines("Kept", "Nothing was written."),
				noteLines("Fix", unreadableFix(runtime.GOOS, a.cfg.file, err)...),
			}, err)
		}
		t.file, t.converts, t.read = a.cfg.file, true, string(data)
		t.doc = shcl.Parse(flatToSHCL(strings.TrimPrefix(string(data), utf8BOM)))
	} else {
		t.file, t.doc, t.read = a.cfg.file, a.cfg.doc, a.cfg.raw
	}
	// Saved as it stands, the file would mix the two formats' spellings, and the
	// next run would convert lines that were already right.
	if mig := a.cfg.migration; mig != nil && !mig.done {
		return refusalBlock("The accounts file is still in the "+mig.formatName()+".", [][]string{
			noteLines("File", nativePath(t.file)),
			noteLines("Why", "It couldn't be converted: "+mig.why+"."),
			noteLines("Kept", "Nothing was written."),
			noteLines("Fix", "Run this again. The next run tries the conversion first."),
		}, nil)
	}
	return nil
}

// lostLinesRefusal: the save would drop lines the read couldn't keep.
func lostLinesRefusal(file string, lost int) error {
	return refusalBlock(fmt.Sprintf("%d line(s) of the accounts file couldn't be read, and a rewrite would drop them.", lost), [][]string{
		noteLines("File", nativePath(file)),
		noteLines("Kept", "Nothing was written."),
		noteLines("Fix", "Edit it by hand."),
	}, nil)
}

// lostRefusal: a line the read dropped comes back where it was when the rest of
// the file does. Only an edit that rewrites the whole file would lose it, and the
// module refuses that save. Said before the plan rather than after the
// confirmation.
func lostRefusal(t accountSetTarget, kept bool) error {
	if lost := t.doc.LostCount(); lost > 0 && !kept {
		return lostLinesRefusal(t.file, lost)
	}
	return nil
}

// accountUnsetPlan resolves what 'account unset' would take out: every line of the key
// in every block of that name, since the loader merges them.
func (a *app) accountUnsetPlan() (t accountSetTarget, done bool, err error) {
	name, err := a.accountNameArg()
	if err != nil {
		return t, false, err
	}
	t.unset, t.disp = true, "account["+name+"]"
	if a.cfg.file == "" {
		// Unreadable is not absent: the key may well be in a file that is there and
		// can't be read, so "nothing to do" would be a guess.
		for _, c := range configCandidates() {
			if state, _, perr := probeConfigCandidate(c); state != candidateAbsent {
				return t, false, unsetUnreadable(c, state, perr)
			}
		}
		a.out.status("No accounts file, so " + t.disp + " has no '" + a.cmd.arg2 + "'; nothing to do.")
		a.out.clean("")
		return t, true, nil
	}
	if err := a.loadForEdit(&t); err != nil {
		return t, false, err
	}
	tidy := t.doc.ToCanonical() == t.read
	var paths, names []string
	blocks, _ := acctBlocks(t.doc)
	for _, b := range blocks {
		if b.name == name {
			paths = append(paths, b.path)
		}
		if !slices.Contains(names, b.name) {
			names = append(names, b.name)
		}
	}
	if len(paths) == 0 {
		has := "it names no accounts"
		if len(names) > 0 {
			has = "it has " + strings.Join(names, ", ")
		}
		a.out.statusNotes("No "+t.disp+" in the accounts file ("+has+"); nothing to do.", noteLines("File", nativePath(t.file)))
		a.out.clean("")
		return t, true, nil
	}
	// A key nothing reads can go too, but only one that is there: a typo on the
	// command line would otherwise come back as "nothing to do".
	t.field = canonAccountField(a.cmd.arg2)
	if t.field == "" {
		for _, p := range paths {
			if t.doc.Count(p+"."+shcl.QuoteSegment(a.cmd.arg2)) > 0 {
				t.field = strings.ToLower(a.cmd.arg2)
			}
		}
	}
	if t.field == "" {
		return t, false, usagef("'%s' isn't an account key %s reads, and %s has no such line. One of: %s.", a.cmd.arg2, meName, t.disp, strings.Join(accountSetFields, ", "))
	}
	for i, p := range paths {
		paths[i] = p + "." + shcl.QuoteSegment(t.field)
		for j := range t.doc.Count(paths[i]) {
			read := t.doc.ReadString(fmt.Sprintf("%s(%d)", paths[i], j))
			line := goneLine{num: read.Line, text: t.field + ":"}
			if read.Raw != nil && *read.Raw != "" {
				line.text += " " + *read.Raw
			}
			t.gone = append(t.gone, line)
		}
	}
	if len(t.gone) == 0 {
		a.out.statusNotes(t.disp+" has no '"+t.field+"' in the accounts file; nothing to do.", noteLines("File", nativePath(t.file)))
		a.out.clean("")
		return t, true, nil
	}
	for _, p := range paths {
		t.doc.Remove(p)
	}
	_, kept := t.doc.ToTextKeepLines()
	if err := lostRefusal(t, kept); err != nil {
		return t, false, err
	}
	if !kept && !tidy && !t.converts {
		t.reshapes = true
	}
	return t, false, nil
}

// unsetUnreadable: nothing was loaded, but something is where an accounts file can
// be.
func unsetUnreadable(file string, state candidateState, cause error) error {
	why := "Something is there that can't be read as a file, and the key may be in it."
	fix := []string{"Run this again once it can be read."}
	switch state {
	case candidateUnreadable:
		why = "Opening it failed with: " + causeText(cause) + ". The key may be in it."
		fix = unreadableFix(runtime.GOOS, file, cause)
	case candidateUsable:
		why = "It turned up after this command looked for it."
		fix = []string{"Run this again. It will edit the file that is there now."}
	}
	return refusalBlock("An accounts file is there, and it can't be read.", [][]string{
		noteLines("File", nativePath(file)),
		noteLines("Why", why),
		noteLines("Kept", "Nothing was written."),
		noteLines("Fix", fix...),
	}, cause)
}

// cmdAccountSet writes one key into one account block and saves it through the module,
// keeping untouched lines where it can. 'account unset' saves through here too.
func (a *app) cmdAccountSet() error {
	if a.set == nil {
		t, err := a.accountSetPlan()
		if err != nil {
			return err
		}
		a.set = &t
	}
	t := *a.set
	if t.creates {
		dir := filepath.Dir(t.file)
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return writeRefusal("Couldn't create the folder the accounts file goes in.", "Creating it", err,
				"Nothing was written.", "Make the folder it goes in writable, then run this again.",
				noteLines("File", nativePath(failedAt(err, dir))))
		}
	}
	// Over a create too: one between its open and its write sees an empty file,
	// which an edit would read and save over.
	unlock, err := lockAccountsFile(t.file, accountLockWait)
	if err != nil {
		return err
	}
	defer unlock()
	if t.creates {
		// 0600 from the first byte: this file names your accounts and points at your
		// token files. Opened so it cannot replace anything, since a file already
		// there - even one this run could not read - has someone's accounts.
		opened, err := createNew(t.file, t.doc.ToCanonical(), 0o600)
		switch {
		case err == nil:
			a.out.statusNotes("Wrote the accounts file.", noteLines("File", nativePath(t.file)))
			return nil
		case opened:
			return refusalBlock("Couldn't finish writing the accounts file, so it may be incomplete.", [][]string{
				noteLines("File", nativePath(t.file)),
				noteLines("Why", "Writing it failed with: "+causeText(err)+"."),
				noteLines("Kept", "The file was made, with whatever went in before the failure."),
				noteLines("Fix", "Check what it holds, then run this again."),
			}, err)
		case errors.Is(err, fs.ErrExist):
			state, fi, perr := probeConfigCandidate(t.file)
			return configRefusal(t.file, state, fi, perr)
		}
		return writeRefusal("Couldn't create the accounts file.", "Creating it", err,
			"Nothing was written.", "Make the folder it is in writable, then run this again.",
			noteLines("File", nativePath(t.file)))
	}
	if now, err := os.ReadFile(t.file); err != nil || string(now) != t.read {
		return changedRefusal(t.file, err)
	}
	if _, err := t.doc.SaveFileKeepLines(t.file); err != nil {
		var refused *shcl.SaveRefused
		if errors.As(err, &refused) {
			return lostLinesRefusal(t.file, refused.Lost)
		}
		// The save writes a new file beside it and renames it over, so a permissions
		// error is the folder's, not the file's.
		return writeRefusal("Couldn't save the accounts file.", "Saving it", err,
			"Nothing was written.", "Make the folder it is in writable, then run this again.",
			noteLines("File", nativePath(t.file)))
	}
	a.out.statusNotes("Wrote the accounts file.", noteLines("File", nativePath(t.file)))
	return nil
}
