// Process running. Everything goes out as an argument list - no shell between, so
// word splitting and expansion cannot happen to user values on the way to a tool.
// The plain readers are free functions because they hold nothing; the announcing
// runners hang off the run, because a step we announce is exactly the thing that
// invalidates what the run has cached.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
)

// runOut captures a command's stdout, trimmed. Any failure is simply no output -
// most callers treat empty as "no answer", never as an error to report.
func runOut(name string, args ...string) string {
	out, _ := runOutOK(name, args...)
	return out
}

// runOutOK is runOut that also says whether the command worked, for the few
// callers that must tell "the tool failed" apart from "the answer is nothing".
// gh in particular exits nonzero for a repo that isn't there and for a network
// that is down, and stating the first when it was the second sends you off to
// create something that already exists.
func runOutOK(name string, args ...string) (string, bool) {
	out, err := toolCmd(name, args...).Output()
	if err != nil {
		return "", false
	}
	return strings.TrimRight(string(out), "\r\n"), true
}

// runOK is the exit-code question: did it succeed at all.
func runOK(name string, args ...string) bool {
	return toolCmd(name, args...).Run() == nil
}

// splitLines cuts captured output into lines. The trailing '\r' comes off every
// one of them: trimming only the end of the whole capture leaves the interior
// ones in place, so the first line of a two-line answer carried a stray carriage
// return that no later comparison could match.
func splitLines(out string) []string {
	lines := strings.Split(out, "\n")
	for i, line := range lines {
		lines[i] = strings.TrimRight(line, "\r")
	}
	return lines
}

// runLines is runOut split into lines, empties dropped.
func runLines(name string, args ...string) []string {
	all := splitLines(runOut(name, args...))
	lines := make([]string, 0, len(all))
	for _, line := range all {
		if line != "" {
			lines = append(lines, line)
		}
	}
	return lines
}

// exitCode reads a failed command's status. A tool that never started counts as
// a plain failure - the PATH check upstream is what catches a missing one.
func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return 1
}

// stdio wires a command to our own streams, for the ones whose output IS the
// point.
func stdio(cmd *exec.Cmd) *exec.Cmd {
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd
}

// inherit streams a command straight to our stdio and carries on regardless -
// for listings whose output IS the point and whose failure has nothing to add.
func (a *app) inherit(name string, args ...string) {
	a.git.forget()
	_ = stdio(toolCmd(name, args...)).Run()
}

// inheritRC is inherit that reports the exit code, for the callers that print it.
func (a *app) inheritRC(name string, args ...string) int {
	a.git.forget()
	return exitCode(stdio(toolCmd(name, args...)).Run())
}

// inheritOK is inherit that still answers whether it worked - for the steps whose
// failure is survivable but worth a word (a remote branch somebody else already
// deleted).
func (a *app) inheritOK(name string, args ...string) bool {
	return a.inheritRC(name, args...) == 0
}

// step announces and runs a command verbatim, with our stdio - the scripts' fRun.
// Display copy is masked per argument, so a credentialed URL never prints its
// token in the announcement or the failure.
func (a *app) step(name string, args ...string) error {
	disp := maskURL(name)
	for i, arg := range args {
		disp += " " + shellWord(maskURL(arg), i > 0 && args[i-1] == "-m") // as the plan shows it
	}
	return a.stepAs(disp, disp, name, args...)
}

