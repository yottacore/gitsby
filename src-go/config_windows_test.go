// Folder rules through a junction, which is how most people link a folder on
// Windows, since it needs no privilege where a symlink does.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// madeJunction is 'mklink /J', then a look for the link, for the same reason as
// madeSymlink.
func madeJunction(target, link string) error {
	if out, err := toolCmd("cmd", "/c", "mklink", "/J", link, target).CombinedOutput(); err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(out)))
	}
	if _, err := os.Lstat(link); err != nil {
		return fmt.Errorf("the junction was reported made but isn't there: %w", err)
	}
	return nil
}

// Go 1.23 stopped resolving junctions in EvalSymlinks, so this held only with
// go.mod's godebug pair. Without it neither spelling matched.
func TestAccountForDirThroughJunction(t *testing.T) { // [dfh6e]
	root := t.TempDir()
	realDir := filepath.Join(root, "real", "proj")
	if err := os.MkdirAll(realDir, 0o700); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "link")
	if err := madeJunction(filepath.Join(root, "real"), link); err != nil {
		t.Skipf("no junctions here: %v", err)
	}
	if got, want := canonPath(filepath.ToSlash(filepath.Join(link, "proj"))), canonPath(filepath.ToSlash(realDir)); got != want {
		t.Errorf("canonPath(through the junction) = %q, want %q", got, want)
	}
	cfg := writeConfig(t, "account.work.ghAccount = octocat\naccount.work.path = "+filepath.ToSlash(link)+"/proj\n")
	if got := cfg.accountForDir(filepath.ToSlash(realDir)); got != "work" {
		t.Errorf("accountForDir(real path) = %q, want %q", got, "work")
	}
	if got := cfg.accountForDir(filepath.ToSlash(filepath.Join(link, "proj"))); got != "work" {
		t.Errorf("accountForDir(junction path) = %q, want %q", got, "work")
	}
	// A clone target under the junction that isn't made yet.
	if got, want := canonPath(filepath.ToSlash(filepath.Join(link, "proj", "new"))), canonPath(filepath.ToSlash(realDir))+"/new"; got != want {
		t.Errorf("canonPath(missing tail through the junction) = %q, want %q", got, want)
	}
}
