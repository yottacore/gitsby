// The accounts file in its current layout: SHCL, read and written through the
// shcl module. One block per account, addressed as account[<name>].<key>; the
// dotted spelling 'account.<name>.<key>: value' - the old flat lines with the '='
// swapped for ':' - is read too, since that is how a file gets converted by hand.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"cmp"
	"fmt"
	"slices"
	"strings"

	shcl "github.com/yottacore/shcl/source/go/v2"
)

// configHeader opens a file 'account set' creates. The keys are listed here
// because the one person who reads a generated config is the one about to edit
// it, and a list in the docs is a list they have to go and find.
const configHeader = "# " + meName + ` accounts: which login, key and author to use under which folder.
# One block per account. Every key is optional:
#   path          an absolute folder this account owns; more than one: a, b
#   pathcontains  a run of folder names found anywhere in a path
#   ghaccount     the GitHub login to act as
#   tokenfile     a file holding that login's token, absolute
#   sshkey        a key to use instead of a token, absolute
#   A path may start at home as ~, ${HOME} or %USERPROFILE%, with either slash.
#   name, email   commit author
#   protocol      https or ssh, for this account's new remotes
#   host, user    the git host and the login there, when not github.com
# Full detail: ` + homeURL + `/blob/main/accounts.md
#
# protocol: https   # for every account that doesn't say
`

// isFlatConfig tells the old layout from the current one: 'key = value' lines
// against 'key: value'. A line with '=' ahead of any ':' is an old-layout line,
// and one line in the current layout means the file is in it.
func isFlatConfig(text string) bool {
	flat, current := 0, 0
	for _, line := range splitLines(text) {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq, colon := strings.IndexByte(line, '='), strings.IndexByte(line, ':')
		switch {
		case eq >= 0 && (colon < 0 || eq < colon):
			flat++
		case colon >= 0:
			current++
		}
	}
	return flat > 0 && current == 0
}

// acctBlock is where one account lives in the document.
type acctBlock struct {
	name string // lower case, the way every lookup spells it
	path string // the block's lookup path: account[#1], or account[#0].work for the dotted form
	disp string // how the ignored list and the plan name it: account[work], account.work
}

// acctBlocks finds every account block, in file order, plus the things under
// 'account' that are not one. By index rather than by name: a selector on a name
// misreads a numeric one as an index, and case-folds nothing, where the model
// folds every name.
func acctBlocks(doc *shcl.Document) (blocks []acctBlock, stray []string) {
	for i := range doc.Count("account") {
		base := fmt.Sprintf("account[#%d]", i)
		if name, status := doc.GetString(base); status == shcl.Good && name != "" {
			blocks = append(blocks, acctBlock{strings.ToLower(name), base, "account[" + name + "]"})
			continue
		}
		// A bare 'account:' with the names nested under it - what the dotted
		// spelling produces.
		for _, child := range dedupe(doc.Children(base)) {
			path := base + "." + shcl.QuoteSegment(child)
			if len(doc.Children(path)) == 0 {
				stray = append(stray, "account."+child)
				continue
			}
			blocks = append(blocks, acctBlock{strings.ToLower(child), path, "account." + child})
		}
	}
	return blocks, stray
}

