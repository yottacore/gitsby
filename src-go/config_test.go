// The config parser and folder matching. Every case here came from something
// that once read as "no rule at all" - the failure mode that makes you act as the
// wrong account while believing you configured it.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestParseConfigValue(t *testing.T) {
	tests := []struct{ in, want string }{
		{"plain", "plain"},
		{"trailing   ", "trailing"},
		{"value # a comment", "value"},
		{"value\t# a comment", "value"},
		{"#whole line", ""},
		{`"kept # hash"`, "kept # hash"},
		{`'kept trailing  '`, "kept trailing  "},
		{"no#comment", "no#comment"}, // a '#' needs whitespace in front to start one
		{"", ""},
	}
	for _, tc := range tests {
		if got := parseConfigValue(tc.in); got != tc.want {
			t.Errorf("parseConfigValue(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestSplitAccountKey(t *testing.T) {
	tests := []struct {
		key         string
		acct, field string
		ok          bool
	}{
		{"account.work.ghaccount", "work", "ghaccount", true},
		{"account.a-b_c.2.sshkey", "a-b_c.2", "sshkey", true},
		{"protocol", "", "", false},
		{"account.work", "", "", false},
		{"account.bad/name.path", "", "", false},
		{"account..path", "", "", false},
	}
	for _, tc := range tests {
		acct, field, ok := splitAccountKey(tc.key)
		if ok != tc.ok || acct != tc.acct || field != tc.field {
			t.Errorf("splitAccountKey(%q) = %q,%q,%v; want %q,%q,%v", tc.key, acct, field, ok, tc.acct, tc.field, tc.ok)
		}
	}
}

func writeConfig(t *testing.T, body string) *config {
	t.Helper()
	file := filepath.Join(t.TempDir(), "config.shcl")
	if err := os.WriteFile(file, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := &config{values: map[string]string{}}
	opt := defaultOptions()
	opt.configFile, opt.configGiven = file, true
	if err := cfg.load(opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	return cfg
}

func TestConfigLoad(t *testing.T) {
	cfg := writeConfig(t, `
# a comment
account.work.ghAccount = octocat
account.work.path = /srv/work
account.work.email = o@example.com
account.play.pathContains = personal/code
account.play.ghAccount = playful
protocol = https
account.work.nonsense = 1
just-a-key
`)
	if got := cfg.value("work", "ghAccount"); got != "octocat" {
		t.Errorf("ghAccount = %q", got)
	}
	// Keys are lowercased on the way in, so the lookup has to be too.
	if got := cfg.value("WORK", "GHACCOUNT"); got != "octocat" {
		t.Errorf("case-insensitive lookup failed: %q", got)
	}
	if cfg.values["protocol"] != "https" {
		t.Errorf("bare protocol = %q", cfg.values["protocol"])
	}
	if want := []string{"work", "play"}; !slices.Equal(cfg.accountNames(), want) {
		t.Errorf("accountNames = %v, want %v", cfg.accountNames(), want)
	}
	// A key nothing reads is reported, never silently dropped.
	if len(cfg.unknown) != 2 {
		t.Errorf("unknown = %v, want the nonsense key and the bare line", cfg.unknown)
	}
}

// git hands core.sshCommand to a shell, so a key path carrying shell characters
// is dropped rather than used - quietly falling back to whatever key ssh picks is
// how you push as the wrong person.
func TestConfigDropsShellCharactersInSSHKey(t *testing.T) {
	cfg := writeConfig(t, "account.work.sshKey = /keys/id; rm -rf /\n")
	if got := cfg.value("work", "sshKey"); got != "" {
		t.Errorf("sshKey = %q, want it dropped", got)
	}
	if len(cfg.unknown) != 1 {
		t.Errorf("the drop was not reported: %v", cfg.unknown)
	}
}

func TestConfigFileMustExistWhenNamed(t *testing.T) {
	opt := defaultOptions()
	opt.configFile, opt.configGiven = filepath.Join(t.TempDir(), "nope.shcl"), true
	if _, err := opt.resolveConfigFile(); err == nil {
		t.Error("a config file that isn't there was accepted")
	}
	// '--config ""' is a mistake, not a fallback: falling back to the default file
	// would act as the wrong identity, quietly.
	opt.configFile = ""
	if _, err := opt.resolveConfigFile(); err == nil {
		t.Error("an empty --config was accepted")
	}
}

func TestAccountForDir(t *testing.T) {
	cfg := writeConfig(t, `
account.outer.path = /srv/code
account.inner.path = /srv/code/client
account.anywhere.pathContains = shared/lib
`)
	tests := []struct{ dir, want string }{
		{"/srv/code", "outer"},
		{"/srv/code/other", "outer"},
		{"/srv/code/client", "inner"}, // the more specific path wins
		{"/srv/code/client/deep", "inner"},
		{"/srv/codex", ""}, // whole folder names only
		{"/elsewhere/shared/lib/x", "anywhere"},
		{"/elsewhere/shared/library", ""}, // ditto, for a segment run
		{"/nothing/here", ""},
	}
	for _, tc := range tests {
		if got := cfg.accountForDir(tc.dir); got != tc.want {
			t.Errorf("accountForDir(%q) = %q, want %q", tc.dir, got, tc.want)
		}
	}
}

// An absolute claim on this machine's own tree beats a folder-name run, even a
// longer one.
func TestAccountForDirPathBeatsSegment(t *testing.T) {
	cfg := writeConfig(t, `
account.byname.pathContains = a/b/c
account.bypath.path = /a/b/c
`)
	if got := cfg.accountForDir("/a/b/c/d"); got != "bypath" {
		t.Errorf("got %q, want bypath", got)
	}
}

func TestCanonPath(t *testing.T) {
	t.Setenv("HOME", "/home/someone")
	tests := []struct{ in, want string }{
		{"", ""},
		{"/a/b/", "/a/b"},
		{"/a/b///", "/a/b"},
		{"/", "/"},
		{`C:\x\y`, "C:/x/y"},
		{"~", "/home/someone"},
		{"~/code", "/home/someone/code"},
		{"~notme/code", "~notme/code"}, // only our own '~' expands
	}
	for _, tc := range tests {
		if got := canonPath(tc.in); got != tc.want {
			t.Errorf("canonPath(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestCanonSegment(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"/a/b/", "a/b"},
		{`a\b`, "a/b"},
		{"", ""},
	} {
		if got := canonSegment(tc.in); got != tc.want {
			t.Errorf("canonSegment(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// '..' has to go before a rule sees it, or a destination reached by climbing out
// of one tree still reads as a folder inside it.
func TestAbsDirResolvesDotDot(t *testing.T) {
	dir := t.TempDir()
	t.Chdir(dir)
	got := absDir("sub/../../elsewhere")
	if want := canonPath(filepath.Dir(dir) + "/elsewhere"); got != want {
		t.Errorf("absDir = %q, want %q", got, want)
	}
}

// '~' resolved through HOME alone, which nothing sets on native Windows - so every
// tilde path there expanded to nothing and quietly matched no folder and read no
// token. One helper answers it now, and leaves anything it cannot resolve as typed.
func TestExpandTilde(t *testing.T) {
	t.Setenv("HOME", "/home/ada")
	tests := []struct{ in, want string }{
		{"~", "/home/ada"},
		{"~/dev/work", "/home/ada/dev/work"},
		{`~\dev\work`, `/home/ada\dev\work`},
		{"~work/dev", "~work/dev"}, // not a home reference; a shell wouldn't expand it either
		{"/dev/~/work", "/dev/~/work"},
		{"", ""},
	}
	for _, tc := range tests {
		if got := expandTilde(tc.in); got != tc.want {
			t.Errorf("expandTilde(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// A rule written through a symlink - a synced folder, a stable name pointing at a
// dated one, a home that is itself a link - matched nothing, because git answers
// with the tree's real path and only the Windows build resolved the other side.
// Nothing said so either: the folder exists, so the "can never match" note in
// 'account list' stayed quiet while runs acted as the wrong account.
func TestAccountForDirThroughSymlink(t *testing.T) {
	root := t.TempDir()
	realDir := filepath.Join(root, "real", "proj")
	if err := os.MkdirAll(realDir, 0o700); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "link")
	if err := os.Symlink(filepath.Join(root, "real"), link); err != nil {
		t.Skipf("no symlinks here: %v", err)
	}
	cfg := writeConfig(t, "account.work.ghAccount = octocat\naccount.work.path = "+filepath.ToSlash(link)+"/proj\n")
	// The rule is spelled through the link; the folder is asked about by its real
	// path, which is the only spelling git ever hands back.
	if got := cfg.accountForDir(filepath.ToSlash(realDir)); got != "work" {
		t.Errorf("accountForDir(real path) = %q, want %q", got, "work")
	}
	// And still by the spelling it was written with.
	if got := cfg.accountForDir(filepath.ToSlash(filepath.Join(link, "proj"))); got != "work" {
		t.Errorf("accountForDir(link path) = %q, want %q", got, "work")
	}
}

// A destination that does not exist yet still has to canonicalize - 'repo clone'
// resolves its account against a folder git has never seen - so resolution stops
// at the nearest ancestor that is really there and puts the rest back on.
func TestCanonPathKeepsMissingTail(t *testing.T) {
	root := t.TempDir()
	if err := os.Symlink(root, filepath.Join(root, "self")); err != nil {
		t.Skipf("no symlinks here: %v", err)
	}
	got := canonPath(filepath.ToSlash(filepath.Join(root, "self", "not", "there", "yet")))
	if want := canonPath(filepath.ToSlash(root)) + "/not/there/yet"; got != want {
		t.Errorf("canonPath = %q, want %q", got, want)
	}
}

// A byte-order mark is what a Windows editor writes by default, and it lands on
// the first key in the file. Read as part of the name, that key became one
// nothing understands - and the line reporting those printed the mark with it,
// so the only diagnostic named a key that looks exactly right.
func TestConfigLoadStripsBOM(t *testing.T) {
	cfg := writeConfig(t, "\ufeff"+"account.work.ghAccount = octocat\naccount.work.email = o@example.com\n")
	if got := cfg.value("work", "ghAccount"); got != "octocat" {
		t.Errorf("first key after a BOM = %q, want %q", got, "octocat")
	}
	if len(cfg.unknown) != 0 {
		t.Errorf("unknown keys = %v, want none", cfg.unknown)
	}
}

// An account is configured when the file names it, whether or not it names a
// GitHub login of its own: a commit identity and an ssh key are a whole way of
// using one. Asked the other way, GITSBY_ACCOUNT read such a name as a bare
// login and applied none of it.
func TestKnowsAccountWithoutGhAccount(t *testing.T) {
	cfg := writeConfig(t, "account.sshonly.email = s@example.com\naccount.byrule.path = /srv/x\n")
	for _, name := range []string{"sshonly", "SshOnly", "byrule"} {
		if !cfg.knowsAccount(name) {
			t.Errorf("knowsAccount(%q) = false, want true", name)
		}
	}
	for _, name := range []string{"", "nobody"} {
		if cfg.knowsAccount(name) {
			t.Errorf("knowsAccount(%q) = true, want false", name)
		}
	}
}

// The accounts file is named wherever the display tells somebody to go and edit
// it, and it almost always lives under home - where its absolute spelling is long
// enough to be the whole line and to push everything else into a wrap.
func TestDisplayPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	cases := map[string]string{
		home:                            "~",
		home + "/.config/gitsby/x.shcl": "~/.config/gitsby/x.shcl",
		"/etc/gitsby/x.shcl":            "/etc/gitsby/x.shcl",
		home + "-not-really/x.shcl":     home + "-not-really/x.shcl",
		"":                              "",
	}
	for in, want := range cases {
		if got := displayPath(in); got != want {
			t.Errorf("displayPath(%q) = %q, want %q", in, got, want)
		}
	}
}

// Folder rules are matched in one canonical spelling - lower case, forward
// slashes - and a listing printed that beside a 'Here' line straight from
// Windows. Same tree, two spellings, on the one screen that exists to say which
// tree a rule claims.
func TestWindowsPath(t *testing.T) {
	cases := map[string]string{
		"c:/opt/dev/github.com/someone": `C:\opt\dev\github.com\someone`,
		`C:\opt\dev`:                    `C:\opt\dev`,
		"~/.config/gitsby/config.shcl":  `~\.config\gitsby\config.shcl`,
		".../github.com/...":            `...\github.com\...`,
		"c:/":                           `C:\`,
		"":                              "",
	}
	for in, want := range cases {
		if got := windowsPath(in); got != want {
			t.Errorf("windowsPath(%q) = %q, want %q", in, got, want)
		}
	}
}
