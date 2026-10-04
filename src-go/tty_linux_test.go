//go:build linux

// The terminal's width comes from the kernel where it can say, with no tput.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"strconv"
	"syscall"
	"testing"
	"unsafe"
)

func ioctl(t *testing.T, f *os.File, request uintptr, arg unsafe.Pointer) {
	t.Helper()
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), request, uintptr(arg)); errno != 0 {
		t.Skipf("no pty here: %v", errno)
	}
}

func TestTerminalWidthAsksTheKernel(t *testing.T) { // [Erl3JlD]
	ptmx, err := os.OpenFile("/dev/ptmx", os.O_RDWR, 0)
	if err != nil {
		t.Skipf("no pty here: %v", err)
	}
	t.Cleanup(func() { _ = ptmx.Close() }) // read-only use; nothing to lose on close
	var unlock int32
	ioctl(t, ptmx, syscall.TIOCSPTLCK, unsafe.Pointer(&unlock))
	var ptyNum uint32
	ioctl(t, ptmx, syscall.TIOCGPTN, unsafe.Pointer(&ptyNum))
	pts, err := os.OpenFile("/dev/pts/"+strconv.Itoa(int(ptyNum)), os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		t.Skipf("no pty here: %v", err)
	}
	t.Cleanup(func() { _ = pts.Close() })
	size := struct{ rows, cols, xpixel, ypixel uint16 }{40, 132, 0, 0}
	ioctl(t, pts, syscall.TIOCSWINSZ, unsafe.Pointer(&size))
	tputLog := logCalls(t, "tput", "echo 80")
	t.Setenv("TERM", "xterm")
	stdout := os.Stdout
	os.Stdout = pts
	defer func() { os.Stdout = stdout }()
	got := newApp(newPrinter()).terminalWidth()
	os.Stdout = stdout
	if got != 132 {
		t.Errorf("terminalWidth() = %d, want 132", got)
	}
	if n := callsTo(t, tputLog, ""); n != 0 {
		t.Errorf("tput ran %d times with the kernel holding the width", n)
	}
	// A pty nobody sized says 0, and tput answers then.
	size.cols = 0
	ioctl(t, pts, syscall.TIOCSWINSZ, unsafe.Pointer(&size))
	os.Stdout = pts
	got = newApp(newPrinter()).terminalWidth()
	os.Stdout = stdout
	if got != 80 || callsTo(t, tputLog, "cols") != 1 {
		t.Errorf("with no width from the kernel, terminalWidth() = %d and tput ran %d times, want 80 and 1", got, callsTo(t, tputLog, "cols"))
	}
}