// loadDoc reads the current layout into the model. Anything the reader cannot
// place - a malformed line, a key nothing reads, a key indented under another
// key, an account named in a way that could climb out of the include directory -
// goes on the ignored list, never quietly by.
func (c *config) loadDoc(doc *shcl.Document) {
	c.doc = doc
	for _, d := range doc.Diagnostics() {
		if d.Severity == shcl.SeverityError {
			c.unknown = append(c.unknown, fmt.Sprintf("line %d (%s)", d.Line, d.Message))
		}
	}
	for _, name := range dedupe(doc.Children("")) {
		switch name {
		case "protocol":
			c.values[name] = c.protocolValue(name, c.lastBinding(bindings(doc, name, name)).value)
			c.listNested(doc, name, name, name)
		case "account":
		default:
			c.unknown = append(c.unknown, name)
			c.listNested(doc, shcl.QuoteSegment(name), name, name)
		}
	}
	blocks, stray := acctBlocks(doc)
	c.unknown = append(c.unknown, stray...)
	// A single-valued key can reach one account more than once: repeated in a
	// block, in a block opened again further down (the format merges the two), or
	// in blocks whose names differ only in case. The last is read, as the flat
	// reader always did. The earlier ones are listed, since two hosts or two emails
	// is two accounts written as one, and reading one of them without a word is how
	// that went unnoticed.
	given := map[[2]string][]binding{}
	var keys [][2]string
	for _, b := range blocks {
		if !acctNameOK.MatchString(b.name) {
			c.unknown = append(c.unknown, b.disp)
			continue
		}
		if !contains(c.order, b.name) {
			c.order = append(c.order, b.name)
		}
		for _, field := range dedupe(doc.Children(b.path)) {
			path := b.path + "." + shcl.QuoteSegment(field)
			switch field {
			case "path", "pathcontains":
				// Repeatable: as an array, or as the key given again.
				for _, value := range allStrings(doc, path) {
					c.absorb(b.name, field, value, b.disp+"."+field)
				}
			default:
				// A key nothing reads is only listed, and listed here, ahead of
				// anything indented under it.
				if !slices.Contains(accountSetFields, field) {
					c.absorb(b.name, field, "", b.disp+"."+field)
					break
				}
				key := [2]string{b.name, field}
				if _, seen := given[key]; !seen {
					keys = append(keys, key)
				}
				given[key] = append(given[key], bindings(doc, path, b.disp+"."+field)...)
			}
			c.listNested(doc, path, b.disp+"."+field, field)
		}
	}
	for _, key := range keys {
		last := c.lastBinding(given[key])
		c.absorb(key[0], key[1], last.value, last.disp)
	}
}

// binding is one line giving a single-valued key.
type binding struct {
	value, disp string
	line        int
}

func bindings(doc *shcl.Document, path, disp string) []binding {
	lines := doc.Lines(path)
	out := make([]binding, 0, len(lines))
	for j := range doc.Count(path) {
		out = append(out, binding{doc.GetStringOr(fmt.Sprintf("%s[#%d]", path, j), ""), disp, lines[j]})
	}
	return out
}

// lastBinding picks the line that is read, and lists every earlier one that said
// something else. By line, since the pieces of one account come back in the order
// their names first appear, not the order their keys do.
func (c *config) lastBinding(list []binding) binding {
	if len(list) == 0 {
		return binding{}
	}
	slices.SortStableFunc(list, func(x, y binding) int { return cmp.Compare(x.line, y.line) })
	last := list[len(list)-1]
	for _, earlier := range list[:len(list)-1] {
		if earlier.value != last.value {
			c.unknown = append(c.unknown, fmt.Sprintf("%s: %s (line %d; line %d gives it again, and that one is read)", earlier.disp, earlier.value, earlier.line, last.line))
		}
	}
	return last
}

// listNested puts every key below a path on the ignored list: nothing reads a
// key from under another key, and a key indented one level too far is otherwise
// gone without a word. A repeated key's children come back for every instance.
// at is the lookup path, disp how the list names it, parent the name of the key
// it sits under.
func (c *config) listNested(doc *shcl.Document, at, disp, parent string) {
	for _, name := range dedupe(doc.Children(at)) {
		// Once per path: a repeated key with a child under each is one line to fix.
		if entry := disp + "." + name + " (indented under " + parent + ")"; !contains(c.unknown, entry) {
			c.unknown = append(c.unknown, entry)
		}
		c.listNested(doc, at+"."+shcl.QuoteSegment(name), disp+"."+name, name)
	}
}

// allStrings reads every value a key was given, across repeats and arrays.
func allStrings(doc *shcl.Document, path string) []string {
	var out []string
	for j := range doc.Count(path) {
		out = append(out, doc.GetStringArrayOr(fmt.Sprintf("%s[#%d]", path, j), nil)...)
	}
	return out
}

