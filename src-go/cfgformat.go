// An accounts file written under an older SHCL format. A new format major changes
// what some lines mean, so such a file is kept aside under a dated name and a new
// one written in its place, converted by the module. Done once, on the first run
// that reads it.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	shcl "github.com/yottacore/shcl/source/go/v3"
)

// The second line of the banner shcl 2.x put under a file it generated. 3.0's
// starts '##', and comes with a Format line, which is asked first anyway.
const shcl2Banner = "# This config file format is SHCL."

// oldPinCutover is when the installed build moved to shcl v3.0.0-beta1. The
// module before it stamped the same Format 3 line but read a backslash in
// double quotes as an escape, where v3 reads it as text, so the two can't be
// told apart by content. A file last written before this came from the earlier
// module. Nobody else had a build from it.
var oldPinCutover = time.Date(2026, 11, 7, 3, 37, 0, 0, time.UTC)

// formatMigration is what the load did with a file in an older format.
type formatMigration struct {
	from     int    // the format major the file was in
	flat     bool   // the file was in v2.1.0's flat 'key = value' layout instead
	escapes  bool   // the file was Format 3 from the earlier module, escapes and all
	backup   string // where the file as it was went; empty when nothing was written
	changed  int    // lines re-spelled so they mean what they did
	lost     int    // lines that set something under the old rules and set nothing now
	why      string // why the file couldn't be replaced, when it couldn't
	done     bool   // the converted text is what the file has now
	reported bool
}

// oldFormat is the earlier format major a file was written in, or 0 for the
// current one. A file with neither a Format line nor the 2.x banner reads as
// current: one typed by hand follows the docs, and those describe this format.
// Asking the module first also means a later module that migrates a file on its
// own leaves nothing here to do.
func oldFormat(text string) int {
	if v, ok := shcl.FormatVersion(text); ok {
		if v >= shcl.FormatMajor {
			return 0
		}
		return v
	}
	for _, line := range splitLines(text) {
		if strings.TrimRight(line, " \t") == shcl2Banner {
			return 2
		}
	}
	return 0
}

// migrateText converts an old file through the module. The 2.x banner, where it
// is there whole, is swapped for the current one, which names the format; a file
// without it gets the module's own Format line at the end.
func migrateText(text string) (string, shcl.Migration) {
	lines := splitLines(text)
	start, end := oldBannerAt(lines)
	if start < 0 {
		m := shcl.Migrate(text, true)
		return m.Text, m
	}
	m := shcl.MigrateUnstamped(text, true)
	eol := "\n"
	if strings.Contains(text, "\r\n") {
		eol = "\r\n"
	}
	out := splitLines(m.Text)
	banner := strings.Split(strings.TrimSuffix(shcl.GenBanner, "\n"), "\n")
	out = append(out[:start], append(banner, out[end+1:]...)...)
	return strings.Join(out, eol), m
}

// oldBannerAt finds the 2.x banner block: a lone '#', the banner line, '# ' lines,
// and a closing lone '#'. Anything else around the line, and it is left alone.
func oldBannerAt(lines []string) (start, end int) {
	for i, line := range lines {
		if strings.TrimRight(line, " \t") != shcl2Banner || i == 0 || lines[i-1] != "#" {
			continue
		}
		for j := i + 1; j < len(lines); j++ {
			if lines[j] == "#" {
				return i - 1, j
			}
			if !strings.HasPrefix(lines[j], "# ") {
				break
			}
		}
	}
	return -1, -1
}

// changedLines counts the lines a migration re-spelled. MigrateUnstamped keeps
// one line for one line; the stamped form only adds lines at the end.
func changedLines(before, after string) int {
	was, now := splitLines(before), splitLines(after)
	n := 0
	for i := range was {
		if i < len(now) && was[i] != now[i] {
			n++
		}
	}
	return n
}

// oldPinRespelled re-spells the double-quoted values the earlier module wrote
// with escapes, so they read the same under the current rules. Only a value
// with a backslash in it changes, and the count is the lines that did. A line
// that module couldn't have read is left as it is. Arrays are not looked for:
// the earlier build wrote none.
func oldPinRespelled(text string) (string, int) {
	lines := strings.Split(text, "\n")
	changed := 0
	var tok shcl.Tokens
	for i, line := range lines {
		body := strings.TrimLeft(line, " \t")
		if body == "" || body[0] == '#' {
			continue
		}
		shcl.Tokenize(body, ':', false, shcl.RulesCurrent, &tok)
		if tok.Sep < 0 {
			continue
		}
		start := tok.Sep + 1
		for start < len(body) && (body[start] == ' ' || body[start] == '\t') {
			start++
		}
		if start >= len(body) || body[start] != '"' {
			continue
		}
		value, end, ok := oldPinUnquote(body, start)
		if !ok {
			continue
		}
		spelled, ok := shcl.FormatValue(value)
		if !ok {
			continue
		}
		lines[i] = line[:len(line)-len(body)] + body[:start] + spelled + body[end:]
		changed++
	}
	return strings.Join(lines, "\n"), changed
}

