// gitsby, compiled. Built out against cicd/test.bash from the first commit; commands land
// slice by slice, so anything not here yet says so and exits nonzero rather than guessing.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"
)

// Set at build time: -ldflags "-X main.version=x.y.z". The bare default marks a
// hand-run 'go build' apart from a pipeline build.
var version = "0.0.0-dev"

const (
	copyrightYear = "2026"
	author        = "Jim Collier"
)

func printCopyright() {
	fmt.Printf("\ngitsby v%s, Copyright © %s %s.\n", version, copyrightYear, author)
	fmt.Println("Licensed under The MIT License (MIT). Full text at:")
	fmt.Println("  https://mit-license.org/")
	fmt.Println("No Warranty.")
	fmt.Println()
}

func main() {
	if len(os.Args) >= 2 {
		switch os.Args[1] {
		case "-v", "--ver", "--version", "version":
			printCopyright()
			return
		}
	}
	fmt.Fprintln(os.Stderr, "gitsby: this build does not do that yet")
	os.Exit(2)
}