// dedupe keeps the first of each name, in order. The module lists a key once per
// line it was given on.
func dedupe(names []string) []string {
	var out []string
	for _, name := range names {
		if !contains(out, name) {
			out = append(out, name)
		}
	}
	return out
}

// shclValue spells a value the way the file will hold it - quoted and escaped
// where the format needs it - by asking the module, so the plan on screen and the
// line on disk cannot disagree.
func shclValue(value string) string {
	doc := shcl.New()
	setValue(doc, "v", value)
	return strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(doc.ToCanonical()), "v:"))
}

// setValue writes a value with a backslash in single quotes, where every
// backslash is itself. The module writes some Windows paths bare, and the file
// should show the spelling that is safe to copy for the next path typed by hand.
// Single quotes can't hold an apostrophe or a line break, so those values, and
// ones with a character the module writes as a \u escape to make it seen, keep
// the module's double quotes, with each backslash doubled.
func setValue(doc *shcl.Document, path, value string) bool {
	if strings.Contains(value, `\`) && !strings.ContainsAny(value, "'\r\n") && !hasUEscape(value) && doc.SetLiteral(path, "'"+value+"'") {
		if got, status := doc.GetString(path); status == shcl.Good && got == value {
			return true
		}
	}
	return doc.SetString(path, value)
}

// hasUEscape: the module spells value with a \u or \U escape. Only double quotes
// hold escapes, and a doubled backslash is not the start of one.
func hasUEscape(value string) bool {
	doc := shcl.New()
	doc.SetString("v", value)
	spelled := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(doc.ToCanonical()), "v:"))
	if !strings.HasPrefix(spelled, `"`) {
		return false
	}
	spelled = strings.ReplaceAll(spelled, `\\`, "")
	return strings.Contains(spelled, `\u`) || strings.Contains(spelled, `\U`)
}

// flatToSHCL respells the old layout in the current one, so the comments and
// blank lines come through where they stood. Real blocks rather than the dotted
// spelling: a comment attaches to the setting after it, and with every setting a
// child of some block, a comment above an account's first line was carried into
// the block. Written as blocks, it sits above the block it introduced. A line
// that was not a setting stays as it was, and the module reports it the way the
// flat reader did.
func flatToSHCL(text string) string {
	lines := splitLines(text)
	var out []string
	open := "" // the account whose block the last line went into
	for i, line := range lines {
		line = strings.TrimLeft(line, " \t")
		if line == "" || strings.HasPrefix(line, "#") {
			// Indented only while the block goes on past it, so a comment above the
			// next account - or the end - is not the last field's.
			if open != "" && flatAccountAfter(lines, i) == open {
				line = "\t" + line
			}
			out = append(out, line)
			continue
		}
		key, rawValue, found := strings.Cut(line, "=")
		if !found {
			out, open = append(out, line), ""
			continue
		}
		key = strings.ToLower(strings.TrimRight(key, " \t"))
		value, comment := splitFlatValue(strings.TrimLeft(rawValue, " \t"))
		acct, field, ok := splitAccountKey(key)
		if !ok {
			out, open = append(out, key+": "+shclValue(value)+comment), ""
			continue
		}
		if acct != open {
			if len(out) > 0 && out[len(out)-1] != "" {
				out = append(out, "")
			}
			out, open = append(out, "account: "+acct), acct
		}
		out = append(out, "\t"+field+": "+shclValue(value)+comment)
	}
	text = strings.Join(out, "\n")
	if !strings.HasSuffix(text, "\n") {
		text += "\n"
	}
	return text + "\n" + shcl.GenBanner
}

// flatAccountAfter names the account the next setting past line i belongs to, or
// nothing where the next line is not an account's.
func flatAccountAfter(lines []string, i int) string {
	for _, line := range lines[i+1:] {
		line = strings.TrimLeft(line, " \t")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, _, found := strings.Cut(line, "=")
		if !found {
			return ""
		}
		acct, _, ok := splitAccountKey(strings.ToLower(strings.TrimRight(key, " \t")))
		if !ok {
			return ""
		}
		return acct
	}
	return ""
}
