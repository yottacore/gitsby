// br prune's pure halves: what origin answered, how the remote candidates sort
// against it, and how the leased delete push splits.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
)

func TestParseOriginHeads(t *testing.T) { // [dcmhn]
	a40, b40, c64 := strings.Repeat("a", 40), strings.Repeat("b", 40), strings.Repeat("c", 64)
	lf := a40 + "\trefs/heads/foo\n" + b40 + "\trefs/heads/x/refs/heads/foo\n"
	want := map[string]string{"refs/heads/foo": a40, "refs/heads/x/refs/heads/foo": b40}
	for name, out := range map[string]string{"lf": lf, "crlf": strings.ReplaceAll(lf, "\n", "\r\n")} {
		got := parseOriginHeads(out)
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s: parseOriginHeads = %q, want %q", name, got, want)
		}
		// The tail match must not stand in for the branch asked about.
		if got["refs/heads/foo"] != a40 {
			t.Errorf("%s: refs/heads/foo = %q, want %q", name, got["refs/heads/foo"], a40)
		}
	}
	if got := parseOriginHeads(c64 + "\trefs/heads/long\n"); got["refs/heads/long"] != c64 {
		t.Errorf("a SHA-256 object came back as %q", got["refs/heads/long"])
	}
	if got := parseOriginHeads(""); len(got) != 0 {
		t.Errorf("empty output gave %q", got)
	}
	if got := parseOriginHeads(a40 + " refs/heads/spaced\n" + b40 + "\trefs/tags/v1\n\trefs/heads/noobject\n"); len(got) != 0 {
		t.Errorf("lines with no tab, no object or no branch gave %q", got)
	}
}

func TestSortRemoteDeletes(t *testing.T) { // [dcmhp]
	tested := map[string]string{"a": "1", "b": "2", "c": "3", "d": "4"}
	onOrigin := map[string]string{"refs/heads/a": "1", "refs/heads/b": "9", "refs/heads/d": "4", "refs/heads/e": "5"}
	send, changed, gone := sortRemoteDeletes([]string{"a", "b", "c", "d", "e"}, tested, onOrigin)
	if want := []string{"a", "d"}; !reflect.DeepEqual(send, want) {
		t.Errorf("send = %q, want %q", send, want)
	}
	// e was never tested, so it is left alone rather than sent.
	if want := []string{"b", "e"}; !reflect.DeepEqual(changed, want) {
		t.Errorf("changed = %q, want %q", changed, want)
	}
	if want := []string{"c"}; !reflect.DeepEqual(gone, want) {
		t.Errorf("gone = %q, want %q", gone, want)
	}
}

func argListLen(args []string) int {
	n := 0
	for _, arg := range args {
		n += len(arg) + 1
	}
	return n
}

func TestLeaseDeleteBatches(t *testing.T) { // [dcmhq]
	got := leaseDeleteBatches([]string{"a", "b"}, map[string]string{"a": "va", "b": "vb"}, leasePushBudget)
	want := []leaseBatch{{
		branches: []string{"a", "b"},
		args:     []string{"push", "--force-with-lease=refs/heads/a:va", "--force-with-lease=refs/heads/b:vb", "origin", "--delete", "refs/heads/a", "refs/heads/b"},
	}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("leaseDeleteBatches = %q, want %q", got, want)
	}

	tested := map[string]string{}
	var names []string
	for _, name := range []string{"b1", "b2", "b3", "b4", "b5"} {
		names = append(names, name)
		tested[name] = strings.Repeat(name[1:], 40)
	}
	// Exactly two of these fit.
	budget := argListLen([]string{"push", leaseArg("b1", tested["b1"]), leaseArg("b2", tested["b2"]), "origin", "--delete", "refs/heads/b1", "refs/heads/b2"})
	checkBatches(t, "five", leaseDeleteBatches(names, tested, budget), tested, budget, [][]string{{"b1", "b2"}, {"b3", "b4"}, {"b5"}}, "")

	long := strings.Repeat("x", budget)
	tested[long] = strings.Repeat("f", 40)
	names = []string{"b1", long, "b2", "b3"}
	checkBatches(t, "long", leaseDeleteBatches(names, tested, budget), tested, budget, [][]string{{"b1"}, {long}, {"b2", "b3"}}, long)
}

