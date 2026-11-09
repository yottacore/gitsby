// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	shcl "github.com/yottacore/shcl/source/go/v3"
)

// The footer shcl 2.x wrote, as it sits in files gitsby made before 3.0.
const shcl2Footer = "#\n" +
	"# This config file format is SHCL.\n" +
	"# \"Simple Hierarchical Config Language\"\n" +
	"#    Home     https://github.com/jim-collier/shcl\n" +
	"#    Syntax   https://github.com/jim-collier/shcl/blob/main/project/spec.md\n" +
	"#    Legal    SHCL is Copyright © 2026 Jim Collier. License: MIT. No warranty.\n" +
	"#\n"

// A bare '\\' was one backslash under 2.x and is two now.
const shcl2Body = "# mine\naccount: w\n\tname: Ada\n\temail: C:\\\\new\n\n" + shcl2Footer

func TestOldFormat(t *testing.T) { // [ddezz]
	cases := map[string]int{
		shcl2Body:                           2,
		"account: w\n\tname: Ada\n":         0,
		"account: w\n" + shcl.GenBanner:     0,
		"account: w\n" + shcl.FormatLine:    0,
		"account: w\n##    Format   2\n":    2,
		"account: w\n## " + shcl2Banner[2:]: 0,
		shcl2Body + shcl.FormatLine + "\n":  0,
	}
	for text, want := range cases {
		if got := oldFormat(text); got != want {
			t.Errorf("oldFormat(%q) = %d, want %d", text, got, want)
		}
	}
}

func dirEntries(t *testing.T, dir string) []string {
	t.Helper()
	list, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range list {
		names = append(names, e.Name())
	}
	return names
}

// A 2.x file is kept under a dated name and replaced by one the module converted,
// with the current banner. The values are the ones 2.x read, and the next run
// leaves it alone.
func TestOldFormatFileIsConverted(t *testing.T) { // [ddf00]
	dir := t.TempDir()
	file := filepath.Join(dir, "config.shcl")
	if err := os.WriteFile(file, []byte(shcl2Body), 0o600); err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	p := newPrinter()
	p.out, p.err = &bytes.Buffer{}, &stderr
	a := newApp(p)
	a.opt.configFile, a.opt.configGiven, a.opt.quiet = file, true, true
	if err := a.resolveAccount(dir, ""); err != nil {
		t.Fatal(err)
	}
	wantValue(t, a.cfg, "w", "email", `C:\new`)
	wantValue(t, a.cfg, "w", "name", "Ada")
	names := dirEntries(t, dir)
	if len(names) != 2 {
		t.Fatalf("want the file and one backup, got %v", names)
	}
	backup := filepath.Join(dir, names[0])
	if names[0] == "config.shcl" {
		backup = filepath.Join(dir, names[1])
	}
	stamp := time.Now().Format("20060102")
	if !strings.HasPrefix(filepath.Base(backup), "config_backup_"+stamp+"-") || !strings.HasSuffix(backup, "_format-v2.shcl") {
		t.Errorf("backup name %q", filepath.Base(backup))
	}
	if got := readBack(t, backup); got != shcl2Body {
		t.Errorf("backup holds %q", got)
	}
	if fi, err := os.Stat(backup); err != nil || (runtime.GOOS != "windows" && fi.Mode().Perm() != 0o600) {
		t.Errorf("backup mode: %v %v", fi.Mode(), err)
	}
	got := readBack(t, file)
	if v, ok := shcl.FormatVersion(got); !ok || v != shcl.FormatMajor {
		t.Errorf("converted file names format %d %v:\n%s", v, ok, got)
	}
	if strings.Contains(got, "\n"+shcl2Banner+"\n") || !strings.Contains(got, shcl.GenBanner) || !strings.HasPrefix(got, "# mine\n") {
		t.Errorf("converted file:\n%s", got)
	}
	msg := stderr.String()
	if !strings.Contains(msg, "SHCL 2.x") || !strings.Contains(msg, nativePath(backup)) || !strings.Contains(msg, "1 line(s) were re-spelled") {
		t.Errorf("notice: %q", msg)
	}
	// What a 3.0 reader makes of the new file is what 2.x made of the old one.
	again := writeConfig(t, got)
	wantValue(t, again, "w", "email", `C:\new`)
	if again.migration != nil {
		t.Errorf("a converted file was converted again: %+v", again.migration)
	}
	second := &config{values: map[string]string{}}
	opt := defaultOptions()
	opt.configFile, opt.configGiven = file, true
	if err := second.load(opt); err != nil {
		t.Fatal(err)
	}
	if second.migration != nil || len(dirEntries(t, dir)) != 2 {
		t.Errorf("second run: %+v, %v", second.migration, dirEntries(t, dir))
	}
}

