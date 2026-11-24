// pr's argument shape, the read-only views, and the two writers. What a PR merges
// into - and whether it is a hotfix - are properties of the PR, not of the branch
// you happen to be standing on, so 'pr ok' asks gh rather than reading HEAD.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

// prRequest is which pull request this run is about, settled before any plan is
// shown.
type prRequest struct {
	sub        string // "create" or "ok"; empty for the bare list and the numeric view
	num        string
	title      string
	headBranch string   // the PR's branch: read from the host for ok, from the push for create
	baseBranch string   // what the PR merges into, as the git host has it: ok only
	fork       bool     // headBranch is on another repo, such as a fork, not origin: ok only
	tool       hostTool // which CLI answers for this repo's host
	cli        string   // that tool as this machine spells it
}

var prNumRE = regexp.MustCompile(`^[0-9]+$`)

// sortPr validates pr's own arguments - before the repo gate, same as the
// scripts: a malformed pr call is wrong anywhere, in a repo or not.
func (a *app) sortPr() error {
	// Shape only. Which tool answers waits for the host, which isn't known until we're
	// in a repo with a remote.
	switch strings.ToLower(a.cmd.arg) {
	case "ok":
		a.pr.sub, a.pr.num = "ok", a.cmd.arg2
		if !prNumRE.MatchString(a.pr.num) {
			return usageOf("pr ok").refuse("")
		}
	case "create":
		a.pr.sub = "create"
		a.pr.title = a.opt.message // sortCommand refused -m beside a typed title
		if a.pr.title == "" {
			a.pr.title = a.cmd.arg2
		}
	case "":
	default: // a number, since collapseCommand refused anything else
		a.pr.num = a.cmd.arg
	}
	return nil
}

// settlePrTool works out which CLI can answer for this repo, and refuses with the
// real reason when none can. Ordered deliberately - host first, tool second: asked
// the other way round, a Gitea repo was told to install a GitHub client it would
// never use, and the answer never mentioned the host that decided it.
func (a *app) settlePrTool() error {
	if !a.hasOrigin() {
		return usagef("No 'origin' remote, so there is nowhere to open a pull request. Connect one first: %s repo connect <url>, or <owner/name> for a GitHub repo.", meName)
	}
	a.pr.tool, a.pr.cli = a.originTool()
	if a.pr.tool == toolGlab && !a.acct.bypassed {
		// The account's token and host, so glab needs no login of its own.
		a.glabTokenEnv(nil)
	}
	if a.pr.tool != toolNone {
		return nil
	}
	// A host we could name, and nothing here that speaks to it. When the tool's
	// name on PATH is only this binary, that is the thing to say, not "install it".
	if host := a.originHost(); host != "" {
		want := teaNames
		if isGitHubHost(host) {
			want = []string{"gh"}
		} else if isGitLabHost(host) {
			want = []string{"glab"}
		}
		if err := shadowed(want...); err != nil {
			return err
		}
		return usagef("Nothing installed here can talk to %s. %s", host, a.hostCLIHint())
	}
	// No host to name. Not a refusal, since a remote we don't understand never triggers
	// one. gh gets the last word, and explains itself if the remote isn't one it serves.
	if inPath("gh") {
		a.pr.tool, a.pr.cli = toolGh, "gh"
		return nil
	}
	if err := shadowed("gh"); err != nil {
		return err
	}
	return usagef("Can't tell which git host '%s' is, and no CLI for one is installed to ask. %s",
		maskURL(a.originURL()), a.hostCLIHint())
}

// The pull-request vocabulary, per tool. Every caller - the preview and the
// command alike - spells its operation through these, so the plan and the run
// cannot describe different things.

// teaDetailFields is what 'pr <n>' shows on Gitea. gh answers the same question
// with two commands, view then diff; tea has the diff as a field of the detail
// view, so one call covers both.
const teaDetailFields = "index,title,state,author,base,head,url,body,diff"

// glabArgs adds the repo, for the reason glabRepoArg gives.
func (a *app) glabArgs(args ...string) []string {
	return append(args, "-R", a.glabRepoArg())
}

