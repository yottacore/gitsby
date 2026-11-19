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
	"errors"
	"io/fs"
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

// oldPinCutover is when the installed build moved to shcl v3.0.0-beta1. The earlier
// module wrote the same Format line, so a file is told by its mtime. Backlog
// 2026110710480989.
var oldPinCutover = time.Date(2026, 11, 7, 3, 37, 0, 0, time.UTC)

// oldPinStart is the commit time of the first module ca0e55c pinned, so no build on
// it wrote anything earlier. A file older than that, or with no real time, as a Nix
// store gives, isn't from it.
var oldPinStart = time.Date(2026, 9, 24, 19, 49, 10, 0, time.UTC)

// fromOldPin is whether a Format 3 file last written at mtime could be the earlier
// module's.
func fromOldPin(mtime time.Time) bool {
	return !mtime.Before(oldPinStart) && mtime.Before(oldPinCutover)
}

// oldKind is which older layout a file was in.
type oldKind int

const (
	oldMajor  oldKind = iota // an older SHCL format major, the one in from
	oldFlat                  // v2.1.0's flat 'key = value' layout
	oldPinned                // Format 3 from the earlier module, escapes and all
)

// formatMigration is what the load did with a file in an older format.
type formatMigration struct {
	kind     oldKind
	from     int    // the format major, for oldMajor
	backup   string // where the file as it was went; empty when nothing was written
	changed  int    // lines re-spelled so they mean what they did
	lost     int    // lines that set something under the old rules and set nothing now
	why      string // why the file couldn't be replaced, when it couldn't
	fix      string // what to do about it, when running again won't
	done     bool   // the converted text is what the file has now
	reported bool
}

// oldFormat is the earlier format major a file was written in, or 0 for the current one.
// With no Format line or 2.x banner it's current, since a hand-typed one follows the
// docs.
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

// convert2x is migrateText for a 2.x file, checked against how 2.x read it. A value
// the module would cut or split is put in quotes first. bad is the first line that
// still reads differently, which keeps the file as it is; 0 when none does.
func convert2x(text string) (converted string, m shcl.Migration, bad int) {
	quoted, bad := quote2xRuns(text)
	converted, m = migrateText(quoted)
	if bad == 0 {
		bad = readings2xDiffer(text, m.Text)
	}
	return converted, m, bad
}

// scan2x is where 2.x found stop in s: outside a quoted run and not after a
// backslash, or -1. A quote anywhere opens a run, even mid-value as in O"Brien#2,
// and it ends at the same quote or the end of the line. splitComment and
// splitUnquotedCommas in shcl 2.x, which is frozen, so this can't drift from it;
// FuzzOld2xHandTyped holds it to the real module.
func scan2x(s string, stop byte) int {
	var quote byte
	for i := 0; i < len(s); i++ {
		switch c := s[i]; {
		case c == '\\':
			i++
		case quote != 0:
			if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == stop:
			return i
		}
	}
	return -1
}

// line2x is one line as 2.x split it: the value's text, trimmed, and where the
// comment starts, or -1. ok is false for a line binding nothing. tok holds the
// module's own 2.x reading of the line, for its separator.
func line2x(body string, tok *shcl.Tokens) (value string, region [2]int, hash int, ok bool) {
	if body == "" || body[0] == '#' {
		return "", region, -1, false
	}
	shcl.Tokenize(body, ':', false, shcl.RulesV2, tok)
	hash = scan2x(body, '#')
	if tok.Sep < 0 || (hash >= 0 && hash < tok.Sep) {
		return "", region, hash, false
	}
	region = [2]int{tok.Sep + 1, len(body)}
	if hash >= 0 {
		region[1] = hash
	}
	return strings.Trim(body[region[0]:region[1]], " \t"), region, hash, true
}

// quote2xRuns puts in quotes each value the module would end at a '#', or split at
// a ',', that 2.x read as text, since a quote before it opened a run. Upstream,
// shcl's 2.x reading doesn't run a quote mid-value to its end. Quotes holding no
// backslash read the same in 2.x, and the module carries them over. bad is the
// first such line no quote fits: a list, or text holding a backslash or both
// quotes.
func quote2xRuns(text string) (string, int) {
	lines := strings.Split(text, "\n")
	bad := 0
	var tok shcl.Tokens
	for i, line := range lines {
		cr := strings.HasSuffix(line, "\r")
		line = strings.TrimSuffix(line, "\r")
		body := strings.TrimLeft(line, " \t")
		value, region, hash, ok := line2x(body, &tok)
		single := scan2x(value, ',') < 0
		if !ok || (hash == tok.Comment && (!single || len(tok.Elements) <= 1)) {
			continue
		}
		var q string
		switch {
		case value == "" || !single || strings.Contains(value, "\\"):
		case !strings.Contains(value, "'"):
			q = "'"
		case !strings.Contains(value, `"`):
			q = `"`
		}
		if q == "" {
			if bad == 0 {
				bad = i + 1
			}
			continue
		}
		was := body[region[0]:region[1]]
		lead := was[:len(was)-len(strings.TrimLeft(was, " \t"))]
		gap := was[len(strings.TrimRight(was, " \t")):]
		line = line[:len(line)-len(body)] + body[:region[0]] + lead + q + value + q + gap + body[region[1]:]
		if cr {
			line += "\r"
		}
		lines[i] = line
	}
	return strings.Join(lines, "\n"), bad
}

