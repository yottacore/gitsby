// One run of gitsby, and the answers it accumulates. Everything a command needs
// arrives through here rather than through package state: what was asked for, what
// has been settled about the repo and the account, and where the output goes.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"context"
	"os"
)

// cached remembers one answer that costs a process to ask for, and keeps "not
// asked yet" apart from "asked, and the answer is nothing" - which is the
// difference between one lookup and the same five over and over.
type cached[T any] struct {
	value T
	known bool
}

func (c *cached[T]) get(ask func() T) T {
	if !c.known {
		c.value, c.known = ask(), true
	}
	return c.value
}

func (c *cached[T]) set(value T) {
	c.value, c.known = value, true
}

func (c *cached[T]) forget() {
	var zero T
	c.value, c.known = zero, false
}

// ahead is an answer worked out on a goroutine of its own, for a round trip the
// run would otherwise sit and wait on in turn. The goroutine touches nothing but
// its own fields, and ends when ask does; ask runs its child under the run's probe
// context, so the end of the run kills one nobody read.
type ahead[T any] struct {
	done  chan struct{}
	value T
}

func startAhead[T any](ask func() T) *ahead[T] {
	pending := &ahead[T]{done: make(chan struct{})}
	go func() {
		defer close(pending.done)
		pending.value = ask()
	}()
	return pending
}

func (p *ahead[T]) wait() T {
	<-p.done
	return p.value
}

// options is everything the parser can be told. The whole vocabulary is taken
// from day one so no spelling is refused now and accepted later.
type options struct {
	message     string
	quiet       bool // -q/--quiet/-y: no prompts, no banner
	fetch       bool // cleared by --no-fetch
	visibility  string
	anyIdentity bool // a gh/ssh account mismatch here is intended
	direct      bool // sync straight to main/master/dev is intended
	staged      bool // commit the index only, and leave the rest of the tree
	configFile  string
	configGiven bool // whether it was typed at all: '--config ""' is a mistake, not a fallback
	sawPublic   bool
	sawPrivate  bool
	sawQuiet    bool // quiet as typed, before the no-tty rule sets it for its own reasons
}

// command is the resolved command and its positional arguments, after the
// grouped-noun collapse has folded '<noun> <verb>' into one flat name.
type command struct {
	name     string
	arg      string // subcommand for a grouped noun, else message/branch/version/PR number
	arg2     string
	arg3     string // 'repo clone <url> [dir]', and 'account set' after the noun shift
	arg4     string // only 'account <set> <name> <key> <value>' goes this deep
	mutating bool
}

// repoState holds the answers a run asks git for more than once. Each is asked
// once and remembered; a step that could move any of them forgets them on its
// way out, so the after-shot reads what the step left behind rather than what
// preceded it.
type repoState struct {
	originURL      cached[string]
	originRef      cached[remoteRef]
	coreSSHCommand cached[string]
	currentBranch  cached[string]
	upstream       cached[upstreamRef]
	branches       cached[branchRefs]
	originHead     cached[string]
	ownTokenFile   cached[string]
	aheadBehind    cached[[2]int]
	contextDir     cached[string]
	defaultBranch  cached[string]
	mergeTarget    cached[string]
}

// forget drops every answer a step could have invalidated. The two branch names
// are deliberately not among them: main settles both once, post-fetch, and no
// step of ours renames a default branch or invents a dev.
func (r *repoState) forget() {
	r.originURL.forget()
	r.originRef.forget()
	r.coreSSHCommand.forget()
	r.currentBranch.forget()
	r.upstream.forget()
	r.branches.forget()
	r.originHead.forget()
	r.ownTokenFile.forget()
	r.aheadBehind.forget()
	r.contextDir.forget()
}

// hostState is what this run knows about the host side of things, as opposed to
// the account side: which CLI is installed for the git host origin lives on. Looking
// it up is two LookPath calls for a name that cannot change mid-run.
type hostState struct {
	tea   cached[string]     // Gitea's CLI as this machine spells it, "" when absent
	login cached[hostAnswer] // who that CLI holds a login for on origin's host
}

