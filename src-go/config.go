// The accounts config: discovery, the flat .shcl parser, and folder matching.
// Hand parsed on purpose, so nothing has to be installed to read it and no
// library can drift from what the scripted builds accept.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

type acctRule struct {
	match string // canonical folder, or a canonical run of folder names
	acct  string
}

// config is one parsed accounts file. Zero accounts and no file are the ordinary
// single-account case, not an error.
type config struct {
	loaded   bool
	values   map[string]string
	paths    []acctRule // 'path' rules: absolute folder claims
	segments []acctRule // 'pathContains' rules: machine-free folder-name runs
	unknown  []string   // named but not understood - reported, never silent
	order    []string   // accounts in declaration order, for ones with keys but no folder rule
	file     string     // named by the identity block when the file held keys nothing reads
}

func isWindows() bool { return runtime.GOOS == "windows" }

// homeDir is where '~' points. HOME first, so a shell that sets one wins - on
// Windows that is the MSYS spelling, and the drive-letter fold below only knows
// what to do with the path it is handed. Nothing sets HOME on native Windows,
// where every '~' in a config file was expanding to nothing at all.
func homeDir() string {
	if home := os.Getenv("HOME"); home != "" {
		return home
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return home
}

// expandTilde resolves a leading '~' in a path from the config file. Unresolvable
// is left as typed: a path starting with a literal '~' matches nothing and reads
// as the typo it is, where one starting with '/' would name somewhere real.
func expandTilde(p string) string {
	if p != "~" && !strings.HasPrefix(p, "~/") && !strings.HasPrefix(p, `~\`) {
		return p
	}
	home := homeDir()
	if home == "" {
		return p
	}
	return home + p[1:]
}

var (
	msysDriveRE = regexp.MustCompile(`^/([A-Za-z])(/.*)?$`)
	driveRootRE = regexp.MustCompile(`^[A-Za-z]:/$`)
)

// canonPath gives a directory one spelling, so a config written on one machine
// matches the same tree on another, and so a rule and the folder it claims are
// compared on the same terms.
func canonPath(p string) string {
	if p == "" {
		return ""
	}
	p = strings.ReplaceAll(p, "\\", "/")
	p = expandTilde(p)
	if isWindows() {
		// Fold the drive letter BEFORE asking the filesystem: '/c/x' means nothing
		// to a native build, and asking first is the bug the PowerShell port had.
		if m := msysDriveRE.FindStringSubmatch(p); m != nil {
			tail := m[2]
			if tail == "" {
				tail = "/"
			}
			p = m[1] + ":" + tail
		}
	}
	p = resolveLinks(p)
	if isWindows() {
		p = strings.ToLower(p)
	}
	for strings.HasSuffix(p, "/") && p != "/" && !driveRootRE.MatchString(p) {
		p = strings.TrimSuffix(p, "/")
	}
	return p
}

// resolveLinks settles symlink and junction spellings through the nearest
// ancestor that exists, then puts the rest of the path back on - a clone target
// need not exist yet, which is why it can't just resolve the whole thing.
//
// Every platform, not just Windows. 'git rev-parse --show-toplevel' answers with
// the tree's real path, so a rule written the way you type it - through a
// symlinked home, a synced folder, a stable name pointing at a dated one - was
// compared against the resolved spelling and never matched. Nothing said so
// either: the folder is real, so the "this rule can never match" note stayed
// quiet, and a run acted as the wrong account while the listing looked right.
func resolveLinks(p string) string {
	head, tail := p, ""
	for head != "" && strings.Contains(head, "/") {
		if fi, err := os.Stat(head); err == nil && fi.IsDir() {
			break
		}
		if tail == "" {
			tail = head[strings.LastIndex(head, "/")+1:]
		} else {
			tail = head[strings.LastIndex(head, "/")+1:] + "/" + tail
		}
		head = head[:strings.LastIndex(head, "/")]
	}
	if fi, err := os.Stat(head); err != nil || !fi.IsDir() {
		return p
	}
	resolved, err := filepath.EvalSymlinks(head)
	if err != nil || resolved == "" {
		return p
	}
	resolved = strings.ReplaceAll(resolved, "\\", "/")
	if tail == "" {
		return resolved
	}
	return strings.TrimRight(resolved, "/") + "/" + tail
}

// absDir puts a relative path on the current directory, so a folder rule sees the
// same spelling it would for a folder we were standing in. Folded first, because
// '/c/x' is already absolute on Windows and joining it to the cwd would bury it.
func absDir(p string) string {
	if p = canonPath(p); p == "" {
		return ""
	}
	if !filepath.IsAbs(p) {
		wd, err := os.Getwd()
		if err != nil {
			return p
		}
		p = wd + "/" + p
	}
	// '..' has to go before a rule sees it, or a destination reached by climbing out
	// of one tree still reads as a folder inside it.
	return canonPath(filepath.ToSlash(filepath.Clean(p)))
}

// canonSegment folds a 'pathContains' run of folder names the same way canonPath
// folds a path, so the two are compared on the same terms. No filesystem involved:
// the whole point is that this rule names no machine.
func canonSegment(s string) string {
	if s == "" {
		return ""
	}
	s = strings.ReplaceAll(s, "\\", "/")
	s = strings.Trim(s, "/")
	if isWindows() {
		s = strings.ToLower(s)
	}
	return s
}

// configFile picks the file to read: the first candidate that exists, or nothing.
// A file named explicitly must exist - naming one that isn't there is a typo, not
// a fallback - and it is asked whether the option was TYPED, not whether it has a
// value: '--config ""' falling back to the default file would act as the wrong
// identity, quietly. An empty GITSBY_CONFIG is left alone deliberately - an unset
// environment variable and an empty one are the same thing, unlike a typed option.
func (o options) resolveConfigFile() (string, error) {
	if o.configGiven {
		switch {
		case o.configFile == "":
			return "", usageSubf("--config was given an empty file name.")
		case !pathExists(o.configFile):
			return "", usageSubf("No readable config file at '%s'.", o.configFile)
		case !isRegularFile(o.configFile):
			return "", usageSubf("--config names '%s', which isn't a file.", o.configFile)
		case !isReadableFile(o.configFile):
			return "", usageSubf("No readable config file at '%s'.", o.configFile)
		}
		return o.configFile, nil
	}
	if env := os.Getenv("GITSBY_CONFIG"); env != "" {
		switch {
		case !pathExists(env):
			return "", usageSubf("GITSBY_CONFIG names '%s', which can't be read.", env)
		case !isRegularFile(env):
			return "", usageSubf("GITSBY_CONFIG names '%s', which isn't a file.", env)
		case !isReadableFile(env):
			return "", usageSubf("GITSBY_CONFIG names '%s', which can't be read.", env)
		}
		return env, nil
	}
	var candidates []string
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		candidates = append(candidates, d+"/gitsby/config.shcl")
	}
	if d := homeDir(); d != "" {
		candidates = append(candidates, d+"/.config/gitsby/config.shcl")
	}
	if d := os.Getenv("APPDATA"); d != "" {
		candidates = append(candidates, d+"/gitsby/config.shcl")
	}
	for _, c := range candidates {
		// A discovered candidate is skipped rather than refused - unlike one named
		// explicitly, nobody asserted it was there.
		if isRegularFile(c) && isReadableFile(c) {
			return c, nil
		}
	}
	return "", nil
}

func pathExists(p string) bool { _, err := os.Stat(p); return err == nil }

func isDir(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}

// dirEmpty errs toward "empty": an unreadable directory lists nothing, same as
// the scripts' 'ls -A', and whatever comes next fails on its own terms.
func dirEmpty(p string) bool {
	entries, err := os.ReadDir(p)
	return err != nil || len(entries) == 0
}

func isRegularFile(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.Mode().IsRegular()
}

func isReadableFile(p string) bool {
	f, err := os.Open(p)
	if err != nil {
		return false
	}
	_ = f.Close()
	return true
}

var acctNameOK = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// Characters a shell would act on rather than pass through as part of a path.
// '~' is deliberately absent: the shell expands it, and '~/.ssh/id_ed25519' is
// how everyone writes a key path.
const sshKeyShellChars = " \t\n\r\"'\\$;&|<>()*?![]{}" + "`"

// load reads the config once. Flat 'key = value' lines, '#' comments, blank lines
// ignored. A file that cannot be read at all is the same as no file: the caller
// asserted nothing about it, and every account path degrades to gh's own.
func (c *config) load(o options) error {
	if c.loaded {
		return nil
	}
	c.loaded = true
	file, err := o.resolveConfigFile()
	if err != nil {
		return err
	}
	if file == "" {
		return nil
	}
	c.file = file
	data, err := os.ReadFile(file)
	if err != nil {
		return nil
	}
	// The byte-order mark a Windows editor writes by default, off the front of the
	// first line. Left on, it landed on the first key in the file, which then read
	// as one nothing understands - and the line that reports those printed the mark
	// as part of the name, so the one diagnostic meant to explain the loss named a
	// key that looks perfectly valid.
	text := strings.TrimPrefix(string(data), "\ufeff")
	for _, line := range splitLines(text) { // a file written on Windows, read on Linux
		line = strings.TrimLeft(line, " \t")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, rawValue, found := strings.Cut(line, "=")
		if !found {
			c.unknown = append(c.unknown, line)
			continue
		}
		key = strings.ToLower(strings.TrimRight(key, " \t"))
		value := parseConfigValue(strings.TrimLeft(rawValue, " \t"))
		if key == "" {
			continue
		}
		// An account name becomes a file name under the include directory, so hold
		// it to characters that cannot climb out of there. A stray slash is an
		// ordinary typo, and 'account apply' wrote the fragment wherever it pointed.
		acct, field, ok := splitAccountKey(key)
		if !ok {
			if key == "protocol" {
				c.values[key] = value
				continue
			}
			c.unknown = append(c.unknown, key)
			continue
		}
		switch field {
		case "path":
			if value != "" {
				c.paths = append(c.paths, acctRule{canonPath(value), acct})
			}
		case "pathcontains":
			if value != "" {
				c.segments = append(c.segments, acctRule{canonSegment(value), acct})
			}
		case "ghaccount", "tokenfile", "sshkey", "name", "email", "protocol":
			// git hands GIT_SSH_COMMAND and core.sshCommand to a shell, so a key
			// path carrying whitespace or a shell character is re-parsed there
			// rather than used - and this file is redirectable by flag and by
			// environment variable. Drop it and say so: quietly falling back to
			// whatever key ssh picks is how you push as the wrong person.
			if field == "sshkey" && strings.ContainsAny(value, sshKeyShellChars) {
				c.unknown = append(c.unknown, key+" (shell characters in the path)")
				value = ""
			}
			c.values[key] = value
			if !contains(c.order, acct) {
				c.order = append(c.order, acct)
			}
		default:
			// Named but not understood. Not fatal - a config from a newer gitsby
			// still has to work - but never silent either: a mistyped key nothing
			// reads is how you act as the wrong account believing you configured it.
			c.unknown = append(c.unknown, key)
		}
	}
	return nil
}

func contains(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}

// splitAccountKey takes 'account.<name>.<field>' apart, validating the name.
// Anything malformed comes back not-ok, and the caller lists the key as unknown.
func splitAccountKey(key string) (acct, field string, ok bool) {
	rest, found := strings.CutPrefix(key, "account.")
	if !found {
		return "", "", false
	}
	dot := strings.LastIndex(rest, ".")
	if dot < 0 {
		return "", "", false
	}
	acct, field = rest[:dot], rest[dot+1:]
	if !acctNameOK.MatchString(acct) {
		return "", "", false
	}
	return acct, field, true
}

// parseConfigValue trims a value: one optional layer of quotes keeps a literal '#'
// or meaningful trailing space; otherwise a '#' after whitespace starts a comment,
// here as well as at the start of a line. Folding one into the value made a folder
// rule that could never match, which reads exactly like no rule at all.
func parseConfigValue(value string) string {
	if len(value) >= 2 && (value[0] == '"' || value[0] == '\'') {
		if end := strings.IndexByte(value[1:], value[0]); end >= 0 {
			return value[1 : 1+end]
		}
	}
	for i := 0; i+1 < len(value); i++ {
		if (value[i] == ' ' || value[i] == '\t') && value[i+1] == '#' {
			value = value[:i]
			break
		}
	}
	if strings.HasPrefix(value, "#") {
		return ""
	}
	return strings.TrimRight(value, " \t")
}

// accountForDir names the configured account whose folder contains this one.
// An absolute 'path' rule wins over a 'pathContains' when both match: naming the
// machine's own tree is the more specific claim. Within each kind the more
// specific rule wins - the longest path, or the most folder names - so a tree
// nested inside another account's tree belongs to the inner one. First defined
// breaks an exact tie.
func (c *config) accountForDir(dir string) string {
	target := canonPath(dir)
	if target == "" {
		return ""
	}
	best, bestLen := "", 0
	for _, r := range c.paths {
		if r.match == "" {
			continue
		}
		if target != r.match && !strings.HasPrefix(target, r.match+"/") {
			continue
		}
		if len(r.match) > bestLen {
			best, bestLen = r.acct, len(r.match)
		}
	}
	if best != "" {
		return best
	}
	// Whole folder names only, which is what the slashes on both sides buy:
	// 'jim-collier' must not match a directory called 'jim-collier-old'. Wrapping
	// the target in slashes lets the run match at either end as well as the middle.
	bestSegs := 0
	for _, r := range c.segments {
		if r.match == "" {
			continue
		}
		if !strings.Contains("/"+target+"/", "/"+r.match+"/") {
			continue
		}
		segs := strings.Count(r.match, "/") + 1
		if segs > bestSegs {
			best, bestSegs = r.acct, segs
		}
	}
	return best
}

// knowsAccount: whether the file defines this account at all, by any key or any
// folder rule. Deliberately not the same question as whether it names a GitHub
// login - an account can be a commit identity and an ssh key and nothing else,
// which is how you hold a second identity with no gh involved, and what the
// folder rules have always applied.
func (c *config) knowsAccount(name string) bool {
	return name != "" && contains(c.accountNames(), strings.ToLower(name))
}

// value reads one key of one configured account. Both halves lowercased, because
// the loader lowercases the whole key on the way in - leaving the name as typed
// made 'GITSBY_ACCOUNT=Work' miss an account stored as 'work', silently.
func (c *config) value(name, key string) string {
	if name == "" || key == "" {
		return ""
	}
	return c.values["account."+strings.ToLower(name)+"."+strings.ToLower(key)]
}

// contextDir is what "here" means for folder matching: the repo's top level when
// in one, so every subdirectory resolves to the same account, and the working
// directory when not - which is what a fresh 'repo clone' has to go on.
func (a *app) contextDir() string {
	return a.git.contextDir.get(func() string {
		if top := runOut("git", "rev-parse", "--show-toplevel"); top != "" {
			return top
		}
		wd, _ := os.Getwd()
		return wd
	})
}
