// The state display's lists, as laid out before printing.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"slices"
	"strings"
	"testing"
)

// The Incoming list's columns come from git's tabs, and no tab is left for
// printable to escape.
func TestNameStatusColumns(t *testing.T) { // [dfhhz]
	out := "M\tfileB.txt\nR087\told name.txt\tnew name.txt\nA\t\"tab\\there.txt\"\nC100\ta\tb\n"
	want := []string{
		"M     fileB.txt",
		"R087  old name.txt -> new name.txt",
		"A     \"tab\\there.txt\"",
		"C100  a -> b",
	}
	got := nameStatusColumns(out)
	if !slices.Equal(got, want) {
		t.Errorf("got %q\nwant %q", got, want)
	}
	for _, line := range got {
		if strings.Contains(printable(line), "◉") {
			t.Errorf("escape left in %q", printable(line))
		}
	}
}
