// Process running. Everything goes out as an argument list, with no shell between. The
// announcing runners hang off the run, since a step invalidates what it cached.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"hash/fnv"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
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

// runOutOK is runOut that also says whether the command worked, for callers that must
// tell a failed tool from an empty answer.
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
// ones in place, so the first line of a two-line answer had a stray carriage
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
// word too, for the plan's message. zsh expands a word that starts with =.
func shellWord(s string, always bool) string {
	if !always && s != "" && !strings.HasPrefix(s, "=") && strings.Trim(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-") == "" {
		return s
	}
	if !strings.ContainsAny(s, "\"$`\\!") {
		return `"` + s + `"`
	}
	return shellQuote(s)
}

// shellQuote single-quotes a word for sh, apostrophes included, so a path in a
// Fix line pastes as one word whatever is in it.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// stepAs announces one thing and runs another, for the gh calls whose real
// argument list has flags the plan never showed - echoing it verbatim would
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
	if hit := findTool(name); hit.path == "" {
		return notInPath(name, hit.ours, hit.batch)
	}
	return nil
}

func inPath(name string) bool {
	return findTool(name).path != ""
}

// notInPath is the refusal for a tool not found, naming any entry passed over
// for being this binary or a batch file, since that is the only reason a user
// can see it there.
func notInPath(tool string, ours, batch []string) error {
	msg := "Not found in path: " + tool
	switch len(ours) {
	case 0:
	case 1:
		msg += fmt.Sprintf(". '%s' is %s itself", ours[0], meName)
	default:
		msg += fmt.Sprintf(". '%s' are %s itself", strings.Join(ours, "', '"), meName)
	}
	switch len(batch) {
	case 0:
	case 1:
		msg += fmt.Sprintf(". '%s' is a batch file, which %s doesn't run, since cmd would read the arguments again", batch[0], meName)
	default:
		msg += fmt.Sprintf(". '%s' are batch files, which %s doesn't run, since cmd would read the arguments again", strings.Join(batch, "', '"), meName)
	}
	if len(ours)+len(batch) > 0 {
		msg += "."
	}
	return usagef("%s", msg)
}

// shadowed is notInPath for the first of names when any of them was passed over
// as this binary or a batch file, and nil otherwise, for a caller with its own
// not-installed text.
func shadowed(names ...string) error {
	var ours, batch []string
	for _, name := range names {
		hit := findTool(name)
		ours = append(ours, hit.ours...)
		batch = append(batch, hit.batch...)
	}
	if len(ours)+len(batch) == 0 {
		return nil
	}
	return notInPath(names[0], ours, batch)
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
		// exec.Command's own look still adds PATHEXT to a path.
		if found, err := exec.LookPath(name); err == nil && batchFile(found) {
			return name, usagef("'%s' is a batch file, which %s doesn't run, since cmd would read the arguments again.", found, meName)
		}
		return name, nil
	}
	hit := findTool(name)
	if hit.path == "" {
		return name, notInPath(name, hit.ours, hit.batch)
	}
	return hit.path, nil
}

func named(cmd *exec.Cmd, name string, missing error) *exec.Cmd {
	cmd.Args[0] = name
	if missing != nil {
		// exec.Command's own look would run the entry that is us.
		cmd.Err = missing
	}
	return cmd
}

// toolCache keeps findTool's answers. PATH is part of the key, since a test may
// change it between runs in one process. Locked, since look-ahead goroutines spawn too.
var toolCache = struct {
	sync.Mutex
	found map[[2]string]toolFound
}{found: map[[2]string]toolFound{}}

// toolFound is a PATH walk's answer: the program, and the entries passed over as
// this binary and as batch files.
type toolFound struct {
	path  string
	ours  []string
	batch []string
}

// findTool is lookTool asked once per name, for every program gitsby runs.
func findTool(name string) toolFound {
	key := [2]string{name, os.Getenv("PATH") + "\x00" + os.Getenv("PATHEXT")}
	toolCache.Lock()
	defer toolCache.Unlock()
	hit, ok := toolCache.found[key]
	if !ok {
		hit = lookTool(name)
		toolCache.found[key] = hit
	}
	return hit
}

// rawActiveVar has the chain of 'raw' runs above this one, for everything 'raw'
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

// FNV, not a crypto hash: the chain only tells one run from another, and
// crypto/sha256 alone pulled in Go's whole FIPS module, 32 MiB of BSS.
func rawHash(parts ...string) string {
	sum := fnv.New64a()
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

// lookTool is exec.LookPath that skips any PATH entry leading back to this binary, by
// link or hardlink, any batch file, and relative entries. Also says what it skipped.
func lookTool(name string) toolFound {
	return walkTool(name, nil)
}

// walkTool is lookTool taking only a candidate take accepts, when take isn't nil.
func walkTool(name string, take func(string) bool) (hit toolFound) {
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
		if batchFile(path) {
			if !slices.Contains(hit.batch, path) {
				hit.batch = append(hit.batch, path)
			}
			continue
		}
		if self != nil {
			if fi, err := os.Stat(path); err == nil && os.SameFile(self, fi) {
				if !slices.Contains(hit.ours, path) {
					hit.ours = append(hit.ours, path)
				}
				continue
			}
		}
		if take != nil && !take(path) {
			continue
		}
		hit.path = path
		return hit
	}
	return hit
}

// batchFile says whether Windows would run path through cmd, which reads the
// command line again by its own rules: an argument holding & runs what follows,
// and %NAME% expands. Go quotes only for the program's own parser, and cmd has no
// quoting that is safe for every argument, so a batch file is passed over like
// gitsby itself (2026111910222873).
func batchFile(path string) bool {
	return runtime.GOOS == "windows" && batchName(path)
}

func batchName(path string) bool {
	ext := filepath.Ext(path)
	return strings.EqualFold(ext, ".bat") || strings.EqualFold(ext, ".cmd")
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