// oldPinUnquote reads the double-quoted value at s[at] by the earlier module's
// rules: a backslash escapes t, n, \, ", ', uXXXX and UXXXXXXXX. end is just past
// the closing quote. ok is false where there is no escape to re-spell, or where
// the value isn't one that module read.
func oldPinUnquote(s string, at int) (value string, end int, ok bool) {
	var b strings.Builder
	escaped := false
	for i := at + 1; i < len(s); i++ {
		switch c := s[i]; {
		case c == '"':
			return b.String(), i + 1, escaped
		case c != '\\':
			b.WriteByte(c)
			continue
		}
		escaped = true
		i++
		if i >= len(s) {
			return "", 0, false
		}
		switch s[i] {
		case 't':
			b.WriteByte('\t')
		case 'n':
			b.WriteByte('\n')
		case '\\', '"', '\'':
			b.WriteByte(s[i])
		case 'u', 'U':
			n := 4
			if s[i] == 'U' {
				n = 8
			}
			if i+n >= len(s) {
				return "", 0, false
			}
			r, err := strconv.ParseUint(s[i+1:i+1+n], 16, 32)
			if err != nil || r > utf8.MaxRune || !utf8.ValidRune(rune(r)) {
				return "", 0, false
			}
			b.WriteRune(rune(r))
			i += n
		default:
			return "", 0, false
		}
	}
	return "", 0, false
}

// backupName is where the old file goes: beside it, named for when and which
// format, e.g. config_backup_20261003-142233_format-v2.shcl, _format-flat for
// v2.1.0's layout, or _format-v3old for the earlier module's spelling.
func backupName(file string, mig *formatMigration, now time.Time) string {
	base := filepath.Base(file)
	base = strings.TrimSuffix(base, filepath.Ext(base))
	format := "v" + strconv.Itoa(mig.from)
	switch {
	case mig.flat:
		format = "flat"
	case mig.escapes:
		format = "v3old"
	}
	return filepath.Join(filepath.Dir(file), base+"_backup_"+now.Format("20060102-150405")+"_format-"+format+".shcl")
}

// formatName names the old format for a notice.
func (mig *formatMigration) formatName() string {
	switch {
	case mig.flat:
		return "flat 'key = value' layout of v2.1.0"
	case mig.escapes:
		return "earlier SHCL 3 spelling"
	}
	return "SHCL " + strconv.Itoa(mig.from) + ".x format"
}

// replaceOldFormat keeps the file as read under its backup name, then writes the
// converted text over it. Under the same lock 'account set' takes, and only while
// the file still has what was read: another run may have converted it already.
func replaceOldFormat(file, read, converted string, mig *formatMigration) {
	// Only a link as the file itself moves the work to its target. A folder reached
	// through a link keeps the name it was given, which the notice shows.
	target := file
	if fi, err := os.Lstat(file); err == nil && fi.Mode()&os.ModeSymlink != 0 {
		if resolved, err := filepath.EvalSymlinks(file); err == nil {
			target = resolved
		}
	}
	unlock, err := lockAccountsFile(target, accountLockWait)
	if err != nil {
		mig.why = "the lock beside it couldn't be taken"
		return
	}
	defer unlock()
	now, err := os.ReadFile(target)
	switch {
	case err != nil:
		mig.why = "it couldn't be read again: " + causeText(err)
		return
	case string(now) == converted:
		mig.done, mig.reported = true, true // the run that converted it said so
		return
	case string(now) != read:
		mig.why = "it changed while this ran"
		return
	}
	fi, err := os.Stat(target)
	if err != nil {
		mig.why = causeText(err)
		return
	}
	backup := backupName(target, mig, time.Now())
	if _, err := createNew(backup, read, fi.Mode().Perm()); err != nil {
		mig.why = "the old copy couldn't be written: " + causeText(err)
		return
	}
	if err := shcl.WriteFileAtomic(target, converted); err != nil {
		// The copy is ours and the file is untouched, so the next run starts clean.
		_ = os.Remove(backup)
		mig.why = causeText(err)
		return
	}
	mig.backup, mig.done = backup, true
}

// reportMigration says once what the load did to an old file. On stderr, so a
// pipeline reading stdout sees none of it, and not silenced by '-q': a config
// rewritten without a word is worse than a line nobody asked for.
func (a *app) reportMigration() {
	mig := a.cfg.migration
	if mig == nil || mig.reported {
		return
	}
	mig.reported = true
	file := nativePath(a.cfg.file)
	notes := noteLines("File", file)
	if !mig.done {
		a.out.errorf("The accounts file is in the %s and couldn't be converted. This run read it in that format. 'account set' and 'account unset' refuse until it is converted.", mig.formatName())
		a.out.notes(append(notes, noteLines("Why", mig.why+".")...))
		return
	}
	notes = append(notes, noteLines("From", nativePath(mig.backup))...)
	msg := "Converted the accounts file from the SHCL " + strconv.Itoa(mig.from) + ".x format, which reads some values differently. The old file is kept."
	switch {
	case mig.flat:
		msg = "Converted the accounts file from the " + mig.formatName() + " to SHCL. The old file is kept."
	case mig.escapes:
		msg = "Converted the accounts file from the " + mig.formatName() + ", which read a backslash in double quotes as an escape. The old file is kept."
	}
	if mig.changed > 0 {
		msg += " " + strconv.Itoa(mig.changed) + " line(s) were re-spelled to keep their values."
	}
	if mig.lost > 0 {
		msg += " " + strconv.Itoa(mig.lost) + " line(s) set something the new format can't, and now set nothing."
	}
	a.out.errorf("%s", msg)
	a.out.notes(notes)
}
