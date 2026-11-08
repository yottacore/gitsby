//go:build linux || darwin || freebsd || netbsd || openbsd || dragonfly

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

// termCols is the terminal's width as the kernel holds it, 0 when it can't say.
// A pty nobody sized reports 0 too, and tput then answers from terminfo.
func termCols(f *os.File) int {
	var size struct{ rows, cols, xpixel, ypixel uint16 }
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&size)))
	if errno != 0 {
		return 0
	}
	return int(size.cols)
}
