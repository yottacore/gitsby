// Output. The blank-line counter is what keeps the section rhythm: repeated blanks
// collapse to one, so callers can ask for breathing room without coordinating with
// each other. Held on a value rather than in package state, so a test can read back
// what a command printed.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
)

// A write to the terminal that fails has nowhere left to report it, and the next
// one would fail the same way - so every write here discards its error on purpose.
type printer struct {
	out       io.Writer
	err       io.Writer
	in        io.Reader
	lastBlank bool
}

func newPrinter() *printer {
	return &printer{out: os.Stdout, err: os.Stderr, in: os.Stdin}
}

func (p *printer) resetBlank() { p.lastBlank = false }

// clean prints a plain line; an empty one only lands when the previous line was
// not already blank.
func (p *printer) clean(s string) {
	if s != "" {
		_, _ = fmt.Fprintln(p.out, s)
		p.lastBlank = false
		return
	}
	if !p.lastBlank {
		_, _ = fmt.Fprintln(p.out)
		p.lastBlank = true
	}
}

func (p *printer) cleanf(format string, a ...any) { p.clean(fmt.Sprintf(format, a...)) }

// forceClean lands a blank even directly after another one, for the framing that
// has to be a fixed number of lines rather than a rhythm.
func (p *printer) forceClean(s string) {
	p.resetBlank()
	p.clean(s)
}

// status prints a bracketed status line - the scripts' fEcho.
func (p *printer) status(s string) {
	if s == "" {
		p.clean("")
		return
	}
	p.clean("[ " + s + " ]")
}

// errorf writes to stderr, prefixed the way every message from here is.
func (p *printer) errorf(format string, a ...any) {
	_, _ = fmt.Fprintln(p.err, meName+": "+fmt.Sprintf(format, a...))
}

// confirm gates every mutation. Only 'y' or 'yes' is yes: a typo, a stray
// newline, or an EOF is a no, because the fallback has to be the harmless answer.
func (p *printer) confirm(prompt string) bool {
	_, _ = fmt.Fprint(p.out, prompt)
	answer, _ := bufio.NewReader(p.in).ReadString('\n')
	p.resetBlank()
	switch strings.ToLower(strings.TrimSpace(answer)) {
	case "y", "yes":
		return true
	}
	return false
}