func (a *app) prListArgs() []string {
	if a.pr.tool == toolGlab {
		return a.glabArgs("mr", "list")
	}
	if a.pr.tool == toolTea {
		return []string{"pulls", "list"}
	}
	return []string{"pr", "list"}
}

// prViewArgs is a list of calls, not one: what gh needs two commands for, tea does
// in a single detail view.
func (a *app) prViewArgs() [][]string {
	if a.pr.tool == toolGlab {
		return [][]string{a.glabArgs("mr", "view", a.pr.num), a.glabArgs("mr", "diff", a.pr.num)}
	}
	if a.pr.tool == toolTea {
		return [][]string{{"pulls", a.pr.num, "--fields", teaDetailFields}}
	}
	return [][]string{{"pr", "view", a.pr.num}, {"pr", "diff", a.pr.num}}
}

func (a *app) prCreateArgs() []string {
	base := a.prTarget()
	if a.pr.tool == toolGlab {
		return a.glabArgs("mr", "create", a.prBaseFlag(), base, "--source-branch", a.pr.headBranch, "--title", a.pr.title, "--description", "", "--yes")
	}
	if a.pr.tool == toolTea {
		return []string{"pulls", "create", a.prBaseFlag(), base, "--head", a.pr.headBranch, "--title", a.pr.title}
	}
	return []string{"pr", "create", a.prBaseFlag(), base, "--head", a.pr.headBranch, "--title", a.pr.title, "--body", ""}
}

// prBaseFlag is how each tool names the branch a new PR goes into. The plan line
// reads it too, since glab has no --base.
func (a *app) prBaseFlag() string {
	if a.pr.tool == toolGlab {
		return "--target-branch"
	}
	return "--base"
}

func (a *app) prApproveArgs() []string {
	if a.pr.tool == toolGlab {
		return a.glabArgs("mr", "approve", a.pr.num)
	}
	if a.pr.tool == toolTea {
		return []string{"pulls", "approve", a.pr.num}
	}
	return []string{"pr", "review", a.pr.num, "--approve"}
}

// prMergeArgs deletes the PR's branch with the merge, except for a fork's: that
// branch isn't ours, and gh's --delete-branch would still take a local branch of
// the same name, such as main.
func (a *app) prMergeArgs() []string {
	if a.pr.tool == toolGlab {
		if a.pr.fork {
			return a.glabArgs("mr", "merge", a.pr.num, "--yes")
		}
		return a.glabArgs("mr", "merge", a.pr.num, "--remove-source-branch", "--yes")
	}
	if a.pr.tool == toolTea {
		return []string{"pulls", "merge", a.pr.num, "--style", "merge"}
	}
	if a.pr.fork {
		return []string{"pr", "merge", a.pr.num, "--merge"}
	}
	return []string{"pr", "merge", a.pr.num, "--merge", "--delete-branch"}
}

// prCleanArgs is the branch delete gh folds into its own merge and tea does not.
// Without it 'pr ok' merges and leaves both feature branches standing on a Gitea
// host - the same command tidying up on one git host and not the other. None for
// a fork's PR, as in prMergeArgs.
func (a *app) prCleanArgs() []string {
	if a.pr.tool == toolTea && !a.pr.fork {
		return []string{"pulls", "clean", a.pr.num}
	}
	return nil
}

// prLocalCleanArgs is the local half of the branch delete, for the tool whose merge
// takes only the git host's copy: glab's --remove-source-branch leaves ours, where
// gh's --delete-branch and tea's clean take both. -D as gh does it, since the
// preflight refused a branch with commits origin's copy lacks, and the run asks
// again just before. Not while pr ok stays on that branch, which git won't delete,
// and not for a fork's PR, whose branch only shares a name with ours.
func (a *app) prLocalCleanArgs() []string {
	head := a.pr.headBranch
	if a.pr.tool != toolGlab || a.pr.fork || !a.branchExistsLocal(head) || (head == a.currentBranch() && !a.prOkMoves()) {
		return nil
	}
	return []string{"branch", "-D", head}
}

