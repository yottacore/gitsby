// Doc comments that name a function. A comment left above the wrong function, or
// still naming one since renamed, sends a reader to code that isn't there.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// A comment that opens with a camelCase word is naming something, so it has to be
// the thing below it. One that opens with prose is left alone. A later line that
// opens with another function's camelCase name and a colon is a second comment
// stacked on.
func TestDocCommentsNameWhatTheySitOn(t *testing.T) { // [Erfyvj9]
	files, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatal(err)
	}
	fset := token.NewFileSet()
	var parsed []*ast.File
	funcs := map[string]bool{}
	for _, name := range files {
		if strings.HasSuffix(name, "_test.go") {
			continue
		}
		src, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		f, err := parser.ParseFile(fset, name, src, parser.ParseComments)
		if err != nil {
			t.Fatal(err)
		}
		parsed = append(parsed, f)
		for _, decl := range f.Decls {
			if fn, ok := decl.(*ast.FuncDecl); ok {
				funcs[fn.Name.Name] = true
			}
		}
	}
	if len(funcs) == 0 {
		t.Fatal("found no functions to check")
	}
	firstWord := regexp.MustCompile(`^[a-z]+[A-Z0-9]\w*`)
	labeled := regexp.MustCompile(`^([a-z]+[A-Z0-9]\w*):`)
	check := func(pos token.Pos, name string, doc *ast.CommentGroup) {
		if doc == nil {
			return
		}
		lines := strings.Split(strings.TrimSpace(doc.Text()), "\n")
		if word := firstWord.FindString(lines[0]); word != "" && word != name {
			t.Errorf("%s: the comment on %s starts with %s", fset.Position(pos), name, word)
		}
		for _, line := range lines[1:] {
			if m := labeled.FindStringSubmatch(line); m != nil && m[1] != name && funcs[m[1]] {
				t.Errorf("%s: the comment on %s also describes %s", fset.Position(pos), name, m[1])
			}
		}
	}
	for _, f := range parsed {
		for _, decl := range f.Decls {
			switch d := decl.(type) {
			case *ast.FuncDecl:
				check(d.Pos(), d.Name.Name, d.Doc)
			case *ast.GenDecl:
				for _, spec := range d.Specs {
					doc := d.Doc
					if len(d.Specs) > 1 || d.Lparen.IsValid() {
						doc = nil
					}
					switch s := spec.(type) {
					case *ast.TypeSpec:
						if s.Doc != nil {
							doc = s.Doc
						}
						check(s.Pos(), s.Name.Name, doc)
					case *ast.ValueSpec:
						if s.Doc != nil {
							doc = s.Doc
						}
						if len(s.Names) == 1 {
							check(s.Pos(), s.Names[0].Name, doc)
						}
					}
				}
			}
		}
	}
}