// shellWord quotes an argument for display so a pasted line runs as shown.
// Double quotes where nothing inside them expands, since the plan has always
// shown a message that way; single quotes otherwise. always quotes a plain
// word too, for the plan's message.
func shellWord(s string, always bool) string {
	if !always && s != "" && strings.Trim(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-") == "" {
		return s
	}
	if !strings.ContainsAny(s, "\"$`\\!") {
		return `"` + s + `"`
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// stepAs announces one thing and runs another, for the gh calls whose real
// argument list carries flags the plan never showed - echoing it verbatim would
// contradict the preview. The failure names the command, not the arguments.
func (a *app) stepAs(announce, label, name string, args ...string) error {
	a.out.clean("")
	a.out.status(announce + " ...")
	if rc := a.inheritRC(name, args...); rc != 0 {
		return &stepError{disp: label, code: rc}
	}
	a.out.resetBlank()
	return nil
}

func mustBeInPath(name string) error {
	if path, ours := findTool(name); path == "" {
		return notInPath(name, ours)
	}
	return nil
}

func inPath(name string) bool {
	path, _ := findTool(name)
	return path != ""
}

// notInPath is the refusal for a tool not found, naming any entry passed over
// for being this binary, since that is the only reason a user can see it there.
func notInPath(tool string, ours []string) error {
	switch len(ours) {
	case 0:
		return usagef("Not found in path: %s", tool)
	case 1:
		return usagef("Not found in path: %s. '%s' is %s itself.", tool, ours[0], meName)
	}
	return usagef("Not found in path: %s. '%s' are %s itself.", tool, strings.Join(ours, "', '"), meName)
}

// shadowed is notInPath for the first of names when any of them was passed over
// as this binary, and nil otherwise, for a caller with its own not-installed text.
func shadowed(names ...string) error {
	var ours []string
	for _, name := range names {
		_, skipped := findTool(name)
		ours = append(ours, skipped...)
	}
	if len(ours) == 0 {
		return nil
	}
	return notInPath(names[0], ours)
}

// toolCmd is exec.Command with the program found by findTool, so nothing gitsby
// runs by name can be gitsby again (2026102111572785). Every spawn goes through it
// or toolCmdContext. The program keeps its own name as argv[0]. A name with a
// path in it is run as given.
func toolCmd(name string, args ...string) *exec.Cmd {
	path, missing := toolPath(name)
	return named(exec.Command(path, args...), name, missing)
}

func toolCmdContext(ctx context.Context, name string, args ...string) *exec.Cmd {
	path, missing := toolPath(name)
	return named(exec.CommandContext(ctx, path, args...), name, missing)
}

// toolPath is what toolCmd runs for name, or name itself and why not.
func toolPath(name string) (string, error) {
	if filepath.Base(name) != name {
		return name, nil
	}
	found, ours := findTool(name)
	if found == "" {
		return name, notInPath(name, ours)
	}
	return found, nil
}

func named(cmd *exec.Cmd, name string, missing error) *exec.Cmd {
	cmd.Args[0] = name
	if missing != nil {
		// exec.Command's own look would run the entry that is us.
		cmd.Err = missing
	}
	return cmd
}

// toolCache holds findTool's answers. PATH is part of the key, since a test may
// change it between runs in one process. Locked, since look-ahead goroutines spawn too.
var toolCache = struct {
	sync.Mutex
	found map[[2]string]toolFound
}{found: map[[2]string]toolFound{}}

type toolFound struct {
	path string
	ours []string
}

// findTool is lookTool asked once per name, for every program gitsby runs.
func findTool(name string) (string, []string) {
	key := [2]string{name, os.Getenv("PATH")}
	toolCache.Lock()
	defer toolCache.Unlock()
	hit, ok := toolCache.found[key]
	if !ok {
		hit.path, hit.ours = lookTool(name)
		toolCache.found[key] = hit
	}
	return hit.path, hit.ours
}

// rawActiveVar holds the chain of 'raw' runs above this one, for everything 'raw'
// starts. A 'raw' passes over a tool file whose run is already on it and takes
// the next one on PATH, so a hook or alias calling 'gitsby raw' works, and so does
// a wrapper on PATH that calls us back (2026101916533300, 2026102306584122).
const rawActiveVar = "GITSBY_RAW_ACTIVE"

// rawDepthMax stops a loop whose arguments change each time. No real hook stack
// nests this deep.
const rawDepthMax = 16

// rawProbing ends the chain while 'raw' runs tools only to check them, before the
// handover. Nothing those start has a reason to call 'raw', so a 'raw' under it
// passes over every tool file on the chain whatever its arguments, and does no
// account work, so its probes can't multiply.
const rawProbing = "probe"

// rawEntry is one 'raw' run on the chain: the tool's name, a short hash of its
// path, and one of its path, the folder and the arguments, so the variable stays
// small and a probe can match the file alone.
func rawEntry(name, path string, args []string) string {
	cwd, _ := os.Getwd() // couldn't tell hashes the same every level
	return name + ":" + rawHash(path) + ":" + rawHash(append([]string{path, cwd}, args...)...)
}

func rawHash(parts ...string) string {
	sum := sha256.New()
	for _, part := range parts {
		sum.Write([]byte(part))
		sum.Write([]byte{0})
	}
	return hex.EncodeToString(sum.Sum(nil)[:6])
}

// rawProbed says whether chain ends in the probe mark.
func rawProbed(chain string) bool {
	above := strings.Fields(chain)
	return len(above) > 0 && above[len(above)-1] == rawProbing
}

// rawOnChain says whether entry is already running above: the same run, or under
// the probe mark the same tool file.
func rawOnChain(chain, entry string) bool {
	probing := rawProbed(chain)
	file := entry[:strings.LastIndexByte(entry, ':')+1]
	for _, above := range strings.Fields(chain) {
		if above == entry || (probing && strings.HasPrefix(above, file)) {
			return true
		}
	}
	return false
}

// rawNest is chain with entry added, keeping any probe mark last, or the refusal
// past rawDepthMax.
func rawNest(chain, name, entry string) (string, error) {
	above := strings.Fields(chain)
	probing := rawProbed(chain)
	if probing {
		above = above[:len(above)-1]
	}
	if len(above) >= rawDepthMax {
		return "", usagef("Looping: 'raw %s' would be %d deep under other 'raw' runs. A tool that calls '%s raw' with new arguments each time does that.", name, len(above)+1, meName)
	}
	above = append(above, entry)
	if probing {
		above = append(above, rawProbing)
	}
	return strings.Join(above, " "), nil
}

// lookTool is exec.LookPath that skips any PATH entry leading back to this very
// binary, through a symlink or a hardlink. Each candidate still goes through
// LookPath, so PATHEXT and the exec bit work as before. A relative entry is
// skipped, since LookPath's ErrDot never let one run. Also returns the entries
// skipped as ours.
func lookTool(name string) (found string, ours []string) {
	return walkTool(name, nil)
}

// walkTool is lookTool taking only a candidate take accepts, when take isn't nil.
func walkTool(name string, take func(string) bool) (found string, ours []string) {
	var self os.FileInfo
	if exe, err := os.Executable(); err == nil {
		self, _ = os.Stat(exe) // couldn't tell is not "it's us"
	}
	for _, dir := range filepath.SplitList(os.Getenv("PATH")) {
		if dir == "" || !filepath.IsAbs(dir) {
			continue
		}
		path, err := exec.LookPath(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		if self != nil {
			if fi, err := os.Stat(path); err == nil && os.SameFile(self, fi) {
				if !slices.Contains(ours, path) {
					ours = append(ours, path)
				}
				continue
			}
		}
		if take != nil && !take(path) {
			continue
		}
		return path, ours
	}
	return "", ours
}

// handover runs the tool with our stdio and leaves with its exit code - the
// portable stand-in for the scripts' exec, which cannot exist on Windows. path is
// what runs; the tool still sees name as its argv[0].
func (a *app) handover(name, path string, args []string) error {
	cmd := exec.Command(path, args...)
	cmd.Args[0] = name
	if err := stdio(cmd).Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return silentExit(exitErr.ExitCode())
		}
		// Whether it exists was settled before the handover, so whatever this is,
		// it isn't that.
		return usageWrapf(err, "Couldn't run '%s'", name)
	}
	return silentExit(0)
}