// remoteState is what this run knows about origin and who it talks to origin as:
// whether the pre-command fetch reached it, which git host CLI the command goes
// through, that CLI's own account, and whoever a remote's ssh key authenticates
// as. The accounts cost a live round trip, so each is asked at most once.
type remoteState struct {
	isCommand bool     // goes through a git host CLI at all -> show whose account that is
	isWrite   bool     // WRITES through one -> also compare against the ssh key
	tool      hostTool // which CLI that is
	cli       string   // and how this machine spells it
	probeURL  string   // the url the ssh identity is read from
	offline   bool     // set when the pre-command fetch can't reach origin; read it through isOffline
	login     cached[string]
	protocol  cached[string]
	// Keyed by remote: one slot answered for whichever url asked first, and three
	// callers ask about three different ones in the same run.
	sshLogins map[string]string
	// The same two questions, already asked and not yet read. Each probe is a
	// network round trip, and in turn the identity block waited on the sum of them.
	loginAhead *ahead[string]
	sshAhead   map[string]*ahead[string]
	// Keyed by login: the listing asks after every account that names one, and
	// 'account set' prints that listing before its own edit, so the same names come
	// round more than once. Nothing logs gh in or out mid-run, and the answer is
	// keyed by the login rather than by whoever gh currently acts as.
	tokens map[string]string
}

// account is who this run acts as, and what selecting them actually changed.
type account struct {
	name     string // configured account claiming this folder, if any
	ghWho    string // the GitHub account this run acts as
	source   string // how we decided that, for the identity line
	pickedBy string // why THIS one of several, where the source doesn't say
	explicit bool
	applied  bool

	// What the selection applied, read back by the identity block.
	noToken       bool
	fromFile      bool // the account came from the accounts file, so a fix that edits it needs no second path
	usedHTTPSAuth bool
	usedSSHKey    string
	usedIdentity  bool
	switchedFrom  string
	// --any-identity: nothing was selected at all, and the block must not read as
	// though it had been.
	bypassed bool
	// Whether to ask who a file-sourced token actually authenticates as. The name
	// above came from a config key, which a stale file will happily agree with.
	checkTokenWho bool
	// A token file other users on this machine can read, named so it can be fixed.
	looseTokenFile string

	// The git host this run authenticates to, the variable its token was exported
	// under, and whether the account we resolved banks somewhere else entirely.
	credHost  string
	tokenEnv  string
	otherHost bool
}

// app is one run. The command functions take it rather than reach for package
// state, so any of them can be called twice - or from a test - without the second
// call inheriting the first one's answers.
type app struct {
	opt    options
	cmd    command
	out    *printer
	cfg    *config
	acct   account
	git    repoState
	remote remoteState
	host   hostState

	inRepo bool

	// Whether GIT_SSH_COMMAND was already set when the run started. Ours goes into
	// the same variable a moment later, and the probes have to be able to tell the
	// two apart: a value the caller chose is left exactly as typed, where our own
	// still wants the connect timeout that stops a dead remote hanging every command.
	userSSHCommand bool

	// The stamp a quiet commit falls back to with no message and no editor.
	stamp string

	// What each command settled before its plan was shown.
	prune prunePlan
	rel   releasePlan
	tgt   repoTarget
	pr    prRequest
	set   *accountSetTarget
	split *treeSplit // --staged only

	// Set by showList; callers that need "was it empty?" read it back.
	lastListCount int
	// Measured once: measuring twice in one run would only let the plan and the
	// after-shot wrap differently.
	termWidth cached[int]

	// Ends with the run, and takes any probe still going with it.
	probeCtx  context.Context
	probeStop context.CancelFunc
}

func newApp(out *printer) *app {
	return &app{
		out:   out,
		cfg:   &config{values: map[string]string{}},
		opt:   defaultOptions(),
		cmd:   command{mutating: true},
		stamp: stampNow(),

		userSSHCommand: os.Getenv("GIT_SSH_COMMAND") != "",
	}
}

// probeContext is what a probe started ahead runs under. Made on first use, so an
// app built bare in a test still has one.
func (a *app) probeContext() context.Context {
	if a.probeCtx == nil {
		a.probeCtx, a.probeStop = context.WithCancel(context.Background())
	}
	return a.probeCtx
}

// endProbes kills whatever was asked ahead and never read: a refusal can end the
// run before the line that wanted the answer prints.
func (a *app) endProbes() {
	if a.probeStop != nil {
		a.probeStop()
	}
}
