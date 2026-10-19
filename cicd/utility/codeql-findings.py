#!/usr/bin/env python3

##	Purpose: Read the SARIF reports a CodeQL run wrote, one per OS, print what
##		they found, and fail on any of it. Third-party code under vendor/ is held
##		to the queries tagged security, correctness or reliability; its style
##		findings are dropped, since they aren't ours to fix. A report that didn't
##		take in first-party code, its tests and vendor/ fails as well, since it
##		checked less than it says.
##	Syntax:
##		codeql-findings.py [--ignore "RULE PATH"]... SARIF...
##		  --ignore   a finding set aside, by rule ID and file. One that no report
##		             has any more fails the run, so the list can't go stale.
##		  SARIF      one report per OS, each held to the same rules.
##	Exit: 0 nothing found, 1 findings, 2 the report is unreadable or covers too little.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import json, sys

KEEP_IN_VENDOR = {"security", "correctness", "reliability"}


def fail(msg):
	sys.stderr.write(f"codeql-findings: {msg}\n")
	sys.exit(2)


def read_run(path):
	try:
		with open(path, encoding="utf-8") as fh:
			runs = json.load(fh)["runs"]
	except (OSError, ValueError, KeyError, TypeError) as err:
		fail(f"can't read {path}: {err}")
	if len(runs) != 1:
		fail(f"{path}: expected 1 run, found {len(runs)}")
	run = runs[0]
	if not run.get("tool", {}).get("driver", {}).get("rules"):
		fail(f"{path}: no queries ran")
	## The extractor names each file it took in. The file list beside it names every .go file
	## under the root, tests included whether they were taken in or not.
	seen = []
	for inv in run.get("invocations", []):
		for note in inv.get("toolExecutionNotifications", []):
			if note.get("descriptor", {}).get("id", "").endswith("/diagnostics/successfully-extracted-files"):
				for loc in note.get("locations", []):
					seen.append(loc.get("physicalLocation", {}).get("artifactLocation", {}).get("uri", ""))
	go_files = [u for u in seen if u.endswith(".go")]
	if not any(u.startswith("vendor/") for u in go_files):
		fail(f"{path}: nothing under vendor/ was extracted")
	if not any(u.endswith("_test.go") and not u.startswith("vendor/") for u in go_files):
		fail(f"{path}: no test files were extracted")
	if not any(not u.endswith("_test.go") and not u.startswith("vendor/") for u in go_files):
		fail(f"{path}: no first-party source was extracted")
	return run


def main(argv):
	ignore, paths = {}, []
	args = iter(argv[1:])
	for arg in args:
		if arg != "--ignore":
			paths.append(arg)
			continue
		spec = next(args, "")
		rule, _, path = spec.partition(" ")
		if not rule or not path:
			fail(f"--ignore wants 'RULE PATH', not {spec!r}")
		ignore[(rule, path)] = 0
	if not paths:
		fail("usage: codeql-findings.py [--ignore \"RULE PATH\"]... SARIF...")

	## One finding in code every OS builds shows up in each report, so each is listed once.
	found = {}
	for sarif in paths:
		run = read_run(sarif)
		tags = {r.get("id"): set(r.get("properties", {}).get("tags", [])) for r in run["tool"]["driver"]["rules"]}
		for res in run.get("results", []):
			rule = res.get("ruleId", "")
			loc = (res.get("locations") or [{}])[0].get("physicalLocation", {})
			path = loc.get("artifactLocation", {}).get("uri", "?")
			line = loc.get("region", {}).get("startLine", 0)
			if path.startswith("vendor/") and not (tags.get(rule, set()) & KEEP_IN_VENDOR):
				continue
			if (rule, path) in ignore:
				ignore[(rule, path)] += 1
				continue
			text = " ".join(res.get("message", {}).get("text", "").split())
			found.setdefault((rule, path, line), text)
	for (rule, path, line), text in sorted(found.items()):
		print(f"  {rule}  {path}:{line}  {text}")
	stale = [key for key, hits in ignore.items() if not hits]
	for rule, path in stale:
		print(f"  {rule}  {path}  is set aside but no longer reported; take it off the list")
	return 1 if found or stale else 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))


##	History:
##		- 20261019: Created, for cicd.bash --leakcheck.
