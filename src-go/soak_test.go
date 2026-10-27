// The soak test: the everyday commands, round after round in one process, against a
// throwaway origin and clone. Whatever a run leaves behind piles up here, where a
// single run that exits would hide it. Off unless GITSBY_SOAK_ROUNDS is set, since
// it takes a while; 'cicd.bash --leakcheck' sets it.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"runtime/pprof"
	"strconv"
	"strings"
	"testing"
	"time"
)

// What the heap may grow by from round N to 2N. The first rounds fill caches, so
// they are never measured. Past them, 2 reads differ by under 100 KB, on a heap
// of under 2 MB.
const soakHeapMargin = 256 << 10

type soakReading struct {
	round      int
	heapInuse  uint64
	goroutines int
}

func TestSoak(t *testing.T) { // [de546]
	rounds, err := strconv.Atoi(os.Getenv("GITSBY_SOAK_ROUNDS"))
	if err != nil || rounds < 1 {
		t.Skip("set GITSBY_SOAK_ROUNDS to run it")
	}
	outDir := os.Getenv("GITSBY_SOAK_OUT")
	if outDir == "" {
		outDir = t.TempDir()
	} else if err := os.MkdirAll(outDir, 0o755); err != nil {
		t.Fatal(err)
	}
	// Coarse enough to cost little, fine enough that a leak of a few KB a run shows
	// up by name in the diff.
	oldRate := runtime.MemProfileRate
	runtime.MemProfileRate = 4096
	t.Cleanup(func() { runtime.MemProfileRate = oldRate })

	_, clone := gitTestRepo(t)
	t.Chdir(clone)
	home := t.TempDir()
	t.Setenv("HOME", home)
	for _, name := range []string{"GITSBY_CONFIG", "XDG_CONFIG_HOME", "APPDATA", "GH_TOKEN", "GITEA_TOKEN"} {
		t.Setenv(name, "")
		if err := os.Unsetenv(name); err != nil {
			t.Fatal(err)
		}
	}
	// Nothing leaves the box. Origin is a folder, and gh or ssh asked anyway says no.
	fakeTool(t, "gh", "exit 1")
	fakeTool(t, "ssh", "exit 255")
	// Steps hand git the real stdio. Nobody is reading it, and no tty means the
	// mutating commands need -q, as in a script.
	devNull, err := os.OpenFile(os.DevNull, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	oldIn, oldOut, oldErr := os.Stdin, os.Stdout, os.Stderr
	os.Stdin, os.Stdout, os.Stderr = devNull, devNull, devNull
	t.Cleanup(func() {
		os.Stdin, os.Stdout, os.Stderr = oldIn, oldOut, oldErr
		_ = devNull.Close()
	})

	var out bytes.Buffer
	p := &printer{out: &out, err: &out, in: devNull}
	gitsby := func(args ...string) {
		out.Reset()
		if err := run(p, args); err != nil {
			if code := reportExit(p, err); code != 0 {
				os.Stderr = oldErr
				t.Fatalf("gitsby %v exited %d:\n%s", args, code, out.String())
			}
		}
	}
	touch := func(name string, round int) {
		f, err := os.OpenFile(filepath.Join(clone, name), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		if err != nil {
			t.Fatal(err)
		}
		_, err = fmt.Fprintf(f, "round %d\n", round)
		if cerr := f.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			t.Fatal(err)
		}
	}
	round := func(i int) {
		touch("notes.txt", i)
		gitsby("pullcom", "-q", fmt.Sprintf("notes %d", i))
		gitsby("br", "create", fmt.Sprintf("soak-%d", i), "-q")
		touch("work.txt", i)
		gitsby("sync", "-q", fmt.Sprintf("work %d", i))
		gitsby("br", "merge", "-q", fmt.Sprintf("merge %d", i))
		gitsby("status")
		gitsby("br")
		gitsby("whoami")
		gitsby("br", "prune", "-q")
	}

	started := time.Now()
	var first, second soakReading
	for i := 1; i <= 2*rounds; i++ {
		round(i)
		switch i {
		case rounds:
			first = soakRead(t, i, outDir, -1)
		case 2 * rounds:
			second = soakRead(t, i, outDir, first.goroutines)
		}
	}
	os.Stderr = oldErr
	// A round that quietly did nothing would pass too.
	merges, err := exec.Command("git", "-C", clone, "rev-list", "--count", "--merges", "origin/main").Output()
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(string(merges)); got != strconv.Itoa(2*rounds) {
		t.Fatalf("origin has %s merges after %d rounds", got, 2*rounds)
	}

	grew := int64(second.heapInuse) - int64(first.heapInuse)
	summary := fmt.Sprintf("rounds %d and %d, %v in all\nheap in use: %d -> %d (%+d bytes, margin %d)\ngoroutines: %d -> %d\nwhat grew: go tool pprof -top -base %s %s\n",
		first.round, second.round, time.Since(started).Round(time.Millisecond),
		first.heapInuse, second.heapInuse, grew, soakHeapMargin,
		first.goroutines, second.goroutines,
		soakProfile(outDir, first.round), soakProfile(outDir, second.round))
	if err := os.WriteFile(filepath.Join(outDir, "soak.txt"), []byte(summary), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Log("\n" + summary)
	if grew > soakHeapMargin {
		t.Errorf("the heap grew %d bytes from round %d to %d, past the %d margin", grew, first.round, second.round, soakHeapMargin)
	}
	if second.goroutines > first.goroutines {
		t.Errorf("%d goroutines at round %d, %d at round %d", second.goroutines, second.round, first.goroutines, first.round)
	}
}

// soakRead settles the heap and reads it, and keeps a heap profile for the round.
// A probe the run cancelled can still be on its way out, so the goroutine count gets
// a few seconds to come back down to want; -1 takes whatever it is.
func soakRead(t *testing.T, round int, outDir string, want int) soakReading {
	t.Helper()
	goroutines := runtime.NumGoroutine()
	for deadline := time.Now().Add(5 * time.Second); want >= 0 && goroutines > want && time.Now().Before(deadline); {
		time.Sleep(50 * time.Millisecond)
		goroutines = runtime.NumGoroutine()
	}
	// One GC can leave garbage that a finalizer or a sweep would free on the next.
	runtime.GC()
	runtime.GC()
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	f, err := os.Create(soakProfile(outDir, round))
	if err != nil {
		t.Fatal(err)
	}
	if err := pprof.Lookup("heap").WriteTo(f, 0); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	return soakReading{round: round, heapInuse: stats.HeapInuse, goroutines: goroutines}
}

func soakProfile(outDir string, round int) string {
	return filepath.Join(outDir, fmt.Sprintf("heap-round-%03d.pprof", round))
}