// checkBatches holds each batch to its shape: its leases, then origin --delete, then
// the same branches in order, within budget unless it has the one oversized name.
// The names it hands back are those branches too.
func checkBatches(t *testing.T, name string, got []leaseBatch, tested map[string]string, budget int, wantBranches [][]string, oversized string) {
	t.Helper()
	if len(got) != len(wantBranches) {
		t.Fatalf("%s: %d batches, want %d: %q", name, len(got), len(wantBranches), got)
	}
	for i, batch := range got {
		branches, args := wantBranches[i], batch.args
		if !reflect.DeepEqual(batch.branches, branches) {
			t.Errorf("%s: batch %d names %q, want %q", name, i, batch.branches, branches)
		}
		want := []string{"push"}
		for _, branch := range branches {
			want = append(want, leaseArg(branch, tested[branch]))
		}
		want = append(want, "origin", "--delete")
		for _, branch := range branches {
			want = append(want, "refs/heads/"+branch)
		}
		if !reflect.DeepEqual(args, want) {
			t.Errorf("%s: batch %d = %q, want %q", name, i, args, want)
		}
		if branches[0] != oversized && argListLen(args) > budget {
			t.Errorf("%s: batch %d is %d bytes, past the budget of %d", name, i, argListLen(args), budget)
		}
	}
}

func TestOriginTips(t *testing.T) { // [dcmhr]
	got := originTips([]string{"a1 refs/remotes/origin/foo", "b2 refs/remotes/origin/feature/x", "c3 refs/heads/foo", "nospace", ""})
	want := map[string]string{"foo": "a1", "feature/x": "b2"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("originTips = %q, want %q", got, want)
	}
}

func TestTypedArg(t *testing.T) { // [dcnmn]
	for _, c := range []struct{ word, goos, want string }{
		{"feature/x-1_2", "linux", "feature/x-1_2"},
		{"--force-with-lease=refs/heads/a:0f", "linux", "--force-with-lease=refs/heads/a:0f"},
		{"a;rm", "linux", "'a;rm'"},
		{"$(x)", "darwin", "'$(x)'"},
		{"it's", "linux", `'it'\''s'`},
		{"", "linux", "''"},
		{"a;rm", "windows", "'a;rm'"},
		{"it's", "windows", "'it''s'"},
		{"refs/heads/v1.2", "windows", "refs/heads/v1.2"},
		{"--force-with-lease=refs/heads/v1.2:0f", "windows", "'--force-with-lease=refs/heads/v1.2:0f'"},
		{"--force-with-lease=refs/heads/v1.2:0f", "linux", "--force-with-lease=refs/heads/v1.2:0f"},
		{"x\u2019;y", "windows", "'x\u2019\u2019;y'"},
		{"\u2018\u201a\u201b", "windows", "'\u2018\u2018\u201a\u201a\u201b\u201b'"},
		{"@foo", "windows", "'@foo'"},
		{"a@b", "windows", "a@b"},
		{"@foo", "linux", "@foo"},
		{"=x", "darwin", "'=x'"},
		{"a=b", "darwin", "a=b"},
		{"=x", "windows", "=x"},
		{`a"b`, "windows", `$(if ($PSNativeCommandArgumentPassing -in 'Standard','Windows') {'a"b'} else {'a\"b'})`},
		{`a\"b'`, "windows", `$(if ($PSNativeCommandArgumentPassing -in 'Standard','Windows') {'a\"b'''} else {'a\\\"b'''})`},
		{`a"b`, "linux", `'a"b'`},
	} {
		if got := typedArg(c.word, c.goos); got != c.want {
			t.Errorf("typedArg(%q, %s) = %s, want %s", c.word, c.goos, got, c.want)
		}
	}
}

