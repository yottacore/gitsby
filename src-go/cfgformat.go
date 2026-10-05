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

	shcl "github.com/yottacore/shcl/source/go/v2"
)

// The second line of the banner shcl 2.x put under a file it generated. 3.0's
// starts '##', and comes with a Format line, which is asked first anyway.
const shcl2Banner = "# This config file format is SHCL."

// formatMigration is what the load did with a file in an older format.
type formatMigration struct {
	from     int    // the format major the file was in
	backup   string // where the file as it was went; empty when nothing was written
	changed  int    // lines re-spelled so they mean what they did
	lost     int    // lines that set something under the old rules and set nothing now
	why      string // why the file couldn't be replaced, when it couldn't
	done     bool   // the converted text is what the file holds now
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

// backupName is where the old file goes: beside it, named for when and which
// format, e.g. config_backup_20261003-142233_format-v2.shcl.
func backupName(file string, from int, now time.Time) string {
	base := filepath.Base(file)
	base = strings.TrimSuffix(base, filepath.Ext(base))
	return filepath.Join(filepath.Dir(file), base+"_backup_"+now.Format("20060102-150405")+"_format-v"+strconv.Itoa(from)+".shcl")
}

// replaceOldFormat keeps the file as read under its backup name, then writes the
// converted text over it. Under the same lock 'account set' takes, and only while
// the file still holds what was read: another run may have converted it already.
func replaceOldFormat(file, read, converted string, mig *formatMigration) {
	target := file
	if resolved, err := filepath.EvalSymlinks(file); err == nil {
		target = resolved
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
	backup := backupName(target, mig.from, time.Now())
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
	if !mig.done {
		a.out.errorf("'%s' is in the SHCL %d.x format and couldn't be converted (%s). This run read it the way %d.x did. 'account set' and 'account unset' refuse until it is converted.", file, mig.from, mig.why, mig.from)
		return
	}
	msg := "Converted '" + file + "' from the SHCL " + strconv.Itoa(mig.from) + ".x format, which reads some values differently. The old file is '" + nativePath(mig.backup) + "'."
	if mig.changed > 0 {
		msg += " " + strconv.Itoa(mig.changed) + " line(s) were re-spelled to keep their values."
	}
	if mig.lost > 0 {
		msg += " " + strconv.Itoa(mig.lost) + " line(s) set something the new format can't, and now set nothing."
	}
	a.out.errorf("%s", msg)
}
