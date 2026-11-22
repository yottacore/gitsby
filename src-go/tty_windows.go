//go:build windows

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

// isTTY answers the scripts' '[[ -t 0 ]]': a console handle accepts a
// console-mode query; files, pipes and NUL do not.
func isTTY(f *os.File) bool {
	var mode uint32
	return syscall.GetConsoleMode(syscall.Handle(f.Fd()), &mode) == nil
}

var procGetConsoleScreenBufferInfo = syscall.NewLazyDLL("kernel32.dll").NewProc("GetConsoleScreenBufferInfo")

// termCols is the console window's width, 0 when f isn't a console. The
// window, not the buffer, since a buffer can be wider than what shows.
func termCols(f *os.File) int {
	var info struct {
		size, cursor             struct{ x, y int16 }
		attributes               uint16
		left, top, right, bottom int16
		maxSize                  struct{ x, y int16 }
	}
	if ok, _, _ := procGetConsoleScreenBufferInfo.Call(f.Fd(), uintptr(unsafe.Pointer(&info))); ok == 0 {
		return 0
	}
	return int(info.right) - int(info.left) + 1
}
