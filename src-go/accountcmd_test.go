// The includeIf ordering, which is the whole reason 'account apply' exists: git
// takes the LAST rule that matches and gitsby takes the most specific, so the two
// only agree if the plan runs least specific to most.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"strings"
	"testing"
)

func planFor(t *testing.T, body string) *config {
	t.Helper()
	cfg := writeConfig(t, body)
	return cfg
}

func TestAccountApplyPlanOrder(t *testing.T) {
	cfg := planFor(t, `
account.inner.path = /srv/code/client
account.outer.path = /srv/code
account.anywhere.pathContains = a/b
account.broad.pathContains = b
`)
	plan := cfg.accountApplyPlan()
	var conds []string
	for _, r := range plan {
		conds = append(conds, strings.TrimSuffix(strings.TrimPrefix(r.cond, "includeIf.gitdir/i:"), ".path"))
	}
	want := []string{"**/b/**", "**/a/b/**", "/srv/code/", "/srv/code/client/"}
	if len(conds) != len(want) {
		t.Fatalf("plan = %v, want %v", conds, want)
	}
	for i := range want {
		if conds[i] != want[i] {
			t.Fatalf("plan = %v, want %v", conds, want)
		}
	}
}

// Every rule points at the fragment for its own account, beside the config file
// that declared it.
func TestAccountApplyPlanTargets(t *testing.T) {
	cfg := planFor(t, "account.work.path = /srv/work\n")
	plan := cfg.accountApplyPlan()
	if len(plan) != 1 {
		t.Fatalf("plan = %v", plan)
	}
	if want := cfg.includeDir() + "/work.gitconfig"; plan[0].target != want {
		t.Errorf("target = %q, want %q", plan[0].target, want)
	}
	if !strings.HasSuffix(cfg.includeDir(), "/accounts") {
		t.Errorf("includeDir = %q", cfg.includeDir())
	}
}

// An account declared by its keys alone has no folder rule, so there is nothing
// to teach plain git.
func TestAccountApplyPlanEmptyWithoutFolderRules(t *testing.T) {
	cfg := planFor(t, "account.work.ghAccount = octocat\n")
	if plan := cfg.accountApplyPlan(); plan != nil {
		t.Errorf("plan = %v, want none", plan)
	}
}

// Least specific first, and equal specificity backwards: gitsby keeps the FIRST
// rule declared, so that one has to be written LAST for git to keep it too.
func TestSortIncludesTieBreaks(t *testing.T) {
	list := []includeCandidate{
		{weight: 2, order: 0, pattern: "/same/", account: "first"},
		{weight: 1, order: 1, pattern: "/short/", account: "second"},
		{weight: 2, order: 2, pattern: "/same/", account: "third"},
	}
	sortIncludes(list)
	want := []string{"second", "third", "first"}
	for i, name := range want {
		if list[i].account != name {
			t.Fatalf("sorted = %v, want accounts %v", list, want)
		}
	}
}

// The tie-break that matters: whichever account gitsby resolves a folder to has to
// be the one git resolves it to, and git takes the last rule written.
func TestAccountApplyPlanAgreesWithAccountForDir(t *testing.T) {
	cfg := planFor(t, `
account.abe.path = /srv/shared
account.zed.path = /srv/shared
`)
	plan := cfg.accountApplyPlan()
	if len(plan) != 2 {
		t.Fatalf("plan = %v", plan)
	}
	lastWins := plan[len(plan)-1].target
	want := cfg.includeDir() + "/" + cfg.accountForDir("/srv/shared/x") + ".gitconfig"
	if lastWins != want {
		t.Errorf("git would keep %q, gitsby resolves to %q", lastWins, want)
	}
}

// Two accounts on one folder is a mistake with no right answer, so it gets said
// out loud rather than settled silently.
func TestContestedRules(t *testing.T) {
	cfg := planFor(t, `
account.abe.path = /srv/shared
account.zed.path = /srv/shared
account.abe.pathContains = w/x
account.zed.pathContains = w/x
account.solo.path = /srv/mine
`)
	got := cfg.contestedRules()
	want := []string{"/srv/shared: abe, zed", "w/x: abe, zed"}
	if len(got) != len(want) {
		t.Fatalf("contestedRules = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("contestedRules = %v, want %v", got, want)
		}
	}
}

// What 'account list' says about an account, which is where you go when a command
// did not act as the one you expected. The host key decides whether any of the
// credentials below it apply at all, so leaving it off the listing meant the
// command that always says was silent about the only field that had refused.
func TestAccountListNamesTheHost(t *testing.T) {
	a := newApp(newPrinter())
	var buf strings.Builder
	a.out.out = &buf
	a.cfg = writeConfig(t, `
account.gitea.host = git.example.test
account.gitea.user = giteauser
account.hub.ghAccount = hublogin
`)
	a.showAccount("gitea", false)
	a.showAccount("hub", false)
	got := buf.String()
	for _, want := range []string{
		"host ....: git.example.test",      // stated
		"login ...: giteauser",             // the host-neutral login, shown where there is one
		"host ....: github.com  (default)", // unstated, and marked as the assumption it is
	} {
		if !strings.Contains(got, want) {
			t.Errorf("account list is missing %q:\n%s", want, got)
		}
	}
	// 'login' is the 'user' key, not a second spelling of the GitHub one - printing it
	// for an account that never set it would invent a login for every existing config.
	if strings.Contains(got, "login ...: hublogin") {
		t.Errorf("the GitHub login was printed as 'login':\n%s", got)
	}
}

// The host line is a comparison, so it appears only where there is something to
// compare. A machine that only ever talks to github.com reads exactly as it did
// before the key existed - the same rule the Account status line follows, which
// stays quiet unless an account was explicitly selected.
func TestAccountListHidesTheHostOnOneForge(t *testing.T) {
	a := newApp(newPrinter())
	var buf strings.Builder
	a.out.out = &buf
	a.cfg = writeConfig(t, `
account.work.ghAccount = worklogin
account.home.ghAccount = homelogin
`)
	a.showAccount("work", false)
	if strings.Contains(buf.String(), "host") {
		t.Errorf("a single-forge config was shown the host key:\n%s", buf.String())
	}
}
