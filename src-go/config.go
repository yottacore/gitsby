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

var (
	configLoaded = false
	cfg          = map[string]string{}
	cfgPaths     []acctRule // 'path' rules: absolute folder claims
	cfgSegments  []acctRule // 'pathContains' rules: machine-free folder-name runs
	cfgUnknown   []string   // named but not understood - reported, never silent
)

// Named by the identity block when the file held keys nothing reads.
var configFileUsed = ""

func isWindows() bool { return runtime.GOOS == "windows" }

var (
	msysDriveRE = regexp.MustCompile(`^/([A-Za-z])(/.*)?$`)
	driveRootRE = regexp.MustCompile(`^[A-Za-z]:/$`)
)

// canonPath gives a directory one spelling, so a config written on one machine
// matches the same tree on another. Text only - the folder does not have to exist,
// which 'repo clone' needs, and a resolver that touched the disk would answer
// differently for a path that isn't there yet.
func canonPath(p string) string {
	if p == "" {
		return ""
	}
	p = strings.ReplaceAll(p, "\\", "/")
	if p == "~" || strings.HasPrefix(p, "~/") {
		p = os.Getenv("HOME") + p[1:]
	}
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
		// Settle junctions and link spellings through the nearest ancestor that
		// exists, then put the rest back on (a clone target may not exist yet).
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
		if fi, err := os.Stat(head); err == nil && fi.IsDir() {
			if resolved, err := filepath.EvalSymlinks(head); err == nil && resolved != "" {
				p = strings.ReplaceAll(resolved, "\\", "/")
				if tail != "" {
					p = strings.TrimRight(p, "/") + "/" + tail
				}
			}
		}
		p = strings.ToLower(p)
	}
	for strings.HasSuffix(p, "/") && p != "/" && !driveRootRE.MatchString(p) {
		p = strings.TrimSuffix(p, "/")
	}
	return p
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
func configFile() string {
	if configFileGiven {
		switch {
		case configFileArg == "":
			throwUsage("--config was given an empty file name.")
		case !pathExists(configFileArg):
			throwUsage("No readable config file at '" + configFileArg + "'.")
		case !isRegularFile(configFileArg):
			throwUsage("--config names '" + configFileArg + "', which isn't a file.")
		case !isReadableFile(configFileArg):
			throwUsage("No readable config file at '" + configFileArg + "'.")
		}
		return configFileArg
	}
	if env := os.Getenv("GITSBY_CONFIG"); env != "" {
		switch {
		case !pathExists(env):
			throwUsage("GITSBY_CONFIG names '" + env + "', which can't be read.")
		case !isRegularFile(env):
			throwUsage("GITSBY_CONFIG names '" + env + "', which isn't a file.")
		case !isReadableFile(env):
			throwUsage("GITSBY_CONFIG names '" + env + "', which can't be read.")
		}
		return env
	}
	var candidates []string
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		candidates = append(candidates, d+"/gitsby/config.shcl")
	}
	if d := os.Getenv("HOME"); d != "" {
		candidates = append(candidates, d+"/.config/gitsby/config.shcl")
	}
	if d := os.Getenv("APPDATA"); d != "" {
		candidates = append(candidates, d+"/gitsby/config.shcl")
	}
	for _, c := range candidates {
		// A discovered candidate is skipped rather than refused - unlike one named
		// explicitly, nobody asserted it was there.
		if isRegularFile(c) && isReadableFile(c) {
			return c
		}
	}
	return ""
}

func pathExists(p string) bool { _, err := os.Stat(p); return err == nil }

func isRegularFile(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.Mode().IsRegular()
}

func isReadableFile(p string) bool {
	f, err := os.Open(p)
	if err != nil {
		return false
	}
	f.Close()
	return true
}

var acctNameOK = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// loadConfig reads the config once. Flat 'key = value' lines, '#' comments,
// blank lines ignored.
func loadConfig() {
	if configLoaded {
		return
	}
	configLoaded = true
	file := configFile()
	if file == "" {
		return
	}
	configFileUsed = file
	data, err := os.ReadFile(file)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSuffix(line, "\r") // written on Windows, read on Linux
		line = strings.TrimLeft(line, " \t")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.Index(line, "=")
		if eq < 0 {
			cfgUnknown = append(cfgUnknown, line)
			continue
		}
		key := strings.ToLower(strings.TrimRight(line[:eq], " \t"))
		value := parseConfigValue(strings.TrimLeft(line[eq+1:], " \t"))
		if key == "" {
			continue
		}
		// An account name becomes a file name under the include directory, so hold
		// it to characters that cannot climb out of there. A stray slash is an
		// ordinary typo, and 'account apply' wrote the fragment wherever it pointed.
		if acct, rest, ok := splitAccountKey(key); ok {
			switch rest {
			case "path":
				if value != "" {
					cfgPaths = append(cfgPaths, acctRule{canonPath(value), acct})
				}
			case "pathcontains":
				if value != "" {
					cfgSegments = append(cfgSegments, acctRule{canonSegment(value), acct})
				}
			case "ghaccount", "tokenfile", "sshkey", "name", "email", "protocol":
				cfg[key] = value
			default:
				// Named but not understood. Not fatal - a config from a newer gitsby
				// still has to work - but never silent either: a mistyped key nothing
				// reads is how you act as the wrong account believing you configured it.
				cfgUnknown = append(cfgUnknown, key)
			}
			continue
		}
		if key == "protocol" {
			cfg[key] = value
			continue
		}
		cfgUnknown = append(cfgUnknown, key)
	}
}

// splitAccountKey takes 'account.<name>.<field>' apart, validating the name. A key
// under 'account.' with a bad or missing name reports as unknown via ok=true with
// an empty field, so the caller's default arm flags it.
func splitAccountKey(key string) (acct, field string, ok bool) {
	if !strings.HasPrefix(key, "account.") {
		return "", "", false
	}
	rest := key[len("account."):]
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
func accountForDir(dir string) string {
	target := canonPath(dir)
	if target == "" {
		return ""
	}
	best, bestLen := "", 0
	for _, r := range cfgPaths {
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
	for _, r := range cfgSegments {
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

// accountValue reads one key of one configured account. Both halves lowercased,
// because the loader lowercases the whole key on the way in - leaving the name as
// typed made 'GITSBY_ACCOUNT=Work' miss an account stored as 'work', silently.
func accountValue(name, key string) string {
	if name == "" || key == "" {
		return ""
	}
	return cfg["account."+strings.ToLower(name)+"."+strings.ToLower(key)]
}

// contextDir is what "here" means for folder matching: the repo's top level when
// in one, so every subdirectory resolves to the same account, and the working
// directory when not - which is what a fresh 'repo clone' has to go on.
func contextDir() string {
	if top := runOut("git", "rev-parse", "--show-toplevel"); top != "" {
		return top
	}
	wd, _ := os.Getwd()
	return wd
}