// gitDisp is a git call the way step announces it, for one run best-effort.
func gitDisp(args []string) string {
	words := make([]string, len(args))
	for i, arg := range args {
		words[i] = shellWord(arg, false)
	}
	return "git " + strings.Join(words, " ")
}

// glabMR is the part of glab's JSON for a merge request that we read. A small
// reader takes the 6 fields: encoding/json cost 344 KB of binary for them. The
// project IDs are numbers as written, and differ when the source is a fork.
type glabMR struct {
	IID           string
	State         string
	Source        string
	Target        string
	SourceProject string
	TargetProject string
}

// readGlabMR reads one merge request from glab's JSON: the object itself, or the
// first one in a list. Only top-level members count, so the author's "state"
// never reads as the merge request's.
func readGlabMR(out string, list bool) (glabMR, bool) {
	j := &jsonScan{s: out}
	if list && (!j.eat('[') || j.eat(']')) {
		return glabMR{}, false
	}
	var mr glabMR
	read := j.eat('{') && j.items('}', func() bool {
		key, ok := j.str()
		if !ok || !j.eat(':') {
			return false
		}
		switch key {
		case "iid":
			mr.IID, ok = j.wholeNumber()
		case "source_project_id":
			mr.SourceProject, ok = j.wholeNumber()
		case "target_project_id":
			mr.TargetProject, ok = j.wholeNumber()
		case "state":
			mr.State, ok = j.str()
		case "source_branch":
			mr.Source, ok = j.str()
		case "target_branch":
			mr.Target, ok = j.str()
		default:
			ok = j.skip(0)
		}
		return ok
	})
	// The rest of a list goes unread; a lone object has nothing after it.
	if !list {
		j.ws()
		read = read && j.i == len(j.s)
	}
	if !read {
		return glabMR{}, false
	}
	return mr, true
}

var jsonNumberRE = regexp.MustCompile(`^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$`)

// jsonScan walks JSON text by hand, for readers that want a few fields.
type jsonScan struct {
	s string
	i int
}

func (j *jsonScan) ws() {
	for j.i < len(j.s) && strings.IndexByte(" \t\r\n", j.s[j.i]) >= 0 {
		j.i++
	}
}

// peek says whether c comes next, after any whitespace.
func (j *jsonScan) peek(c byte) bool {
	j.ws()
	return j.i < len(j.s) && j.s[j.i] == c
}

// eat steps over c if it comes next.
func (j *jsonScan) eat(c byte) bool {
	if !j.peek(c) {
		return false
	}
	j.i++
	return true
}

// items reads the members of an object or array whose opener was just read,
// one call of item each, with the commas between and the closer.
func (j *jsonScan) items(end byte, item func() bool) bool {
	if j.eat(end) {
		return true
	}
	for {
		if !item() {
			return false
		}
		if j.eat(end) {
			return true
		}
		if !j.eat(',') {
			return false
		}
	}
}

// wholeNumber is a JSON number with no sign, fraction or exponent, as written.
func (j *jsonScan) wholeNumber() (string, bool) {
	n := j.lit()
	return n, jsonNumberRE.MatchString(n) && strings.Trim(n, "0123456789") == ""
}

// lit is a number, true, false or null, as written.
func (j *jsonScan) lit() string {
	j.ws()
	start := j.i
	for j.i < len(j.s) && strings.IndexByte("+-.0123456789Eaeflnrstu", j.s[j.i]) >= 0 {
		j.i++
	}
	return j.s[start:j.i]
}

// str reads a string with its escapes decoded.
func (j *jsonScan) str() (string, bool) {
	if !j.eat('"') {
		return "", false
	}
	var b strings.Builder
	for j.i < len(j.s) {
		c := j.s[j.i]
		j.i++
		switch {
		case c == '"':
			return b.String(), true
		case c < 0x20:
			return "", false
		case c != '\\':
			b.WriteByte(c)
		case j.i < len(j.s) && strings.IndexByte(`"\/`, j.s[j.i]) >= 0:
			b.WriteByte(j.s[j.i])
			j.i++
		case j.i < len(j.s) && strings.IndexByte("bfnrt", j.s[j.i]) >= 0:
			b.WriteByte("\b\f\n\r\t"[strings.IndexByte("bfnrt", j.s[j.i])])
			j.i++
		default:
			r, ok := j.hex4()
			if !ok {
				return "", false
			}
			// A pair of escapes stands for one rune past U+FFFF.
			if utf16.IsSurrogate(r) && strings.HasPrefix(j.s[j.i:], `\u`) {
				back := j.i
				j.i++
				if low, ok := j.hex4(); ok && utf16.DecodeRune(r, low) != utf8.RuneError {
					r = utf16.DecodeRune(r, low)
				} else {
					j.i = back
				}
			}
			b.WriteRune(r)
		}
	}
	return "", false
}

