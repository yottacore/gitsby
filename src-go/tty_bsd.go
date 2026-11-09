//go:build darwin || freebsd || netbsd || openbsd || dragonfly

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"syscall"
	"unsafe"
)

// isTTY answers the scripts' '[[ -t 0 ]]' on the BSDs and macOS by the terminal query,
// TIOCGETA, since a character-device test passes for /dev/null.
func isTTY(f *os.File) bool {
	var t syscall.Termios
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), syscall.TIOCGETA, uintptr(unsafe.Pointer(&t)))
	return errno == 0
}