// A file typed by hand names no format and is read as the current one, untouched.
func TestUnmarkedFileIsLeftAlone(t *testing.T) { // [ddf01]
	body := "account: w\n\temail: C:\\\\new\n"
	cfg := writeConfig(t, body)
	wantValue(t, cfg, "w", "email", `C:\\new`)
	if cfg.migration != nil {
		t.Errorf("migration: %+v", cfg.migration)
	}
	if names := dirEntries(t, filepath.Dir(cfg.file)); len(names) != 1 || readBack(t, cfg.file) != body {
		t.Errorf("file touched: %v", names)
	}
}

// Where the new file can't be written, nothing is: no backup, the file as it was,
// the values still read the 2.x way, and an edit refuses rather than mixing the
// two formats in one file.
func TestOldFormatUnwritable(t *testing.T) { // [ddf02]
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("needs a folder this user can't write")
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "config.shcl")
	if err := os.WriteFile(file, []byte(shcl2Body), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o700) })
	var stderr bytes.Buffer
	p := newPrinter()
	p.out, p.err = &bytes.Buffer{}, &stderr
	a := newApp(p)
	a.opt.configFile, a.opt.configGiven, a.opt.quiet = file, true, true
	if err := a.resolveAccount(dir, ""); err != nil {
		t.Fatal(err)
	}
	wantValue(t, a.cfg, "w", "email", `C:\new`)
	if names := dirEntries(t, dir); len(names) != 1 || readBack(t, file) != shcl2Body {
		t.Errorf("left behind: %v", names)
	}
	if !strings.Contains(stderr.String(), "couldn't be converted") {
		t.Errorf("notice: %q", stderr.String())
	}
	a.cmd = command{name: "account-set", arg: "w", arg2: "name", arg3: "Bob", mutating: true}
	if err := a.cmdAccountSet(); err == nil || !strings.Contains(err.Error(), "still in the SHCL 2.x format") {
		t.Errorf("set: %v", err)
	}
	if readBack(t, file) != shcl2Body {
		t.Error("set wrote the file")
	}
}