// hex4 reads 'u' and 4 hex digits, the tail of a \u escape.
func (j *jsonScan) hex4() (rune, bool) {
	if j.i+5 > len(j.s) || j.s[j.i] != 'u' {
		return 0, false
	}
	n, err := strconv.ParseUint(j.s[j.i+1:j.i+5], 16, 16)
	if err != nil {
		return 0, false
	}
	j.i += 5
	return rune(n), true
}

// skip steps over one value of any kind. The depth bound keeps hostile nesting
// off the stack.
func (j *jsonScan) skip(depth int) bool {
	switch {
	case depth > 1000:
		return false
	case j.peek('"'):
		_, ok := j.str()
		return ok
	case j.peek('{'), j.peek('['):
		end := byte('}')
		if j.s[j.i] == '[' {
			end = ']'
		}
		j.i++
		return j.items(end, func() bool {
			if end == '}' {
				if _, ok := j.str(); !ok || !j.eat(':') {
					return false
				}
			}
			return j.skip(depth + 1)
		})
	}
	v := j.lit()
	return v == "true" || v == "false" || v == "null" || jsonNumberRE.MatchString(v)
}

// prDisp is one call written out the way the preview shows it.
func (a *app) prDisp(args []string) string { return a.pr.cli + " " + strings.Join(args, " ") }

// parseTeaTable reads tea's tabular output: a header line naming the fields, then a row
// per record. Anything else comes back empty, which callers read as "couldn't tell".
func parseTeaTable(out string) []map[string]string {
	lines := splitLines(out)
	if len(lines) < 2 {
		return nil
	}
	header := strings.Split(lines[0], "\t")
	records := make([]map[string]string, 0, len(lines)-1)
	for _, line := range lines[1:] {
		if strings.TrimSpace(line) == "" {
			continue
		}
		cells := strings.Split(line, "\t")
		record := map[string]string{}
		for i, name := range header {
			if i < len(cells) {
				record[strings.ToLower(unquoteCell(name))] = unquoteCell(cells[i])
			}
		}
		records = append(records, record)
	}
	return records
}

// unquoteCell strips the double quotes tea's tsv writer puts around every field,
// header names included. Left on, every lookup misses and every value takes them
// into whatever it was compared against.
func unquoteCell(cell string) string {
	cell = strings.TrimSpace(cell)
	if len(cell) >= 2 && strings.HasPrefix(cell, `"`) && strings.HasSuffix(cell, `"`) {
		cell = cell[1 : len(cell)-1]
	}
	return strings.TrimSpace(cell)
}

// headBranchName drops the 'owner:' a git host puts in front of a head branch that
// lives on a fork. What we compare against, and later hand git, is the branch.
func headBranchName(head string) string {
	if colon := strings.LastIndex(head, ":"); colon >= 0 {
		return head[colon+1:]
	}
	return head
}

