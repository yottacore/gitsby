// The build number: minutes elapsed since 2000-01-01 UTC, Crockford base32, lower
// case. Five characters until 2063. Stamped at build time from the source commit's
// date rather than the clock, so the same commit always builds to the same bytes.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Set at build time: -ldflags "-X main.buildEpoch=<unix seconds>". Empty on a hand
// -run 'go build', which then reports no build number at all rather than inventing
// one - a number that moved every minute would say the opposite of what it means.
var buildEpoch = ""

// 2000-01-01T00:00:00Z as unix seconds.
const epoch2000 = 946684800

// Crockford's alphabet: no I, L, O or U, so nothing in a build number can be
// misread aloud or retyped as something else.
const crockford32 = "0123456789abcdefghjkmnpqrstvwxyz"

// buildNumber is the stamped seconds as minutes since 2000, base32. Anything before
// 2000, unparseable, or unstamped gives "", which every caller reads as "no build
// number" rather than as zero.
func buildNumber() string {
	secs, ok := buildSecs()
	if !ok {
		return ""
	}
	return crockfordBase32((secs - epoch2000) / 60)
}

func buildSecs() (int64, bool) {
	if buildEpoch == "" {
		return 0, false
	}
	secs, err := strconv.ParseInt(buildEpoch, 10, 64)
	return secs, err == nil && secs >= epoch2000
}

func crockfordBase32(n int64) string {
	if n == 0 {
		return "0"
	}
	var digits []byte
	for n > 0 {
		digits = append(digits, crockford32[n%32])
		n /= 32
	}
	// Built least significant first.
	for i, j := 0, len(digits)-1; i < j; i, j = i+1, j-1 {
		digits[i], digits[j] = digits[j], digits[i]
	}
	return string(digits)
}

// What git describe adds past a tag: commits since it and the hash, or edits.
var describeTailRE = regexp.MustCompile(`-[0-9]+-g[0-9a-f]{4,}(-dirty)?$|-dirty$`)

// isReleaseVersion is true for a tag's own version, 2.1.0 or 3.0.0-beta.1. A build
// past a tag, a bare hash from a repo with no tags, and the 0.0.0 stand-ins aren't.
func isReleaseVersion(v string) bool {
	return releaseVerRE.MatchString(v) && !describeTailRE.MatchString(v) && !strings.HasPrefix(v, "0.0.0")
}

// versionText is "v2.1.0 build dbrk8", or just the version where nothing stamped a
// build. Between releases the commit's date follows, in the viewer's time zone
// can't be read as a date by eye.
func versionText() string {
	b := buildNumber()
	if b == "" {
		return "v" + version
	}
	if isReleaseVersion(version) {
		return "v" + version + " build " + b
	}
	secs, _ := buildSecs()
	return "v" + version + " build " + b + " (" + time.Unix(secs, 0).Local().Format("2006-01-02") + ")"
}
