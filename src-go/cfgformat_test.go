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

	shcl "github.com/yottacore/shcl/source/go/v2"
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

func TestOldFormat(t *testing.T) { // [ErfO2Bg]
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
func TestOldFormatFileIsConverted(t *testing.T) { // [ErfO2Bt]
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
func TestUnmarkedFileIsLeftAlone(t *testing.T) { // [ErfO2C7]
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
func TestOldFormatUnwritable(t *testing.T) { // [ErfO2CK]
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
func TestOldFormatThroughALink(t *testing.T) { // [ErfO2CY]
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

// Another run converted the file between this one's read and its lock. It keeps
// what that run wrote, makes no second backup, and says nothing more.
func TestOldFormatConvertedByAnotherRun(t *testing.T) { // [ErfO2Cl]
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