// prPreflight is everything the writers need settled before a plan is shown, so
// nothing can fail after it was confirmed.
func (a *app) prPreflight() error {
	prBranch := a.currentBranch()
	if prBranch == "" {
		return errDetached()
	}
	if a.pr.sub == "ok" {
		return a.prAcceptPreflight(prBranch)
	}
	if prBranch == a.mergeTarget() || prBranch == a.defaultBranch() {
		// br create would leave the commits here.
		if a.ownCommitsAhead() {
			return usagef("'%s' is what pull requests merge into; there is nothing to propose. Move its commits to a new branch first with %s.", prBranch, a.keepOffText(true))
		}
		return usagef("'%s' is what pull requests merge into; there is nothing to propose. Start a branch first: %s br create <name>", prBranch, meName)
	}
	head, err := a.prCreateHead(prBranch)
	if err != nil {
		return err
	}
	a.pr.headBranch = head
	// No title given: the last commit subject is what the work is called already.
	if a.pr.title == "" {
		a.pr.title = runOut("git", "log", "-1", "--pretty=%s")
	}
	if a.pr.title == "" {
		return usagef("No commits on '%s' yet; nothing to propose.", prBranch)
	}
	if err := a.refuseUnrelatedPr(prBranch); err != nil {
		return err
	}
	// An open PR for this branch already is the answer to 'pr create' - say so
	// instead of letting the git host error.
	if existing := a.openPrForBranch(head); existing != "" {
		return usagef("PR #%s is already open for '%s'. View it: %s pr %s", existing, head, meName, existing)
	}
	return nil
}

// refuseUnrelatedPr: GitHub and Gitea won't open a pull request from a branch that
// shares no commit with its base, and they say so only after the park push has
// published it. GitLab opens and merges one, so glab is left to it. The base is
// origin's, which is what the git host compares against. A shallow clone can't tell,
// and the git host has the whole history, so it's left to the git host too.
func (a *app) refuseUnrelatedPr(branch string) error {
	if a.pr.tool == toolGlab {
		return nil
	}
	base := a.prTarget()
	refs := a.branchRefs()
	baseRef := "refs/remotes/origin/" + base
	if refs.tip[baseRef] == "" {
		baseRef = "refs/heads/" + base
	}
	if refs.tip[baseRef] == "" || refs.tip["refs/heads/"+branch] == "" {
		return nil
	}
	if runOK("git", "merge-base", "refs/heads/"+branch, baseRef) || runOut("git", "rev-parse", "--is-shallow-repository") == "true" {
		return nil
	}
	return usagef("'%s' shares no history with '%s', so %s won't open a pull request for it. Nothing was done. Joining unrelated histories is raw-git territory: git merge --allow-unrelated-histories %s",
		branch, base, a.hostName(), typedArg(strings.TrimPrefix(strings.TrimPrefix(baseRef, "refs/heads/"), "refs/remotes/"), runtime.GOOS))
}

// prTarget is what the PR merges into. For create it's read off the branch the
// park push lands on, never the current branch's name, which opened a hotfix's PR
// on dev. For ok it's the base the git host has, since that's where the merge goes
// whatever the head is called: a hotfix opened against dev on the web page never
// reaches main, and a branch opened against main does.
func (a *app) prTarget() string {
	if a.pr.sub == "ok" {
		return a.pr.baseBranch
	}
	return a.branchTarget(a.pr.headBranch)
}

// prOkBackMerges is whether pr ok owes dev a merge afterward: the PR went into the
// default branch, and dev is a branch of its own. Read off the base, not the head's
// name, for the reason prTarget gives.
func (a *app) prOkBackMerges() bool {
	return a.pr.sub == "ok" && a.pr.baseBranch == a.defaultBranch() && a.mergeTarget() != a.pr.baseBranch
}

// prCreateHead is the branch on origin the park push sends the work to, which the
// pull request has to name.
func (a *app) prCreateHead(branch string) (string, error) {
	return a.parkHead(branch)
}

// openPrForBranch is the number of the open PR proposing this branch, or nothing -
// which covers both "there isn't one" and "we couldn't ask". Only a courtesy
// message hangs off it, so the two collapsing into one answer costs nothing.
func (a *app) openPrForBranch(prBranch string) string {
	if a.pr.tool == toolGlab {
		out, ok := runOutOK(a.pr.cli, a.glabArgs("mr", "list", "--source-branch", prBranch, "--output", "json")...)
		if !ok {
			return ""
		}
		mr, ok := readGlabMR(out, true)
		if !ok {
			return ""
		}
		return mr.IID
	}
	if a.pr.tool == toolTea {
		out, ok := runOutOK(a.pr.cli, "pulls", "list", "--state", "open", "--fields", "index,head", "--output", "tsv")
		if !ok {
			return ""
		}
		for _, record := range parseTeaTable(out) {
			if headBranchName(record["head"]) == prBranch {
				return record["index"]
			}
		}
		return ""
	}
	return runOut("gh", "pr", "list", "--head", prBranch, "--state", "open", "--json", "number", "--jq", ".[0].number // empty")
}

