// A goroutine still running once every test has finished fails the run, whoever
// started it. Per-test checks can't sit beside t.Parallel, so it's the whole run.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"testing"

	"go.uber.org/goleak"
)

// Suppressions go here by function name only, with the backlog ID beside each.
func TestMain(m *testing.M) { // [Et9PJqa]
	goleak.VerifyTestMain(m)
}
