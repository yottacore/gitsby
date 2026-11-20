// A file another program holds open without read sharing: the Windows way a
// file can be there and unreadable, since chmod can't take the read bit away.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"strings"
	"syscall"
	"testing"
)

// Reads pass over a file held open without read sharing, and the create refuses
// by name instead of blaming permissions. The OS sentence is localized, so only
// the fixed text is matched.
func TestAccountSetRefusesAFileHeldOpen(t *testing.T) { // [dcmk0]
	a := createApp(t, newPrinter())
	file := putDefaultConfig(t, keptBody)
	name, err := syscall.UTF16PtrFromString(file)
	if err != nil {
		t.Fatal(err)
	}
	// Read and write, as an editor holds a file. A handle opened for reading alone
	// with no sharing still let this same process open the file to read.
	h, err := syscall.CreateFile(name, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, syscall.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		t.Fatal(err)
	}
	held := true
	release := func() {
		if held {
			held = false
			// Opened only to hold the file; nothing went through it, so Close has nothing to say.
			_ = syscall.CloseHandle(h)
		}
	}
	t.Cleanup(release)
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	if a.cfg.file != "" {
		t.Errorf("reads took up the held file: %q", a.cfg.file)
	}
	err = a.cmdAccountSet()
	if err == nil {
		t.Fatal("set: no refusal")
	}
	for _, want := range []string{"can't be read", "Run this again once it can be read."} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal is missing %q:\n%s", want, err)
		}
	}
	release()
	if got := readBack(t, file); got != keptBody {
		t.Errorf("the held file changed:\n%q", got)
	}
}

// A save over a file another program holds without delete sharing, in the
// APPDATA folder a new file goes in. The Why line spelled the path with both
// slashes, and the Fix named only the folder's permissions.
func TestAccountSetSaveOverAHeldFile(t *testing.T) { // [dfhmz]
	a := createApp(t, newPrinter())
	t.Setenv("APPDATA", t.TempDir())
	file := putDefaultConfig(t, keptBody)
	if !strings.HasPrefix(file, os.Getenv("APPDATA")+`\`) {
		t.Errorf("the new file isn't under APPDATA: %q", file)
	}
	if strings.Contains(file, "/") {
		t.Errorf("the accounts file is spelled with a slash: %q", file)
	}
	name, err := syscall.UTF16PtrFromString(file)
	if err != nil {
		t.Fatal(err)
	}
	// Reads and writes shared, delete not: the way an editor or a sync tool can
	// hold a file, which lets the plan read it and refuses the rename over it.
	h, err := syscall.CreateFile(name, syscall.GENERIC_READ, syscall.FILE_SHARE_READ|syscall.FILE_SHARE_WRITE, nil, syscall.OPEN_EXISTING, syscall.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		t.Fatal(err)
	}
	held := true
	release := func() {
		if held {
			held = false
			// Opened only to hold the file; nothing went through it, so Close has nothing to say.
			_ = syscall.CloseHandle(h)
		}
	}
	t.Cleanup(release)
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	if a.cfg.file != file {
		t.Fatalf("reads found %q, want %q", a.cfg.file, file)
	}
	err = a.cmdAccountSet()
	if err == nil {
		t.Fatal("set: no refusal")
	}
	msg := err.Error()
	if !strings.Contains(msg, "Couldn't save the accounts file.") {
		t.Fatalf("not the save refusal:\n%s", msg)
	}
	// The module's message names the file, as the OS spells it, and a long one
	// wraps onto the lines under Why.
	why, _, _ := strings.Cut(msg[strings.Index(msg, "Why:"):], "Kept:")
	if strings.Contains(why, "/") {
		t.Errorf("the Why lines spell a path with a slash:\n%s", why)
	}
	if !strings.Contains(msg, "File: "+file) {
		t.Errorf("the File line is missing %q:\n%s", file, msg)
	}
	if !strings.Contains(msg, "Fix:  Another program may have it open.") {
		t.Errorf("the Fix doesn't name a program holding it:\n%s", msg)
	}
	release()
	if got := readBack(t, file); got != keptBody {
		t.Errorf("the held file changed:\n%q", got)
	}
}