// readPr asks the git host which branch a PR proposes, which one it goes into,
// whether it's still open, and whether the branch is on another repo, such as a
// fork. A fork's branch can share a name with one of origin's, main included, so
// the name alone doesn't say which. ok is "we got an answer"; the caller refuses
// on !ok, before the plan.
func (a *app) readPr() (head, base, state string, fork, ok bool) {
	if a.pr.tool == toolGlab {
		out, ran := runOutOK(a.pr.cli, a.glabArgs("mr", "view", a.pr.num, "--output", "json")...)
		mr, read := readGlabMR(out, false)
		if !ran || !read || mr.Source == "" || mr.Target == "" {
			return "", "", "", false, false
		}
		// glab says 'opened' where gh and tea say open.
		state = strings.ToLower(mr.State)
		if state == "opened" {
			state = "open"
		}
		return mr.Source, mr.Target, state, mr.SourceProject != mr.TargetProject, true
	}
	if a.pr.tool == toolTea {
		out, ran := runOutOK(a.pr.cli, "pulls", a.pr.num, "--fields", "index,head,base,state", "--output", "tsv")
		if !ran {
			return "", "", "", false, false
		}
		records := parseTeaTable(out)
		if len(records) != 1 {
			return "", "", "", false, false
		}
		// tea puts the fork's owner before the branch, and 'delete:' for a fork
		// that's gone. A branch name can't hold a colon.
		head = records[0]["head"]
		return headBranchName(head), records[0]["base"], records[0]["state"], strings.Contains(head, ":"), true
	}
	info, ran := runOutOK("gh", "pr", "view", a.pr.num, "--json", "headRefName,baseRefName,state,isCrossRepository", "--jq", ".headRefName, .baseRefName, .state, .isCrossRepository")
	fields := splitLines(info)
	if !ran || len(fields) != 4 || (fields[3] != "true" && fields[3] != "false") {
		return "", "", "", false, false
	}
	return fields[0], fields[1], fields[2], fields[3] == "true", true
}

// prAcceptPreflight is 'pr ok <n>', which runs from anywhere: ask gh which branch the PR
// proposes and whether it's still open, with no fallback to the current branch.
func (a *app) prAcceptPreflight(prBranch string) error {
	head, base, state, fork, ok := a.readPr()
	if !ok || head == "" || base == "" {
		return usagef("Can't read PR #%s; check the number, and that %s can see this repo.", a.pr.num, a.pr.cli)
	}
	a.pr.headBranch, a.pr.baseBranch, a.pr.fork = head, base, fork
	// Case-insensitively: gh answers 'OPEN' and tea answers 'open', and comparing
	// against one spelling makes every PR on the other git host read as already closed.
	if !strings.EqualFold(state, "open") {
		return usagef("PR #%s is %s, not open; there is nothing to accept.", a.pr.num, strings.ToLower(state))
	}
	if err := refuseOptionShapedRefs(a.pr.headBranch, a.pr.baseBranch); err != nil {
		return err
	}
	if err := a.refuseProtectedPrHead(); err != nil {
		return err
	}
	// The base can be any branch the PR was opened against, and the checkout after
	// the merge would fail on one this clone has never fetched, with the merge done.
	if a.prOkMoves() && !a.branchExistsLocal(a.pr.baseBranch) && !a.branchExistsRemote(a.pr.baseBranch) {
		return usagef("PR #%s goes into '%s', which this clone has no copy of, so the checkout after the merge would fail. Fetch it first:\n  git fetch origin %s", a.pr.num, a.pr.baseBranch, typedArg(a.pr.baseBranch+":refs/remotes/origin/"+a.pr.baseBranch, runtime.GOOS))
	}
	// The git host merges what origin already has, then the branch goes local and remote.
	// Work that never reached origin is outside the PR and outside the merge -
	// refuse, don't lose it.
	if a.treeDirty() || isAhead() {
		if prBranch == a.pr.headBranch && !a.pr.fork {
			return usagef("'%s' has changes that aren't on origin, so PR #%s can't include them. Run '%s sync' first.", prBranch, a.pr.num, meName)
		}
		return usagef("'%s' has changes that aren't on origin. Park them first: %s sync", prBranch, meName)
	}
	// Asked of the PR's own branch by name, wherever we are standing: gh deletes it
	// with 'branch -D' either way, and '@{u}' above answers nothing at all for a
	// branch that was pushed without -u - so standing on that one, the guard passed
	// and the commits went with the branch. A fork's PR deletes nothing, and a
	// branch here of the same name isn't its.
	if !a.pr.fork && a.branchExistsLocal(a.pr.headBranch) {
		if !a.branchExistsRemote(a.pr.headBranch) {
			return usagef("'%s' is here but not on origin, so PR #%s holds none of it - and it would be deleted. Push it first:\n  git push -u origin %s", a.pr.headBranch, a.pr.num, typedArg(a.pr.headBranch, runtime.GOOS))
		}
		if branchHasUnpushed(a.pr.headBranch) {
			return usagef("'%s' has commits that never reached origin, so PR #%s can't include them - and it would be deleted. Push them first:\n  git push origin %s", a.pr.headBranch, a.pr.num, typedArg(a.pr.headBranch, runtime.GOOS))
		}
	}
	return nil
}

