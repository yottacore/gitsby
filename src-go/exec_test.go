// Finding the tools gitsby runs, without finding ourselves.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// A gh that is this binary, by link, comes before the real one on PATH and is
// passed over. So is a relative entry, which LookPath would never run.
func TestLookToolSkipsSelf(t *testing.T) { // [de89d]
	if runtime.GOOS == "windows" {
		t.Skip("needs symlinks and the exec bit")
	}
	exe, err := os.Executable()
	if err != nil {
		t.Skip("can't name the test binary:", err)
	}
	root := t.TempDir()
	link, realDir, rel := filepath.Join(root, "link"), filepath.Join(root, "realDir"), "relbin"
	for _, dir := range []string{link, realDir, filepath.Join(root, rel)} {
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(exe, filepath.Join(link, "gh")); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{realDir, filepath.Join(root, rel)} {
		if err := os.WriteFile(filepath.Join(dir, "gh"), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Chdir(root)
	sep := string(os.PathListSeparator)
	t.Setenv("PATH", rel+sep+link+sep+realDir)

	hit := lookTool("gh")
	found, ours := hit.path, hit.ours
	if found != filepath.Join(realDir, "gh") || !slices.Equal(ours, []string{filepath.Join(link, "gh")}) {
		t.Errorf("found %q, ours %q", found, ours)
	}

	t.Setenv("PATH", link+sep+link+string(filepath.Separator))
	hit = lookTool("gh")
	found, ours = hit.path, hit.ours
	if found != "" || len(ours) != 1 {
		t.Errorf("only ourselves on PATH: found %q, ours %q", found, ours)
	}
}

// A 'raw' whose tool file is already running under a 'raw' above it, same
// arguments and folder, is a wrapper's: it passes over that file to the next one
// on PATH, and refuses naming it only when none is left. Unsetting the variable
// would loop, so the refusal doesn't say to. The variable is read as the run
// found it.
func TestRawRefusesInsideRaw(t *testing.T) { // [de89e]
	wrapDir, realDir := t.TempDir(), t.TempDir()
	ext := ""
	if runtime.GOOS == "windows" {
		ext = ".exe"
	}
	ran := filepath.Join(realDir, "ran")
	wrap, realGh := filepath.Join(wrapDir, "gh"+ext), filepath.Join(realDir, "gh"+ext)
	// Never this test binary, so a regression that runs it can't start us again.
	for gh, says := range map[string]string{wrap: "wrapper", realGh: "real"} {
		if err := os.WriteFile(gh, []byte("#!/bin/sh\necho "+says+" > '"+ran+"'\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	args := []string{"auth", "status"}
	above, err := rawNest("", "gh", rawEntry("gh", wrap, args))
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv(rawActiveVar, above)

	if runtime.GOOS != "windows" {
		t.Setenv("PATH", wrapDir+string(os.PathListSeparator)+realDir)
		err = newApp(newPrinter()).cmdPassthrough("gh", args)
		if err == nil || err.Error() != silentExit(0).Error() {
			t.Errorf("passing over: %v", err)
		}
		// A failed read is empty, which fails the check too.
		if got, _ := os.ReadFile(ran); string(got) != "real\n" {
			t.Errorf("the next gh didn't run: %q", got)
		}
		if chain := strings.Fields(os.Getenv(rawActiveVar)); len(chain) != 2 || chain[1] != rawEntry("gh", realGh, args) {
			t.Errorf("handed over with %q", chain)
		}
		t.Setenv(rawActiveVar, above)
	}

	t.Setenv("PATH", wrapDir)
	err = newApp(newPrinter()).cmdPassthrough("gh", args)
	if err == nil || !strings.Contains(err.Error(), "Looping") || !strings.Contains(err.Error(), wrap) || strings.Contains(err.Error(), rawActiveVar) {
		t.Errorf("got %v", err)
	}
}

// Only a repeat is on the chain: other arguments, another folder or another tool
// file nest, as a hook calling 'raw git' under 'raw git commit' does. Under the
// probe mark the tool file alone is a match, and the mark stays last.
func TestRawNestChain(t *testing.T) { // [de8pk]
	t.Chdir(t.TempDir())
	commit := []string{"commit", "-m", "x"}
	chain, err := rawNest("", "git", rawEntry("git", "/bin/git", commit))
	if err != nil || len(strings.Fields(chain)) != 1 {
		t.Fatalf("first: %q, %v", chain, err)
	}
	if !rawOnChain(chain, rawEntry("git", "/bin/git", commit)) {
		t.Errorf("a repeat isn't on the chain")
	}
	// Joined differently, the same words are other arguments.
	for _, args := range [][]string{{"status"}, {"commit-m", "x"}, {"commit", "-mx"}} {
		if rawOnChain(chain, rawEntry("git", "/bin/git", args)) {
			t.Errorf("%q counted as a repeat", args)
		}
		if next, err := rawNest(chain, "git", rawEntry("git", "/bin/git", args)); err != nil || len(strings.Fields(next)) != 2 {
			t.Errorf("%q refused: %q, %v", args, next, err)
		}
	}
	if rawOnChain(chain, rawEntry("git", "/usr/local/bin/git", commit)) {
		t.Errorf("another git counted as a repeat")
	}
	probing := chain + " " + rawProbing
	if !rawOnChain(probing, rawEntry("git", "/bin/git", []string{"--version"})) {
		t.Errorf("under the probe mark, the same git with other arguments isn't on the chain")
	}
	if rawOnChain(probing, rawEntry("gh", "/bin/gh", []string{"api", "user"})) {
		t.Errorf("under the probe mark, another tool counted as on the chain")
	}
	next, err := rawNest(probing, "gh", rawEntry("gh", "/bin/gh", []string{"api", "user"}))
	if fields := strings.Fields(next); err != nil || len(fields) != 3 || fields[2] != rawProbing {
		t.Errorf("under the probe mark: %q, %v", next, err)
	}
	t.Chdir(t.TempDir())
	if rawOnChain(chain, rawEntry("git", "/bin/git", commit)) {
		t.Errorf("another folder counted as a repeat")
	}
}

// A loop with new arguments each time stops at rawDepthMax, and says how deep.
// The probe mark isn't a level.
func TestRawNestDepth(t *testing.T) { // [de8pm]
	chain := ""
	for n := range rawDepthMax {
		var err error
		if chain, err = rawNest(chain, "gh", rawEntry("gh", "/bin/gh", []string{strconv.Itoa(n)})); err != nil {
			t.Fatalf("refused at %d: %v", n+1, err)
		}
	}
	_, err := rawNest(chain, "gh", rawEntry("gh", "/bin/gh", []string{"last"}))
	if err == nil || !strings.Contains(err.Error(), strconv.Itoa(rawDepthMax+1)+" deep") || strings.Contains(err.Error(), rawActiveVar) {
		t.Errorf("got %v", err)
	}
	_, err = rawNest(chain+" "+rawProbing, "gh", rawEntry("gh", "/bin/gh", []string{"last"}))
	if err == nil || !strings.Contains(err.Error(), strconv.Itoa(rawDepthMax+1)+" deep") {
		t.Errorf("under the probe mark: %v", err)
	}
}

// Every spawn takes the same lookup: a gh that is this binary is refused rather
// than run (never Run here, since a regression would start this test binary again), the real one runs by full path under its own name, and a name with a
// path in it is left alone.
func TestToolCmdSkipsSelf(t *testing.T) { // [de89z]
	if runtime.GOOS == "windows" {
		t.Skip("needs symlinks and the exec bit")
	}
	exe, err := os.Executable()
	if err != nil {
		t.Skip("can't name the test binary:", err)
	}
	root := t.TempDir()
	link, realDir := filepath.Join(root, "link"), filepath.Join(root, "realDir")
	for _, dir := range []string{link, realDir} {
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(exe, filepath.Join(link, "gh")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(realDir, "gh"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	t.Setenv("PATH", link)
	cmd := toolCmd("gh", "auth", "status")
	if cmd.Err == nil || !strings.Contains(cmd.Err.Error(), "is "+meName+" itself") {
		t.Errorf("only ourselves on PATH: Err %v", cmd.Err)
	}
	if inPath("gh") || mustBeInPath("gh") == nil || shadowed("tea", "gh") == nil {
		t.Error("a gh that is us counts as installed")
	}

	t.Setenv("PATH", link+string(os.PathListSeparator)+realDir)
	cmd = toolCmd("gh", "auth", "status")
	if cmd.Err != nil || cmd.Path != filepath.Join(realDir, "gh") || cmd.Args[0] != "gh" {
		t.Errorf("got Err %v, Path %q, argv[0] %q", cmd.Err, cmd.Path, cmd.Args[0])
	}

	given := filepath.Join(link, "gh")
	if cmd = toolCmd(given); cmd.Path != given || cmd.Err != nil {
		t.Errorf("a path was looked up: Path %q, Err %v", cmd.Path, cmd.Err)
	}
}

// No spawn outside exec.go, so none can skip toolCmd's lookup. A new call site
// running a tool by bare name is how 2026102111572785 came back after raw's fix.
func TestOneSpawnSite(t *testing.T) { // [de8a0]
	files, err := filepath.Glob("*.go")
	if err != nil || len(files) < 10 {
		t.Fatalf("found %d sources: %v", len(files), err)
	}
	for _, file := range files {
		if file == "exec.go" || strings.HasSuffix(file, "_test.go") {
			continue
		}
		src, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for _, call := range []string{"exec.Command(", "exec.CommandContext(", "exec.LookPath(", "os.StartProcess(", "syscall.Exec("} {
			if strings.Contains(string(src), call) {
				t.Errorf("%s calls %s; use toolCmd or findTool in exec.go", file, call)
			}
		}
	}
}

// Where a raw tool's own options put it, read as the tool reads them: git up to its
// command, -C on from the last -C, a separate value for an option that takes one.
func TestToolRepoOf(t *testing.T) { // [dffz8]
	t.Setenv("GIT_DIR", "")
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	abs := func(p string) string { return filepath.Join(wd, p) }
	other := filepath.Join(t.TempDir(), "other")
	cases := []struct {
		tool string
		args []string
		want toolRepo
	}{
		{"git", []string{"status"}, toolRepo{}},
		{"git", []string{"-C", other, "status"}, toolRepo{dir: other}},
		{"git", []string{"-C", "a", "-C", "b", "log"}, toolRepo{dir: filepath.Join("a", "b")}},
		{"git", []string{"-C", "a", "-C", other}, toolRepo{dir: other}},
		{"git", []string{"-C", "", "status"}, toolRepo{}},
		{"git", []string{"-c", "-C", "status"}, toolRepo{}},
		{"git", []string{"-c", "x.y=1", "-C", "a", "status"}, toolRepo{dir: "a"}},
		{"git", []string{"--namespace", "-C", "status"}, toolRepo{}},
		{"git", []string{"--git-dir=g", "--work-tree", "w", "status"}, toolRepo{gitDir: "g", workTree: "w"}},
		{"git", []string{"--git-dir", "g", "--git-dir=h"}, toolRepo{gitDir: "h"}},
		{"git", []string{"-C", "a", "--bare", "log"}, toolRepo{dir: "a", gitDir: abs("a")}},
		{"git", []string{"--git-dir=g", "--bare"}, toolRepo{gitDir: "g"}},
		{"git", []string{"log", "-C", "a"}, toolRepo{}},
		{"git", []string{"--", "-C", "a"}, toolRepo{}},
		{"git", []string{"-C"}, toolRepo{}},
		{"tig", []string{"-C", "a", "-C", "b", "status"}, toolRepo{dir: filepath.Join("a", "b")}},
		{"tig", []string{"status", "-C", "a"}, toolRepo{}},
		{"lazygit", []string{"-p", "a"}, toolRepo{dir: abs("a"), workTree: abs("a"), gitDir: filepath.Join(abs("a"), ".git")}},
		{"lazygit", []string{"status", "--path=" + other}, toolRepo{dir: other, workTree: other, gitDir: filepath.Join(other, ".git")}},
		{"lazygit", []string{"-g", "g", "-w", "w"}, toolRepo{gitDir: abs("g"), dir: abs("w"), workTree: abs("w")}},
		{"gh", []string{"-C", "a"}, toolRepo{}},
	}
	for _, c := range cases {
		if got := toolRepoOf(c.tool, c.args); got != c.want {
			t.Errorf("toolRepoOf(%s, %q) = %+v, want %+v", c.tool, c.args, got, c.want)
		}
	}
}

// git's -C options end where a chdir per -C ends, so raw takes that folder's account.
// On Windows that takes in C:foo and \foo after another -C. 2026112017135400.
func TestToolRepoOfFollowsChdir(t *testing.T) { // [dfnev]
	t.Setenv("GIT_DIR", "")
	root := t.TempDir()
	for _, dir := range []string{"a/b", "c", "top/foo"} {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	start := filepath.Join(root, "top")
	t.Chdir(start)
	vol := filepath.VolumeName(root)
	rooted := root[len(vol):]
	seqs := [][]string{
		{".."}, {"..", "c"}, {"..", "a", "b"}, {filepath.Join(root, "a"), "b"}, {"..", filepath.Join(root, "c")}, {"foo", "..", "foo"},
	}
	if vol != "" {
		seqs = append(seqs,
			[]string{vol + "foo"}, []string{"..", vol + "top"}, []string{"..", vol + "c"}, []string{"..", "a", vol}, []string{vol + "foo", vol + ".."},
			[]string{"..", filepath.Join(rooted, "top", "foo")}, []string{"foo", filepath.Join(rooted, "c")}, []string{vol + "..", filepath.Join(rooted, "a"), "b"},
		)
	}
	where := func(dirs ...string) string {
		t.Helper()
		defer func() {
			if err := os.Chdir(start); err != nil {
				t.Fatal(err)
			}
		}()
		for _, d := range dirs {
			if err := os.Chdir(d); err != nil {
				return "<" + err.Error() + ">"
			}
		}
		wd, err := os.Getwd()
		if err != nil {
			t.Fatal(err)
		}
		return wd
	}
	for _, seq := range seqs {
		var args []string
		for _, d := range seq {
			args = append(args, "-C", d)
		}
		r := toolRepoOf("git", append(args, "status"))
		want := where(seq...)
		if strings.HasPrefix(want, "<") {
			t.Fatalf("git %q leads nowhere: %s", args, want)
		}
		if got := where(r.dir); got != want {
			t.Errorf("git %q: toolRepoOf gives %q, which is %s, but git would be in %s", args, r.dir, got, want)
		}
		if r = toolRepoOf("tig", append(args, "status")); where(r.dir) != where(seq...) {
			t.Errorf("tig %q: toolRepoOf gives %q", args, r.dir)
		}
	}
}

// A batch file is told by its extension alone, in any case, and only on Windows,
// where cmd runs it. The refusal for a tool found only as one names it.
func TestBatchFile(t *testing.T) { // [dfhmh]
	for name, want := range map[string]bool{
		"git.bat": true, "git.BAT": true, "git.cmd": true, "git.Cmd": true,
		"git": false, "git.exe": false, "git.batch": false, "git.bat.exe": false, "bat": false, "cmd": false,
	} {
		if got := batchName(filepath.Join("dir", name)); got != want {
			t.Errorf("%s: got %v", name, got)
		}
		if got := batchFile(name); got != (want && runtime.GOOS == "windows") {
			t.Errorf("%s on %s: got %v", name, runtime.GOOS, got)
		}
	}
	err := notInPath("git", nil, []string{"/a/git.bat", "/b/git.cmd"})
	if err == nil || !strings.Contains(err.Error(), "'/a/git.bat', '/b/git.cmd' are batch files") {
		t.Errorf("two: %v", err)
	}
	err = notInPath("git", []string{"/c/git"}, []string{"/a/git.bat"})
	if err == nil || !strings.Contains(err.Error(), "'/c/git' is "+meName+" itself. '/a/git.bat' is a batch file") {
		t.Errorf("with ours: %v", err)
	}
	if err = notInPath("git", nil, nil); err == nil || err.Error() != "Not found in path: git" {
		t.Errorf("neither: %v", err)
	}
}