// A linked config is converted where it lives, and the link stays a link.
func TestOldFormatThroughALink(t *testing.T) { // [ddf03]
	if runtime.GOOS == "windows" {
		t.Skip("links need privileges there")
	}
	targetDir, linkDir := t.TempDir(), t.TempDir()
	target := filepath.Join(targetDir, "accounts.shcl")
	if err := os.WriteFile(target, []byte(shcl2Body), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(linkDir, "config.shcl")
	if err := madeSymlink(target, link); err != nil {
		t.Fatal(err)
	}
	cfg := &config{values: map[string]string{}}
	opt := defaultOptions()
	opt.configFile, opt.configGiven = link, true
	if err := cfg.load(opt); err != nil {
		t.Fatal(err)
	}
	if fi, err := os.Lstat(link); err != nil || fi.Mode()&os.ModeSymlink == 0 {
		t.Errorf("link replaced: %v", err)
	}
	if names := dirEntries(t, linkDir); len(names) != 1 {
		t.Errorf("backup beside the link: %v", names)
	}
	names := dirEntries(t, targetDir)
	if len(names) != 2 || !strings.HasPrefix(names[1], "accounts_backup_") {
		t.Errorf("want accounts_backup_* beside the target: %v", names)
	}
	if v, ok := shcl.FormatVersion(readBack(t, target)); !ok || v != shcl.FormatMajor {
		t.Errorf("target not converted")
	}
}

// A config folder reached through a link is named the way it was given, on the
// File and From lines alike. macOS keeps t.TempDir() under /var, a link to /private/var.
func TestOldFormatThroughAFolderLink(t *testing.T) { // [df0ex]
	if runtime.GOOS == "windows" {
		t.Skip("links need privileges there")
	}
	realDir, linkParent := t.TempDir(), t.TempDir()
	linkDir := filepath.Join(linkParent, "cfg")
	if err := madeSymlink(realDir, linkDir); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(linkDir, "config.shcl")
	if err := os.WriteFile(file, []byte(shcl2Body), 0o600); err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	p := newPrinter()
	p.out, p.err = &bytes.Buffer{}, &stderr
	a := newApp(p)
	a.opt.configFile, a.opt.configGiven = file, true
	if err := a.resolveAccount(t.TempDir(), ""); err != nil {
		t.Fatal(err)
	}
	a.reportMigration()
	if a.cfg.migration == nil || a.cfg.migration.backup == "" {
		t.Fatalf("not converted: %+v", a.cfg.migration)
	}
	if got := filepath.Dir(a.cfg.migration.backup); got != linkDir {
		t.Errorf("backup in %q, want the folder as given, %q", got, linkDir)
	}
	if want := "From: " + nativePath(a.cfg.migration.backup); !strings.Contains(stderr.String(), want) || strings.Contains(stderr.String(), realDir) {
		t.Errorf("notice %q", stderr.String())
	}
}

// Another run converted the file between this one's read and its lock. It keeps
// what that run wrote, makes no second backup, and says nothing more.
func TestOldFormatConvertedByAnotherRun(t *testing.T) { // [ddf04]
	dir := t.TempDir()
	file := filepath.Join(dir, "config.shcl")
	converted, _ := migrateText(shcl2Body)
	if err := os.WriteFile(file, []byte(converted), 0o600); err != nil {
		t.Fatal(err)
	}
	mig := &formatMigration{from: 2}
	replaceOldFormat(file, shcl2Body, converted, mig)
	if !mig.done || !mig.reported || mig.backup != "" {
		t.Errorf("%+v", mig)
	}
	if names := dirEntries(t, dir); len(names) != 1 {
		t.Errorf("left behind: %v", names)
	}
	// Changed to something else: left as it is, and an edit will refuse.
	if err := os.WriteFile(file, []byte("account: x\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	mig = &formatMigration{from: 2}
	replaceOldFormat(file, shcl2Body, converted, mig)
	if mig.done || readBack(t, file) != "account: x\n" {
		t.Errorf("%+v", mig)
	}
}

// What v2.1.0 read: flat lines, a comment, quotes and a trailing comment.
const flatBody = "# mine\r\naccount.w.name = \"O'Brien # x\"\r\naccount.w.email = 'C:\\new'  # work\r\nprotocol = ssh\r\n"

// A whole v2.1.0 file is kept under a dated name and replaced by the same values
// in SHCL, with a notice naming both files. The next run leaves it alone.
func TestFlatFileIsConverted(t *testing.T) { // [df065]
	dir := t.TempDir()
	file := filepath.Join(dir, "config.shcl")
	if err := os.WriteFile(file, []byte(utf8BOM+flatBody), 0o600); err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	p := newPrinter()
	p.out, p.err = &bytes.Buffer{}, &stderr
	a := newApp(p)
	a.opt.configFile, a.opt.configGiven, a.opt.quiet = file, true, true
	if err := a.resolveAccount(dir, ""); err != nil {
		t.Fatal(err)
	}
	wantValue(t, a.cfg, "w", "name", "O'Brien # x")
	wantValue(t, a.cfg, "w", "email", `C:\new`)
	if a.cfg.values["protocol"] != "ssh" || a.cfg.flat {
		t.Errorf("protocol %q, flat %v", a.cfg.values["protocol"], a.cfg.flat)
	}
	names := dirEntries(t, dir)
	if len(names) != 2 {
		t.Fatalf("want the file and one backup, got %v", names)
	}
	backup := filepath.Join(dir, names[0])
	if names[0] == "config.shcl" {
		backup = filepath.Join(dir, names[1])
	}
	if !strings.HasPrefix(filepath.Base(backup), "config_backup_"+time.Now().Format("20060102")+"-") || !strings.HasSuffix(backup, "_format-flat.shcl") {
		t.Errorf("backup name %q", filepath.Base(backup))
	}
	if got := readBack(t, backup); got != utf8BOM+flatBody {
		t.Errorf("backup holds %q", got)
	}
	got := readBack(t, file)
	if v, ok := shcl.FormatVersion(got); !ok || v != shcl.FormatMajor || !strings.HasPrefix(got, "# mine\n") {
		t.Errorf("converted file:\n%s", got)
	}
	msg := stderr.String()
	for _, want := range []string{"flat 'key = value' layout of v2.1.0", "File: " + nativePath(file), "From: " + nativePath(backup)} {
		if !strings.Contains(msg, want) {
			t.Errorf("notice is missing %q: %q", want, msg)
		}
	}
	again := writeConfig(t, got)
	wantValue(t, again, "w", "name", "O'Brien # x")
	wantValue(t, again, "w", "email", `C:\new`)
	if again.migration != nil || again.flat {
		t.Errorf("a converted file was converted again: %+v", again.migration)
	}
}

// A line v2.1.0 couldn't read, or a key it refused, keeps the file as it is. The
// flat reader lists that line, as it always has.
func TestPartlyFlatFileIsLeftAlone(t *testing.T) { // [df066]
	for _, body := range []string{
		"account.w.email = a@x\nnot a setting\n",
		"account.w.email = a@x\naccount.../x.path = /srv\n",
		"account.w.email = a@x\n= x\n",
	} {
		cfg := writeConfig(t, body)
		wantValue(t, cfg, "w", "email", "a@x")
		if !cfg.flat || cfg.migration != nil {
			t.Errorf("%q: flat %v, migration %+v", body, cfg.flat, cfg.migration)
		}
		if names := dirEntries(t, filepath.Dir(cfg.file)); len(names) != 1 || readBack(t, cfg.file) != body {
			t.Errorf("%q: file touched: %v", body, names)
		}
	}
}

// Where the new file can't be written, the flat file is read as v2.1.0 read it,
// and an edit refuses rather than writing past the conversion.
func TestFlatFileUnwritable(t *testing.T) { // [df067]
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("needs a folder this user can't write")
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "config.shcl")
	if err := os.WriteFile(file, []byte(flatBody), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o700) })
	var stderr bytes.Buffer
	p := newPrinter()
	p.out, p.err = &bytes.Buffer{}, &stderr
	a := newApp(p)
	a.opt.configFile, a.opt.configGiven, a.opt.quiet = file, true, true
	if err := a.resolveAccount(dir, ""); err != nil {
		t.Fatal(err)
	}
	wantValue(t, a.cfg, "w", "email", `C:\new`)
	if names := dirEntries(t, dir); len(names) != 1 || readBack(t, file) != flatBody {
		t.Errorf("left behind: %v", names)
	}
	if !strings.Contains(stderr.String(), "flat 'key = value' layout of v2.1.0 and couldn't be converted") {
		t.Errorf("notice: %q", stderr.String())
	}
	a.cmd = command{name: "account-set", arg: "w", arg2: "name", arg3: "Bob", mutating: true}
	if err := a.cmdAccountSet(); err == nil || !strings.Contains(err.Error(), "still in the flat 'key = value' layout") {
		t.Errorf("set: %v", err)
	}
	if readBack(t, file) != flatBody {
		t.Error("set wrote the file")
	}
}

