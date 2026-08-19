//go:build !linux && !windows && !darwin && !freebsd && !netbsd && !openbsd && !dragonfly

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import "os"

// isTTY, best effort on a platform nothing here is built for: a character device.
// Wrong for /dev/null, which is why every platform gitsby actually publishes has
// the real terminal query instead - Linux, Windows, macOS and the BSDs each in
// their own file.
func isTTY(f *os.File) bool {
	fi, err := f.Stat()
	return err == nil && fi.Mode()&os.ModeCharDevice != 0
}