// readings2xDiffer is the first line v3 reads apart from how 2.x read the line
// before: its comment starts elsewhere, or one is a list and the other isn't. 0
// when none is. The module keeps one line for one line, so after is its text
// before any banner is swapped in.
func readings2xDiffer(before, after string) int {
	was, now := splitLines(before), splitLines(after)
	var old, cur shcl.Tokens
	for i := range was {
		if i >= len(now) {
			break
		}
		body := strings.TrimLeft(now[i], " \t")
		if body == "" || body[0] == '#' {
			continue
		}
		shcl.Tokenize(body, ':', false, shcl.RulesCurrent, &cur)
		if cur.Sep < 0 {
			continue
		}
		oldBody := strings.TrimLeft(was[i], " \t")
		value, _, hash, ok := line2x(oldBody, &old)
		oldNote, curNote := "", ""
		if hash >= 0 {
			oldNote = oldBody[hash:]
		}
		if cur.Comment >= 0 {
			curNote = body[cur.Comment:]
		}
		if !ok || oldNote != curNote || (scan2x(value, ',') >= 0) != (cur.Array >= 0) {
			return i + 1
		}
	}
	return 0
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

// oldPinRespelled re-spells the double-quoted values the earlier module wrote with
// escapes. The count is the lines changed. Arrays aren't looked for: it wrote none.
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
	switch mig.kind {
	case oldFlat:
		format = "flat"
	case oldPinned:
		format = "v3old"
	}
	return filepath.Join(filepath.Dir(file), base+"_backup_"+now.Format("20060102-150405")+"_format-"+format+".shcl")
}

// formatName names the old format for a notice.
func (mig *formatMigration) formatName() string {
	switch mig.kind {
	case oldFlat:
		return "flat 'key = value' layout of v2.1.0"
	case oldPinned:
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
		switch cause := errors.Unwrap(err); {
		case errors.Is(err, fs.ErrPermission):
			mig.why = "the folder it is in can't be written"
		case cause != nil:
			mig.why = "the lock beside it couldn't be made: " + causeText(cause)
		default:
			mig.why = "another run held the lock beside it"
		}
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
	// The file's own time, so a copy moved back reads as the file did: the time is
	// what tells the earlier module's file from a v3 one.
	if err := os.Chtimes(backup, time.Time{}, fi.ModTime()); err != nil {
		_ = os.Remove(backup) // ours, and the file is untouched
		mig.why = "the old copy couldn't keep the file's time: " + causeText(err)
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
	if a.cfg.newer > 0 && !a.cfg.newerSaid {
		a.cfg.newerSaid = true
		a.out.errorf("The accounts file is in SHCL format %d, newer than this build reads. This run read it by format %d's rules, so some values may read differently. 'account set' and 'account unset' refuse until %s is updated.", a.cfg.newer, shcl.FormatMajor, meName)
		a.out.notes(noteLines("File", nativePath(a.cfg.file)))
	}
	mig := a.cfg.migration
	if mig == nil || mig.reported {
		return
	}
	mig.reported = true
	file := nativePath(a.cfg.file)
	notes := noteLines("File", file)
	if !mig.done {
		a.out.errorf("The accounts file is in the %s and couldn't be converted. This run read it in that format. 'account set' and 'account unset' refuse until it is converted.", mig.formatName())
		notes = append(notes, noteLines("Why", mig.why+".")...)
		if mig.fix != "" {
			notes = append(notes, noteLines("Fix", mig.fix)...)
		}
		a.out.notes(notes)
		return
	}
	notes = append(notes, noteLines("From", nativePath(mig.backup))...)
	var msg string
	switch mig.kind {
	case oldFlat:
		msg = "Converted the accounts file from the " + mig.formatName() + " to SHCL. The old file is kept."
	case oldPinned:
		msg = "Converted the accounts file from the " + mig.formatName() + ", which read a backslash in double quotes as an escape. The old file is kept."
	default:
		msg = "Converted the accounts file from the " + mig.formatName() + ", which reads some values differently. The old file is kept."
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