// refuseProtectedPrHead: every tool's merge deletes the PR's branch, on the git
// host and here, so a PR from main or dev (opened on the git host's page, since
// pr create won't) would take that branch with it. Refused, as br merge refuses
// landing one, rather than merged with the delete left off, since release is how
// dev goes into main. A fork's main or dev isn't origin's, and its merge deletes
// nothing.
func (a *app) refuseProtectedPrHead() error {
	head := a.pr.headBranch
	if a.pr.fork || !a.isProtectedBranch(head) {
		return nil
	}
	release := ""
	if head == a.mergeTarget() && a.pr.baseBranch == a.defaultBranch() {
		release = " To merge " + head + " into " + a.pr.baseBranch + " as a release: " + meName + " release"
	}
	return usagef("PR #%s proposes '%s', a protected branch, and pr ok deletes the branch it merges, on %s and here. Nothing was done. Merge it on %s's page, keeping the branch.%s",
		a.pr.num, head, a.hostName(), a.hostName(), release)
}

// cmdPrView: bare lists open PRs; a number views one plus its diff.
func (a *app) cmdPrView() error {
	if a.pr.num == "" {
		return a.step(a.pr.cli, a.prListArgs()...)
	}
	for _, call := range a.prViewArgs() {
		if err := a.step(a.pr.cli, call...); err != nil {
			return err
		}
	}
	return nil
}

func (a *app) cmdPrCreate() error {
	// The git host can only diff what origin has, so park the work first - same as br merge
	// and release do.
	if err := a.cmdPush(); err != nil {
		return err
	}
	// Announced by hand rather than through step, like the approve below: step would
	// print --head and --body too, which the preview doesn't, so the two lines would
	// disagree.
	return a.stepAs(a.prCreateDisp(), a.pr.cli+" "+a.prCreateVerb(), a.pr.cli, a.prCreateArgs()...)
}

func (a *app) prCreateVerb() string {
	switch a.pr.tool {
	case toolTea:
		return "pulls create"
	case toolGlab:
		return "mr create"
	}
	return "pr create"
}

// prCreateDisp is the one line the preview and the run both show for a create -
// the title and the base, without the flags neither of them promised.
func (a *app) prCreateDisp() string {
	return a.pr.cli + " " + a.prCreateVerb() + " " + a.prBaseFlag() + " " + a.prTarget() + " --title " + shellWord(a.pr.title, true)
}