// Every paste line reads back as the words it names, in the shell it's printed for:
// PowerShell on Windows, pwsh and Windows PowerShell where each is there, and sh and
// zsh elsewhere. 'git rev-parse --sq-quote' takes the git command's place, so each line
// goes through the real parser and the real argument passing, and git says what it got.
// PowerShell reads all 5 of its single quotes as quotes, and @ at the start of a word as
// splatting, and zsh expands a word that starts with =. 2026111910223104, 2026111910222886.
func TestPasteLinesReadBack(t *testing.T) { // [dfhfc]
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("no git")
	}
	words := []string{
		"x\u2019;hostname;#", "a\u2018;b", "c\u201a;d", "e\u201b;f", "g';h", "\u2019", "\u2018\u2019", "it\u2019s",
		"@foo", "@", "a@b", "@(x)", "=x", "a=b", "-a.b", "feature/v1.2", "1.0", "0x10", "1kb", "+5",
		"$x", "`x", "a;b", "a,b", "a&b", "(x)", "{x}", "%PATH%", "~x", "a#b", "*", "it's",
		`a"b`, `"`, `""`, `"a"`, `x";hostname;#`, `-a".b`, "a\"\u2019;b", `a\"b`, `a\\"b`, `a"b\`,
	}
	type shell struct {
		name, goos string
		lines      func(word string) []string
		run        func(t *testing.T, lines []string) [][]string
	}
	// pwsh 7.3 and later pass a double quote inside an argument escaped, and Windows
	// PowerShell 5.1 passes it bare. pwsh set to Legacy passes it bare too, even on Linux,
	// where .NET splits its command line back the Windows way, so it stands in for 5.1 there.
	const legacy = "$PSNativeCommandArgumentPassing = 'Legacy'\n"
	gitLines := func(goos string) func(string) []string {
		return func(word string) []string {
			return []string{leaseDeleteLine(word, "0f", goos), "git switch " + typedArg(word, goos)}
		}
	}
	var shells []shell
	if isWindows() {
		for _, ps := range []string{"pwsh", "powershell"} {
			if path, err := exec.LookPath(ps); err == nil {
				shells = append(shells, shell{ps, "windows", gitLines("windows"), psRun(path, "")})
				if ps == "pwsh" {
					shells = append(shells, shell{"pwsh Legacy", "windows", gitLines("windows"), psRun(path, legacy)})
				}
			}
		}
	} else {
		if path, err := exec.LookPath("pwsh"); err == nil {
			shells = append(shells, shell{"pwsh", "windows", gitLines("windows"), psRun(path, "")})
			shells = append(shells, shell{"pwsh Legacy", "windows", gitLines("windows"), psRun(path, legacy)})
		}
		for _, sh := range []string{"sh", "zsh"} {
			if path, err := exec.LookPath(sh); err == nil {
				lines := func(word string) []string {
					return append(gitLines("linux")(word), "git switch "+shellWord(word, false))
				}
				shells = append(shells, shell{sh, "linux", lines, shRun(path)})
			}
		}
	}
	if len(shells) == 0 {
		t.Skip("no shell to read the lines back")
	}
	for _, sh := range shells {
		var lines []string
		var wants [][]string
		for _, word := range words {
			for _, line := range sh.lines(word) {
				lines = append(lines, line)
				if strings.HasPrefix(line, "git push ") {
					wants = append(wants, []string{"push", leaseArg(word, "0f"), "origin", "--delete", "refs/heads/" + word})
				} else {
					wants = append(wants, []string{"switch", word})
				}
			}
		}
		got := sh.run(t, lines)
		for i, line := range lines {
			if !reflect.DeepEqual(got[i], wants[i]) {
				t.Errorf("%s reads %s as %q, want %q", sh.name, line, got[i], wants[i])
			}
		}
	}
}

// probeLine puts 'rev-parse --sq-quote' in the git command's place.
func probeLine(line string) string {
	return "git rev-parse --sq-quote" + strings.TrimPrefix(line, "git")
}

// sqWords reads back what 'git rev-parse --sq-quote' printed, one word per argument.
func sqWords(out string) []string {
	var words []string
	for _, field := range strings.Fields(out) {
		if word, ok := shWord(field); ok {
			words = append(words, word)
		} else {
			words = append(words, "<unreadable "+field+">")
		}
	}
	return words
}

// shRun runs each line in its own sh -c, so one that breaks out can't take the next.
func shRun(path string) func(*testing.T, []string) [][]string {
	return func(t *testing.T, lines []string) [][]string {
		got := make([][]string, len(lines))
		for i, line := range lines {
			out, err := exec.Command(path, "-c", probeLine(line)).Output()
			if err != nil {
				t.Errorf("%s -c %s: %v", path, line, err)
			}
			got[i] = sqWords(string(out))
		}
		return got
	}
}

// psRun hands the lines over in a UTF-8 file with a BOM, since Windows PowerShell reads
// a file without one in the ANSI code page, and runs each through Invoke-Expression,
// which parses it as a typed line is parsed. A marker ahead of each splits the output,
// so a line that breaks out shows as its own extra words. prelude runs first.
func psRun(path, prelude string) func(*testing.T, []string) [][]string {
	return func(t *testing.T, lines []string) [][]string {
		dir := t.TempDir()
		var probes strings.Builder
		probes.WriteString("\xef\xbb\xbf")
		for _, line := range lines {
			probes.WriteString(probeLine(line) + "\n")
		}
		lineFile, script := filepath.Join(dir, "lines.txt"), filepath.Join(dir, "run.ps1")
		if err := os.WriteFile(lineFile, []byte(probes.String()), 0o600); err != nil {
			t.Fatal(err)
		}
		runner := prelude + "$utf8 = New-Object Text.UTF8Encoding $false\n" +
			"[Console]::OutputEncoding = $utf8\n$OutputEncoding = $utf8\n$i = 0\n" +
			"foreach ($line in Get-Content -LiteralPath $args[0] -Encoding UTF8) {\n" +
			"\t\"@@probe $i\"; $i++\n" +
			"\ttry { Invoke-Expression $line 2>&1 | ForEach-Object { \"$_\" } } catch { \"parse: $_\" }\n}\n"
		if err := os.WriteFile(script, []byte(runner), 0o600); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command(path, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, lineFile)
		cmd.Env = append(os.Environ(), "POWERSHELL_TELEMETRY_OPTOUT=1")
		out, err := cmd.Output()
		if err != nil {
			var stderr []byte
			if exit := (*exec.ExitError)(nil); errors.As(err, &exit) {
				stderr = exit.Stderr
			}
			t.Fatalf("%s: %v\n%s\n%s", path, err, out, stderr)
		}
		got := make([][]string, len(lines))
		i := -1
		for _, row := range strings.Split(strings.ReplaceAll(string(out), "\r\n", "\n"), "\n") {
			if n, found := strings.CutPrefix(row, "@@probe "); found {
				if i, err = strconv.Atoi(n); err != nil || i >= len(lines) {
					t.Fatalf("%s: stray marker %q", path, row)
				}
				continue
			}
			if i >= 0 && row != "" {
				if strings.HasPrefix(row, " '") {
					got[i] = append(got[i], sqWords(row)...)
				} else {
					got[i] = append(got[i], "<output "+row+">")
				}
			}
		}
		return got
	}
}

func TestLeaseDeleteLine(t *testing.T) { // [dcnmp]
	if got, want := leaseDeleteLine("far", "0f", "linux"), "git push --force-with-lease=refs/heads/far:0f origin --delete refs/heads/far"; got != want {
		t.Errorf("leaseDeleteLine = %s, want %s", got, want)
	}
	if got, want := leaseDeleteLine("a$b", "0f", "linux"), "git push '--force-with-lease=refs/heads/a$b:0f' origin --delete 'refs/heads/a$b'"; got != want {
		t.Errorf("leaseDeleteLine = %s, want %s", got, want)
	}
}