// What the earlier Format 3 module wrote for O'Brien \ x, a tab, and a file name
// with no escape in it. Same text whichever module reads it.
const oldPinBody = "account: work\n\tname: \"O'Brien \\\\ x\"  # me\n\tghaccount: \"a\\tb'c\"\n\temail: 'C:\\new'\n" + shcl.GenBanner

func writeOldPin(t *testing.T, body string, old bool) (dir, file string) {
	t.Helper()
	dir = t.TempDir()
	file = filepath.Join(dir, "config.shcl")
	if err := os.WriteFile(file, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	if old {
		was := oldPinCutover.Add(-time.Hour)
		if err := os.Chtimes(file, was, was); err != nil {
			t.Fatal(err)
		}
	}
	return dir, file
}

// A Format 3 file last written before the move to v3.0.0-beta1 came from the
// earlier module, so its double-quoted escapes are re-spelled, the file as it was
// is kept beside it, and the run says so. The next run leaves it alone.
func TestOldPinFileIsConverted(t *testing.T) { // [df08m]
	dir, file := writeOldPin(t, oldPinBody, true)
	var stderr bytes.Buffer
	p := newPrinter()
	p.out, p.err = &bytes.Buffer{}, &stderr
	a := newApp(p)
	a.opt.configFile, a.opt.configGiven, a.opt.quiet = file, true, true
	if err := a.resolveAccount(dir, ""); err != nil {
		t.Fatal(err)
	}
	wantValue(t, a.cfg, "work", "name", `O'Brien \ x`)
	wantValue(t, a.cfg, "work", "ghaccount", "a\tb'c")
	wantValue(t, a.cfg, "work", "email", `C:\new`)
	names := dirEntries(t, dir)
	if len(names) != 2 {
		t.Fatalf("want the file and one backup, got %v", names)
	}
	backup := filepath.Join(dir, names[0])
	if names[0] == "config.shcl" {
		backup = filepath.Join(dir, names[1])
	}
	if !strings.HasPrefix(filepath.Base(backup), "config_backup_"+time.Now().Format("20060102")+"-") || !strings.HasSuffix(backup, "_format-v3old.shcl") {
		t.Errorf("backup name %q", filepath.Base(backup))
	}
	if got := readBack(t, backup); got != oldPinBody {
		t.Errorf("backup holds %q", got)
	}
	got := readBack(t, file)
	if !strings.Contains(got, "\tname: \"O'Brien \\ x\"  # me\n") || !strings.Contains(got, "\tghaccount: \"a◉TAB◉b'c\"\n") || !strings.Contains(got, "\temail: 'C:\\new'\n") {
		t.Errorf("converted file:\n%s", got)
	}
	msg := stderr.String()
	for _, want := range []string{"from the earlier SHCL 3 spelling, which read a backslash in double quotes as an escape.", "2 line(s) were re-spelled", "File: " + nativePath(file), "From: " + nativePath(backup)} {
		if !strings.Contains(msg, want) {
			t.Errorf("notice is missing %q: %q", want, msg)
		}
	}
	again := writeConfig(t, got)
	wantValue(t, again, "work", "name", `O'Brien \ x`)
	if again.migration != nil {
		t.Errorf("a converted file was converted again: %+v", again.migration)
	}
}

// The same text written since the move was written by v3, where a backslash is
// text, so it is read as it is. The file's time is the only way to tell the two
// apart: both stamp Format 3.
func TestNewFileEscapesAreText(t *testing.T) { // [df08n]
	dir, file := writeOldPin(t, oldPinBody, false)
	cfg := &config{values: map[string]string{}}
	opt := defaultOptions()
	opt.configFile, opt.configGiven = file, true
	if err := cfg.load(opt); err != nil {
		t.Fatal(err)
	}
	wantValue(t, cfg, "work", "name", `O'Brien \\ x`)
	if cfg.migration != nil || len(dirEntries(t, dir)) != 1 || readBack(t, file) != oldPinBody {
		t.Errorf("a v3 file was converted: %+v", cfg.migration)
	}
}

// An old file with nothing to re-spell is left as it is, time and all, with no
// backup and no notice.
func TestOldPinFileWithoutEscapesIsLeftAlone(t *testing.T) { // [df08p]
	body := "account: work\n\tname: \"O'Brien x\"\n\temail: 'C:\\new'\n" + shcl.GenBanner
	dir, file := writeOldPin(t, body, true)
	before, err := os.Stat(file)
	if err != nil {
		t.Fatal(err)
	}
	cfg := &config{values: map[string]string{}}
	opt := defaultOptions()
	opt.configFile, opt.configGiven = file, true
	if err := cfg.load(opt); err != nil {
		t.Fatal(err)
	}
	wantValue(t, cfg, "work", "email", `C:\new`)
	after, err := os.Stat(file)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.migration != nil || len(dirEntries(t, dir)) != 1 || !after.ModTime().Equal(before.ModTime()) {
		t.Errorf("an old file with no escapes was touched: %+v, %v", cfg.migration, dirEntries(t, dir))
	}
}

// The earlier module's escapes, and the lines it couldn't have read, which stay.
func TestOldPinRespelling(t *testing.T) { // [df08q]
	for _, tc := range []struct {
		line, want string
		changed    int
	}{
		{`k: "a\\b"`, `k: a\b`, 1}, // bare where nothing needs a quote
		{`k: "a\"b"`, `k: 'a"b'`, 1},
		{`k: "a\'b"`, `k: "a'b"`, 1},
		{`k: "a\nb" # c`, `k: "a◉NEWLINE◉b" # c`, 1},
		{`k: "\u00e9\U0001F600"`, `k: é😀`, 1},
		{"\tk:\t\"a\\tb\"", "\tk:\t\"a◉TAB◉b\"", 1},
		{`k: "a\qb"`, `k: "a\qb"`, 0},                 // not an escape that module read
		{`k: "a\U00110000b"`, `k: "a\U00110000b"`, 0}, // past the last rune
		{`k: "a\UFFFFFFFFb"`, `k: "a\UFFFFFFFFb"`, 0}, // too big for a rune
		{`k: "a\uD800b"`, `k: "a\uD800b"`, 0},         // a surrogate
		{`k: "a\\b`, `k: "a\\b`, 0},                   // never closed
		{`k: 'a\\b'`, `k: 'a\\b'`, 0},                 // single quotes read a backslash as text there too
		{`k: a\\b`, `k: a\\b`, 0},                     // and so did a bare value
		{`k: "ab"`, `k: "ab"`, 0},                     // nothing to re-spell
		{`# "a\\b"`, `# "a\\b"`, 0},                   // a comment
		{`"a\\b": x`, `"a\\b": x`, 0},                 // a key
		{`k: "a\\b", "c\\d"`, `k: a\b, "c\\d"`, 1},    // only the first piece, since that build wrote one
	} {
		got, n := oldPinRespelled(tc.line + "\n")
		if got != tc.want+"\n" || n != tc.changed {
			t.Errorf("%q -> %q (%d); want %q (%d)", tc.line, got, n, tc.want, tc.changed)
		}
	}
}

// The notice names the old format one way, in both its sentences. "The earlier
// module" meant nothing to anyone who never built gitsby.
func TestFormatNoticeOneName(t *testing.T) { // [df367]
	for _, mig := range []formatMigration{
		{from: 3, escapes: true, why: "the folder is read-only"},
		{from: 3, escapes: true, done: true, backup: "/h/old.shcl"},
	} {
		p, _, stderr := testPrinter()
		a := newApp(p)
		a.cfg = &config{file: "/h/config.shcl", migration: &mig, values: map[string]string{}}
		a.reportMigration()
		if got := stderr.String(); !strings.Contains(got, "earlier SHCL 3 spelling") || strings.Contains(got, "module") {
			t.Errorf("done=%v: %q", mig.done, got)
		}
	}
}