// prOkLine names the PR's branch and the base the git host merges it into, for the
// state block. Empty for pr create, whose base the plan line names.
func (a *app) prOkLine() string {
	if a.pr.sub != "ok" || a.pr.headBranch == "" || a.pr.baseBranch == "" {
		return ""
	}
	from := " from "
	if a.pr.fork {
		from = " from a fork's "
	}
	return "#" + a.pr.num + from + a.pr.headBranch + " into " + a.pr.baseBranch
}

// prOkMoves is whether pr ok ends on the PR's merge target rather than on the
// branch it started from. The merge deletes origin's copy of the PR's branch, so
// a branch tracking that one has nothing left to pull, and neither has a branch
// with no upstream. Any other branch stays, and its own upstream is pulled. The
// plan, the worktree check and the run all read this, and only before the merge,
// since the merge is what changes the answer. A fork's PR leaves origin's branch
// of the same name standing.
func (a *app) prOkMoves() bool {
	up := a.upstream().full
	return up == "" || (!a.pr.fork && up == "refs/remotes/origin/"+a.pr.headBranch)
}

func (a *app) cmdPrAccept() error {
	// Resolve both before gh deletes the branch out from under us, and off the PR's
	// own head branch (resolved up front) rather than the current one - they need not
	// be the same.
	targetBranch := a.prTarget()
	backMerges := a.prOkBackMerges()
	moves := a.prOkMoves()
	localClean := a.prLocalCleanArgs()
	// What the git host merged, at least: origin's copy as fetched. Read before the
	// prune takes it.
	var headTip string
	if localClean != nil {
		headTip = runOut("git", "rev-parse", "--verify", "--quiet", "refs/remotes/origin/"+a.pr.headBranch)
	}
	a.out.clean("")
	approve := a.prApproveArgs()
	a.out.status(a.prDisp(approve) + " ...")
	// Best-effort: both git hosts refuse to approve your own PR; merging is the part
	// that matters.
	if !a.inheritOK(a.pr.cli, approve...) {
		a.out.status("Could not approve (own PR?); merging anyway.")
	}
	a.out.resetBlank()
	if err := a.step(a.pr.cli, a.prMergeArgs()...); err != nil {
		return err
	}
	// The branch delete gh folds into its merge, for the tool that doesn't. Best
	// effort: the merge is what was asked for, and a branch somebody already removed
	// is not a failure worth ending the run on.
	if clean := a.prCleanArgs(); clean != nil {
		a.out.status(a.prDisp(clean) + " ...")
		if !a.inheritOK(a.pr.cli, clean...) {
			a.out.status("Could not delete the merged branch; it may already be gone.")
		}
		a.out.resetBlank()
	}
	// The merge removes the PR's branch on the remote but leaves our origin/* copy
	// behind, so an upstream still looks present. Prune first, so the pull below
	// reads what origin has now. Under --no-fetch origin isn't asked, and the pull
	// is skipped with it.
	if a.opt.fetch {
		a.out.status("git fetch --prune origin ...")
		a.fetchRemote()
	}
	// The plan's answer, settled before the merge. An upstream the prune took
	// anyway can only be one somebody else deleted since the first fetch, and
	// pulling it would fail after the merge went through.
	if moves || !a.hasUpstream() {
		if err := a.checkout(targetBranch); err != nil {
			return err
		}
	}
	if localClean != nil {
		a.out.clean("")
		// Asked again here, since the prompt can sit: a commit made on the branch
		// since then isn't in the PR.
		if headTip == "" || !runOK("git", "merge-base", "--is-ancestor", "refs/heads/"+a.pr.headBranch, headTip) {
			a.out.status("WARNING: '" + a.pr.headBranch + "' has commits PR #" + a.pr.num + " doesn't; left it alone.")
		} else {
			a.out.status(gitDisp(localClean) + " ...")
			if !a.inheritOK("git", localClean...) {
				a.out.status("WARNING: couldn't delete '" + a.pr.headBranch + "' here; left it alone.")
			}
		}
		a.out.resetBlank()
	}
	if err := a.pullIfOnline(); err != nil {
		return err
	}
	// Same rule as br merge's hotfix: what reached the default branch still owes dev
	// a merge.
	if backMerges {
		return a.backMergeToDev()
	}
	return nil
}
