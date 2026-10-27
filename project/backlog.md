<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Gitsby backlog

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Introduction](#introduction)
- [Issues](#issues)
- [Old format](#old-format)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
	- [Deferred](#deferred)
	- [Canceled](#canceled)
- [Template](#template)

<!-- /TOC -->

## Introduction

Going forward, new issues in the new template at the bottom of this file, will go in the '## New format' section only. No more status emojis. Refer to '## Reference' for sort order. Issues in the old format (with status emojis) won't be refactored, but will continue to be worked until moved to closed, canceled, or deferred sections, and emojis updated. (Eventually this will all be moved to nano-git-db anyway. This new template is an intermediate effort to make issues going forward more structured and importable.)

This is the product backlog, until bugs, features, and enhancements move to GitHub Issues.

## Issues

- CICD reset: CPU and priority on the Windows box
	- ID: 2026102508333054
	- Type: Enhancement
	- Status: Waiting on automated testing
	- Needs external testing: stage 7's Go tests on b29w, or vm925w, twice: as is, and with one test failing on purpose. The failing run fails the box with no `WARNING: ... still exited 0` line, which shows the exit code still comes back. While one runs, `wmic process where name="gitsby-test.exe" get Priority` there gives 6 (BelowNormal).
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-083330
	- Opened by: jim-collier
	- Parent ID: 2026102416313103
	- Requirements [Feature]:
		- Stage 7's Go tests on the Windows box run in the `BelowNormal` priority class, with `GOMAXPROCS` at half that box's cores, rounded down and at least 1, per `Machine use`.
		- Windows has no load average. Say on the item what stands in for the busy rule there, or that none does.
	- Progress log:
		- ssh lands in cmd there. `set /a` can work the count out before the marker line. `start /belownormal /wait` may not hand back the test binary's exit code. Neither can be run from here.
		- 2026-10-25: The Windows command sets `GOMAXPROCS` to `%NUMBER_OF_PROCESSORS%/2`, or 1 under 2 cores, ahead of the marker, and runs the tests with `start "" /belownormal /b /wait`.
		- 2026-10-25: A `--- FAIL` line in the output fails the box even when the exit code comes back 0, with a warning that says so.
		- Under Wine's cmd, the same command line gave `GOMAXPROCS` 16 on 32 cores, and the test binary's exit code 3 came back through `start /wait`. Wine ignores the priority class, so BelowNormal is unchecked. Wine's `set /a` doesn't read a variable by name, so the line expands `%NUMBER_OF_PROCESSORS%`.
		- Verified: test.bash 1737/0 on the box, and `--backlog-run-quick` in the image, with test.bash 1737/0, fuzz 313/0 and parity 29/0. Against the harness before the change, `[dee74]` and `[dee75]` fail.
	- Decisions:
		- Nothing stands in for the busy rule. The box always gets half its cores, and BelowNormal yields to its other work. A one-shot CPU sample was passed over, since it's not an average. Filed as a Check in questions.md.
	- Branch: round-20261025b
	- Test case: test.bash `[dee74]` (the count and class on the command line), `[dee75]` (a failing test that exits 0).
	- Swept: every remote command in remote-tests.bash's `fRunWindows`. The copy and cleanup steps run no tests, so they keep normal priority.
	- Prereq IDs: 2026102519554107
	- 2026-10-25: The round's full run reached stage 7, where vmDebARM64 failed 22 harness checks (2026102519554107). Waits on that.

- Stage 7 can't start vm925w once it has started vmKt6m or vmFreeBSD
	- ID: 2026102510404322
	- Type: Bug
	- Status: Waiting on automated testing
	- Needs external testing: stage 7 with b29w held under the lock and vm925w off. vm925w comes up before vmFreeBSD and vmKt6m, and runs the Go tests.
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261025-104043
	- Opened by: jim-collier
	- Related IDs: 2026102416313101
	- Incorrect behavior [Bug]: In the round-20261025 full run, b29w was held by another job, so stage 7 went to vm925w, which was off. It didn't come up, with "Failed to reserve port 5900", and was skipped. No Windows box ran the Go tests.
	- Expected behavior [Bug]: vm925w starts and runs the Windows Go tests when b29w is busy.
	- Reproduced [Bug]: 2026-10-25 on b23, gover plus 4388d96. vmKt6m was started earlier in the run and ignored the ACPI shutdown, so it was still up and held the port.
	- Possible cause [Bug]: vm925w's SPICE port is fixed at 5900, while vmFreeBSD and vmKt6m take the first free one. Starting vm925w before the other VMs, or only after they're down, would avoid it. vmKt6m also needs shutting down from inside, since it ignores the ACPI request.
	- Estimated effort: Avg
	- Actual cause [Bug]: Confirmed from the guest definitions. `vm925w-iommu` has `port='5900' autoport='no'`, and vmFreeBSD and vmKt6m have `autoport='yes'`. Stage 7 took the Windows box last, after the Mac and Unix boxes, and vmKt6m stayed up after its turn.
	- Actual fix [Bug]: Stage 7 takes the Windows box first. That covers gitsby's own VMs, not another session's. The guest's own fix, `autoport='yes'`, is outside the repo, drafted in `private/claude_simple/upstream/2026102510404322/`. The guest is unchanged.
	- Progress log:
		- 2026-10-25: The Windows loop in remote-tests.bash runs before the Mac and Unix ones. Every build is still made before any box is taken.
		- 2026-10-25: The fixture's VM helper now refuses vm925w with "Failed to reserve port 5900" while another VM it woke is still up.
		- Verified: test.bash 1737/0 on the box, and `--backlog-run-quick` in the image, with test.bash 1737/0, fuzz 313/0 and parity 29/0. Against the harness before the change, `[dee73]` fails, and so do the new checks of the other two items in this change and the changed `[dedpc]`, 1732/5.
	- Branch: round-20261025b
	- Test case: test.bash `[dee73]`.
	- Swept: every loop over the boxes in remote-tests.bash. Only the three run loops take boxes, and the summary is sorted by name, so the order shows nowhere else. config.bash's stage 7 comment names the order.
	- Prereq IDs: 2026102519554107
	- 2026-10-25: The round's full run reached stage 7, where vmDebARM64 failed 22 harness checks (2026102519554107). Waits on that.

- Stage 7 takes every box through the VM state helper's wrap
	- ID: 2026102511210617
	- Type: Enhancement
	- Status: Waiting on automated testing
	- Needs local test suite run?: the round's `--backlog-run-full`, stage 7, which takes b26, b29w and vmDebARM64 through the real helper's `wrap` as boxes that aren't VMs here.
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261025-112106
	- Opened by: jim-collier
	- Related IDs: 2026102416313101
	- Requirements [Feature]:
		- The helper's `wrap` takes `--why` and `--eta` since 2026-10-25, and leaves a box that isn't a VM alone. So stage 7 can use it for every box, with `--why "gitsby: <kind> tests"`, and drop the lock's own `wrap` branch in `fUnderLock`.
		- The comment above `fUnderLock` that says the helper has no `--why` goes with it.
		- A box with no helper on the PATH still runs through the lock's `wrap`.
	- Estimated effort: Low
	- Progress log:
		- 2026-10-25: `fUnderLock` makes one call, to the helper's `wrap` where there is one and to the lock's otherwise, with `--wait 0 --why "gitsby: <kind> tests"` either way. Its comment, the script's Purpose and config.bash's stage 7 comment say so.
		- The helper is still looked for beside the lock, not on the PATH, as before. With none, the lock takes each box, and a sleeping VM is skipped.
		- 2026-10-25: Asserts given new values for this change. `[dedpc]`: `vmstate wrap vmFreeBSD --wait 0 --` and `lock wrap vmFreeBSD --wait 0 --` -> the same with `--why gitsby: unix tests`, and "vmDebARM64 never goes through the helper" -> "the helper never wakes vmDebARM64". Its label's "keeps the lock's own wrap" -> "is left alone". The fixture's helper takes any options before `--` and passes them to the lock, and leaves a box that isn't a VM to it, as the real one does.
		- Verified: test.bash 1737/0 on the box, and `--backlog-run-quick` in the image, with test.bash 1737/0, fuzz 313/0 and parity 29/0. Against the harness before the change, `[dee71]` fails. `[dee72]` passes there too, since the no-helper path didn't change.
	- Branch: round-20261025b
	- Test case: test.bash `[dee71]` (every box through the helper, with why), `[dee72]` (no helper, the lock's own wrap with why), plus `[dedpc]` as changed.
	- Swept: every call of the lock and the helper in remote-tests.bash. `hosts` and `status` are reads, and stay as they were.
	- Prereq IDs: 2026102519554107
	- 2026-10-25: The round's full run reached stage 7, where vmDebARM64 failed 22 harness checks (2026102519554107). Waits on that.

- CICD reset: standard flags
	- ID: 2026102416313104
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Related IDs: 2026101816064793
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per the flags in `CICD style guide` and per `Merge gate`, in the shared CICD rules.
		- New flags: `--long`, with `--slow` as another name, `--backlog-run-quick [<area>...]`, `--backlog-run-full`, `--merge-gate`, `--keep-temp` and `--list`. `--help` lists the areas.
		- `--gate` and `--ci` stay as other names for `--backlog-run-quick` and `--merge-gate`, and say so in one line when used. `pre-push.bash` looks for the `--gate)` arm, so it changes with it.
		- `--quick` is what fits in about 10 minutes in all, not a 30 s budget per step.
		- The backlog and merge gate flags never dogfood, publish, commit, push, install, sync, rewrite a tracked file, or prompt. That covers the demo gif.
		- The pre-push hook runs `--merge-gate`, every check of the default run, on a push to main. A push whose commits change only docs and the other paths listed in one place the hook reads skips it. No gate on dev or gover.
		- Earlier decisions this overrides: 2026101816064793, where `--gate` gets no `--ci` alias and `--quick` has a 30 s budget per step, and the private CI/CD notes, where the gate on main runs lint and the unit tests only.
	- Progress log:
		- 2026-10-25: Split, too big for one pass. Children: 2026102506452473 (the new run flags and the aliases), 2026102506452478 (`--keep-temp` and `--list`), 2026102506452483 (`--quick` in about 10 minutes) and 2026102506452488 (the hook runs `--merge-gate`). The other reset items wait on the first.
	- Test case: the children's tests: 2026102506452473, 2026102506452478, 2026102506452483 and 2026102506452488, all in test.bash.
	- Closed: 20261026-171340
	- Acceptance signoff: closed with its 4 children.

- CICD reset: step output
	- ID: 2026102416313105
	- Type: Enhancement
	- Status: Waiting on automated testing
	- Needs local test suite run?: `--backlog-run-full`, to see a real run in the image number its steps after the ones out here, with the step times in this box's time.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per the step lines in `CICD style guide` in the shared CICD rules. Stage headers already have the blank line, the rule of `•` and the bracketed title.
		- The rule is 79 `•` wide. Today it's 74.
		- Each step opens with `[ <local time to the hundredth>: Step N of M; Starting <name> ]` and closes with the same line saying `PASS` or `FAIL`, in place of the `N/8` headers and the `OK:` lines.
		- A step that's turned off isn't counted in M. The first section lists those, with the flag or reason for each.
		- Earlier decisions this overrides: the private CI/CD notes, which number the stages 0/8 to 8/8.
	- Progress log:
		- 2026-10-26: The rule is 79 wide. Each step opens with `[ <time>: Step N of M; Starting <step> ]` and closes with `PASS`, or `FAIL` from the exit trap, Ctrl+C included. M counts only the steps that run. The quick run's areas are its steps.
		- 2026-10-26: The plan names the flag or reason for each step that's off, such as `(skipped --no-sync)`, `(skipped --merge-gate)` or `(done by the run outside the container)`, and the quick run lists the areas not named. `--list` titles read `Step N of M` too.
		- 2026-10-26: The run in the image is handed where its steps start and the run's total, so its steps take their place in the one count. It also gets this box's UTC offset for the step times, since the image runs in UTC.
		- 2026-10-26: Asserts that read the old text now read the new, old -> new, and check nothing less:
			- [dd5g1] `[ 0/8  Remote sync ]` and [ddg83] `[ 7/8  Remote tests ]` -> their `Step 1 of 1; Starting` lines. [dd5fn] the source's `fSection "0/8  Remote sync"` -> `fStep sync`.
			- [dee4y] list titles `2/8`, `4/8`, `Quick 1/1` -> `Step 3 of 9`, `Step 5 of 8`, `Step 1 of 1`.
			- [dd5g5], [dedm0], [dedm1], [de8q2], [de4c5]: `remote sync skipped`, `dogfood disabled`, `publish disabled`, `fuzz + security skipped`, `Remote tests skipped (--quick)` -> the plan's `(skipped <flag>)` line for each. [ddg84] -> the plan's cross-builds line and a `Cross-builds` step.
			- [ddrp7], [ddrrn]: `lint ran in the container`, `demo gif ran in the container` -> the plan's Container line, and no such step out here. [dedn8], [dedna]: `OK: Remote tests` -> `PASS Remote tests`.
	- Decisions:
		- An `OK:` line that only repeated its step's verdict gave way to `PASS`: tests passed, fuzz + security passed, the parity line, Remote tests, published. Lines inside a step that name what passed stay, such as `OK: shellcheck clean` or `OK: soak test`.
			- That departs from the wording, which reads as every `OK:` line. Filed as a Check in questions.md.
		- The `Container` section stays as a plain section with its `OK: the container run` line, since the steps it runs are numbered in there.
		- Under `--quick` the remote step is named `Cross-builds`, since that's all it does then.
		- The image gets the offset, not the box's zone files, so the demo gif and the suites in there keep UTC. A DST change mid-run shows only in the times printed in there.
		- The help's stage list keeps its numbers. Docs and comments name stages by them, and the output no longer prints them.
	- Branch: round-20261026
	- Test case: test.bash [defmr], [defms], [defmt], [defmv], [defmw], [defmx], and the 14 changed above.
	- Verified: `--backlog-run-quick lint suite parity` passed in the image: test.bash 1748 -> 1754, 0 failed, parity 29/0. Against HEAD's cicd.bash the 6 new checks and the 14 changed ones fail. shellcheck passes.
	- Swept: every `fSection`, `OK:` line and skip line in cicd.bash, and every reader of them in the repo; test.bash is the only one. The other scripts' `•` rules are in comments only. pre-push.bash keys on `--gate)`, unchanged.

- CICD reset: a test for every Done item
	- ID: 2026102416313106
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per the regression bullet in `Testing` in the shared CICD rules. Done items in the new format name their test, all but 2026100611181886. Most old-format Done items name none.
		- Each of those gets a test where one could exist and would make sense, or a line saying why not.
	- Progress log:
		- 2026-10-26: Split, too big for one pass. 399 old-format Done items name no test, 299 bugs and 100 features. Children, by backlog section: 2026102617594206, 2026102617594208, 2026102617594210, 2026102617594212, 2026102617594214, 2026102617594216, 2026102617594218 and 2026102617594221.
		- 2026-10-26: 2026102617594206 is done, with 2 new checks. The other 7 are Queued.

- CICD reset: a test for every Done item, Code review 20260909
	- ID: 2026102617594208
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-175942
	- Opened by: jim-collier
	- Parent ID: 2026102416313106
	- Requirements [Feature]:
		- The old-format items under `Code review 20260909 - the pass against the standing directives`. 21 items.
		- Each item there with no test row gets a `Test:` row that names its test by ID, or says in a few words why there is none.
		- Where a test could exist and would make sense but doesn't, add it, watched to fail first.

- CICD reset: a test for every Done item, the 20260812 groups and the 20260819 to 20260821 reviews
	- ID: 2026102617594210
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-175942
	- Opened by: jim-collier
	- Parent ID: 2026102416313106
	- Requirements [Feature]:
		- The old-format items under `Accounts and arguments, 20260812`, `Installers, 20260812`, `Pipeline, 20260812`, `Documentation, 20260812`, and code reviews 20260821, 20260819d, 20260819c, 20260819b and 20260819. 52 items.
		- Each item there with no test row gets a `Test:` row that names its test by ID, or says in a few words why there is none.
		- Where a test could exist and would make sense but doesn't, add it, watched to fail first.

- CICD reset: a test for every Done item, Code review 20260819a
	- ID: 2026102617594212
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-175942
	- Opened by: jim-collier
	- Parent ID: 2026102416313106
	- Requirements [Feature]:
		- The old-format items under `Code review 20260819a`. 66 items.
		- Each item there with no test row gets a `Test:` row that names its test by ID, or says in a few words why there is none.
		- Where a test could exist and would make sense but doesn't, add it, watched to fail first.

- CICD reset: a test for every Done item, code reviews 20260818, 20260813 and 20260812
	- ID: 2026102617594214
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-175942
	- Opened by: jim-collier
	- Parent ID: 2026102416313106
	- Requirements [Feature]:
		- The old-format items under those three reviews. 33 items.
		- Each item there with no test row gets a `Test:` row that names its test by ID, or says in a few words why there is none.
		- Where a test could exist and would make sense but doesn't, add it, watched to fail first.

- CICD reset: a test for every Done item, code reviews 20260731 to 20260723
	- ID: 2026102617594216
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-175942
	- Opened by: jim-collier
	- Parent ID: 2026102416313106
	- Requirements [Feature]:
		- The old-format items under code reviews 20260731, 20260730, 20260727b, 20260727, 20260726, and 20260725 and 20260723. 102 items. Likely too big for one pass, so split it by review first.
		- Each item there with no test row gets a `Test:` row that names its test by ID, or says in a few words why there is none.
		- Where a test could exist and would make sense but doesn't, add it, watched to fail first.

- CICD reset: a test for every Done item, features, first half
	- ID: 2026102617594218
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-175942
	- Opened by: jim-collier
	- Parent ID: 2026102416313106
	- Requirements [Feature]:
		- The old-format items in `Done - Features and enhancements`, from the top through `` `account set` writes one key of one account into the accounts file ``. 48 items.
		- Each item there with no test row gets a `Test:` row that names its test by ID, or says in a few words why there is none.
		- Where a test could exist and would make sense but doesn't, add it, watched to fail first.

- CICD reset: a test for every Done item, features, second half
	- ID: 2026102617594221
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-175942
	- Opened by: jim-collier
	- Parent ID: 2026102416313106
	- Requirements [Feature]:
		- The old-format items in `Done - Features and enhancements`, from `Other Git hosts are first-class` to the end. 52 items.
		- Each item there with no test row gets a `Test:` row that names its test by ID, or says in a few words why there is none.
		- Where a test could exist and would make sense but doesn't, add it, watched to fail first.

- CICD reset: test IDs
	- ID: 2026102416313107
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per the ID and per-test line bullets in `Testing` in the shared CICD rules. Every test already has an ID and prints one line.
		- An ID is whole minutes since 2000-01-01 00:00 UTC, in lowercase Crockford base 32, such as `decp8`. Today they're milliseconds in base 62.
		- Every existing ID is converted once, from the time it already holds. When 2 come out the same, the newer one takes the next free minute.
		- `test-id.bash`, the duplicate check in test.bash, the backlog check and the IDs named in this backlog move together.
		- Each test prints `PASS <id> <name>`, `FAIL <id> <name>` or `SKIP <id> <why>`, in place of `ok: [<id>] <name>` and the rest, on this box and on the remote boxes.
		- Earlier decisions this overrides: the private test ID rule, milliseconds in base 62.
	- Progress log:
		- 2026-10-26: Split. The ID conversion is done here, and the per-test line is 2026102618140158.
		- 2026-10-26: All 1860 IDs converted from the times they held, the 3 commented-out checks included, in the suites, the Go tests and this backlog. 1650 of them took a later free minute, since most were minted in bursts a few ms apart. The furthest moved 145 minutes.
		- 2026-10-26: `test-id.bash` mints the new form, moves past a minute a test already has, and takes `-n` for several. `--check` fails an ID that isn't five Crockford base 32 characters. The test fixtures' IDs are in the new form too.
		- 2026-10-26: Asserts given new values for this change. `[ErTFcXs]`, "an ID minted for now is seven characters of base 62", is now `[ddc2j]`, "five characters of lowercase Crockford base 32". `[Er2NSAB]`, "a minted ID is milliseconds since 2000 in base 62", is now `[dd5kt]`, "whole minutes since 2000", minting for 00:32:59 rather than 00:00:00.062, still `10`. `[dd5ez]` and `[dd5p5]` match the ID in spawn-count's output as `[0-9a-z]{5}`, not `[0-9A-Za-z]{7}`.
		- 2026-10-26: Checks relabeled on the round branches before this, now under their new IDs, so against gover they read as removed: `[Er1LxTh]` -> `[dd5g1]`, `[Et6FC4K]` -> `[de4by]`, `[Et9PJrE]` -> `[de548]`, `[Etj1UKH]` -> `[dedpc]`.
	- Decisions:
		- Ties go in age order: each ID, oldest first, takes its own minute or the next one no older test has. So a burst keeps its order.
		- `--check` takes exactly five characters, which lasts until 2063, rather than any length. A leftover old ID then can't pass.
		- Old IDs in run logs under `cicd/artifacts/`, in commit messages and in private notes are left as they were. The old-to-new table is kept outside the repo.
		- The `ok: [<id>] <name>` lines keep their shape until 2026102618140158.
	- Test case: test.bash `[defpc]` (an old ID fails the check), `[defpd]` (a taken minute goes to the next one), `[defpe]` (`-n`), `[ddc2j]` and `[dd5kt]` (the new form), and `[dd5kr]` (every test has its own ID, in the new form).
	- Needs local test suite run?: No. `--backlog-run-quick` passed, with the IDs only renamed.
	- Verified: `[defpc]`, `[defpd]`, `[defpe]`, `[ddc2j]` and `[dd5kt]` fail against the old test-id.bash and pass against the new one. `--backlog-run-quick` passed in the image: lint with `test-id.bash --check` (1857 tests) and `backlog-check.bash`, go test, test.bash 1757 -> 1760, 0 failed, fuzz 313/0, spawn counts and parity 29/0. shellcheck passes.
	- Branch: round-20261026
	- Swept: every pattern that reads an ID in cicd/, cicd/utility/ and its include/ folder, cicd.bash's fuzz target IDs and `go-test-lines.bash`, which take either form. backlog-check.bash, whose ID match takes either form too. README, contributing.md and design.md, which don't give the ID rule.

- CICD reset: PASS, FAIL and SKIP test lines
	- ID: 2026102618140158
	- Type: Enhancement
	- Status: Waiting on automated testing
	- Needs local test suite run?: the round's `--backlog-run-full`, stage 7, to see test.bash's SKIP lines for its Linux-only blocks on b26, where the block is read with the Mac's awk.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-181401
	- Opened by: jim-collier
	- Parent ID: 2026102416313107
	- Requirements [Feature]:
		- Each test prints `PASS <id> <name>`, `FAIL <id> <name>` or `SKIP <id> <why>`, in place of `ok: [<id>] <name>` and the rest, on this box and on the remote boxes.
		- Per the per-test line bullet in `Testing` in the shared CICD rules.
		- Covers test.bash, fuzz.bash, parity.bash and spawn-count.bash, and whatever reads their lines: cicd.bash's counts and remote-tests.bash's summary.
	- Progress log:
		- 2026-10-26: test.bash, fuzz.bash and parity.bash print `PASS <id> <label>` or `FAIL <id> <label>`, from the `[<id>] <label>` they're handed. parity's `DIFFER:` is a FAIL now.
		- 2026-10-26: A block of test.bash a box can't run, such as the Linux-only ones, prints a SKIP for each test in it, with the old skip text as the why. fuzz.bash's three skips name their test. Both totals count the skips.
		- 2026-10-26: The Go test lines and the native fuzz targets print the same shape, on this box and the remote ones, and a fuzz target that finds a crasher prints FAIL before the run stops.
		- 2026-10-26: spawn-count.bash prints PASS, FAIL or SKIP and the ID, with the old verdict after the count, such as `, regressed` or `, new`. A rise that `--record` takes is a PASS. With no strace each command is a SKIP. lint-report.bash drops the new lines.
		- 2026-10-26: Asserts given new values for this change, old -> new, and check nothing less:
			- `[dd6vy]`, `[dd6vz]`, `[ddg8c]`, `[ddg8j]`, `[dee75]`, `[ddgm1]`: `  ok: [aaaab] TestA`, `  ok: TestC`, `  FAIL: [aaaab] TestA` -> `  PASS aaaab TestA`, `  PASS TestC`, `  FAIL aaaab TestA`. `[dd6g0]`: `  ok: [aaaaa] FuzzA` -> `  PASS aaaaa FuzzA`.
			- `[dd5ez]` `REGRESSED  [<id>] status: 0 -> ` -> `FAIL <id> status: 0 -> <n>, regressed`. `[dd5p5]`, `[ddf82]` `ok  [<id>]` -> `PASS <id>`. `[ddf54]` `OVER LIMIT [dbftf] status: <n>, limit 3 (expected 1)` -> `FAIL dbftf status: <n>, over its limit of 3 (expected 1)`.
			- `[dbftb]`'s log and the remote fixture's suite lines are in the new shape.
	- Decisions:
		- The lines keep their two-space indent under the step, as before.
		- A Go test with no ID prints `PASS TestName`, as it printed `ok: TestName`. The ID check in lint fails it anyway.
		- A Go SKIP names the test, not why, since the log puts the reason on a line of its own that parallel tests can split from it.
		- remote-tests.bash's `SKIP: <box>, ...` and `FAIL: <box> go test` lines keep their colon. They're about a box, not a test, and the summary reads boxes only, so it didn't change.
		- A skipped block's tests are read from the block itself, the nearest `if` and `fi` one tab out from the skip, rather than listed by hand, so a check added to the block is skipped by name with no second edit.
		- parity's total still says `differed`.
	- Branch: round-20261026
	- Test case: test.bash `[defpy]` (each suite's PASS and FAIL lines), `[defpz]` (SKIP), `[defq0]` (a skipped block, either branch, nested), `[defq1]` (every skipped block names a test), `[defq2]` (lint summary), `[defq3]` (Go test lines), `[defq4]` (a rise `--record` takes), `[defq5]` (no strace), plus the 11 changed above.
	- Verified: `--backlog-run-quick lint unit suite fuzz parity` passed in the image: test.bash 1760 -> 1768, 0 failed, fuzz 313/0, spawn counts, parity 29/0. Against HEAD's scripts every new check but `[defq1]` fails, and so does each changed one. `[defq0]` fails with the block found one tab off, and with the wrong caller line. The skipped-block fixture gives the same lines under mawk, busybox awk and gawk --posix. shellcheck and `test-id.bash --check` pass.
	- Swept: every `ok:`, `FAIL:`, `skip:`, `skipped:`, `DIFFER:` and spawn verdict printed in cicd/, cicd/utility/ and include/, and every reader: test.bash, lint-report.bash and remote-tests.bash. cicd.bash counts nothing from the lines. README, contributing.md and design.md don't give the line shape.

- CICD reset: temp files and safe removal
	- ID: 2026102416313108
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Prereq IDs: 2026102506452478
		- It uses `--keep-temp` from that item. The other new flags are in since a1c62bb.
	- Related IDs: 2026101912030138
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per `Temp files` and `Safe removal` in the shared CICD rules. A run's own temp files are already in one folder that goes on exit, and the harnesses remove theirs.
		- Each run makes one folder, `${HOST_TEMP}/gitsby/<YYYYmmDD-HHMMSS>_<NNN>/`, with a plain `mkdir` and a counter, and points `TMPDIR`, `TEMP` and `TMP` at it. The harnesses and utilities make theirs inside it.
		- `--keep-temp` keeps it and prints where it is.
		- Each run writes a `run.pid` in it, and removes the project's own stale run folders: over 2 days old, with no live process.
		- Every recursive removal goes through the repo's own copy of the safe removal guard, in the pipeline, the harnesses, the utilities, release.bash, the installer and stage 7's commands on the other boxes. The checks of a folder's name and marker that some have today stay as well.
		- 35 recursive removals in 12 files, none through the guard. File list in the private notes.
	- Progress log:
		- 2026-10-25: Split. 2026102516194062 has the removals outside cicd.bash. The rest is in.
		- 2026-10-25: A run's folder is `${HOST_TEMP}/gitsby/<start time>_<NNN>`, else under `TMPDIR`, made with a plain `mkdir` and the first free counter, with `TMPDIR`, `TEMP` and `TMP` pointed at it and a `run.pid`. The harnesses and release.bash already follow `TMPDIR`, so theirs go inside it. Each run removes the project's run folders over 2 days old whose pid is gone.
		- 2026-10-25: `cicd/utility/include/safe-rm.bash` is the repo's copy of the guard. cicd.bash's own removals go through it, with the name and marker checks kept.
	- Decisions:
		- The sweep leaves a folder with no `run.pid`, since a run didn't make it.
	- Branch: round-20261025b
	- Test case: test.bash [dee5h] and [dee5j], plus [de5m8], [dee4z] and [dee50] for the new folder.
	- Verified: Both fail against the round branch's cicd.bash, and pass with the change. The run in the image passed with them.

- CICD reset: every other recursive removal through the guard
	- ID: 2026102516194062
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261025-161940
	- Opened by: jim-collier
	- Parent ID: 2026102416313108
	- Requirements [Feature]:
		- The parent's last requirement, outside cicd.bash: the harnesses, stage 7's commands on the other boxes, the utilities, release.bash, the installers, and the image build's own removals. Each goes through the guard in `cicd/utility/include/safe-rm.bash`, or a copy of it on the other boxes, and keeps the name and marker checks it has.
		- The guard calls `realpath -e`. Check it on macOS and FreeBSD before stage 7 uses it there.

- CICD reset: CICD process gaps
	- ID: 2026102416313109
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- What else the shared CICD rules ask for that no other reset item covers:
			- One line at the end of a run saying what was removed and about what it freed, files as well as docker.
			- Go's module cache in the volume pruned of what the current `go.sum` doesn't name.
		- Packaging and dependabot stay deferred, per the standing decision. 20261024: kept out of this item, since nothing makes them pressing.
	- Progress log:
		- 2026-10-26: Split. Children: 2026102617543861 (the line at the end of a run, done) and 2026102617543961 (the module cache).

- CICD reset: prune Go's module cache in the volume
	- ID: 2026102617543961
	- Type: Enhancement
	- Status: Queued
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261026-175439
	- Opened by: jim-collier
	- Parent ID: 2026102416313109
	- Requirements [Feature]:
		- The parent's second requirement: Go's module cache in the `gitsby-cicd-cache` volume pruned of what the current `go.sum` doesn't name.
	- Notes:
		- The volume is shared by every worktree's runs, and another branch's `go.sum` may name other versions. A prune could take a module from under a run in progress. Prune only when no other gitsby run's container is up, which only the run out here can see.
		- Keep the `golang.org/toolchain` modules for the `toolchain` line in go.mod, which `go.sum` doesn't name, and the `/go.mod`-only entries it does.
		- test.bash builds the SHCL 2.x build offline from the cache ([ddg6f]), so check that every module it needs is in `go.sum`.
		- Module paths in the cache spell capitals as `!` plus the lower case letter, and go makes the files read-only.

- CICD reset: a test for every Done item, the top-level bugs
	- ID: 2026102617594206
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261026-175942
	- Opened by: jim-collier
	- Parent ID: 2026102416313106
	- Requirements [Feature]:
		- 2026100611181886, the one new-format Done item with no test named, and the old-format `Done - Bugs` items that sit at the top level, outside a code review group. 25 items.
		- Each item there with no test row gets a `Test:` row that names its test by ID, or says in a few words why there is none.
		- Where a test could exist and would make sense but doesn't, add it, watched to fail first.
	- Progress log:
		- 2026-10-26: Each of the 25 old-format items has a `Test:` row, found from the checks and Go tests its fix commit added. 2026100611181886 has a `Test case:` row.
		- 2026-10-26: 2 new checks where none was: [defny], the backlog gate's count of open review items, and [defp0], the committed demo gif under a minute.
	- Decisions:
		- A Go test is named by the ID on its func line, like a suite check.
		- A test renamed or removed since is named as it is now, with the old name. `TestDisplayPath` went with the `~` fold in 0ad1374, so that item names the Windows run of the Go tests.
		- The gif check's bound is a minute, against design.md's "about fifty seconds", so a scene's small change in timing doesn't trip it.
	- Branch: round-20261026
	- Test case: test.bash [defny] and [defp0]. The rest name tests that already ran.
	- Verified: `--backlog-run-quick lint suite` passed in the image, test.bash 1757/0. [defny]'s fixture gives `(0 listed)` against backlog-check.bash from 2319e09, before the fix, and with the count's `^\t` pattern put back, and `(2 listed)` as it is. [defp0]'s test fails on the gif before 37a4adf, 124.8 s, and passes on the committed one, 47.7 s.
	- Swept: all 25 items, each against its fix commit's added checks and Go tests, with each ID grepped once in the suites. Each item kept its wording; only the rows were added.
	- Closed: 20261026-180932
	- Acceptance signoff: Self-closed, tests and backlog rows only.

- CICD reset: one line at the end of a run for what it removed
	- ID: 2026102617543861
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261026-175438
	- Opened by: jim-collier
	- Parent ID: 2026102416313109
	- Requirements [Feature]:
		- The parent's first requirement: one line at the end of a run saying what was removed and about what it freed, files as well as docker.
	- Progress log:
		- 2026-10-26: A run's last line is `Cleanup: removed <what>; freed about <size>`, or `Cleanup: nothing to remove`, then the closing blank line. It takes in the run's own folder and the stale run folders as well as what the docker tidy-up removed. The `Docker:` line and the line per stale folder are gone into it.
		- 2026-10-26: Asserts given the new line, old -> new: [dee5j] `removed a stale run folder: <path>` -> `Cleanup: removed 1 stale run folder(s), the run folder`. [dee5k] `Docker: nothing to remove`, `Docker: removed 2 image(s)`, `Docker: removed ... volume` and a failed run's `Docker:` line -> the same as `Cleanup:` lines, with the run folder named.
	- Decisions:
		- Folders count at their apparent size. ZFS reports a compressed size that lags fresh writes, and the line says "about".
		- The run in the image prints its own line for its own folder, before the line out here.
	- Branch: round-20261026
	- Test case: test.bash [defng], plus [dee5j] and [dee5k] changed.
	- Verified: `--backlog-run-quick lint suite` passed in the image, test.bash 1754 -> 1755, 0 failed. Against the previous cicd.bash [defng], [dee5j] and [dee5k] fail. A real quick run in the image ended with `Cleanup: removed the run folder; freed about 8B`. shellcheck passes.
	- Swept: every removal in cicd.bash that printed its own line: the stale sweep and the docker tidy-up. The soak and CodeQL report pruning keep their own warning, since they remove artifacts, not temp files.
	- Acceptance signoff: Self-closed: its tests passed.
	- Closed: 20261026-175508

- test.bash's stage 7 checks fail on vmDebARM64 after round-20261025b
	- ID: 2026102519554107
	- Type: Bug
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-195541
	- Opened by: jim-collier
	- Related IDs: 2026102511210617, 2026102510404322, 2026102508333054
	- Steps to reproduce [Bug]:
		- `--merge-gate` at 3490090, stage 7, test.bash on vmDebARM64.
	- Incorrect behavior [Bug]: 1711 passed, 22 failed, all in the block that runs `remote-tests.bash` against the fixture's stub lock. The first to fail is [ddg8a], the first check where the stub lock wraps a box. [ddg88], [ddg89] and [dee72] pass. The others include [ddg8b], [ddg8c], [dedq5], [dedpc], [dee73], [dee75] and [ddgm7].
	- Expected behavior [Bug]: 0 failed, as on b26, vmFreeBSD and vmKt6m in the same run, and on b23 both in the image and on the box (1748/0).
	- Reproduced [Bug]: 2026-10-26 on vmDebARM64, with that block of test.bash run on its own: the same 22 failed. On b23 it passed 43/0.
	- Possible cause [Bug]: Not found yet. vmDebARM64 passed 1699/0 on gover earlier on 2026-10-25, so it came in with this round. 6343351 is the only round commit that touches `remote-tests.bash`; it sends every box through one `fLockEnv "${vmState:-${lock}}" wrap` call. The fixture prints only FAIL lines, so the first step is to run that block on vmDebARM64 and keep `rtOut` and `rtLog`.
	- Actual cause [Bug]: b14ae19, also in this round, runs the Mac's module fetch with Homebrew's bash folder first on PATH, which is `/usr/local/bin` in the fixture. The fixture's ssh stub runs that copy step for real. So on a box with its own `/usr/local/bin/go`, that go answered instead of the stub, and failed with "go: no modules specified". Every run that reached b26 then failed. vmDebARM64 has one, linked to `/usr/local/go/bin/go`, and b23 and the image don't. The block is Linux only, so no other stage 7 box runs it.
	- Actual fix [Bug]: The stub's Mac reads `/usr/local/bin` as an empty folder of the fixture's. The calls log still shows the command as sent, so no assert changed.
	- Progress log:
		- 2026-10-25: The run's log is kept as `private/claude_simple/round-20261025b_full-run.log`, lines 9590 to 9810. round-20261025b stays unmerged until this is fixed.
		- Verified: the block alone on vmDebARM64, held through the VM helper's wrap and put back to off: 22 failed before the fix, 43/0 after. On b23, 43/0 both ways. `--backlog-run-quick lint suite` passed in the image, with test.bash 1748/0.
		- Not run: the whole test.bash on vmDebARM64. The round's full run covers it.
	- Decisions:
		- The path is mapped in the stub, rather than pointing the fixture's `REMOTE_MAC_BASH` elsewhere, since [ddg8d] and [dedpf] check for `/usr/local/bin` in the command sent, and that's the real Mac's path.
	- Branch: round-20261026
	- Test case: the 22 checks above, on a box with go in `/usr/local/bin`, [ddg8e] first, since it needs the stub's `go mod download` in the calls log. No check on b23 can put a go under the real `/usr/local/bin`.
	- Swept: every stub in test.bash that runs a remote command for real. Only the b26 branch of the harness's ssh puts a fixed system folder ahead of the stubs. The Unix branch's fetch has no PATH prefix.
	- Acceptance signoff: Self-closed. Reproduced on the box, and fails before the fix and passes after.
	- Closed: 20261026-171155

- `raw gh` loops forever when `gh` on PATH leads back to gitsby
	- ID: 2026101916533300
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. test.bash ran 1597/0.
	- Priority [Feature|Enhancement] | Severity [Bug]: Critical
	- Opened: 20261019-165333
	- Opened by: jim-collier
	- Prereq IDs: 2026102306584122
	- Target OS: Linux
	- Test environment: b28l
	- Steps to reproduce [Bug]:
		- On a box where the first `gh` on PATH is, or runs, gitsby, run `gitsby raw gh <anything>`.
		- Not confirmed which form b28l had: a symlink or copy of gitsby named `gh`, or a wrapper script that calls `gitsby raw gh "$@"`.
	- Incorrect behavior [Bug]:
		- Endless loop that eats time and a lot of memory. The session that hit it got out by calling the real `gh` by full path.
	- Expected behavior [Bug]:
		- Stop at once with a plain error that names the PATH entry, and never start a second copy of itself.
	- Reproduced [Bug]: 2026-10-21 on b23, with stand-ins on PATH. A wrapper `gh` that runs `gitsby raw gh "$@"` started itself until its counter stopped it at 20. A link named `gh` to the build ran gitsby as gh, which answered "Unknown command 'auth'". The link alone doesn't loop, since gitsby doesn't read its own name, so b28l most likely had a wrapper.
	- Possible cause [Bug]:
		- `cmdPassthrough` in main.go checks `gh` only with `mustBeInPath`, then `handover` in exec.go runs it by bare name. Nothing checks that the file found isn't gitsby itself, or something that calls it. A wrapper makes each run start the next, with no limit.
	- Requirements [Bug fix]:
		- Find the tool by walking PATH ourselves. Skip any entry that resolves (symlinks followed, `os.SameFile`) to the running gitsby. If nothing else is left, refuse with the usual "Not found in path" error and say a PATH entry points back at gitsby.
		- Set an env var such as `GITSBY_RAW_ACTIVE` on the handover. If it's already set when `raw` starts, refuse with a message that names it. This catches wrappers the file check can't see. Read it at startup, before the run sets it.
		- Cover `tea`, `glab`, `lazygit`, and `tig` the same way, since they share the path.
		- Test case needs a stand-in `gh` that is a wrapper and one that is a symlink to the build. Watch both fail on the current build first, and put a spawn limit on the test so a regression can't eat the box.
	- Progress log:
		- 2026-10-19: Logged from a report by another project's session on b28l. Cause is from reading the code, not from a run there. Still need the output of `type -a gh` on b28l.
		- 2026-10-21: Fixed as the requirements ask. `raw` walks PATH itself, through `exec.LookPath` on each entry, and passes over an entry that is the running binary. It sets `GITSBY_RAW_ACTIVE` to the tool's path before anything runs the tool, the tea probes and the account's gh calls included, and a `raw` that finds it set at startup refuses and names it. The hermetic suites unset it.
		- 2026-10-22: The guard refused every nested `raw`, hooks and aliases included. `GITSBY_RAW_ACTIVE` is now the chain of `raw` runs above, one short entry each, and a `raw` refuses only to start one already on it. While `raw` runs tools only to check them, such as the tea and gh probes, the chain ends in a probe mark, and a `raw` started under that refuses. A loop with new arguments each time stops at 16 deep.
		- 2026-10-23: The b28l session was tukzedo's. Its memory.md says a `gh` wrapper running `exec gitsby raw gh "$@"` grew to about 15,000 processes and 56 GB in 28 minutes on 2026-10-19. Tried that wrapper on b23 against the gover build: no loop, 2 or 3 starts and a refusal. The old build loops in every case until the rig's cap. The wrapper still fails, and so do gitsby's own gh calls behind it, filed as 2026102306584122. A wrapper that clears the environment still loops, filed as 2026102306584127. Rig: `private/claude_simple/tools/rawloop-rig.bash`.
	- Actual cause [Bug]:
		- As the possible cause says. `raw` ran the tool by bare name and never asked what it found. Every run through a wrapper started the next.
	- Actual fix [Bug]: `lookTool` in exec.go, used by `cmdPassthrough` for all six tools, and `rawActive` read in `newApp`. The tool still sees its own name as argv[0]. design.md's `raw` bullets say so. Since 2026-10-22, `rawNest` in exec.go builds and checks the chain.
	- Decisions:
		- With no other copy left, the refusal is "Not found in path: gh. '<entry>' is gitsby itself.", with the entry as found.
		- A gitsby entry ahead of a real tool is passed over without a word.
		- A plain copy of gitsby named `gh` isn't the same file, so only the env check stops it, on its second start.
		- 2026-10-22, from the answer "What any sane human git user would expect": whatever nesting plain git allows works the same under gitsby, with no refusal and nothing added to the output. That covers hooks under `raw git commit` or `push`, git aliases, lazygit and tig custom commands, and scripts. A loop gitsby causes still stops at once and names what looped.
		- An entry is the tool's name and a 12-digit hash of its path, the folder and the arguments. The folder is in it so a hook that runs the same command in a submodule isn't taken for a loop. Refusing on the same tool file alone was rejected, since it refuses `raw git` under `raw git`.
		- A `raw` started by one of gitsby's own checks of a tool is refused, since nothing a check runs has a reason to call `raw`. Without that, the tea wrapper check `[de89c]` failed, since the `--version` and `logins list` probes each started a nested `raw`.
		- The depth limit is 16. Plain git would loop forever there.
	- Branch: round-20261021, then round-20261022
	- Test case: test.bash `[de897]`, `[de898]`, `[de899]` and `[de89a]` for gh, and `[de89b]` and `[de89c]` for tea, glab, lazygit and tig, as a link and as a wrapper each. Each wrapper quits after 5 starts. Go `[de89d]` for the PATH walk and `[de89e]` for the refusal, reworded 2026-10-22 to a repeat on the chain. Since then test.bash `[de8pg]` and `[de8ph]` for a pre-commit hook running `raw git` under `raw git commit`, `[de8pj]` for an alias doing the same, and Go `[de8pk]` for the chain and the probe mark and `[de8pm]` for the depth limit.
	- Verified: All 12 new test.bash checks fail on the build before the fix, with the other 1579 passing. The 5 with only the link on PATH were rerun outside the suite with the same command and pattern, and fail there too. After it, test.bash 1579 -> 1591, 0 failed. Both Go tests fail with the self check and the env check taken out. `GOOS=windows go vet` and darwin and freebsd builds pass. The wrapper stand-in started once, then refused.
	- Verified: 2026-10-21, stage 7 passed on every box. test.bash 1368/0 on b26 and 1271/0 on vmFreeBSD, each 15 more than on 10-19, all from this round, and 1579/0 on vmDebARM64, 23 more, with leakflags' 8. All 12 of this item's test.bash checks ran on each. The Go tests passed there and on vm925w, where `[de89d]` skips, since it needs symlinks and the exec bit, and `[de89e]` passed.
	- Verified: 2026-10-22, test.bash 1594 -> 1597, 0 failed, with the reworded `[de899]` and `[de89c]`. On the build before, the 3 new checks fail. The Go tests fail with each part of `rawNest` taken out in turn: the repeat check, the probe mark, the depth limit, the folder and the separator between arguments. Outside the suite, a wrapper `gh` started once and was refused, and one adding an argument each time stopped at 16. `GOOS=windows go vet` and the Windows test build, and darwin and freebsd builds, pass.
	- Verified: 2026-10-22, stage 7 passed on every box for the nesting change. test.bash 1371/0 on b26 and 1274/0 on vmFreeBSD, each 3 more than on 10-21, which are `[de8pg]`, `[de8ph]` and `[de8pj]`. 1583/0 on vmDebARM64, 4 more, those 3 plus `[de8q2]`, which sits in the Linux-only pre-push gate block. `[de8pk]` and `[de8pm]` passed in the Go tests on b26, vmFreeBSD, vmDebARM64 natively and under Wine, and vm925w, where the Go tests were 191 ok and 23 skipped, 2 more ok than on 10-21. `[de89e]` passed there too. Log: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261021-19403500/run1.log`.
	- Verified: 2026-10-23 on b28l, the box that hit it, on the synced build `c917c95`, which has this fix and 2026102306584122's. In tukzedo-linux's repo there, with tukzedo's wrapper `exec gitsby raw gh "$@"` first on PATH and the real `gh` 2.46.0 behind it, each start counted and capped at 20: `gitsby raw gh auth status`, a bare `gh auth status`, `gh repo view`, a script calling `gh api user`, `gitsby whoami`, `gitsby --no-fetch pr` and `gitsby -q raw gh api rate_limit` all reached the real `gh` as t00mietum and exited 0. 2 to 9 wrapper starts each, with no gitsby left running. The control, the same wrapper with `9e82970` first on PATH as `gitsby`, ran into the cap on both forms tried.
	- Verified: 2026-10-24 on b23, gover `c87c131`, with the rig. The wrapper reached the stand-in `gh` with 2 starts for `raw gh`, 3 for a bare `gh` or a script, and 6 for `whoami` and `pr`. A link or copy named `gh` is refused by name since 2026102306584132. A wrapper adding an argument each time stopped at 17 deep after 32 starts. No gitsby was left running.
	- Swept: every `raw` tool shares `cmdPassthrough`, git included. 2026-10-22: `rawActive` has one reader, `cmdPassthrough`, and the variable is unset in all 4 hermetic suites. Other commands still run gh and tea by bare name, so a gh link to gitsby gives a confusing error there; logged as 2026102111572785. Not a loop, since only `raw` hands over.
	- Acceptance signoff: Hand test on b28l, run in the 2026-10-23 round as asked.
	- Closed: 20261023-195424

- The quick run fails staticcheck in the hook's gate worktree
	- ID: 2026102518002917
	- Type: Bug
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-180029
	- Opened by: jim-collier
	- Related IDs: 2026102507133273, 2026102506452488
	- Steps to reproduce [Bug]:
		- `git -C .git/gitsby-gate checkout --detach --force 422b8aa`
		- `(cd .git/gitsby-gate && cicd/cicd.bash --backlog-run-quick lint)`
	- Incorrect behavior [Bug]: Stage 1 fails with "error obtaining VCS status: exit status 128 ... Use -buildvcs=false to disable VCS stamping", then "FAILED: staticcheck findings". The same commit passes in the live checkout.
	- Expected behavior [Bug]: The run passes in the gate worktree as it does in the checkout, so the pre-push hook can gate a push to main.
	- Reproduced [Bug]: 2026-10-25, at the round tip 6a752d7 in the gate worktree, in the image.
	- Possible cause [Bug]: The gate worktree's `.git` is a file pointing at `repo/.git/worktrees/gitsby-gate`, which isn't mounted in the container, so git can't read the repo there. Since 461657d the quick run, `--gate` included, runs in the image, so every gated push to main fails this way.
	- Actual cause [Bug]:
		- The repo's git dir is mounted, and git works there. Go takes only a `.git` folder for a repo, not a worktree's `.git` file. So from the gate worktree under `repo/.git/` it walks up and takes the main checkout for the repo.
		- In the image the main checkout's folder is a mount point owned by root, so git refuses it as dubious ownership and exits 128. On the box it passes, and stamps the main checkout's revision into the lint builds.
	- Actual fix [Bug]: cicd.bash exports `GOFLAGS` with `-buildvcs=false`, after any flags the caller set, so nothing go builds there stamps a revision. The `-o` builds already passed it.
	- Progress log:
		- 2026-10-25: Found when the round's early full run started in the gate worktree. gover 422b8aa fails the same way, so it predates the round.
	- Branch: round-20261025b
	- Test case: test.bash [dee90].
	- Verified: [dee90] fails against the old cicd.bash, with the other 1740 passing. `--backlog-run-quick` passed with every area: test.bash 1740 -> 1748, 0 failed, fuzz 313/0, parity 29/0. The issue's steps, and `--backlog-run-quick unit`, passed in the gate worktree with the fix, in the image.
	- Swept: `GO_BUILD_FLAGS` already has the flag. `fImageGo` mounts only the tree, so go finds no repo there. release.bash runs its checks through cicd.bash. test.bash, fuzz.bash and parity.bash get it from the run.
	- Acceptance signoff: Self-closed: its test failed before and passes after, and so did the issue's own steps.
	- Closed: 20261025-181343

- `repo clone` hands git a folder name taken from the URL, and git can read it as an option
	- ID: 2026100607545802
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: High
	- Opened: 20261006-074900
	- Closed: 20261006-104608
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: With no folder given, `repo clone` names it after the URL's last part. A URL ending in `--upload-pack=<cmd>.git` put that text in git's argument list as an option. On a local or `file://` clone git runs it as a command.
	- Expected behavior [Bug]: The URL and the folder always reach git as plain arguments.
	- Reproduced [Bug]: Yes. A bare repo named `--upload-pack=touch CANARY;git-upload-pack.git`, then `gitsby -q repo clone file://...` made the canary file.
	- Actual cause [Bug]: `cmdClone` ran `git clone <url> <dir>` with no `--` in front.
	- Actual fix [Bug]: `git clone -- <url> <dir>`, and the plan line shows the same.
	- Swept: every `a.step` call for git, gh and tea. gitsby's own parser refuses an argument that starts with a dash, `--` included, checked for `br create`, `repo connect`, `repo url` and `repo create`. So only a value gitsby builds from other input can start with one, and the clone folder was the only such value. Built URLs start with a scheme.
	- Branch: fuzzwork
	- Commit: c1b10fc
	- Test case: fuzz.bash [ddjyb]. Red on `gover`'s code, green here.
	- Verified: fuzz.bash 311/0, test.bash 1491/0, parity.bash 29/0 on the branch.

- test.bash removes the folder it was started from when mktemp fails
	- ID: 2026100415391365
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: High
	- Opened: 20261004-153913
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- Run `cicd/test.bash` with `TMPDIR` set to something that isn't a folder, such as a file.
	- Incorrect behavior [Bug]: `mktemp -d` fails, and `work` ends up as the current folder. The exit trap then runs `rm -rf` on it. Started from the repo root, that is the whole checkout, `.git` included.
	- Expected behavior [Bug]: The suite stops before it sets the trap, and removes nothing.
	- Reproduced [Bug]: Yes, 2026-10-04 on b23, against a scratch folder, which was removed. The same day it removed the gitsby checkout, which came back whole from the 15:30 ZFS snapshot.
	- Possible cause [Bug]: test.bash line 32 is `work="$(cd "$(mktemp -d ...)" && pwd -P)"`. The mktemp failure is lost, and `cd ""` succeeds without moving.
	- Note: a probable fix checks the mktemp result before resolving it, and refuses a `work` that isn't a `gitsby-test.*` folder before arming the trap. A grep of `cicd` and the installers finds no other `cd "$(mktemp` site.
	- Actual cause [Bug]: The mktemp call sat inside the `cd` that resolves it, so its failure was lost. `cd ""` succeeds without moving, so `work` became the current folder, and the exit trap removed it.
	- Actual fix [Bug]: mktemp runs on its own line and stops the suite when it fails. Before the trap is set, the resolved folder has to be the one mktemp made, named `gitsby-test.*`, and empty. A marker file goes in it, and the trap removes the folder only while the name and the marker are both there.
	- Swept: install.bash and every script in cicd/, cicd/utility/ and cicd/utility/demo/. Only test.bash wrapped mktemp in a `cd`. The rest assign mktemp straight to a variable under `set -e`, so a failure stops them or leaves an empty value that `${x:?}` refuses before any `rm`. demo-repo.bash and remote-tests.bash already check a marker before removing. The shared files in cicd/utility/include/ have no mktemp and no recursive removal.
	- Verified: with TMPDIR a file, the suite before the fix removed the folder it was started from, canary included, and the fixed one stopped at mktemp and left it alone. `[ddgkk]` fails against the old test.bash and passes against the new one, and so does `[ddgkm]`'s pattern on test.bash. With mktemp working, the scratch folder is still removed and the exit code kept, for a plain TMPDIR, one ending in a slash, and one reached through a link.
	- Verified: shellcheck, `test-id.bash --check`, and `cicd.bash --gate`.
	- Not run: the full test.bash. No run reaches the trap's refusal of a folder without the marker.
	- Test case: test.bash `[ddgkk]`, a real run with mktemp failing, and `[ddgkm]`, no script changes into a mktemp result unchecked.
	- Verified: the 2026-10-04 test batch. test.bash on b23 passed 1452 and failed 1, which is 1412 plus this round's 41 new checks. The one failure is `[db712]`, from enhancement 8.
	- Verified: stage 7 on 2026-10-04. vm925w passed its Go tests. vmFreeBSD and vmDebARM64 passed their Go tests, and their test.bash failed only `[db712]`, from enhancement 8. b26 was skipped, since another session held it.
	- Acceptance signoff: Self-closed. Reproduced, its test failed before the fix and passes after, and the sweep is answered.
	- Closed: 20261004-182117
	- Branch: tmpguard
	- Commit: 609ccb9

- The README install line fails while v2.1.0 is the newest full release
	- ID: 2026100315501800
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: High
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Related IDs: 2026100313491873
	- Steps to reproduce [Bug]:
		- Run gover's install.bash with no version, against the releases as they are today.
	- Incorrect behavior [Bug]: It picks v2.1.0 and stops with "publishes no gitsby binary for linux/amd64". v2.1.0 has only the `gitsby` and `gitsby.ps1` scripts.
	- Expected behavior [Bug]: The install line works on the day the Go build reaches `main`.
	- Reproduced [Bug]: Yes, 2026-10-03, against the live release list.
	- Possible cause [Bug]: The installer takes a pre-release only when no full release exists, and the first Go release is v3.0.0-beta.1, which must not reach the install line. So the line resolves to a release the new installer can't install. This was true before item 2026100313491873.
	- Notes:
		- Blocks the release that merges gover to `main`.
		- What the install line should give during the beta is a call for signoff, not a worker.
	- Actual cause [Bug]: With no tag, both installers took the newest full release from the `releases/latest` redirect and never asked whether it had a Go binary. The release list was read only when there was no full release at all.
	- Decisions:
		- 2026-10-03: The install line takes the beta while no full release publishes a gitsby binary. This reverses the earlier rule that the beta must not reach the install line. A full release with a binary always wins over any pre-release, so once 3.0.0 is out, later betas stay off the line.
		- A binary means any asset named `gitsby-<os>-<arch>`, not one for this platform. Every machine is pointed at the same release, and one it leaves out is told "publishes no gitsby binary for linux/386. It publishes: ..." rather than quietly getting an older beta that covers it.
		- Newest is the highest version. Full releases are compared only with each other, and pre-releases only with each other, so the `sort -V` trap can't arise. Two pre-releases of one version go by list order, which is publish order.
		- `releases/latest` is still asked first, since it has no API limit, and settles it when its SHA256SUMS lists a binary. The release list is read only otherwise, in one request, from the asset URLs it carries.
		- The README's `--tag v3.0.0-beta.1` line is dropped, since the plain line takes that beta. The paragraph says a later pre-release needs `--tag`.
		- Against: design.md "The proof is the contract, not the installer". Phase 3 now also runs the tag's install.bash, only to read which release it takes. The contract proof is unchanged, and design.md has a bullet for the new step.
	- Actual fix [Bug]: Both installers, with no tag, keep the redirect's release only when its SHA256SUMS lists a gitsby binary. Otherwise they read the list and take the highest full release with one, else the highest pre-release with one, and say so. When none has one they stop and say so, and when the list can't be read they name the full release that had none. An explicit tag works as before, and `--tag v2.1.0` still stops with "publishes no gitsby binary". release.bash phase 3 runs the tag's install.bash into a throwaway home, says which release the line takes, and warns when a full release isn't taken or a pre-release loses to an older one.
	- Swept: `releases/latest`, `pre-release`, `full release`, `beta.1` and `one-liner` across install.bash, install.ps1, release.bash, README.md, design.md and test.bash. README, design.md "Release policy" and "Automating a release", and release.bash's header and pre-release comment are updated. `legacy/` is frozen and left alone.
	- Verified: 14 of the 21 new checks fail against gover's installers and release.bash and pass here. The other 7 pin what must not change (an explicit tag, a full release over a newer beta, no list request when the redirect's release has a binary) and pass on both. test.bash 1365/0, and `cicd.bash --gate` passes. Both installers run against the live release list stop with "No release of yottacore/gitsby publishes a gitsby binary yet", which is today's state.
	- Note: the checks run under pwsh 7 and bash 5.2 here. Windows PowerShell 5.1 and macOS bash 3.2 were not run, as with the other installer checks.
	- Branch: betainst
	- Commit: 4ccd133
	- Test case: [ddf98] through [ddf9g] (install.bash), [ddf9h] through [ddf9s] (install.ps1) and [ddf9t], [ddf9v], [ddf9w] (release.bash phase 3) in test.bash.
	- Acceptance signoff: Self-closed: the rule was set by hand on 2026-10-03, and the checks fail before the fix and pass after.
	- Closed: 20261003-171623

- Code Review 20261003 item 1: release.bash can stop partway with no message
	- ID: 2026100313123851
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: High
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- Have `pr create` print no github.com pull URL, or have curl fail in the proof step.
	- Incorrect behavior [Bug]: The script exits 1 with nothing printed. The first case is after the branch, the changelog edit and the PR exist. The second is after the release is published, so the proof is skipped.
	- Expected behavior [Bug]: The `fDie` right below each line runs and says what's left half done.
	- Reproduced [Bug]: Yes, 2026-10-03. The first by hand, the second by simulation.
	- Possible cause [Bug]: `x="$(... | grep ...)"` and `x="$(curl ... | sed ...)"` under `set -e` and `pipefail`, with no `|| true`. It's one of the Bash traps.
	- Origin: release.bash:248 from 6cdfd95 (2026-08-12) and :306 from 5a2239b (2026-09-24). Neither was filed before. The :306 block is the phase 3 path that has never run. Confirmed.
	- Actual cause [Bug]: Under `set -e`, an assignment from `$( )` takes its command's failure. The PR number grep, the `releases/latest` curl and the build line read from the native binary each ended the run there, above the message meant for it.
	- Estimated effort: Low
	- Actual fix [Bug]: Each of the three ends in `|| true`, so the check below it runs and says what happened.
	- Swept: every `$( )` assignment in release.bash. The build line was the only other one that could end the run unseen. The rest end in `|| true` or `|| fDie`, or run a command that prints its own error.
	- Verified: both checks fail on `gover` and pass here. Each of the three sites, put back alone, fails its check. test.bash passes 1280 of 1280 with both fixes in.
	- Branch: relpipe
	- Commit: f529e4f
	- Test case: [ddf3q] and [ddf3r] in test.bash. They run release.bash past its dry run, with gh, curl and gitsby stubbed. The second is the first run of the phase 3 `releases/latest` block.
	- Acceptance signoff: Self-closed: reproduced, and the checks fail before the fix and pass after.
	- Closed: 20261003-141520

- CICD reset: the hook runs `--merge-gate`
	- ID: 2026102506452488
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-064524
	- Opened by: jim-collier
	- Parent ID: 2026102416313104
	- Related IDs: 2026102506452473
		- Builds on that item's flags, in since a1c62bb.
	- Requirements [Feature]:
		- The pre-push hook runs `--merge-gate`, every check of the default run, on a push to main. A push whose commits change only docs and the other paths listed in one place the hook reads skips it. No gate on dev or gover.
		- A commit cut before `--merge-gate` existed keeps the gate it had.
		- Overrides the private CI/CD notes, where the gate on main runs lint and the unit tests only.
	- Progress log:
		- 2026-10-25: The hook runs `--merge-gate` on a commit whose cicd.bash has its arm, and `--gate` on one cut before it. A push to main whose diff from the remote's main is all in `MERGE_GATE_SKIP`, read from the pushed commit's `cicd/config.bash`, goes out with a note and no gate. A new main, or a remote commit not here, is gated.
		- 2026-10-25: `MERGE_GATE_SKIP` is `*.md`, `project/`, `reference/` and `assets/logo.png`. A pattern ending in `/` is a top folder, and any other is a glob over the whole path.
		- 2026-10-25: `--merge-gate` and `--backlog-run-full` no longer make or mount the gif's archive, since they never write there. From the gate worktree it would have landed inside `.git`.
	- Decisions:
		- The list is read from the commit, so an edit to it is itself gated, and a working-tree edit counts for nothing.
		- The hook still waits up to 10 minutes for a gate already running, though one now takes about 50.
	- Branch: round-20261025b
	- Test case: test.bash [dee52], [dee53], [dee54], [dee55], [dee56] and [dee57].
	- Verified: [dee52], [dee53], [dee54] and [dee55] fail against the round branch's pre-push.bash and config.bash. [dee56] and [dee57] are guards and pass on both. The older hook checks pass unchanged, since their stub has only `--gate)`. test.bash 1715 -> 1725, 0 failed, with 2026102506452478's checks, in `--backlog-run-quick` in the image.
	- Swept: pre-push.bash's header, install message, gate call and failure line. cicd.bash's help and its option arm comment. README, contributing.md and design.md's hook bullets. test.bash's hook checks, whose stub has no `--merge-gate`.
	- Prereq IDs: 2026102518002917
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-195133
	- 2026-10-25: Its gate worktree run stopped in stage 1 on 2026102518002917, which gover has too. Waits on that fix.
	- Verified 2026-10-25: `--merge-gate` ran from `.git/gitsby-gate` at 3490090 through all 8 stages, stages 1 to 6 in the image, all passing. Stage 7 failed on vmDebARM64 for 2026102519554107, which isn't this item's. Log: `private/claude_simple/round-20261025b_full-run.log`.

- CICD reset: containers
	- ID: 2026102416313100
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Related IDs: 2026101009380628
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per `Containers` in the shared CICD rules. A full run already uses the pinned image by default, falls back to the box with a warning, and takes `--no-container`.
		- `--gate`, and the backlog and merge gate runs that replace it, run in the image too, where docker works.
		- The builds for dogfood, stage 7 and a release come from the image's Go, not the box's. Copying them into place and the tests on other boxes stay outside it.
		- Earlier decisions this overrides: the line in 2026101009380628 that keeps dogfood and the remote tests' builds on the host, and the private notes, where `--gate` stays on the box.
	- Progress log:
	- Test case: Its children's tests: 2026102507133273, 2026102507133278 and 2026102507133283.
	- Acceptance signoff: Self-closed: every child is Done.
	- Closed: 20261025-175831
		- 2026-10-25: Split in three, one per place a build or check still runs on the box: 2026102507133273 for the quick run, 2026102507133278 for the dogfood and stage 7 builds, and 2026102507133283 for the release builds. `--merge-gate` and `--backlog-run-full` are a plain run, so their stages 1-4 and 6 are in the image already, and their stage 7 builds go with the second child.
	- 2026-10-25: Closed with its last child, 2026102507133283. It had no work of its own left.

- CICD reset: `--quick` in about 10 minutes
	- ID: 2026102506452483
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. A real `--quick` passed in the image, and so did `--backlog-run-quick`.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-064524
	- Opened by: jim-collier
	- Parent ID: 2026102416313104
	- Related IDs: 2026102506452473
		- Builds on that item's flags, in since a1c62bb.
	- Requirements [Feature]:
		- `--quick` is what fits in about 10 minutes in all, not a 30 s budget per step, per `CICD style guide` in the shared CICD rules. The regression suite likely comes back in.
		- Overrides the 30 s per step budget in 2026101816064793.
	- Progress log:
		- 2026-10-25: `--quick` runs the regression suite, the native fuzz targets and the soak test again. It still leaves out CodeQL, which `--leakcheck` adds, govulncheck and pip-audit, which ask a server, the demo gif, and stage 7's tests, though it still cross-builds stage 7's targets. `--quick --list` lists the suite and the fuzz targets too.
		- 2026-10-25: [de4by] wanted the suite and native fuzzing left out, and now wants them run. [de548] wanted no soak test under `--quick`, and now wants the soak test without CodeQL. [dee4y] wanted no suite in `--quick --list`, and now wants it. Each is relabeled to match; the rest of each check is as it was.
	- Decisions:
		- CodeQL stays out of `--quick`, since it takes about 2 minutes and more on a busy box. The soak test is the fast leak check that's in.
		- govulncheck and pip-audit stay out, since 2026101816064793's "skips anything requiring an external host" is overridden only for its 30 s budget.
	- Branch: round-20261025b
	- Test case: test.bash [de4by], [de548] and [dee4y].
	- Verified: All 3 fail against the round branch's cicd.bash and pass after. A real `cicd.bash --quick -y --no-sync --no-dogfood --no-publish` passed in the image in 222 s at a load of 14 on 32 cores: lint, go test, test.bash 1740/0, fuzz 313/0, the native fuzz targets, spawn counts, the soak test and parity, then stage 7's cross-builds. Dogfood adds 3 cross-builds of a few seconds each.
	- Swept: every `quick` test in cicd.bash's stages 2 and 3, its plan, `--list`, help, option comment and leak check default. README, contributing.md, and test.bash's other `--quick` checks, which pass unchanged.
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-175731

- CICD reset: release builds from the image's Go
	- ID: 2026102507133283
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. `--backlog-run-quick` passed in the image, and a full run doesn't run release.bash.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-071332
	- Opened by: jim-collier
	- Parent ID: 2026102416313100
	- Prereq IDs: 2026102507133278
	- Requirements [Feature]:
		- release.bash's builds, both of the reproducibility pair included, come from the image's Go where docker works. The upload and the checks against the published assets stay on the box.
	- Progress log:
		- 2026-10-25: Both of release.bash's builds go through `fImageGo`: phase 1's in the tree, and phase 3's in the tag's export, which `fImageGo` now mounts at its own path when it sits outside the tree. The image's tag and build moved out of cicd.bash into `fImageRecipe` and `fImageBuild` in `cicd/utility/include/image-go.bash`, so both scripts name the same image.
		- 2026-10-25: Without docker the builds use the box's Go with a warning, and with `CICD_CONTAINER` off they use it with a note. A dry run probes no docker and builds no image.
		- 2026-10-25: The exit trap stops and removes any build left under the release's run label, `release-<start time>`, and INT and TERM end the run through it.
	- Decisions:
		- The image is picked after phase 1's pipeline run, which builds it when it's missing, and kept for phase 3.
		- No docker is a warning, not a refusal, since GOTOOLCHAIN pins the box's Go to the same version.
	- Branch: round-20261025b
	- Test case: test.bash [dee7q], [dee7r] and [dee7s].
	- Verified: All 3 fail against the round branch's release.bash and pass after. test.bash 1737 -> 1740, 0 failed, in `--backlog-run-quick` in the image, with lint, go test, fuzz.bash, spawn counts and parity. With the real image, linux/amd64 built from an export of HEAD outside the tree matched the box's Go 1.26.2 build byte for byte, and left no container.
	- Swept: both `fpCrossBuild` calls, its one build line, and the build pin checks [dbshv], [dbft2], [dd5ex], [dd5ey] and [de56v], which count the same sites. [dbft4] no longer sees release.bash's build, since the line no longer starts with `go build`; `-p` is still on it. cicd.bash's image tag and `fContainerRun`. README, contributing.md, design.md's release section and release.bash's notes.
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-175731

- CICD reset: container cleanup
	- ID: 2026102416313102
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. `--backlog-run-quick` passed in the image.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Prereq IDs: 2026102506452478
		- It uses `--keep-temp` from that item. The other new flags are in since a1c62bb.
	- Related IDs: 2026101912030138, 2026102307533128
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per the container bullets in `Cleanup after a run` in the shared CICD rules. Containers already run with `--rm`, under a name and labels for the run.
		- Every container, image and volume the pipeline makes gets 2 labels, `dev.project=gitsby` and `dev.run=<run folder>`. Containers are named `gitsby-<run folder>-<step>`.
		- At the end of a run, on failure and Ctrl+C too, the run's containers are stopped and removed by label. `--keep-temp` keeps them.
		- Dangling images go by the project label. An older tag goes once a newer one has passed, and the current tag and the one before it stay.
		- Then `docker builder prune -f --filter until=168h`, so a week of build cache stays warm.
		- The `gitsby-cicd-cache` volume follows a 2 GB cap.
		- One line at the end says what was removed and about what it freed, from `docker system df` before and after.
		- What was built before the labels gets one pass by hand, by ID.
		- Earlier decisions this overrides: 2026101912030138, where a new image removes the one it replaces and the cache volume is kept whole, and the label and name format from 2026102307533128.
	- Progress log:
		- 2026-10-25: The run's container, the image's Go builds, the image and the `gitsby-cicd-cache` volume carry `dev.project=gitsby` and `dev.run=<run folder>`. The run's container is `gitsby-<run folder>-checks`, or `-quick` for the quick run, and each build in the image `gitsby-<run folder>-go-<subcommand>-<N>`. The image's tag hashes the project label, so the first run after this builds it again with the labels.
		- 2026-10-25: The exit trap stops and removes the run's containers by label, then removes the project's dangling images, the older tags once this one passed, and week-old build cache, and the cache volume when it's over 2 GB. One line says what went and about what it freed, or that nothing did.
		- 2026-10-25: A stop never reached the trap before. Bash holds a trap until the command in front ends, and docker passes Ctrl+C on into the container. The container run and the image's builds are now waited on, and INT and TERM end the run through the exit trap.
		- 2026-10-25: By hand, once the new image passed: the unlabeled `gitsby-cicd-cache` volume, 1.65 GB, so the next run made it with the labels, and the old image `gitsby-cicd:e6176a22793a` by ID.
	- Decisions:
		- The old `gitsby.cicd.tree` label is gone too. The run folder's counter tells two worktrees' runs apart.
		- Image tags newer than the one that passed stay, since they're another branch's.
		- A cache volume over the cap goes whole, and the next run makes it again.
	- Branch: round-20261025b
	- Test case: test.bash [dee5k], plus [debj1], [dee50], [dedn8] and [dednb] for the names and labels.
	- Verified: [dee5k] fails against the round branch's cicd.bash and image-go.bash, and so do the other 4 for the old format. `--backlog-run-quick` passed in the image: test.bash 1725 -> 1732, 0 failed, fuzz 313/0, parity 29/0. The rebuilt image and the new volume carry both labels. A real quick run in the image stopped by Ctrl+C, and another by TERM, each ended within 16 s with its container and folder gone, and said "removed 1 container(s)". Two real builds through `fImageGo` with the containers kept took `-go-version-1` and `-2`. shellcheck passes.
	- Swept: every `docker run`, `docker build` and named volume in cicd.bash, image-go.bash and remote-tests.bash. contributing.md.
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-165449

- CICD reset: `--keep-temp` and `--list`
	- ID: 2026102506452478
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. `--backlog-run-quick` passed, test.bash 1725/0.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-064524
	- Opened by: jim-collier
	- Parent ID: 2026102416313104
	- Related IDs: 2026102506452473
		- Builds on that item's flags, in since a1c62bb.
	- Requirements [Feature]:
		- `--keep-temp` keeps the run's temp folder and containers, and prints where they are.
		- `--list` prints the steps and test IDs the other flags given would run, and runs nothing.
	- Progress log:
		- 2026-10-25: `--list` prints the run's plan, then each step that runs with its count and one `<id> <label>` line per test, and stops before the prompt. It makes no temp folder and starts nothing but docker's probe. With `--backlog-run-quick` it lists the areas the same way. Stage 7 gets one line naming its boxes, since its IDs are the ones above.
		- 2026-10-25: `test-id.bash --list` gives those lines, from the same scan `--check` uses.
		- 2026-10-25: `--keep-temp` keeps the run's temp folder, and the logs and scratch files its steps would have removed from it, passed or failed, and prints the path at the end. Containers lose `--rm`, the image's builds included, and the end names what docker kept under the run's label, with the `docker rm` line. The run in the image puts its folder inside the kept one, so both are on the box.
	- Decisions:
		- `--keep-temp` with `--list` is refused, and so is either one with `--install-hook`.
		- The harnesses' own temp folders still go when they finish. Moving them into the run's folder is 2026102416313108.
	- Branch: round-20261025b
	- Test case: test.bash [dee4y], [dee4z], [dee50] and [dee51].
	- Verified: All 4 fail against the round branch's cicd.bash, image-go.bash and test-id.bash. test.bash 1715 -> 1725, 0 failed, with 2026102506452488's checks. `--backlog-run-quick` passed in the image: lint, go test, test.bash, fuzz 313/0, spawn counts and parity 29/0. A real `--backlog-run-quick unit --keep-temp` in the image kept its container and both folders, with the go test log in the inner one. `test-id.bash --check`, `backlog-check.bash` and shellcheck pass.
	- Swept: cicd.bash's help, refusals, every removal under the run's folder, both `docker run` sites, and the exit trap before and after the run log starts. README and contributing.md.
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-160233

- CICD reset: dogfood and stage 7 builds from the image's Go
	- ID: 2026102507133278
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: Done. The round's `--backlog-run-full` at c266d62 passed in the container, with stage 7's builds from the image.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-071332
	- Opened by: jim-collier
	- Parent ID: 2026102416313100
	- Prereq IDs: 2026102507133273
	- Requirements [Feature]:
		- Stage 5's cross-builds, stage 7's builds and `--quick`'s cross-builds come from the image's Go, where docker works: `fCrossBuild` in cicd.bash, and the `go test -c` binaries in remote-tests.bash.
		- Copying a build into place, and the tests on the other boxes, stay on the box.
	- Progress log:
		- 2026-10-25: Both go through `fImageGo` in the new `cicd/utility/include/image-go.bash`. Once the image is there, a run that uses it exports its tag as `GITSBY_CICD_IMAGE`, and stage 7 hands that on to remote-tests.bash. Each build is its own `docker run`, with the tree and the out dir mounted at their own paths and the Go cache volume the full run uses. Without the image, `--no-container` or no docker, they build on the box as before, and the docker warning now says the builds do too. The joining of the Mac halves and the copy into place stay on the box.
		- 2026-10-25: The round's `--backlog-run-full` at c266d62 passed stages 1-6 in the container, and stage 7 on b26 (1455/0), vmFreeBSD (1358/0) and vmDebARM64 (1699/0), against builds from the image. Dogfood was off, so its builds from the image first run at the next dogfood.
	- Decisions:
		- remote-tests.bash run by hand builds with the box's Go unless `GITSBY_CICD_IMAGE` is set. Only cicd.bash knows the image's tag.
		- cicd.bash clears `GITSBY_CICD_IMAGE` at the start, so a stale one in the shell can't move a `--no-container` build into an image.
	- Branch: round-20261025
	- Test case: test.bash [dedn8], [dedn9], [dedna] and [dednb].
	- Verified: `cicd.bash --backlog-run-quick` passed in the image: lint, go test, test.bash 1700/0, fuzz 313/0, spawn counts and parity 29/0. Against the old cicd.bash and remote-tests.bash, [dedn8], [dedn9] and [dednb] fail, and [dedna] fails with the `unset` taken out. With the real image, `fImageGo` built linux/amd64 and darwin/arm64 into a folder outside the tree, and the windows/amd64 Go tests into one under `/tmp`. The linux/amd64 build matched the box's byte for byte, both on Go 1.26.2.
	- Swept: every `go build` and `go test -c` in cicd.bash and remote-tests.bash. `fCrossBuild` covers dogfood, stage 7's Mac and Unix builds and `--quick`'s cross-builds, and `fBuildTests` covers all four of the harness's builds. The native and demo builds already run in the image when the run does. release.bash is 2026102507133283. The GOAMD64 and cgo pin checks ([de56v], [dd5ex]) still count the same sites. README, contributing.md and cicd.bash's help, plan line and warning.
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-110103

- CICD reset: other hosts and VMs
	- ID: 2026102416313101
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: Done. The round's `--backlog-run-full` at c266d62 passed stage 7 on b26, vmFreeBSD and vmDebARM64.
	- Needs external testing: Done. vmKt6m and b29w passed at e47bd23, under the real lock and VM helper.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Related IDs: 2026100312332924
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per `Other hosts and VMs` in the shared CICD rules. Stage 7 already runs on the Mac, the Unix boxes and a Windows box, holds each through the shared host lock, and skips a box that's off or taken.
		- Windows tries b29w first, and vm925w only when b29w is taken or down. Nothing here needs the discrete GPU.
		- Windows tests use `b29w`, never `b29w-wif`. The Windows host list in `cicd/config.bash` still has `b29w-wif` as a second ssh name.
		- A VM is put back the way it was found, through the VM state helper: a paused one resumed and paused again, one that was off started and powered off, a running one left running.
		- Each box's work folder for the project is under that box's temp root. On the Mac and the Unix boxes it's in the home folder today.
		- A skipped box shows as `SKIP` in its step line and in the summary at the end, and never stops a run, `--merge-gate` included.
		- vmKt6m joins b26 for Intel macOS, where it adds something b26 doesn't.
		- Earlier decisions this overrides: the 2026-10-04 decisions in 2026100312332924 that take vm925w first on Windows and keep the tree's copy under each box's home.
	- Estimated effort: Avg
	- Progress log:
		- 2026-10-25: Windows is `b29w` then `vm925w`, and `b29w-wif` is gone from config.bash.
		- 2026-10-25: A box the VM state helper knows as a VM runs through its `wrap`, which wakes it under the lock and puts it back after. Such a box isn't looked for over ssh until it's up. One that won't come up is skipped with the helper's reason. One that won't go back gets a warning, and its result stands. Other boxes keep the lock's own `wrap`. With no helper beside the lock, a note says so, and a sleeping VM is skipped as before.
		- 2026-10-25: Each Mac and Unix box keeps its copy in `gitsby/remote-tests` under `HOST_TEMP`, else `TMPDIR` without its last slash, else `/tmp`. The Wine prefix sits beside it. Windows already used `%TEMP%`, and is unchanged.
		- 2026-10-25: vmKt6m is a second Mac host, as `mactest`. A Mac now checks for its bash, git and go the way the Unix boxes do. Without them it runs the Go tests only and names what it lacks.
		- 2026-10-25: Every skip line in the harness says `SKIP`. The summary names the skipped boxes after `SKIP:`. A skip still never fails the run.
		- 2026-10-25: Asserts given new values for this change. `[ddg8a]`, `[ddgm1]`: Windows list `vm925w b29w` -> `b29w vm925w`. `[ddg8b]`, `[dednb]`, `[ddg8f]`, `[ddg8j]`, `[ddg8p]`: the first Windows box is b29w, not vm925w. `[ddg8g]`, `[ddg8h]`, `[ddga0]`, `[ddg89]`: the same order, and the summary now ends in `SKIP: <boxes>`. `[ddg8g]` keeps its second-name case on vm925w in the fixture, since `b29w-wif` is gone. `[ddg8d]`, `[ddgm3]`: `cd "$HOME/gitsby-remote-tests/tree"` -> `cd "$d/tree"`. `[ddg88]`, `[ddg8m]`, `[ddg8n]`, `[ddgm4]`, `[ddgm5]`, `[ddgm6]`: `skip:` -> `SKIP:`.
		- Verified: the 9 new checks and the changed ones pass. Run against the old remote-tests.bash and config.bash, all 9 new checks fail, and so do 14 of the existing stage 7 checks.
		- Verified: shellcheck, `test-id.bash --check`, and `--backlog-run-quick lint unit` pass.
		- Note: vmKt6m ignores the ACPI shutdown. A run that finds it off waits 300 s for the helper's restore, then warns and leaves it running. The fix belongs in the helper. Draft in `private/claude_simple/upstream/2026102416313101/`.
		- 2026-10-25: The helper's `wrap` takes `--why` and `--eta` now, fixed in place. Moving stage 7 onto it for every box is 2026102511210617.
		- Note: the old `~/gitsby-remote-tests` folders on b26, vmFreeBSD and vmDebARM64 are no longer used. Nothing removes them.
		- 2026-10-25: In the round's full run, vmKt6m failed its copy step with `go: command not found` (exit 127). The tools check looks for go with Homebrew's bash folder first on PATH, and found it there. The module fetch ran on the bare ssh PATH. The fetch is only for the suite, so it now runs on the suite's PATH, the one the check used. A Mac with no go there still fetches nothing and names go.
		- 2026-10-25: The Go tests step needs no go, since its binary is built here. It runs on the box's own PATH, and the Go tests that use git skip without one. Not checked: a Mac whose `/usr/bin/git` only offers to install the command line tools would fail those tests rather than skip them.
		- Verified: test.bash 1715/0 with the fix. Against the harness before the fix, `[dedtn]` fails on the same exit 127, and the other 1714 pass. `--backlog-run-quick` passed in the image: test.bash 1715/0, fuzz 313/0, parity 29/0.
		- 2026-10-25: In The round's `--backlog-run-full` at c266d62, stage 7 passed on b26 (1455/0), vmFreeBSD (1358/0) and vmDebARM64 (1699/0), each copy under its box's temp root, and both VMs went back to off. b29w was held by another job, and vm925w was skipped on "Failed to reserve port 5900", which is Bug 2026102510404322.
		- 2026-10-25: Stage 7 on vmKt6m alone at e47bd23: it was off and came up through the helper, the copy went under its temp root, the module fetch worked, and it ran the Go tests (213 ok, 6 skipped) and test.bash 1357/0. The helper's restore went through only after a shutdown from inside, per the note above.
		- 2026-10-25: The Windows Go tests on b29w at e47bd23, with vmKt6m down: 197 ok, 23 skipped, none failed. b29w was free, so vm925w wasn't tried.
		- Verified: stage 7 on vmKt6m, test.bash 1357/0 and the Go tests, and on b29w, the Go tests, both passed.
	- Decisions:
		- 2026-10-25: vmKt6m runs everything b26 runs. Both are Intel macOS 15.8, and the GPU difference means nothing to a CLI. What it adds is a test user who isn't an admin, with only the system on PATH.
		- 2026-10-25: Only VMs go through the helper. Its `wrap` takes no `--why`, so the other boxes keep the lock's `wrap` and still say what they're held for.
		- 2026-10-25: The tools check, the fetch and test.bash share one PATH on a Mac, the suite's. So a Mac whose Homebrew folder has go and git runs test.bash, even when the bare ssh PATH has neither.
	- Swept: every reader of `REMOTE_WINDOWS_HOSTS`, `REMOTE_MAC_HOSTS`, `REMOTE_MAC_DIR` and `REMOTE_UNIX_DIR`. cicd.bash only prints the host lists, and the test.bash fixture pins its own. Every `skip:` line in remote-tests.bash. README and contributing.md, which named one Mac and said nothing about VMs.
		- 2026-10-25: every remote command in `fRunPosix`, for a tool it runs off the PATH it was checked on. Only the fetch did. The Unix boxes use the bare PATH for all of it, and the copy, Go tests and Wine steps run nothing from Homebrew.
	- Branch: round-20261025
	- Commit: 4388d96, b14ae19
	- Test case: test.bash `[dedp8]` (config order), `[dedp9]` (temp root), `[dedpa]` and `[dedpg]` (copies under it), `[dedpb]` (no helper), `[dedpc]`, `[dedpd]` and `[dedpe]` (VM wake, no wake, no restore), `[dedpf]` (Mac tools), `[dedtn]` (Mac fetch on the suite's PATH), plus the changed asserts above.
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-110103

- CICD reset: CPU and priority
	- ID: 2026102416313103
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: Done. The round's `--backlog-run-full` at c266d62 passed in the container.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261024-163131
	- Opened by: jim-collier
	- Related IDs: 2026102508333054
	- Requirements [Feature]:
		- Sweeping override, 2026-10-24: this supersedes any earlier decision on this project that conflicts with it.
		- Per `Machine use` in the shared CICD rules. `BUILD_JOBS` in `cicd/config.bash` is already worked out once and handed to the Go tools and CodeQL.
		- At most half the cores, rounded down and at least 1. Today it rounds up.
		- A quarter on a busy box, where the 1-minute load is over half the CPU count. Checked at the start and again before each stage.
		- A quarter, busy or not, for the hard steps: native fuzzing, `go test -race`, the soak test and CodeQL.
		- Steps that run side by side share the count.
		- Everything runs under `nice -n 19`, plus `ionice -c 3` where it exists.
		- The container run gets `--cpus <jobs>` and `--cpu-shares 256`, and `nice` inside too.
			- 2026-10-25: that covers the per-build `docker run` in `fImageGo` (`cicd/utility/include/image-go.bash`, eb6aa5e) as well as `fContainerRun`.
		- The same rules on the boxes stage 7 uses, with each box's own CPU count and load. The Go tests there run with no limit today.
	- Progress log:
		- Done: half the cores rounded down, or a quarter on a busy box, never under 1, worked out at the start and again at each stage header. The hard steps take a quarter.
		- cicd.bash, release.bash and remote-tests.bash renice themselves to 19, with `ionice -c 3`, so all they start inherits it.
		- Both `docker run` sites get `--cpus` and `--cpu-shares 256`, and go runs niced in the image. The run in there works its counts out from the box's cores and load.
		- Each Mac and Unix box in stage 7 works out its own count from its own cores and load, and runs its Go tests and test.bash at low priority.
		- The plan prints a "Cores" line with the counts and the load.
		- Steps run one at a time, and the module is one package, so nothing shares a count yet.
		- Split: the Windows box's part is 2026102508333054.
		- 2026-10-25: [dedn8], [dedn9] and [dednb] want `nice -n 19 go` after the image name, where they wanted `go`. [ddg8d] and [ddgm3] want `$lo` before the box's bash, where they wanted none.
		- Verified: all 5 new checks fail on the tree before and pass after. [dedq4] passes in the image too.
		- Verified: `--backlog-run-quick` in the image, test.bash 1714/0, fuzz 313/0, parity 29/0, with "8 of 32" cores at a load of 25.
		- 2026-10-25: The round's `--backlog-run-full` at c266d62 passed stages 1-6 in the container, at "8 of 32" cores and load 37.75, and stage 7 on b26, vmFreeBSD and vmDebARM64. vmKt6m and b29w passed at e47bd23.
	- Decisions:
		- The budget stays in config.bash, as `fCpuBudget`, setting `BUILD_JOBS` and the new `HEAVY_JOBS`.
		- Each script lowers its own priority once at the top, rather than a prefix on every command.
		- The container's quota is the count at its start. `GITSBY_CICD_CPUS` hands the box's core count in, since the quota leaves nproc alone.
	- Test case: test.bash [dedq1] (the counts), [dedq2] (the hard steps), [dedq4] (low priority), [dedq3] (the container's quota), [dedq5] (each box in stage 7).
	- Swept: every `BUILD_JOBS` reader in cicd.bash, release.bash and remote-tests.bash, both `docker run` sites, and every remote command in remote-tests.bash. The Windows box's commands are the child. `docker build` runs only when the image changes, and is left alone.
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-110103

- CICD reset: run flags and aliases
	- ID: 2026102506452473
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: Done. The round's `--backlog-run-full` at c266d62 ran end to end.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-064524
	- Opened by: jim-collier
	- Parent ID: 2026102416313104
	- Requirements [Feature]:
		- `--long`, with `--slow` as another name, `--backlog-run-quick [<area>...]`, `--backlog-run-full` and `--merge-gate`. `--help` lists the areas.
		- `--gate` and `--ci` stay as other names for `--backlog-run-quick` and `--merge-gate`, and say so in one line when used. `pre-push.bash` looks for the `--gate)` arm, so it changes with it.
		- The backlog and merge gate flags never dogfood, publish, commit, push, install, sync, rewrite a tracked file, or prompt. That covers the demo gif.
	- Progress log:
		- 2026-10-25: Done in cicd.bash. `--backlog-run-quick` runs the areas `lint`, `unit`, `suite`, `fuzz` and `parity`, all of them with none named, the three suites against one build of their own. `--merge-gate` and `--backlog-run-full` are a plain run with sync, dogfood and publish off and no prompt, and stage 6 leaves a gif that differs as committed. The run in the image is told the same.
		- 2026-10-25: [dcman] and [ddg86] read the closing line `gate: passed`, now `quick run: passed`. [dcman] no longer forbids the build and the suites under `--gate`, since `--gate` runs them now. The rest of both is as it was.
		- 2026-10-25: The round's `--backlog-run-full` at c266d62 ran end to end with sync, dogfood and publish off and no prompt, and left the gif as committed. Stages 1-6 passed in the container. Its one failure was vmKt6m in stage 7, fixed by b14ae19 and passed at e47bd23.
	- Decisions:
		- With no area named, `--backlog-run-quick` runs the suites too. A worker ran them by hand beside `--gate` anyway, and the whole thing took about 3 minutes on 8 cores at a load of 10.
		- `--merge-gate` and `--backlog-run-full` are the same checks, the other boxes included. They take the `--no-<step>` and container flags, and refuse `-m` and `--quick`.
		- A gif that differs under them is a warning, not a failure, since the gif isn't a check.
		- `--long` adds nothing yet, since no step here takes hours. `--backlog-run-quick` stays on the box until 2026102416313100.
		- pre-push.bash is unchanged. `--backlog-run-quick|--gate)` still holds `--gate)`, so a commit with the gate is told apart as before. The hook still runs `--gate`, which now runs the suites too. Moving it to `--merge-gate` is 2026102506452488.
	- Branch: round-20261025
	- Test case: test.bash [dedkw], [dedkx], [dedky], [dedkz], [dedm0], [dedm1], [dedm2], [dedm3], [dedm4], [dedm5] and [dedm6].
	- Verified: All 11 fail against the round branch's cicd.bash, and [dedm0], [dedm1] and [dedm2] fail with the gif and image hand-offs taken out. test.bash 1677 -> 1688, 0 failed. `cicd.bash --backlog-run-quick` passes on this tree, lint, go test, test.bash 1688/0, fuzz 313/0, spawn counts and parity 29/0, in 175 s. `test-id.bash --check` and `backlog-check.bash` pass.
	- Swept: cicd.bash's help, option arms, refusals, container hand-off, plan and stage 6. README, contributing.md and design.md's gate bullet. pre-push.bash's arm check and its call. test.bash's gate checks that read the old closing line.
	- Acceptance signoff: Self-closed: its test runs passed.
	- Closed: 20261025-110103

- CICD reset: the quick run in the image
	- ID: 2026102507133273
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261025-071332
	- Opened by: jim-collier
	- Parent ID: 2026102416313100
	- Requirements [Feature]:
		- `--backlog-run-quick`, and `--gate` with it, runs in the pinned image where docker works, like a full run. A box without a working docker runs it here, with the same one-line warning.
		- `--no-container` keeps it on the box, and `--container` makes the image a must.
	- Progress log:
		- 2026-10-25: `--backlog-run-quick` hands itself to the image as a full run does, by its own name with the areas and `-q` as given, and prints the outer passed line once the inner one passes. The image's tag and its run are shared with the full run, so the two can't drift. The gif's archive isn't mounted for it.
	- Decisions:
		- `--container` and `--no-container` go with the quick run now, and only `--install-hook` refuses them. [ddrp5], "--container with --gate is refused", is commented out in test.bash for that reason: it encoded `--gate` staying on the box, which this issue overrides. [dedms] checks the new behavior in its place.
		- 2026-10-25: [ddrp5] stays commented out, with the reason above it, rather than deleted.
		- The pre-push hook's `--gate` goes into the image with it, so a push to main is gated by the image's tools too.
	- Branch: round-20261025
	- Test case: test.bash [dedmq], [dedmr], [dedms], [dedmt] and [dedmv].
	- Verified: `cicd.bash --backlog-run-quick` passed with every area in the image: lint, go test, test.bash 1688 -> 1692, 0 failed, fuzz 313/0, spawn counts and parity 29/0. Against the old cicd.bash, [dedmq], [dedmr], [dedms] and [dedmt] fail, and [dedmv] passes as a guard. The image sees the pre-push snapshot under the git dir and resolves it. `--no-container --backlog-run-quick lint`, `test-id.bash --check` and `backlog-check.bash` pass.
	- Swept: cicd.bash's container decision, refusals, help, image tag and its one `docker run`, now shared by both runs. test.bash's gate checks, each of which now says `--no-container`, apart from the refusals, which stop before the choice. README, contributing.md and design.md's gate bullet. pre-push.bash still calls `--gate` and needs no change.
	- Acceptance signoff: Self-closed: its own tests passed, and so did the real quick run in the image.
	- Closed: 20261025-072651

- Updates to CICD script flags
	- ID: 2026101816064793
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261018-160647
	- Opened by: jim-collier
	- Milestone: Pre-next-cut. Do next.
	- Requirements [Feature]:
		- `--gate` keeps its name. No `--ci` alias.
		- `--quick`:
			- Runs whatever linting, validation, and testing steps are very quick.
			- Cross-compiles whatever is fast; e.g. maybe skip slow arm64.
			- Skips anything requiring an external host.
		- No flags by default does everything.
		- The other existing flags can stay.
	- Note: `--gate` is also named by the pre-push hook `--install-hook` writes, and in the README and memory.
	- Progress log:
		- 2026-10-18: Each step was timed on b23, at a load of about 16. Every cross-build takes 4 to 6 s, arm64 included, and the lint stage about 23 s in all. The regression suite takes about 100 s, and the native fuzz targets 5 s each for 8 targets. fuzz.bash takes about 7 s, the spawn counts 3 s, parity 2 s, and go test 3 to 12 s.
		- 2026-10-19: The leak checks join the plain full run, through 2026101912030152, so no flags does everything again.
	- Decisions:
		- The 30 s budget is per step. The lint stage alone is close to it, so a whole-run budget would leave nothing else.
		- Sync and publish stay in `--quick`. They only fetch from and push to origin, the repo's own git host, and the requirement is about other hosts. `--no-sync` and `--no-publish` still turn them off.
		- govulncheck is out of `--quick`, since it asks vuln.go.dev. That reverses the 2026-08-19 call that it runs there as a lookup.
		- `--quick` runs fuzz.bash and the spawn counts now. Both take seconds. The native fuzz targets stay out.
		- `--quick` dogfoods every target again, and builds the FreeBSD and Linux arm64 targets without testing them. That reverses review 20260819a item 18, whose reason was that cross-builds were the slow part. `[dbft5] --quick narrows the cross-builds too` is off for that reason.
		- The regression suite is out of `--quick`. That supersedes the 20260909 enhancement 7 call to keep it whole there. contributing.md now says to run the full pipeline before a PR.
		- The demo gif stays out of `--quick`. It takes about 15 s, but it's not a check.
	- Branch: cicdflags
	- Test case: test.bash `[de4bw]` for the `--gate)` arm the hook looks for. `[de4by]`, `[de4bx]`, `[de4bv]` and `[de4bt]` for `--quick`. `[dbft5]` is off since 2026-10-18.
	- Swept: the help header, history footer, README, contributing.md and config.bash comments for both flags. pre-push.bash still finds `--gate)` in the option arm. design.md names only `--gate` and is unchanged. The test.bash helpers that used `--quick` as shorthand for skipping fuzz, the demo and the remote tests now name those flags.
	- Acceptance signoff: Signed off by jim-collier in conversation, 2026-10-19.
	- Closed: 20261019-150000

- pip-audit fails every full run in the container on 8 new Pillow 12.3.0 advisories
	- ID: 2026102113100000
	- Type: Task
	- Status: Done
	- Needs local test suite run?: No. The plain full run in the container passed 2026-10-22.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261021-131000
	- Opened by: jim-collier
	- Related IDs: 2026101905585018, 2026101912030152
	- Requirements [Feature]:
		- pip-audit in the image reports CVE-2026-112395, 112397, 112400, 112404, 112895, 112896, 112897 and 112899 against Pillow 12.3.0, all fixed in 13.0.0. Stage 3 stops there, so a plain full run in the container can't pass.
		- Check each, then move the lock's Pillow to 13.0.0, or list on `PIP_AUDIT_IGNORE` any that can't reach the demo. A newer Pillow means rendering and comparing the gif again, as 2026101905585018 did.
	- Progress log:
		- 2026-10-21: Seen on a full run on b23. Log: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261021-12295100/run1.log`. Stages 1 and 2 passed, test.bash 1594/0, and so did fuzz.bash 313/0, the native fuzz targets and govulncheck.
		- 2026-10-21: Checked all 8 against PyPI's advisories. 4 are in TIFF decoding and saving (112395, 112404, 112896, 112897). The others are a PDF append (112895), a GIF seek after a decompression bomb error (112400), a zero-width PPM through ImageMorph (112397), and EPS through Ghostscript (112899). The demo opens no image file and saves only its own GIF, so none reach it.
		- 2026-10-21: PyPI now lists 24 advisories against 12.3.0, all fixed in 13.0.0. 13.0.0 has a CPython 3.13 manylinux x86_64 wheel, and the lock's hash is the one PyPI gives. Its breaking changes touch nothing the renderer calls.
		- 2026-10-21: The lock's Pillow is 13.0.0, and `PIP_AUDIT_IGNORE` still holds only fontTools' entry. The image's tag moved to `gitsby-cicd:6fd011f04201`.
	- Decisions:
		- Moved Pillow rather than listing the 8. The answer on 2026101905585018 allows it, 13.0.0 fixes them all, and a list of 24 would need its own upkeep.
	- Branch: round-20261022
	- Commit: 73d6a98
	- Test case: test.bash [de5av] for the lock's Pillow, and pip-audit's [de54e] and [de54k]. The image build also stops on a Pillow other than the recorded one. No new check, since the audit in the image is what failed.
	- Verified: Stage 3 and the demo stage in the new image. pip-audit is clean on Pillow 13.0.0 with fontTools' one entry set aside, govulncheck is clean, fuzz.bash 313/0, and the spawn counts pass. The demo gif renders byte for byte the same, so it didn't change. test.bash 1598/0, and `cicd.bash --gate` passes.
	- Swept: `TOOL_VERSIONS`, the Dockerfile's Pillow check, which reads the ARG, and its apt comment, the lock's header, and contributing.md's demo prerequisite, which names no version. "12.3.0" is left only in the backlog and the history footer.
	- Verified: 2026-10-22, a plain full run in the container on b23 passed every stage. Stage 3's pip-audit was clean on Pillow 13.0.0, and stage 6 rendered the demo gif unchanged. test.bash 1598/0, fuzz.bash 313/0, parity 29/0. Log: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261021-19403500/run1.log`.
	- Acceptance signoff: Self-closed: its own test, the plain full run in the container, passed.
	- Closed: 20261021-203604

- `--staged`: commit only what is staged, and leave the rest of the tree alone
	- ID: 2026100512025340
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: High
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- A `--staged` flag on `pullcom`, `sync`, and the branch commands that commit the tree before they move: `br create` off a feature branch, `br switch` and `br merge`.
		- With it, the commit takes the index only. Nothing is staged, and unstaged or untracked edits stay where they are.
			- Nothing staged means nothing is committed. The command goes on with the rest.
			- On a checkout, the leftover edits come along, the way plain git does it.
			- Where git would refuse that checkout, the plan says so before anything runs.
		- The plan shows which files get committed and which stay behind.
		- Without the flag, nothing changes.
	- Notes:
		- Each of those commands runs `git add --all` first today. In a tree with hand edits that aren't part of the change, that sweeps them in.
		- `br create` from `main` or `dev` already carries edits over, and stays that way.
	- Decisions:
		- A flag, not a new command (2026-10-05). It keeps the count of commands down.
		- Opt-in, not switched on by finding something staged (2026-10-05). A file staged long ago would quietly make the commit smaller, and under `-q` nobody reads the plan. Most users never think about the index, and shouldn't have to.
		- It doesn't go against design.md's line that partial staging belongs to raw git. Gitsby still stages nothing itself. It only stops undoing a `git add` that was already made. design.md gets a line saying so.
		- Before the first Go release, since flags and aliases are permanent after it.
	- Estimated effort: Avg
	- Progress log:
		- Verified: git's autostash brings staged work back unstaged, on git 2.51. A file staged and then edited again lost its staged copy. Git's current source still reapplies it that way. A plain fast-forward with no stash kept the index, and where incoming commits touched a file with edits here, git refused and changed nothing.
		- So with `--staged` no pull uses `--autostash`. Committing the staged part before the pull was the other way, but a remote that moved ahead would then be diverged.
		- Done: `--staged` on `pullcom`, `sync`, `br create`, `br hotfix`, `br switch` and `br merge`. The commit takes the index only, and the plan lists what is committed and what stays. Nothing staged commits nothing, and the run goes on.
		- Done: a pull or checkout that git would refuse over the edits left in the tree is refused before the plan, with nothing done. That is the reading taken of "the plan says so before anything runs": a plan that can't finish isn't shown. A pull from a remote other than origin can't be read ahead; git refuses that one at the time.
		- Note: `br hotfix` takes the flag too, since it is the same recipe as `br create`. `pr create` and `release` also commit the whole tree, and refuse the flag for now. Adding it there later breaks nobody.
		- Done: help, README, workflows.md, the changelog, and design.md, with the line the Decisions ask for and the autostash finding.
		- Verified: `go test ./...` and the gate pass. The 18 new suite checks pass on their own. With `--autostash` put back on every pull, 6 of them fail. With the read-ahead turned off, 4 fail.
		- Verified: the full test.bash on the merged tree, 1471/0 (2026-10-05).
		- For signoff: `br hotfix` taking the flag, `pr create` and `release` refusing it, and the plan's two list labels, "staged, so committed:" and "not staged, so left as is:".
		- Answered 2026-10-05: `br hotfix` taking the flag is OK.
		- Answered 2026-10-05: `pr create` and `release` take the flag too, with the same rules as the other commands.
		- Still open: the plan's two list labels. They are being looked at in context, and stay as they are until then.
		- Done: `--staged` on `pr create` and `release`. Their commit takes the index only, no pull uses `--autostash`, and the plan lists what is committed and what stays. Nothing staged commits nothing, and the run goes on.
		- Done: `release` reads ahead every pull and checkout up to the default branch, and refuses before the plan where git would stop. A file that passes is the same on every branch read, so the merge, the move back to `dev` and the last checkout can't touch it. Only the index counts as work to release, so a level repo with only unstaged edits says there is nothing new, as it would with a clean tree.
		- Done: `pr create` parks the way `sync` does. Both `gh` and `tea` are handed the branch with `--head`, and with that neither looks at the working tree. Read in their source, not run against a real host.
		- Done: `pr ok` still refuses the flag, since it commits nothing. The old test.bash check that release refuses the flag, `[ddhth]`, is commented out with the reason, and `[ddhvb]` asks the same of `repo connect`. Go test `[ddht9]` now expects `pr create` and `release` to take it.
		- Done: README, the changelog and design.md list the 2 commands. Help and workflows.md name no commands for the flag, so they needed nothing.
		- Verified: `go test ./...` and the gate pass. The 12 new suite checks and the 25 around them pass on their own. Against the build before this, 10 of the 12 fail; the other 2, a plan with no `git add` and `pr ok` refusing, pass either way and guard against a regression. With the release read-ahead turned off, 2 fail. With the nothing-new rule back on the whole tree, 3 fail.
		- Verified: the full test.bash on the branch, 1482/0 (2026-10-05).
		- For signoff: the plan's two list labels only.
		- Answered 2026-10-05: the labels read "Changes to commit:" and "Changes to leave alone:". The plan prints before anything runs, so past tense read wrong.
	- Branch: staged, stagedpr
	- Commit: 9f53a91, 7c3281d
	- Test case: Go tests `[ddht8]`, `[ddht9]`, `[ddhta]`. test.bash `[ddhtb]` through `[ddhtw]`, 18 checks, with `[ddhth]` off since 2026-10-05. For `pr create` and `release`: `[ddhvb]` through `[ddhvk]` and `[ddhvm]` through `[ddhvp]`, 12 checks.
	- Swept: every `--autostash` and `git add --all` in `src-go`. The commit and the pull in mutate.go, br create from `main` or `dev` in branchcmd.go, and both plan lines in preview.go. The file list in repo.go is for `repo create` and `repo connect`, which refuse the flag. The pulls in pr.go and release.go run on a clean tree, and those commands refuse the flag.
	- Swept (2026-10-05, `pr create` and `release`): every step after their commit. In release.go the pulls of `dev` and the default branch, both checkouts, the merge and its back-out, the tag, both pushes, and the fast-forward of `dev`. Its nothing-new check read the whole tree as work to release, and now reads the index under the flag. In pr.go the push and the `gh` or `tea` call. `pr ok` reads the whole tree to refuse, and refuses the flag. The line above about pr.go and release.go held only while they refused the flag.
	- Acceptance signoff: 2026-10-05, all 3 choices answered.
	- Closed: 2026-10-05

- A `gh` wrapper that calls `gitsby raw gh` still fails, and gitsby's own `gh` calls fail behind it
	- ID: 2026102306584122
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. test.bash ran 1667/0.
	- Needs external testing: No. Stage 7 on vmDebARM64 ran them 2026-10-23.
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261023-065841
	- Opened by: jim-collier
	- Related IDs: 2026101916533300
	- Target OS: All
	- Steps to reproduce [Bug]:
		- Put the wrapper tukzedo used on b28l first on PATH, a `gh` that runs `exec gitsby raw gh "$@"`, with the real `gh` later on PATH.
		- Run `gitsby raw gh --version`, a bare `gh --version`, a script that calls bare `gh`, `gitsby whoami` and `gitsby pr`.
	- Incorrect behavior [Bug]:
		- No loop since 2026101916533300, but every one fails. `raw` refuses with "Looping: ... Unset GITSBY_RAW_ACTIVE to run anyway." `whoami` says gh is not logged in, and `pr` says "'gh pr list' failed".
		- The hint is wrong for a wrapper. Unsetting the variable brings the endless loop back.
	- Expected behavior [Bug]:
		- The wrapper does what it was written for. Every one of those reaches the real `gh`, as the account, after one extra start.
	- Reproduced [Bug]: 2026-10-23 on b23, with `private/claude_simple/tools/rawloop-rig.bash`. 2 or 3 wrapper starts each, then the refusal. 6 for `whoami` and `pr`, from their probes.
	- Possible cause [Bug]:
		- `rawNest` refuses when its own entry is already on the chain. That entry means the file it found is what started it, so the file is a wrapper. Passing over that entry and going on down PATH would find the real tool.
	- Requirements [Bug fix]:
		- A `raw` whose entry for a PATH entry is already on the chain passes over that entry and tries the next one. It refuses only when none is left, or past the depth limit.
		- A `raw` started under the probe mark does the same, and hands over with no account work or probes of its own, so probes can't multiply.
		- The refusal drops the advice to unset `GITSBY_RAW_ACTIVE`, or gives it only where it can't loop.
		- Hooks and aliases that call `raw` keep working as the 2026-10-22 decision says.
		- Test case: the wrapper above, with each of those commands reaching the real `gh` and a counted cap on starts. Watch it fail on the current build first.
	- Actual cause [Bug]:
		- As guessed. `rawNest` refused a repeat instead of passing over the file that started it, and a `raw` under the probe mark refused outright, so every probe behind the wrapper failed too.
	- Estimated effort: Avg
	- Actual effort: Avg
	- Progress log:
		- 2026-10-23: The item it follows set out to refuse. The 2026-10-22 answer, "What any sane human git user would expect", points at making a wrapper like this work instead. tukzedo's memory now says never to put such a wrapper on PATH.
		- 2026-10-23: Fixed. `raw` walks PATH per candidate and passes over a tool file whose run, same folder and arguments, is already on the chain, then takes the next one. It refuses only when none is left, or past 16 deep, and no longer says to unset `GITSBY_RAW_ACTIVE`. A `raw` that passed one over, or runs under the probe mark, hands over with no account work or probes.
		- Cost behind the wrapper, in wrapper starts: `raw gh` 2, its probe and the handover. A bare `gh` or a script 3. Each `gh` call gitsby makes 3, so `whoami` and `pr` take 6, as before, but now reach the real `gh`. A wrapper adding an argument each time takes 2 per level and stops at 16 deep, 32 starts, the same as before.
		- Departs from the wording: not "one extra start". Getting there would mean gitsby's own `gh` calls not starting a full `raw` behind the wrapper, for one by having every gitsby mark what it runs the way the probes are marked. That changes hooks under non-raw commands, so it isn't done here.
	- Decisions:
		- Under the probe mark, a tool file on the chain is passed over whatever its arguments. A probe's arguments are gitsby's own, so nothing under it has a reason to run that file again. Matching on the arguments too cost 2 starts a probe, and a drifting wrapper's probes each ran to the depth limit.
		- A chain entry now holds a hash of the tool's path on its own as well as the one over path, folder and arguments.
		- The entry handed over is for the arguments handed over, which `glab auth status` changes.
	- Actual fix [Bug]:
		- `walkTool` in exec.go is `lookTool` with a filter, and `cmdPassthrough` uses it with `rawOnChain`. `rawNest` only adds the entry and keeps the probe mark last.
	- Branch: round-20261023b
	- Test case: test.bash `[de899]`, `[de89a]` and `[de89c]`, reworded to reach the tool, and new `[deatd]` (bare gh), `[deate]` and `[deatf]` (refusal with nothing after it), `[deatg]` (whoami) and `[death]` (pr). Each wrapper quits past 8 starts now, since a gitsby `gh` call takes 3. Go `[de89e]`, `[de8pk]` and `[de8pm]`, reworded.
	- Verified: 2026-10-23, test.bash 1662 -> 1667, 0 failed. On the build before, the 8 reworded and new checks fail. The Go tests fail with the pass-over, the probe file match and the kept probe mark each taken out. The rig shows every one of the five commands reaching the real `gh`, where before each was refused. The hook and alias rig still passes. `GOOS=windows go vet` and the Windows test build, and darwin and freebsd builds, pass.
	- Verified: 2026-10-23, the round's full run. The 8 reworded and new test.bash checks passed in the container, on b26 and on vmFreeBSD, and `[de89e]`, `[de8pk]` and `[de8pm]` in the Go tests on b26, vmFreeBSD and vm925w. test.bash was 1438 of 1439 on b26 and 1341 of 1342 on vmFreeBSD, each 6 more than on 10-22. The one failure on each is `[de5av]`, from 2026102220133673. Go tests: b26 211 ok and 6 skipped, vmFreeBSD 213 ok and 4 skipped, vm925w 195 ok and 23 skipped. The macOS workflow, run 39970887647, passed the same checks on both runners, test.bash 1417 of 1418 with the same one failure. b29w was not reachable. Logs: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261023-07353000/run.log` for the container, `run2.log` beside it for stage 7.
	- Verified: 2026-10-23 on b28l with tukzedo's wrapper and the real `gh`, on the synced build `c917c95`, together with 2026101916533300. Every command in the steps above reached the real `gh` and exited 0. `whoami` took 9 wrapper starts and `pr` 6, the rest 2 or 3.
	- Verified: 2026-10-23, stage 7 on vmDebARM64 alone, on round-20261023d `e2f93e9`. The 8 reworded and new test.bash checks passed, and `[de89e]`, `[de8pk]` and `[de8pm]` in the Go tests for linux/arm64 and for windows/arm64 under Wine. Go tests 218 ok and 2 skipped, and 190 ok and 30 skipped under Wine. test.bash failed 23 checks of the remote harness and stopped there, all from the narrowed host lists, filed as 2026102321011743. Log: `/mnt/ext/wip2/wip/tmp/gitsby/20261023-200002/001/run.log`.
	- Swept: `rawActive` and `rawNest` have one caller, `cmdPassthrough`, which every `raw` tool shares. `findTool` and its cache are unchanged for every other spawn. README names no refusal text. design.md's `raw` bullet updated.
	- Acceptance signoff: Self-closed 2026-10-24. The behavior changed from the expected "one extra start" to 2 or 3 per `gh` call. Each is a short Go start, and getting to one would change hooks under every command, against the 2026-10-22 decision.
	- Closed: 20261024-133500

- test.bash's goleak check `[de54n]` fails on macOS, since BSD find has no `-printf`
	- ID: 2026102220274491
	- Type: Bug
	- Status: Done
	- Needs external testing: No
	- Priority|Severity [Bug]: Avg
	- Opened: 20261022-202744
	- Opened by: jim-collier
	- Related IDs: 2026102218410000
	- Target OS: macOS
	- Steps to reproduce [Bug]:
		- Run `cicd/test.bash` on a Mac whose `find` is the system one.
	- Incorrect behavior [Bug]: `[de54n]` fails. The first macOS workflow run, 39893939993 on `macos-latest` (arm64), passed 1411 and failed only that one.
	- Expected behavior [Bug]: It passes whenever every folder with Go tests calls `goleak.VerifyTestMain(m)`, on any OS.
	- Reproduced [Bug]: Yes, 2026-10-22 on b23, with a stand-in `find` on PATH that refuses `-printf` the way BSD find does. The check failed.
	- Actual cause [Bug]: The check listed test folders with `find ... -printf '%h\n'`. BSD find has no `-printf`, so it printed nothing. The loop then counted 0 folders and failed.
	- Actual fix [Bug]: The folder is cut off the file path with `sed`, then `sort -u`. Same folders as before on b23, and the check still fails when one package lacks goleak. New check `[dea6f]` fails if a `find` with `-printf` or `-fprintf` comes back into test.bash or install.bash.
	- Swept: `find -printf`, `sed -i` without a suffix, `grep -P`, `readlink -f`, `date -d`, `date +%N`, `stat -c`, `sort -V`, `xargs -r`, `realpath -m`, `tar --transform`, `wc -l` compared as text, `\?` and `\t` in sed, in cicd/*.bash, cicd/utility/*.bash, cicd/utility/include/*.bash and install.bash. In test.bash, only `[de54n]` used one where a Mac runs it. The bare `sed -i` and `date +%N` sit in the Linux-only release and pre-push blocks, and so do the `wc -l` compares and the remote-tests checks that run `tar --transform`. `date -d` runs behind a probe for GNU date. `stat` falls back to BSD's. The rest are in Linux-only cicd.bash, in keep-build.bash's `--keep` path, which test.bash doesn't run, and in the `--help` text of backlog-check, test-id and lint-report, where BSD sed would leave the tab in the printed help.
	- Verified: 2026-10-22, with BSD-like find, `[de54n]` fails on the old test.bash and passes on the new one. It passes on a stand-in tree and fails once one package there drops goleak. `[dea6f]` fails on the old test.bash and passes on the new one. `cicd.bash --gate` and `backlog-check.bash` passed.
	- Verified: 2026-10-22, test.bash on b23 1662/0, 1661 -> 1662.
	- Not checked: why `[de54n]` passed in stage 7 on b26 and vmFreeBSD. Likely a GNU find first on b26's PATH, and a FreeBSD find that has `-printf`.
	- Test case: test.bash `[de54n]` itself on the Mac runners, and `[dea6f]`, which needs no Mac.
	- Branch: fix-macos-find
	- Commit: 0d01f82
	- Verified: 2026-10-22, run 39895628537: `[de54n]` and `[dea6f]` passed on `macos-15-intel` and `macos-latest`. Both had failed `[de54n]` in run 39893939993.
	- Acceptance signoff: Passed its own test on both runners, no open choice.
	- Closed: 20261022-203900

- Stage 7 fails b26 when a Finder window is open on the test folder
	- ID: 2026100611181887
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 20261006-111818
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: The full run on 2026-10-06 failed b26 before any test ran. The tree there held only `.git` and 3 `.DS_Store` files, all from the run's minute.
	- Expected behavior [Bug]: A Finder window on the folder doesn't stop the run.
	- Reproduced [Bug]: Yes, on Linux, with a file in the old tree that `rm` can't remove. The copy step exits 1 and leaves the same half-removed tree.
	- Actual cause [Bug]: Finder rewrites `.DS_Store` while `rm -rf` runs, the rmdir fails, and `set -e` ends the copy step.
	- Actual fix [Bug]: The old tree is moved aside to `old.<pid>` before it's removed. What won't go gets a note, and another try next run.
	- Branch: ptyguard
	- Test case: None in a suite. Checked by hand against the old and new step.
	- Note: Not yet run on b26, which was held by another session. The next full run there closes it.
	- Verified: the full run on 2026-10-19 copied the tree to b26 and passed there, test.bash 1346/0.
	- Acceptance signoff: Self-closed. The item asked for one full run on b26.
	- Closed: 20261019-084100

- test.bash's `--direct` prompt check fails on FreeBSD and macOS
	- ID: 2026100611181886
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 20261006-111818
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: [ddj6s] failed on vmFreeBSD in stage 7 on 2026-10-06, 1222/1.
	- Reproduced [Bug]: Yes, by running test.bash again on vmFreeBSD.
	- Actual cause [Bug]: The check answers the prompt through util-linux `script -qec`, and the BSD `script` doesn't take it. Every other prompt check sits under `hasPty`. This one, from e1cc030, didn't.
	- Actual fix [Bug]: Put it under `hasPty`.
	- Branch: ptyguard
	- Verified: test.bash 1222/0 on vmFreeBSD.
	- Closed: 20261006-111818
	- Test case: test.bash [ddj6s] itself, which failed on vmFreeBSD before the fix. Stage 7 runs it on vmFreeBSD and b26, where the BSD `script` is.

- Code Review 20261005 item 1: workflows.md says gitsby won't push your own work to `main` or `dev`, and it does
	- ID: 2026100516202544
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: workflows.md says "There's no command for 'push to `main` anyway'", and that gitsby won't push your own work to `main` or `dev` even with permission. `pullcom` commits there and `sync` pushes there, and the plan says nothing about it. The refusal on a dirty `main` or `dev` even suggests `gitsby pullcom` to commit there on purpose. The README's first line says the tool enforces the workflow.
	- Expected behavior [Bug]: The docs and the tool say the same thing.
	- Reproduced [Bug]: Yes. A clone of a bare origin, one edit on `main`, then `gitsby sync -q -m x` pushed `main -> main` and exited 0. The same on `dev`.
	- Origin: workflows.md:96 from ab8d389 and :105 from 584e0ff, both 2026-07-28. The behavior is older. The 2.x refusal named `update` as the way to commit on a protected branch on purpose. No earlier round saw it. Confirmed.
	- Note: 2 ways out. Reword workflows.md to say gitsby steers work onto branches and still allows a deliberate commit on `main` or `dev`. Or warn above the prompt when the push goes to `main` or `dev`. Refusing is out, since the tool's own advice and every repo with no `dev` lean on it.
	- Note: The reword is the smaller change. A warning would show on every push in a GitHub Flow repo that commits to `main`.
	- Progress log:
		- 2026-10-05: The fix chosen is a warning on stderr before going ahead, with a flag to turn it off.
		- 2026-10-05: The flag is `--direct`. `-q` without it refuses, per the UI style guide's rule for warnings, since the question about `-q` went unanswered.
		- 2026-10-05: Warning reworded as given in review. The `-q` refusal starts with the same sentences.
	- Decisions:
		- A warning plus `--direct`, not a refusal and not a doc reword alone (2026-10-05).
		- A flag for this one case, not a general `--no-warn` (2026-10-05).
	- Actual fix [Bug]: `sync` on `main`, `dev` or the default branch warns on stderr above the prompt when it would push commits made on that branch, or commit a dirty tree there. Under `-q` it refuses and names `--direct`. A merge left for `sync` to publish doesn't count, so `br merge` offline and the hotfix back-merge still publish without it. workflows.md, the README, design.md and the UI style guide say so.
	- Note: [dafrt], [da8m8] and [ddf5y] sync on `main` to test sync itself, and now pass `--direct`. What each checks is unchanged.
	- Branch: direct
	- Commit: e1cc030
	- Test case: test.bash [ddj6q] refuses under `-q`, [ddj6r] pushed nothing, [ddj6s] warns above the prompt on a pty, [ddj6t] help lists it. Each red on `gover`. [ddj6v] a clean re-run and [ddj6w] a merge published from `dev` stay quiet, each red with the merge and clean-tree tests taken out.
	- Closed: 20261005-190835

- `br switch HEAD` commits and pushes the working tree, then fails
	- ID: 2026100607545807
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 20261006-074900
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: `origin/HEAD` was counted as a branch on origin. So `br switch HEAD` passed the check that the branch exists, parked the dirty tree with a commit and a push, then failed at `git checkout -b HEAD`.
	- Expected behavior [Bug]: Refuse before touching anything.
	- Reproduced [Bug]: Yes, with a dirty tree on a pushed feature branch.
	- Actual cause [Bug]: `branchRefs` read every `refs/remotes/origin/*` as a branch, `HEAD` included.
	- Actual fix [Bug]: `origin/HEAD` is skipped there.
	- Swept: `branchRefs` is the one place origin's branches are read for the existence checks.
	- Branch: fuzzwork
	- Commit: c1b10fc
	- Test case: fuzz.bash [ddjyc]. Red on `gover`'s code, green here.
	- Verified: fuzz.bash 311/0, test.bash 1491/0, parity.bash 29/0 on the branch.
	- Acceptance signoff: Self-closed: reproduced, red before the fix and green after.
	- Closed: 20261006-075458

- test.bash's binary checks fail on macOS
	- ID: 2026100409453279
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 20261004-094532
	- Opened by: jim-collier
	- Related IDs: 2026100312332924
	- Target OS: macOS
	- Incorrect behavior [Bug]: On b26 `tr -d '\000'` stops with "Illegal byte sequence" on a binary file. So `[dd5fe]` and `[dbftv]` fail, and `[dd5ff]` and `[dbftx]`, which expect no match, pass without reading anything.
	- Expected behavior [Bug]: The four checks read the file on macOS as they do on Linux.
	- Reproduced [Bug]: Yes, 2026-10-04, in stage 7's run on b26, where ssh gets `LANG=en_US.UTF-8`, and again by hand on the `.syso` files.
	- Possible cause [Bug]: macOS `tr` and `grep` both check bytes against the locale. With `LC_ALL=C` on both, the copyright check found its string on b26. On the `tr` alone it still failed.
	- Origin: the `tr` lines, from 5eadb03 (2026-10-01, the macOS pass, which swapped out `grep -P`) and 7846d29 (2026-09-26). Not seen by an earlier round. Confirmed.
	- Estimated effort: Low
	- Actual cause [Bug]: macOS `tr` and `grep` check bytes against the locale, and ssh there gets a UTF-8 one. `tr` stopped at the first byte that wasn't text. The two checks expecting no match passed because nothing was read.
	- Actual effort: Low
	- Progress log:
		- Verified: on b26 the old checks fail two and pass two without reading. The new ones pass all four.
		- Verified: the new `[ddg8y]` fails against the old way of reading and passes with the helper.
		- Verified: test.bash on Linux, 1399 -> 1400, all passing.
		- Verified: stage 7 run alone passes on b26 and vm925w. test.bash on b26 is 1216/0.
	- Actual fix [Bug]: The four checks go through one helper in test.bash that runs `tr` and `grep` in the C locale. It tells a string not found apart from a file not read, so the two no-match checks fail when the read fails.
	- Note: the two no-match checks moved from `fAssertFail` to `fAssert`. They keep their IDs and labels.
	- Swept: every `tr` and `grep` in `cicd/` that reads a binary file. Only these four did. The icon check `[dbftw]` already had `LC_ALL=C`, and the `od` reads of Mach-O headers don't depend on the locale.
	- Branch: remfix
	- Commit: 6842035
	- Test case: test.bash `[dbftv]`, `[dbftx]`, `[dd5fe]` and `[dd5ff]`, plus the new `[ddg8y]`.
	- Acceptance signoff: Self-closed: reproduced, and the checks fail before and pass after on b26.
	- Closed: 20261004-103900

- Code Review 20261003 item 3: Write and read failures in account commands guess at the cause
	- ID: 2026100313123881
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- Run `account apply` or `account set` where the write fails for a reason other than permissions, such as a full disk or a read-only filesystem.
	- Incorrect behavior [Bug]: The message says to check permissions. The real error is dropped.
	- Expected behavior [Bug]: The message keeps the real error. The permissions hint shows only when it is a permissions error.
	- Reproduced [Bug]: Yes, 2026-10-03. A folder where an `account apply` fragment goes, a lock name too long for the filesystem, and a plain file where the accounts file's folder goes. Each dropped the reason, and the first two said to check permissions.
	- Possible cause [Bug]: `usagef` where `usageWrapf` exists for this. Seven sites in accountcmd.go.
	- Origin: accountcmd.go, from 0ad1374 (2026-09-16) and 1ed0f3a (2026-09-28). Not seen by an earlier round. Confirmed.
	- Sweep: every `usagef("Couldn't ...` that has an `err` in scope.
	- Actual cause [Bug]: Each site had the error in hand and printed a fixed message instead. Most of them guessed permissions.
	- Estimated effort: Low
	- Actual fix [Bug]: Each refusal now says what failed, with File, Why, Kept and Fix lines under it. Why has the OS's reason. Fix names permissions only for a permissions error, and otherwise says to run again once the reason is fixed. The save, the create and the lock point at the folder, since that is what they write in.
	- Note: The labeled layout is the UI guide's, which keeps a path out of the sentence.
	- Swept: the seven sites the review named, plus the lock, the partly written create and the relative path in `account set`. Left alone: the three `git config` failures in `account apply`, which have no error in hand while git prints its own, and the three in repo.go, which already give the reason. Found by a grep for `usagef("Couldn't` over src-go.
	- Verified: the five site tests fail on `gover` and pass here. The test.bash pair was run by hand against both builds. test.bash passes 1288 of 1288, and `go test ./...` and `cicd.bash --gate` pass.
	- Branch: errmsg
	- Commit: b64bc2e
	- Test case: TestAccountApplyKeepsTheReasonAFragmentFailed, TestLockKeepsTheReasonItFailed, TestAccountSetKeepsTheReasonItsFolderFailed, TestLoadForEditKeepsTheReasonTheReadFailed and TestAbsPathValueKeepsTheReasonTheFolderIsGone for the sites, TestWriteRefusalNamesPermissionsOnlyWhenTheyAreTheCause for the rule, and [ddf43] and [ddf44] in test.bash. The chmod and save sites have no unprivileged way to fail, so the rule test covers them.
	- Acceptance signoff: OK, 2026-10-03.
	- Closed: 20261003-163955

- Code Review 20261003 item 4: `br merge` says the target is as it was without checking
	- ID: 2026100313123895
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- Have `git merge --abort` fail after a conflicted `br merge`.
	- Incorrect behavior [Bug]: gitsby ignores the failure and prints that the target "is as it was". The tree is still mid-merge.
	- Expected behavior [Bug]: When the abort fails, say the tree is mid-merge and name the commands to settle it.
	- Reproduced [Bug]: Yes, 2026-10-03, with a git that refuses only `merge --abort`. `br merge` said dev "is as it was", then failed a checkout on the conflicted tree. The hotfix back-merge said dev was untouched and ended in Done, exit 0. `release` goes through the same code as `br merge`.
	- Possible cause [Bug]: `_ = runOK("git", "merge", "--abort")` in `backOutMerge`, and the same at the dev back-merge.
	- Origin: branchcmd.go:226 from b34a25c (2026-09-15). Not seen before. Confirmed.
	- Actual cause [Bug]: Both sites threw away the abort's exit status.
	- Estimated effort: Low
	- Actual fix [Bug]: A failed abort now refuses with Why, Kept and Fix lines. They say the target is still mid-merge, that nothing was committed to it, and give the commands to drop the merge and go back. git's own reason for the failed abort shows above it. The back-merge also offers finishing the merge by hand, which carries the hotfix across.
	- Note: The back-merge now exits 1 when its abort fails, even though the hotfix landed. A clean abort there is unchanged and still ends in a warning.
	- Note: That refusal's Kept line says the hotfix landed on the default branch and that part is done. [ddf81] checks it, added 2026-10-03.
	- Swept: both `merge --abort` calls in src-go. `release` backs out through `backOutMerge`, so it is covered too and was run by hand. No other git step in src-go has its result discarded, apart from the listings and two best-effort calls in repo.go and remote.go whose comments say why.
	- Verified: the same runs on `gover` said the target was as it was, and the back-merge exited 0. Here all six checks pass, and test.bash passes 1288 of 1288. `go test ./...` and `cicd.bash --gate` pass.
	- Branch: errmsg
	- Commit: ef2b917
	- Test case: [ddf4b], [ddf4c] and [ddf81] for the back-merge, [ddf4d], [ddf4e], [ddf4f] and [ddf4g] for `br merge`, all in test.bash.
	- Acceptance signoff: OK, 2026-10-03.
	- Closed: 20261003-163955

- Code Review 20261003 item 2: A pipeline reader that quits early can fail its writer
	- ID: 2026100313123865
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Incorrect behavior [Bug]:
		- release.bash's proof step pipes `--version` into `grep -q`. Now and then grep quits first and the check fails. That costs two retries and can end in a false warning that the release didn't verify.
		- `tag --sort ... | head -n 1` in release.bash and gen-winres.bash fails the same way once there are enough tags.
	- Expected behavior [Bug]: Capture the output first, then match it, the way cicd.bash already does.
	- Reproduced [Bug]: The proof step failed 1 run in 300. The tag lookup failed every time with 3000 tags, never with today's 6.
	- Origin: release.bash:132 and :333 from 1928f35 (2026-08-18), gen-winres.bash:100 from cf5922e (2026-08-19). Same class as the Bash trap on early-exit readers. Confirmed for the proof step, Plausible at today's tag count.
	- Actual cause [Bug]: `head -n 1` and `grep -q` stop reading at the first match. A writer with more to say than a pipe holds then fails writing the rest, and `pipefail` fails the pipeline.
	- Sweep: also `spawn-report.bash:53` and `install.bash:196`.
	- Estimated effort: Low
	- Actual fix [Bug]: The tag lists and the proof's `--version` are captured whole and then matched, the way cicd.bash reads the tags. The installer and spawn-report.bash take their first lines with `sed -n`, which reads to the end.
	- Swept: release.bash:132 and :333, gen-winres.bash:100, spawn-report.bash:53 and install.bash:196, all fixed. Left alone, since `|| true` keeps the right value there: install.bash's wget redirect read, cicd.bash's tool version read and parity.bash's diff excerpts. Found by a grep for `| head`, `| grep -q` and `| awk ... exit` over every `.bash` outside `legacy/`. test.bash's `| grep -q` runs inside `bash -c`, which has no pipefail.
	- Verified: all five checks fail on `gover` and pass here. test.bash passes 1280 of 1280 with both fixes in.
	- Branch: relpipe
	- Commit: 76675b3
	- Test case: in test.bash, [ddf3s] for a published binary whose `--version` outruns a pipe, [ddf3t] and [ddf3v] for 3000 tags, [ddf3w] for a long SHA256SUMS, and [ddf3x] for 1000 spawn recordings.
	- Acceptance signoff: Self-closed: reproduced, the checks fail before the fix and pass after, and the sweep is answered.
	- Closed: 20261003-141543

- Two account blocks with one name merge without a word
	- ID: 2026093013034093
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 2026-09-30
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- Write `account: t00mietum` twice, one block with `host: gitea.com` and one with `host: github.com`.
		- Run `gitsby account list --config` on that file.
	- Incorrect behavior [Bug]: One account is listed, with a mix of both blocks' values. Nothing says a block was merged.
	- Expected behavior [Bug]: The clash is reported, the same way an unread key is.
	- Reproduced [Bug]: Yes, 2026-09-30.
	- Actual cause [Bug]:
		- SHCL merges two blocks with the same name on purpose. It is how a key gets added further down.
		- gitsby read each repeated key last-wins and said nothing. Names differing only in case, and a dotted line beside a block, merged the same way.
		- `account set` edited the first block even when a later one held the key.
		- The 2.x flat reader had the same silent last-wins.
	- Estimated effort: Low
	- Actual effort: Avg
	- Decisions:
		- Merging stays, since the format allows it. What gets reported is a key given two different values.
		- The last line is still read, as before. Each earlier one is listed as ignored, with its line.
		- A repeated top-level `protocol` is listed the same way.
	- Actual fix [Bug]: Repeated keys are checked per account after the whole file is read, in both layouts. `account set` edits the block holding the key, and refuses when more than one does.
	- Branch: dup-acct
	- Test case: TestRepeatedAccountKeys, TestAccountSetFindsTheKeyInAnyPiece, and one account list check in test.bash.
	- Closed: 2026-09-30

- Builds should clean up stale artifacts and side-effects when done
	- ID: 2026101912030138
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261019-120301
	- Opened by: jim-collier
	- Milestone: Pre-next-cut.
	- Requirements [Feature]:
		- Verify or ensure that builds clean up stale artifacts and side-effects after they're done.
			- Caches, container cruft, tmp files, etc.
	- Progress log:
		- 2026-10-19: Checked each kind on b23. The harnesses, release.bash and the utilities already remove their temp folders on exit. Artifacts under `cicd/artifacts/` are rotated or capped at 20. Containers run with `--rm`, a new image removes the one it replaces, and the build cache is all in use by images. The Go cache volume is kept on purpose, and Go trims its own build cache. The pre-push snapshot is kept on purpose too, for warm caches.
		- 2026-10-19: 2 gaps were found and fixed. cicd.bash's own temp files were removed one by one, so a run stopped partway left them behind. They now sit in one folder per run, removed on exit, a TERM or Ctrl+C included. The demo's repos at `/tmp/gitsby-demo` stayed after every run off the container. Stage 6 now removes them through `demo-repo.bash --remove`, which keeps the script's ownership check.
	- Branch: leakflags
	- Test case: test.bash `[de5m8]` for the temp folder after a pass, a stop and a TERM, and `[de5m9]` for the demo's repos.
	- Verified: Both fail against gover's cicd.bash. test.bash 1571 -> 1579, 0 failed, and `cicd.bash --gate` passes. `demo-repo.bash --remove` removed a world it built, refused a folder it didn't, and passed on one that wasn't there.
	- Note: Needs one real full run, in the container and with `--no-container`, to see `/tmp/gitsby-demo` and the scratch folder gone.
	- Verified: 2026-10-21 on b23. A `--no-container` full run passed every stage, and after it `/tmp/gitsby-demo`, left there by a run on 10-19, was gone, and so was its scratch folder. A full run in the container stopped in stage 3 on pip-audit (2026102113100000), and its scratch folder was still gone, as was the one from a `--quick --leakcheck` run there. No gitsby-cicd container was left, and no new untagged image. The container's `/tmp` is a tmpfs that goes with it, so its demo repos can't outlive it.
	- Note: Reopened 2026-10-22. The container half never reached stage 6, so it still needs one full run there that passes.
	- Verified: 2026-10-22 on b23. A full run in the container passed every stage, stage 6 and stage 7 included. After it its scratch folder was gone, `/tmp/gitsby-demo` wasn't there, no gitsby-cicd container was left, and there was no new untagged image. A `--no-container --no-remote` full run then passed too, with the same 4 checks clean. Logs: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261021-19403500/run1.log` and `run2.log` beside it.
	- Acceptance signoff: Self-closed: the full run in the container passed with nothing left behind, which was all that was left.
	- Closed: 20261021-203604

- CICD gets `--leakcheck` and `--no-leakcheck` flags
	- ID: 2026101912030152
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261019-120301
	- Opened by: jim-collier
	- Milestone: Pre-next-cut.
	- Related IDs: 2026101816064793, 2026101816064794
	- Requirements [Feature]:
		- CICD should have both `--leakcheck` and `--no-leakcheck`.
			- `--leakcheck` is useful to add back in for `--quick`.
			- `--no-leakcheck` is useful to exclude it from the default, or with `--quiet`.
	- Decisions:
		- The leak checks run on a plain full run. `--quick` and `--no-fuzz` both turn them off, since they're part of stage 3. Either flag wins over that, in any order. Both together are refused.
		- A plain run off the container, with no CodeQL, warns and skips CodeQL like govulncheck. `--leakcheck` asked for by name still stops there.
		- The run in the container gets the flag as given. It gets `--quick` and `--no-fuzz` too, so it works out the same default.
	- Branch: leakflags
	- Test case: test.bash `[de5m3]`, `[de5m4]`, `[de5m5]`, `[de5m6]`, `[de5m7]` and `[de5ma]`, plus `[de548]` and `[de54c]` reworded with the same IDs.
	- Verified: Every one fails against gover's cicd.bash. test.bash 1571 -> 1579, 0 failed, and `cicd.bash --gate` passes. `[dd5fp]`'s stage 3 run takes `--no-leakcheck` now, since its fixture's go stub has no soak test.
	- Swept: the help text, stage 3's header line, README, contributing.md, config.bash comments and both history footers.
	- Note: A full run now takes CodeQL's time, once per release OS plus Python. Needs one real full run to see it pass in the container.
	- Verified: 2026-10-21 on b23. A plain full run in the container stopped in stage 3 on pip-audit, on new Pillow advisories (2026102113100000), before the leak checks. A `--quick --leakcheck` run there then passed: the soak test in about 15 s, and CodeQL clean on darwin, freebsd, linux and windows at about 15 s each and Python at about 45 s, so the leak checks add about 2 minutes. The rest of stage 3 took about 1.5 minutes in the stopped run. A `--no-container` full run warned and skipped CodeQL, and passed.
	- Acceptance signoff: Self-closed: the flags and the leak checks passed in the container. The pip-audit stop is its own item.
	- Closed: 20261021-130500

- Leak, memory, and correctness checks in CICD
	- ID: 2026101816064794
	- Type: Enhancement
	- Status: Done
	- Needs external testing: Done 2026-10-19. A full run passed stage 7 on b26, vmFreeBSD, vmDebARM64 and vm925w.
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261018-160647
	- Opened by: jim-collier
	- Milestone: Pre-next-cut.
	- Related IDs: 2026101816064793, 2026101009380628
	- Requirements [Feature]:
		- For all code:
			- The checks cover first-party and third-party code. Vendored code is included.
				- On third-party code, run the leak, memory, and correctness checks named here, not style lints. Style findings in someone else's module aren't ours to fix.
				- CodeQL reports only on source inside the database's root. For its run, vendor the dependencies into the tree first (`go mod vendor`, unpacked sdists for Python).
			- Any report fails the test that made it.
			- Any leak is fixed. If the fix has to wait, it gets a backlog item, and the test that shows it turns the check off with that item's ID beside it.
			- A `--leakcheck` flag adds the slow checks:
				- CodeQL, from a pinned CLI run locally. No hosted service.
				- A soak test. It loops through the program's main actions headless, and fails if the heap at round 2N is larger than at round N by more than a set margin. The heap report is kept as a pipeline artifact.
			- Every tool is pinned and runs in the build container or lint image, never installed on the host.
			- Each new gate is watched to fail before it's trusted, by planting the leak it's meant to catch and seeing it go red.
			- Known-advisory scans run on every full run: `govulncheck` and `pip-audit`. They cover third-party code only, which is the point.
		- For Go:
			- Go leaks are goroutines that never exit, and references held too long: a map or slice that only grows, or a small slice keeping a big backing array alive.
			- Every package's tests run `goleak.VerifyTestMain(m)` from `go.uber.org/goleak`, pinned in go.mod. A goroutine still running after the tests fails the run, whether our code or a dependency started it.
			- Every full run runs the whole test suite with `-race`.
			- If the code uses cgo, every full run also runs the tests with `-asan`, in a build dir of its own.
			- Every full run runs `go vet` and `staticcheck`. `go vet`'s `lostcancel` and `copylocks` checks are the leak-related ones.
			- The soak test reads `runtime.MemStats.HeapInuse` and `runtime.NumGoroutine()` at round N and 2N, after `runtime.GC()`. Its heap profile (`pprof`) is kept as the artifact, and `go tool pprof -base` shows what grew.
			- Traps:
				- `goleak.VerifyNone` per test doesn't work with `t.Parallel()`. Use `VerifyTestMain`.
				- goleak ignores by function name. That's the only form of suppression allowed.
				- `go test` caches a pass. Run with `-count=1`.
				- One `runtime.GC()` can leave garbage behind. Call it twice before reading the stats, or the margin has to be wide enough to hide a real leak.
				- `-race` needs cgo on some platforms. A job with `CGO_ENABLED=0` fails to build it or skips it, so check the job's env.
				- `-race` is 2 to 20 times slower and uses 5 to 10 times the memory. Size the job's timeout for it.
		- For Python:
			- Python leaks are references held too long: module-level caches, `functools.lru_cache` on a method, closures kept in a global list, and C extensions that drop a reference count.
			- Every full run runs the tests with `-X dev` and `-W error::ResourceWarning`, so an unclosed file or socket fails the test.
			- Every full run runs the tests under `pytest-memray`. Each test that loops gets `@pytest.mark.limit_leaks(...)` with a margin. memray sees native allocations, so leaks in C extensions show up, third-party ones included.
			- After the tests, `gc.collect()` runs, and `gc.garbage` must be empty.
			- The soak test takes `tracemalloc` snapshots at round N and 2N and fails on growth past the margin. The top lines of `snapshot.compare_to()` are kept as the artifact.
			- ruff runs `B019` (`lru_cache` on a method), `SIM115` (`open` with no context manager), and `B006` (mutable default argument).
			- `--leakcheck` also runs the tests on a CPython built with `--with-address-sanitizer`, under `PYTHONMALLOC=malloc`, for C extensions.
				- The interpreter's own reports are suppressed by library name, `libpython` only.
			- Traps:
				- Start `tracemalloc` before importing the code under test, or allocations made at import aren't traced.
				- The first rounds fill caches: the regex cache, interned strings, freelists, and lazy imports. That's why it's round N against 2N, never 0 against N.
				- `tracemalloc` sees only allocations made through Python's allocator. A C extension calling `malloc` directly is invisible to it. memray covers that.
				- memray runs on Linux and macOS only. On Windows, the test exits as skipped, not passed.
				- pytest keeps the traceback of a failed test, which keeps its frames alive. A leak count from a run with failures means nothing.
				- `ResourceWarning` shows only in dev mode or with `-W`. A plain run hides it.
				- Without `PYTHONMALLOC=malloc`, ASan can't see inside pymalloc's pools.
	- Note: The Rust, C, and C++ parts of the list were left out, since there's no code in those here. The only Python is the demo gif script, which uses Pillow, cairo, Pango, and fontTools, and it has no tests yet. The Go code starts one goroutine (`startAhead` in app.go), and builds use `CGO_ENABLED=0`.
	- Progress log:
		- 2026-10-19: Everything but CodeQL is in, on `leakchk`. CodeQL is the part left. `fLeakCheck` in cicd.bash marks where it joins.
		- 2026-10-19: Already there, so not added again: every full run had `go test -race`, `go vet` with its default analyzers, `lostcancel` and `copylocks` among them, and `staticcheck`. Only the builds set `CGO_ENABLED=0`. The image has gcc, so the race detector works there, and a planted data race failed it.
		- 2026-10-19: Not applicable: `-asan`, since nothing imports "C". The test-time Python checks (`-X dev`, pytest-memray, `gc.garbage`, the tracemalloc soak, and an ASan CPython) wait until the demo script has tests to run them on.
		- 2026-10-19: CodeQL is in, on `codeql`. `--leakcheck` runs it in the image over a scratch copy of the module, with `go mod vendor` done there. The Go extractor leaves out tests and vendor/ by default, so both are turned on. It runs once for each OS a release is built for, since the extractor sees one OS's files at a time.
		- 2026-10-19: CodeQL found 2 problems in shcl 2.0.0, the old writer the tests use. Both are set aside until 2026101906343987.
		- 2026-10-19: Split out: CodeQL over the demo script and its Python libraries, as 2026101907065426.
		- 2026-10-19: A source check now stops any tracked script or Go file from running tmux, pkill or killall.
	- Decisions:
		- The soak test is a Go test, `TestSoak`, run in one process. It loops pullcom, br create, sync, br merge, status, br, whoami and br prune against a bare origin and a clone, 30 rounds and then 30 more. It skips unless `GITSBY_SOAK_ROUNDS` is set, so a plain `go test` doesn't run it. The heap margin is 256 KB; 2 reads differ by under 100 KB, on a heap under 2 MB.
		- pip-audit checks the demo's libraries at the versions installed, given as pins, since they come from Debian's archive and not pip. Debian patches them without moving the upstream version, so the 18 advisories reported today are set aside in config.bash until 2026101905585018 checks them. A new one fails the run.
		- ruff and pip-audit go into the image from a lock that pins every wheel by hash.
		- CodeQL goes in the default image, not one of its own. The Go-only bundle adds about 400 MB on disk to a 2.6 GB image, and a second image would need its own tag, build and cleanup.
		- On vendor/, only findings from queries tagged security, correctness or reliability count. The rest of the suite is style, such as a value assigned and never read.
		- A finding is set aside by rule and file in `CODEQL_IGNORE`, with its backlog item beside it. An entry no report has any more fails the run.
		- `--leakcheck --no-container` stops on a box without CodeQL rather than skipping it, since it was asked for by name.
	- Branch: leakchk, codeql
	- Test case: `TestMain` [de545] runs goleak, and `TestSoak` is [de546]. test.bash [de547], [de548], [de549], [de54a], [de54h], [de54j], [de54b] and [de54c] for `--leakcheck`. [de54d] and the ruff pass of [dcmap] for ruff. [de54e], [de54g] and [de54k] for pip-audit and `govulncheck -test`. [de54m] for `-count=1`, [de54n] for goleak in every Go package, and [de54f] for the image tag. [de55e], [de55f], [de55g], [de55h], [de55j] and [de55k] for the CodeQL step, and [de55x] for its install. [de55m], [de55n], [de55p], [de55q], [de55r], [de55s], [de562], [de55t], [de563] and [de55v] for how its reports are read. [de55w] for tmux, pkill and killall.
	- Verified:
		- A goroutine left running in `startAhead` failed the unit tests through goleak. In the soak test, a goroutine left per run failed it on the count, and a 4 KB slice kept per run failed it on the heap, where `go tool pprof -base` named `run`. Each was restored by copy, and both pass after.
		- ruff failed on a planted B019, SIM115 and B006, and `--gate` stopped on it. pip-audit failed in the image with one advisory taken off the list.
		- test.bash 1524 -> 1540, 0 failed. The 16 new checks all failed against gover's cicd.bash and config.bash. A full container run with `--leakcheck` passed, with sync, dogfood, the demo, the remote tests and publish off.
		- A planted `n == n` in app.go failed `--leakcheck` in the image, on CodeQL's comparison-of-identical-expressions query. Turning off the extractor's test option failed it too. Both were restored by copy, and the run passes after.
		- test.bash 1540 -> 1560, 0 failed. The new checks all failed against gover's cicd.bash, config.bash and Dockerfile, or against a broken copy of codeql-findings.py. The kill check failed on `pkill` and `tmux` lines planted in a script, a `tmux` line in a Go file, and a `killall` line in legacy/bin/gitsby.
		- A full container run with `--leakcheck` passed, with sync, dogfood, the demo, the remote tests and publish off: test.bash 1560/0, fuzz.bash 313/0, parity 29/0, the spawn counts, the soak test and CodeQL on all 4 OSes.
	- Swept: The comments in cicd.bash and test.bash that said there were no third-party dependencies, the 2 "pure stdlib" lines in config.bash, the style guide's goroutine rule, the help header, both history footers, README and contributing.md. install.bash's "pure Go with no dependencies" is about what a build needs installed first, and goleak is test-only, so it stays. remote-tests.bash runs compiled test binaries, which never cache, so it needs no `-count=1`.
		- CodeQL: the help header, the history footers of cicd.bash, config.bash, test.bash and the Dockerfile's comments, README and contributing.md. The kill check covers legacy/ too, which has none.
	- Verified: full run 2026-10-19, publish off. test.bash 1561/0 and fuzz.bash 313/0 in the image, then test.bash 1346/0 on b26, 1249/0 on vmFreeBSD and 1546/0 on vmDebARM64, and the Go tests on all 4 boxes.
	- Acceptance signoff: Self-closed. The open calls moved to 2026101905585018, 2026101906343987 and 2026101907065426.
	- Closed: 20261019-084100

- Run the lint and test stages in a pinned container
	- ID: 2026101009380628
	- Type: Enhancement
	- Status: Done
	- Priority|Severity [Feature]: Avg
	- Opened: 2026-10-10
	- Opened by: jim-collier
	- Requirements [Feature]:
		- Stages 1-4 can run in a Debian trixie image with our Go and every pinned lint and test tool, so a host update can't move a finding.
		- The versions come from config.bash, not a second list.
		- The demo gif renders there too, so a host update can't change its bytes either.
		- The rest stays on the host: sync, dogfood, remote tests and publish.
	- Done: `cicd.bash --container`, from `cicd/container/Dockerfile`. The tag hashes the recipe and the versions, and a new image replaces the old one. Go caches live in a named volume. git joined `TOOL_VERSIONS`, since trixie's 2.47 spawns 4 more processes on a fetch than the host's 2.51.
	- Branch: ctr
	- Test case: [ddrp4] to [ddrp8] in test.bash, against the stubbed engine. The recipe guard was watched to fail by hand.
	- Verified: a run in the container matched the host baselines, test.bash 1509/0, fuzz.bash 313/0, parity.bash 29/0 and spawn counts. With the new checks, 1514/0 both in the container and on the host. The fixture sets the container marker itself, since the suite inside the image inherited it.
	- Done 2026-10-10: the demo gif renders in the image as well. Apt reads the snapshot the base was cut from, so Pillow, freetype and cairo can't move, and the image has the Monaspace release file the host uses. The emoji font is Debian's, not the host's build, but the demo draws no emoji. The render matched the committed gif byte for byte, and with the font hidden it didn't.
	- Test case: [ddrrn] in test.bash.
	- Done 2026-10-10: a plain run uses the container, set by `CICD_CONTAINER` in config.bash. `--no-container` runs on the box. A box without a working docker does too, with a warning, so a contributor isn't blocked, and `--container` there stops. `--gate` stays on the box.
	- Test case: [ddrs1] to [ddrs4] in test.bash. 1519/0 in the container and on the host. With the default off, the 3 checks that need it failed.
	- Closed: 20261010-100500

- `raw` runs tea and other common CLIs, not only git and gh
	- ID: 2026100611524343
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 20261006-115243
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- `raw tea` (or `tea-cli`), `raw glab`, `raw lazygit` and `raw tig` run as the folder's account, like `raw git`.
	- Decisions:
		- A fixed list, not any program. An open slot would hand the token to whatever was typed there.
		- tea and glab get the account's token in their own variables, with the host beside it. Never a GitHub token.
		- gitui is left out. It uses libgit2, which never sees the account.
		- tea before 0.11 ignores the token. When its own login for the host is somebody else, gitsby warns, and `-q` refuses.
	- Note: `--any-identity` before `raw` was taken and ignored. It now applies nothing, and the "acting as" line stays quiet.
	- Note: The "acting as" line now names a Gitea account too. It only read the GitHub login before.
	- Branch: raw-tools
	- Test case: test.bash, 12 new checks and 1 reworded. 10 are red on `gover`, and the other 3 went red with the fix broken. 2 Go tests, and 2 fuzz vectors.
	- Verified: test.bash 1509/0, fuzz.bash 313/0, parity.bash 29/0, the gate. Only against stubs. No real tea 0.11 or glab here.
	- Closed: 20261006-115243

- macOS release gets a universal binary
	- ID: 2026100313491873
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Related IDs: 2026100312571262
	- Requirements  [Feature]:
		- MacOS gets a universal binary for both amd64 and ARM.
	- Notes:
		- Dogfood already builds one with `macho-universal.bash`. Release assets still publish `darwin/amd64` and `darwin/arm64` apart.
	- Decisions:
		- It replaces the two `darwin/amd64` and `darwin/arm64` assets, rather than sitting beside them (2026-10-03).
		- Published as `gitsby-darwin-universal`. On a Mac, `--arch` is noted and changes nothing.
	- Progress log:
		- Done: the release builds both Mac CPUs and joins them with `macho-universal.bash`, as dogfood does. Both installers ask any Mac for the one file. The release proof checks it against `SHA256SUMS` from Linux, where it can't run. README says how to rebuild it, and design.md has the decision.
		- Verified: release.bash's own cross-build, run twice from an empty build cache each time, wrote the same `SHA256SUMS` over seven assets, with no per-CPU Mac file left beside them. `file` reads the Mac one as a universal binary holding both builds.
		- Verified: a release dry run, the gate, and the full test.bash, 1337 passed.
		- Verified: 9 new checks pass, and all 9 fail on the tree before.
		- Note: the Go installer can't install v2.1.0 on any platform, before or after this. That release publishes the `gitsby` and `gitsby.ps1` scripts, not per-platform binaries.
	- Branch: macuni
	- Commit: 28b8f2d
	- Test case: test.bash `[ddf6f]`, `[ddf6g]`, `[ddf6h]` (install.bash on a Mac), `[ddf6j]` (install.ps1, pinned since pwsh can't fake a Mac), `[ddf6a]`, `[ddf6b]`, `[ddf6c]`, `[ddf6d]`, `[ddf6e]` (release.bash).
	- Swept: every `darwin` and `arm64` reader in the repo. release.bash, config.bash, both installers, the installer and release fixtures in test.bash, README, design.md and the changelog. cicd.bash dogfood already joins. Nothing in `src-go` reads asset names. `legacy/` is frozen.
	- Verified: stage 7 on b26 (2026-10-04) passed the installer checks with stubbed downloads, `[ddf6f]`, `[ddf6g]` and `[ddf6h]` among them.
	- Verified 2026-10-05 on b26, an Intel Mac on macOS 15.8: the real universal build, served as a stand-in pre-release in place of GitHub. install.bash piped into the stock bash 3.2, and install.ps1 under pwsh, each found the pre-release, checked the sum, installed it and ran it. `lipo` lists both CPUs, and the arm64 half keeps a valid ad-hoc signature after the join.
	- Not run here: the download from GitHub itself. release.bash downloads and checks the Mac file from every real release. Running it on Apple silicon moved to the deferred ARM hardware item.
	- Acceptance signoff: OK, 2026-10-05, after the b26 install.
	- Closed: 2026-10-05

- Run the windows/arm64 build somewhere
	- ID: 2026100507345200
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Related IDs: 2026100413264100
	- Requirements  [Feature]:
		- The release publishes `gitsby-windows-arm64.exe`, but no box runs it. Stage 7 runs Windows tests on amd64 only, on vm925w.
	- Notes:
		- vmDebARM64 has Wine. In theory the windows/arm64 build runs there, slowly, since that CPU is emulated.
		- First probe: whether that Wine runs an ARM64 PE at all, with `--version` and then the Go test binary. Not run yet. The box was held by another session on 2026-10-05.
		- If it runs, stage 7 could run the windows/arm64 Go tests there, under Wine, beside the linux/arm64 run. Wine is not Windows, so it would add to vm925w's run, not replace it.
	- Progress log:
		- Verified: vmDebARM64 has Debian's Wine 10.0 for arm64, with the ARM64 Windows libraries. gitsby and its Go tests both build for windows/arm64 as ARM64 PE files.
		- Tried 2026-10-05: `gitsby.exe --version` under Wine, as the test user, over ssh with no display. It never printed anything. Wine's own first-run setup spun at full CPU for 12 minutes and wrote nothing to the new Wine folder. The Go test binary was not tried, since no Windows program gets that far.
		- Verified: every Wine process there faults with an illegal instruction, over and over, on the first instruction of Wine's own system call entry points. That is inside Wine, before any of gitsby's code runs.
		- Cause, inferred: branch protection. The emulated CPU has it, Debian builds Wine's library marked for it, and those entry points lack the instruction it requires. Not confirmed by turning it off, since that takes root plus a reboot or a VM change. The C library there has no per-program switch for it.
		- Not changed: stage 7 and the docs. Nothing runs under Wine there yet.
		- Question: run it at all? One way is to give vmDebARM64 a CPU model without branch protection, which changes its linux/arm64 runs too. Another is `arm64.nobti` on its kernel command line plus a reboot. Or leave windows/arm64 untested until a Wine fix.
		- Answered 2026-10-05: `arm64.nobti` on vmDebARM64's kernel command line, kept across reboots.
		- Done: the boot loader config there adds `arm64.nobti`. How to undo it is in the private notes.
		- Verified: after the reboot the kernel line has it, the kernel no longer reports branch protection, and the CPU flags no longer list it.
		- Verified: that was the cause. Wine's first-run setup finished in about 90 seconds, and `gitsby.exe --version` printed the version in 1 second.
		- Verified: the windows/arm64 Go tests under Wine, first run: 171 passed, 6 failed, 22 skipped, in under a minute. All 6 make a symlink. Wine's symlink call reports success and makes nothing. That is a known Wine stub, and a small probe there showed it.
		- Fixed: the tests check the link is there after making it, and skip or drop the link case when it isn't. Under Wine that gives 173 passed, 26 skipped, none failed. The Go tests here still pass.
		- Verified: linux/arm64 on that box still works after the change. The native `--version` runs, and its Go tests pass, 198 with 1 skipped.
		- Done: stage 7 runs the windows/arm64 Go tests under Wine on vmDebARM64, after its linux/arm64 ones. It adds to vm925w's run; that is unchanged. README, contributing.md and the script headers say so.
		- Verified: stage 7's script alone, against vmDebARM64 only and without test.bash, passed both Go test runs in 3 minutes, Wine's first-run setup included.
		- Note: Wine there has no Windows git, so the tests that need git skip under Wine. vm925w still runs those.
		- Verified 2026-10-05: a full stage 7 run passed on every box. Under Wine, 173 passed and 26 skipped. vmDebARM64's test.bash passed 1438, b26's 1255 and vmFreeBSD's 1179, none failed. b29w ran the Windows Go tests, symlink helper included, since vm925w was held: 180 passed, 19 skipped.
	- Branch: winebti, winenobti
	- Commit: cda31a7
	- Test case: stage 7's Wine run on vmDebARM64. The 6 symlink tests failed under Wine before the fix, and pass or skip after.
	- Swept: every `os.Symlink` in the Go tests, 8 sites. Code outside the tests makes no links.

- Code Review 20261003 enhancement 2: Network probes run one after another
	- ID: 2026100313123988
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Prereq IDs: 2026100313123975
	- Requirements  [Feature]:
		- `status` and `whoami` in a token-file account folder wait on two `gh api user` calls and an `ssh -T`, in turn. With 300 ms each that is about 950 ms where 300 would do.
		- `account list` starts `gh` once per account, in turn. `account apply`, `set` and `unset` pay it too, since they print the list.
	- Decisions:
		- Against: the public style guide allows goroutines only with a measured reason. The 950 ms against 300 above is that reason, so the fix may use them.
		- The first probe might be replaced by a local `gh config get` read, with no goroutine at all. Try that first.
	- Origin: account.go and accountcmd.go. The per-account `gh` call was measured in 20260909 item 19 and kept. Confirmed with injected delays.
	- Progress log:
		- Done: the first probe reads gh's active login from gh's own config, with no network. Only a token already in the environment still sends it to the API, since that token outranks the config.
		- Done: the token-file check and the ssh probe start ahead, and each is read where its line prints. The token check starts when the token is exported, so it also runs alongside the fetch. `whoami` and the commands that write through gh start theirs the same way. Output order is unchanged.
		- Done: `account list` asks gh about every login at once, up to eight at a time, then prints in the same order. The per-login cache from 20260909 item 19 stays.
		- Done: a probe nobody read is killed when the run ends.
		- Verified: with 300 ms injected on each round trip, best of 3 on b23: status in the ssh account folder 930 -> 319 ms, whoami there 923 -> 316, status in the https folder 624 -> 316, status with a failed fetch 628 -> 319. With 300 ms on gh's token store as well: status 1228 -> 621, account list with three accounts 917 -> 615. Output is byte for byte the same in all five.
		- Verified: spawn counts unchanged on all 14 measures. The config read replaces one gh call one for one.
		- Verified: `[ddg72]`, `[ddg75]`, `[ddg73]` and the changed `[dd5e6]` fail on the build before this and pass after. `[ddg72]` and `[ddg75]` also fail with only the ssh probe put back in turn. `[ddg71]` fails with the end-of-run kill taken out. The affected test.bash blocks pass 103/0, also on a race-enabled build with no race reported. `go test -race ./...` and the gate (lint and Go tests) are clean.
		- Note: `[dd5e6]` now looks for the config read and no API call, and `[dd5e7]` and `[dd5e8]` refuse either one. `[dd5e9]` runs with a token already in the environment, the one case that still reaches the API. The rule they check, ask only where a block prints, is unchanged. The fake gh stubs answer `config get ... user`.
		- Note: offline, the identity block can now name gh's active account from its config, where it said nothing before. Display only.
	- Swept: every caller of `ghLogin`, `sshLogin` and `ghTokenFor`. The probes in `settleGh`, `selectAccount`, `identityGate` and the identity block lines all read through the same caches. `showHostLine` asks tea, which reads a local file, so it stays as it was.
	- Branch: probes
	- Commit: 545712a
	- Test case: test.bash `[ddg72]`, `[ddg75]`, `[ddg73]`, `[ddg74]` (regression guard), `[dd5e6]`; Go `[ddg6z]`, `[ddg70]`, `[ddg71]`, `[ddg76]`.
	- Verified: test.bash 1408/0, `go test ./...`, fuzz.bash 301/0 and parity 29/0 on merged gover, 2026-10-04.
	- Acceptance signoff: Self-closed: the goroutines have the measured reason the style guide asks for, output is unchanged, and the checks fail before and pass after.
	- Closed: 20261005-072140

- Release notes group the downloads in a table
	- ID: 2026100415020736
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-04
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- When creating a release, use a table to group downloads.
		- CPU architecture goes in columns, and target OS in rows.
	- Notes:
		- The release body is the changelog section verbatim today. GitHub lists the assets in a flat list under it.
		- macOS is one universal file, so its row doesn't split by CPU the way the others do.
	- Decisions:
		- The table goes in the changelog's release section too, so the release body stays a verbatim copy of that section. release.bash writes it into the section when it cuts the release, from the actual asset list (2026-10-04).
		- Rows are target OS (Linux, macOS, Windows, FreeBSD, whatever the release publishes). Columns are CPU (amd64, arm64). macOS is one universal file, `gitsby-darwin-universal`, so its row doesn't split by CPU. Each cell links the asset's download URL for that tag (2026-10-04).
		- `SHA256SUMS` and the install scripts go on one line under the table (2026-10-04).
		- The macOS file is linked under both CPU columns (2026-10-04).
	- Progress log:
		- Done: release.bash phase 2 adds a `### Downloads` table at the foot of the section it retitles, built from the files phase 1 made. Rows run Linux, macOS, Windows, FreeBSD, then any other OS. Columns run amd64, arm64, then any other CPU. A missing file shows `-`. One line below links `SHA256SUMS` and the tag's `install.bash` and `install.ps1`.
		- Done: the macOS file is linked under both CPU columns, since a markdown table cell can't span two. That is one reading of "doesn't split by CPU", for signoff.
		- Done: phase 1 refuses a vNEXT section that already has a `### Downloads` heading. Phase 3 warns when the table and the files it publishes disagree. With no binaries built, phase 2 warns and writes no table.
		- Done: design.md and the changelog say so. The repo name is set once in release.bash.
		- Verified: shellcheck on both scripts, `test-id.bash --check`, and markdownlint on changelog.md and design.md. A table written into a copy of the real changelog passed markdownlint.
		- Verified: the release.bash block of test.bash, 38 passed. Against release.bash before the change, four of the five new checks fail. `[ddgka]` held before too, since the body was already the section.
		- Not run: the full test.bash, the gate, and a real cut.
	- Branch: dltable
	- Commit: 035cb8e
	- Test case: test.bash `[ddgk8]`, `[ddgk9]`, `[ddgka]`, `[ddgkb]`, `[ddgkc]`.
	- Verified: the 2026-10-04 test batch. test.bash on b23 passed 1452 and failed 1, which is 1412 plus this round's 41 new checks. The one failure is `[db712]`, from enhancement 8.
	- Note: the installers read `SHA256SUMS` and the release list, never the body, so they are untouched.
	- Question: a table cell can't span two columns, so the macOS universal file is listed under both amd64 and arm64. Is that the wanted reading of "its row doesn't split by CPU"?
		- Answer: yes, both columns. Moved to Decisions.
	- Acceptance signoff: Self-closed: its one question is answered, and the checks fail before and pass after. The first real cut runs it against GitHub, and phase 3 warns if the table and the published files disagree.
	- Closed: 20261005-072140

- Run the tests on a Mac and a Windows box as part of the pipeline
	- ID: 2026100312332924
	- Type: Enhancement
	- Status: Done
	- Needs external testing: None left. It ran on b26 and vm925w on 2026-10-04. b29w runs only when vm925w is taken.
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Related IDs: 2026100409453279, 2026100409453281, 2026100409453283
	- Target OS: macOS, Windows
	- Requirements  [Feature]:
		- macOS is still built every run, either here or on b26.
		- When b26 is up and not reserved, the pipeline runs the tests on it, against the universal dogfood build.
		- It does the same on a Windows box, vm925w or b29w, against the Windows dogfood build.
		- A box that is off, or reserved by another session, is skipped, and the run says so. It does not fail the run, and it does not wait in line.
		- Each box is taken through the host lock first, the way the other projects do.
			- The lock's `wrap <host> --wait 0 -- <command>` takes a free box and holds it only while the command runs.
			- The lock script is not in this repo. Where it is missing, the stage is skipped with a note.
	- Decisions:
		- Not built or tested on either box yet. This item only files the work.
			- Since 2026-10-04 it is built, and has run on both boxes.
		- 2026-10-04: What runs. Both boxes run the Go tests, cross-built here for darwin/amd64 and windows/amd64. b26 also runs test.bash against the universal dogfood build, under Homebrew's bash (`/usr/local/bin/bash`, 5.2), since `/bin/bash` there is 3.2. It runs in a copy of the tree kept in the stage's own folder under the remote home. Fuzz and parity are not run remotely.
			- So the Windows box gets the Go tests only, not a run against the Windows dogfood build. Neither box has a bash to run test.bash with.
		- 2026-10-04: The stage runs on full runs only. `--quick` and `--gate` skip it.
		- 2026-10-04: Locking. The lock script knows only vm925w and b29w by default. The stage adds b26 to the lock's host list in its own environment, and takes each box with `wrap <host> --wait 0 -- <command>`. A box that is off, unreachable, or held by another session is skipped with a note, and never fails the run or waits. On Windows either vm925w or b29w will do, whichever is free. With no lock script the stage is skipped with a note.
		- 2026-10-04: The lock script is outside this repo, and is not changed for this.
	- Progress log:
		- The macOS build is already here. A release builds `darwin/amd64` and `darwin/arm64`.
		- Note: since item 2026100313491873, a release publishes one universal macOS file in place of those two.
		- b26 is an Intel Mac, so testing there needs `darwin/amd64`. Dogfood builds it since item 2026100312571262.
		- The pipeline and the Go tests were made to pass on macOS on 2026-10-01 (5eadb03), run by hand. Nothing runs them there since.
		- The Go tests can be cross-built with `go test -c`, so neither box would need Go installed. test.bash on b26 would need Homebrew's bash, since the default there is 3.2.
		- No stage runs the Go tests on Windows today. That is how `TestCanonPath` and `TestDisplayPath` broke there unnoticed.
		- Done: stage 7, "Mac + Windows tests", in `cicd/remote-tests.bash`. Publish is stage 8. How it works is on the child item.
		- Verified: the stage run alone on 2026-10-04, on b26 and vm925w. b26's Go tests all pass, and its test.bash run passed 1209 and failed 5. vm925w's Go tests failed one. Those come from three bugs, filed as their own items. vm925w was free, so b29w was not tried.
		- Verified: `TestCanonPath` passes on vm925w. `TestDisplayPath` no longer exists, since `displayPath` was removed on 2026-09-16.
		- Note: until those three bugs are fixed, a full run stops at stage 7.
	- Branch: remtest
	- Commit: 956d07b
	- Test case: test.bash `[ddg83]` to `[ddg87]` for the stage in cicd.bash, and `[ddg88]` to `[ddg8r]` for the harness, 22 in all.
	- Verified: a full pipeline run on 2026-10-05 passed on every box.
	- Acceptance signoff: OK, 2026-10-05, after the full run.
	- Closed: 20261005-071114

- Build the stage
	- ID: 2026100313002135
	- Type: Task
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Parent ID: 2026100312332924
	- Requirements  [Feature]:
		- Write the pipeline stage the parent item describes.
		- It is not done until it has run on b26 and on a Windows box.
	- Progress log:
		- Done: `cicd/remote-tests.bash` asks each box over ssh first, then builds the Go tests for the platforms that answered. Each box is taken through the lock only for its own run.
		- Done: the Mac gets a copy of the tree with the git dir, fetches the Go modules, then runs the Go tests and test.bash. The suite reads the history, and its own builds run with downloads blocked. The copy sits in `~/gitsby-remote-tests`, marked as the stage's, and a folder of that name without the mark is left alone.
		- Done: Windows gets the module and its test binary in a folder under `%TEMP%` made for the run. It is removed after, and only when the run made it.
		- Done: cicd.bash builds the universal Mac binary with the function dogfood uses, and hands it to the harness. Each Go test prints a line with its ID, from an include stage 2 now shares. `--no-remote` skips the stage.
		- Note: b26's shell startup file prints on every ssh command, which breaks rsync, scp and sftp. The copy goes as a tar stream, and output is read from a marker line on.
		- Note: the lock is asked as a plain process. Asked as the calling session, a miss keeps the session in line, and the box is set aside for it for up to five minutes.
		- Note: the copy is about 120 MB with the git dir, sent whole each run. That takes a few seconds on the LAN. The Mac half of a run takes about seven minutes, most of it test.bash.
		- Verified: test.bash 1398/0 on b23, with the 22 new checks.
		- Verified: eight faults put into a copy of the harness, one at a time, each turned its check red. The session id handed to the lock, no `--wait 0`, no skip without a lock script, no mark check, removing a Windows folder the run didn't make, no marker filter, every free Windows box run, and a dropped box counted as failed.
		- Verified: with `--quick` no longer skipping stage 7 and the Mac build left behind in cicd.bash, test.bash failed exactly `[ddg83]`, `[ddg84]` and `[ddg85]`. The gate (lint and Go tests) passes.
	- Branch: remtest
	- Commit: 956d07b
	- Test case: test.bash `[ddg83]` to `[ddg8r]`, as on the parent.
	- Verified: a full pipeline run on 2026-10-05 passed on every box.
	- Acceptance signoff: OK, 2026-10-05, after the full run.
	- Closed: 20261005-071114

- Pipeline test for converting old SHCL settings files
	- ID: 2026100313483664
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Related IDs: 2026100312145843
	- Requirements  [Feature]:
		- As part of CICD, create settings files in the older SHCL format versions.
		- Test the automatic conversion on them, the one gitsby does on first run with no help from shcl.
	- Notes:
		- Today's checks feed in hand-typed 2.x text.
	- Progress log:
		- Done: test.bash compiles the last gitsby build on SHCL 2.x from its commit (53a6231), and has it write an accounts file with `account set`. The current build has to convert that file, list every account the way the old build did, and keep the old file byte for byte. A fuzz target writes values through the 2.x module itself and checks each reads the same after the conversion.
		- Note: nothing is downloaded at test time. The 2.x module is a test-only require in go.mod, so the lint and unit test stages put it in the module cache, and the old build compiles from there with the proxy off. A box whose cache lacks it fails `[ddg6f]` by name; `go mod download` in `src-go` fixes that.
		- Note: 2.x is the only older format gitsby ever wrote. SHCL 1.x has no Go module and writes the same footer as 2.x, so a 1.x file is converted as a 2.x one. By shcl's 2.0.0 changelog only quoted key names changed between the two, and gitsby's keys have none. Not run.
		- Verified: the five checks pass on their own against the current build. `[ddg6j]` fails with the conversion taken out of `migrateText`, and all five fail with an empty module cache. `go vet ./...` from an empty module cache fetched the 2.x module, and the old build then compiled offline.
		- Verified: FuzzOldFormatValue's seeds fail with the conversion taken out, 6 of 13, and 90 s of fuzzing found nothing. go test -race, vet, staticcheck, golangci-lint, shellcheck and the test ID check are clean.
	- Branch: oldshcl
	- Commit: af80433
	- Test case: FuzzOldFormatValue, and test.bash `[ddg6f]`, `[ddg6g]`, `[ddg6h]`, `[ddg6j]`, `[ddg6k]`.
	- Verified: test.bash 1408/0, `go test ./...`, fuzz.bash 301/0 and parity 29/0 on merged gover, 2026-10-04.
	- Acceptance signoff: Self-closed: tests only, the intent was clear, and every new check passes in the full suite. 30 s more of FuzzOldFormatValue found nothing.
	- Closed: 20261004-114742

- Code Review 20261003 enhancement 1: The spawn-count fixture can't see the account paths
	- ID: 2026100313123975
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- Add a configured account, a fake `gh` and a pty run to the fixture, so it counts what a real user's `status`, `whoami` and `account list` start.
		- Give each counted command a threshold that fails the gate.
	- Actual effort: Avg
	- Decisions:
		- Do this first. The other spawn items in this round need it to prove anything.
	- Origin: spawn-count.bash uses an empty config, a local origin and captured stdout. Four of this round's spawn findings are out of its sight. Confirmed.
	- Done: The fixture has two more clones whose origin is on github.com, one over ssh and one over https. An account's folder rule covers each, with a token file and no token in gh. A fake `gh` and `ssh` answer on PATH, and a proxy on a closed port stops anything else. HOME moved into the fixture.
	- Done: Five new measures run on a pty with no `-q`: `status` with a fetch, `status`, `whoami` and `account list` in the ssh folder, and `status` in the https folder.
	- Done: Each command has a limit written beside it, set at today's count. A count over it fails and records nothing, and `--record` doesn't lift it. The baseline compare is unchanged. So is the tsv, so spawn-report.bash reads it as before.
	- Note: The new measures see what enhancements 2, 5 and 6 will move: both `gh api user` calls and the `ssh -T`, one `gh` per login in the listing, `tput cols`, the `gitsby.ghTokenFile` lookup made twice, the protocol asked of `gh` on an https origin, and `origin/HEAD` read twice after a fetch. The older measures already see `show-ref` in `br switch` and `br prune`, and the two `rev-parse` calls at startup.
	- Done: The number beside each command is its expected count. The limit is that plus 2, or a tenth again, whichever is larger, the same room the baseline compare gives. A git update that starts one more helper no longer fails the gate. Changed after signoff, 2026-10-03.
	- Note: The stub build in test.bash's spawn-count checks names `/bin/sh` rather than going through env, so its count doesn't depend on PATH.
	- Verified: full test.bash on spawnfix, 1311 passed, 0 failed.
	- Verified: the 13 counts were the same over four runs, and the first eight match the 2026-09-30 baseline. Lowering one limit below its count failed a `--record` run with nothing recorded; put back, the run passes.
	- Branch: spawnfix
	- Commit: e6fca88, 0073a9c
	- Test case: The limits in spawn-count.bash, run in stage 3. [ddf54] in test.bash fails a count over its limit under `--record`. It fails against the script before this change. [ddf82] passes a count one over the expected one, and fails against the limits with no headroom.
	- Acceptance signoff: OK, 2026-10-03, with headroom on the limits.
	- Closed: 20261003-163955

- Code Review 20261003 enhancement 4: PowerShell lint starts pwsh four times
	- ID: 2026100313124015
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- Run both PSScriptAnalyzer passes over every file in one pwsh call. It's about 10 s now and about 3 s that way, on every `--gate`.
		- Put the rules in a `PSScriptAnalyzerSettings.psd1`, as the directive asks, rather than inline in cicd.bash.
	- Decisions:
		- Indentation stays four spaces. The directive's tab rule doesn't reindent existing code.
	- Origin: cicd.bash stage 1. Confirmed, timed.
	- Done: One pwsh now probes for the module, lints every file and reports the module's version, so the tool version check doesn't start another. The rules are in `PSScriptAnalyzerSettings.psd1` at the repo root. A file that doesn't parse is caught by the parser before the analyzer runs, so a Severity filter added to the settings later can't hide it.
	- Note: The old first pass filtered by severity, which dropped parse errors. Only the 5.1 pass caught them.
	- Done: `PSUseConsistentIndentation` is on, at four spaces. Nine continuation lines in install.ps1 were reindented to suit it, and one `@( )` around a loop was dropped, since nothing there needs an array. Turned on after signoff, 2026-10-03.
	- Swept: every pwsh start in cicd.bash. The lint probe, both passes per file and the version check were the only ones.
	- Verified: the lint went from six pwsh starts to one, and from about 5.4 s to 2.6 s on this box. `cicd.bash --gate` passes, 21.1 s before and 20.2 s after, most of it the Go tests. It fails on an alias, on 5.1-only syntax and on a parse error in run-latest.ps1, and on an alias in install.ps1, then passes again once the file is back. test.bash passes 1318 of 1318.
	- Branch: pslint
	- Commit: 94db0f5
	- Test case: [ddf5g] counts the pwsh starts in a gate run and checks both files are in the one call. [ddf5h], [ddf5j], [ddf5k], [ddf5m], [ddf5n] and [ddf5p] cover the missing module, the missing settings file, the real lint on clean, 5.1-only and broken files, and the settings file being ASCII. Each failed against the old code or a broken settings file, except [ddf5h], which the old code also passes. [ddf83] fails a file indented two spaces, and fails against the settings without the rule.
	- Acceptance signoff: OK, 2026-10-03, with the indentation rule on.
	- Closed: 20261003-163955

- Code Review 20261003 enhancement 3: `sync` and `pullcom` fetch twice
	- ID: 2026100313124002
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- After the start-of-command fetch works, merge from the upstream with `--ff-only` rather than pulling, so origin is asked once.
	- Actual effort: Avg
	- Decisions:
		- The plan text changes, and so does parity with v2.1.0. OK'd 2026-10-03.
	- Origin: mutate.go pull steps, there since the port. Confirmed in a trace.
	- Done: Every pull step is now `git merge --ff-only @{u}`, with `--autostash` where the pull had it. That covers `pullcom`, `sync`, and the park and target pulls in `br`, `release` and `pr`. The merge brings in what the plan's incoming list showed, rather than whatever origin has by the time the prompt is answered.
	- Done: A branch whose upstream is on another remote still pulls, since the start fetch covers origin only. Merging there would call the branch up to date against a stale ref. The plan reads each branch's upstream and shows the step that will run.
	- Done: `--no-fetch` and offline keep their meaning: the step is skipped with the same message, and nothing stale is merged. A diverged branch still refuses, as v2.1.0 did, since its pull was `--ff-only --autostash` too. Same git message, exit code, and untouched tree. A conflicting autostash still stops before the commit.
	- Done: The plan reads one `for-each-ref` for the target branch's upstream. `br switch` and the rest take the branch's local existence from the same answer, so their counts don't rise.
	- Done: design.md has the rule, and the plan example in style-guide_ui-ux.md shows the new line.
	- Note: Parity had no plan check before. It now compares the `pullcom` and `sync` plans with the frozen build, with the two spellings of the pull line mapped to one token.
	- Note: The spawn-count `pullcom` measure runs with `--no-fetch`, so the pull step never runs there and it stays at 25. A new measure, `pullcom` with a fetch, went from 38 to 32 and its limit is 32. The measure is the gate.
	- Note: [dafrs] in test.bash matched `git pull --ff-only` in the `br switch` plan. It now matches the merge line. What it checks, that switching onto the current branch still plans the pull, is unchanged.
	- Swept: `grep -n 'pull' src-go/*.go`. The two runners, `cmdPull` and `pullIfOnline`, and every plan line that named a pull, all in preview.go. cicd.bash's own fast-forward already used `merge --ff-only --autostash '@{u}'`.
	- Verified: `go test ./...`, `cicd/parity.bash` 29/0, `cicd/cicd.bash --gate`, spawn-count with every count at or under its limit, and full test.bash 1328/0.
	- Verified: against the gover build, [ddf5v], [ddf5x] and [ddf5z] fail, parity's two plan checks pass without the mapping, and the new spawn measure goes over its limit at 38. With the other-remote case taken out, [ddf62], [ddf63], [ddf64] and [ddf65] fail. With `--no-fetch` merging, [ddf60] and [ddf61] fail. With the plan guessing the target's upstream, [ddf64] fails.
	- Branch: onefetch
	- Commit: f61adb6
	- Test case: [ddf5v] to [ddf63] and [ddf64] in test.bash, [ddf65] TestPullArgsFor, [ddf66] and [ddf67] in parity.bash, and the [ddf68] spawn-count limit.
	- Acceptance signoff: OK, 2026-10-03. The plan will name the resolved branch rather than `@{u}`, filed as its own item.
	- Closed: 20261003-163955

- Dogfood builds macOS for both CPUs
	- ID: 2026100312571262
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Related IDs: 2026100312332924
	- Requirements  [Feature]:
		- Add `darwin/amd64` to the dogfood targets.
	- Decisions:
		- There is one macOS dogfood folder and both builds are named `gitsby`, so they are joined into one universal binary there.
		- lipo only exists on a Mac, so a small script writes the universal file. Each build goes in unchanged.
	- Branch: macfat
	- Test case: four checks in test.bash for the joined file, its refusals and the dogfood target.
	- Closed: 2026-10-03

- Convert an accounts file from an older SHCL format
	- ID: 2026100312145843
	- Type: Enhancement
	- Status: Done
	- Priority|Severity [Feature]: Avg
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- When a new shcl major breaks the old format, the old file is renamed `<name>_backup_YYYYmmDD-HHMMSS_format-v<N>.shcl`.
		- A new file goes in its place at the same path, written through shcl with whatever it can convert.
		- Don't race or trample shcl, which may do the backup and conversion itself one day. Look for a shcl API that helps first.
	- Decisions:
		- shcl 3.0 changes what a backslash means outside double quotes, so 2.x files qualify. Its `Migrate` and `FormatVersion` do the conversion and the check.
		- A file is old when its `Format` line says so, or when it has the 2.x footer. One with neither reads as current and is left alone.
		- Done on the first run that reads the file, with a note on stderr. Where it can't be written, the run reads it converted and `account set` refuses.
	- Branch: cfgmig
	- Test case: TestOldFormat, TestOldFormatFileIsConverted, TestUnmarkedFileIsLeftAlone, TestOldFormatUnwritable, TestOldFormatThroughALink, TestOldFormatConvertedByAnotherRun, and three checks in test.bash.
	- Closed: 2026-10-03

- Run the tests on FreeBSD and on Linux arm64 in stage 7 too
	- ID: 2026100413264100
	- Type: Enhancement
	- Status: Done
	- Needs external testing: None left. b26 ran on 2026-10-04.
	- Priority [Feature]: Avg
	- Opened: 20261004-132641
	- Opened by: jim-collier
	- Related IDs: 2026100312332924, 2026100416430451, 2026100416430456
	- Target OS: FreeBSD, Linux arm64
	- Requirements  [Feature]:
		- Two more test boxes share the host lock: vmFreeBSD and vmDebARM64. Both are VMs with a virtual display.
		- Stage 7 runs the cross-built Go tests on each, against the FreeBSD amd64 and Linux arm64 builds, the same way it does on vm925w.
		- test.bash runs there too where bash and the tools it needs are on the box.
		- A box that is off or reserved is skipped, the same as the others.
	- Note: FreeBSD and Linux arm64 are published targets that no test has run on yet.
	- Decisions:
		- 2026-10-04: Both boxes have a test user with no password: `bsdtest` on vmFreeBSD and `tester` on vmDebARM64, neither with sudo. Both also take root over ssh. Root is for setup only, such as installing what test.bash needs. The tests run as the test user.
		- 2026-10-04: vmFreeBSD runs FreeBSD 15.1 at a static 192.168.1.119. vmDebARM64 is at 192.168.1.118. Both are libvirt VMs on b23.
		- 2026-10-04: Both boxes are taken through the host lock by name, in its other-hosts list, like b26.
	- Progress log:
		- Done: stage 7 runs the Mac's flow on each Unix box in `REMOTE_UNIX_HOSTS`, as its test user. Each box gets a copy of the tree, the Go tests built for its target, and the build cicd.bash makes for that target. Targets are set per box in `REMOTE_UNIX_TARGETS`.
		- Done: test.bash runs only where the box has bash, git and go (`REMOTE_UNIX_NEEDS`). Otherwise the box runs the Go tests and the run names what it lacks. The module fetch is skipped too.
		- Done: cicd.bash builds `freebsd/amd64` and `linux/arm64` the way dogfood builds, hands them to the harness with `--bin`, and removes them after. The stage keeps its name, "Mac + Windows tests".
		- Done: README and contributing.md list the new boxes.
		- Installed on vmDebARM64 as root: Go 1.26.8 from go.dev, in `/usr/local/go`, linked from `/usr/local/bin/go` and `gofmt`. bash, git and jq were already there.
		- Nothing installed on vmFreeBSD. bash, git, jq and Go 1.25 were already there. Go fetches the 1.26.2 toolchain go.mod names into the test user's module cache on the first run.
		- Verified: the 8 new checks and `[ddg83]` pass, and each new one fails against gover's harness. Six faults put into a copy of the harness, one at a time, each turned its check red: the Unix boxes left out of the lock's list, a missing tool ignored, the module fetch always run, no target check, one target's build sent to every box, and gover's harness. `[ddg83]` fails against gover's cicd.bash and with a Unix build left behind.
		- Verified: shellcheck, `test-id.bash --check` and the gate pass.
		- Verified: stage 7's harness run against only the two new boxes, under the lock, 2026-10-04. vmFreeBSD: test.bash 1178/0, Go tests all pass but `TestLockAccountsFile`. vmDebARM64: Go tests all pass, test.bash 1436/1, the one being `[ddg72]`. Both filed as their own bugs.
		- Note: vmDebARM64 is an emulated arm64 CPU. Its test.bash took about 40 minutes, against about one on vmFreeBSD, so a full run is that much longer.
	- Swept: every reader of the stage 7 settings. cicd.bash prints and builds from them, remote-tests.bash runs from them, and the test.bash fixture copies config.bash. The existing harness checks pin the Mac and Windows boxes, so their fixture empties `REMOTE_UNIX_HOSTS` and the new checks put it back.
	- Note: `[ddg83]` keeps its ID. It used to require only the Mac build in the harness call, and now requires the two Unix builds as well, all three removed after.
	- Branch: unixrt
	- Commit: c59ef24
	- Test case: test.bash `[ddgm1]`, `[ddgm2]`, `[ddgm3]`, `[ddgm4]`, `[ddgm5]`, `[ddgm6]`, `[ddgm7]`, `[ddgm8]`, and `[ddg83]` (changed).
	- Verified: the 2026-10-04 test batch. test.bash on b23 passed 1452 and failed 1, which is 1412 plus this round's 41 new checks. The one failure is `[db712]`, from enhancement 8.
	- Verified: stage 7 on 2026-10-04. vm925w passed its Go tests. vmFreeBSD and vmDebARM64 passed their Go tests, and their test.bash failed only `[db712]`, from enhancement 8. b26 was skipped, since another session held it.
	- Question: stage 7 is still labeled "Mac + Windows tests". Renaming it changes output text that `[ddg83]`, `[ddg84]` and `[ddg85]` check. Rename it?
		- Answer: yes, to "Remote tests". Filed as 2026100418431100.
	- Verified: stage 7's harness on gover after round 4, 2026-10-04. b26: Go tests pass, and test.bash against the universal build 1255/0. vmFreeBSD, vmDebARM64 and vm925w: Go tests pass. The Unix boxes ran Go tests only this time, since no Unix builds were passed. Their full test.bash ran earlier the same day and failed only `[db712]`, fixed since.
	- Acceptance signoff: Self-closed: tested on every box, and its one question is answered.
	- Closed: 20261004-190953

- release.bash --help prints nothing
	- ID: 2026102517464688
	- Type: Bug
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261025-174646
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- `bash cicd/release.bash --help`
	- Incorrect behavior [Bug]: No output, exit 0.
	- Expected behavior [Bug]: The header's Purpose, Syntax and Notes, as `cicd.bash --help` prints its own.
	- Reproduced [Bug]: 2026-10-25, no output and exit 0.
	- Possible cause [Bug]: The `--help` arm looks for a `- Purpose:` line, and release.bash's header spells it `Purpose:`.
	- Actual cause [Bug]: As above.
	- Actual fix [Bug]: The arm looks for `Purpose:`, as remote-tests.bash and the utility scripts do.
	- Branch: round-20261025b
	- Test case: test.bash [dee92], once for each script whose `--help` prints its header, 7 now.
	- Verified: [dee92]'s command fails on the old release.bash and passes on the new one. test.bash 1748/0 in `--backlog-run-quick`.
	- Swept: every script with a `--help` arm. cicd.bash, remote-tests.bash, pre-push.bash, gen-winres.bash, keep-build.bash and spawn-count.bash print their headers. test.bash, fuzz.bash, parity.bash and install.bash print a usage line, and backlog-check.bash, lint-report.bash, spawn-report.bash and test-id.bash print their headers their own way.
	- Acceptance signoff: Self-closed: its test failed before and passes after.
	- Closed: 20261025-181343

- test.bash's remote harness checks fail when stage 7 is narrowed to one box
	- ID: 2026102321011743
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. test.bash ran 1677/0, narrowed and not.
	- Needs external testing: No.
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261023-210117
	- Opened by: jim-collier
	- Related IDs: 2026102306584122
	- Target OS: All
	- Steps to reproduce [Bug]:
		- In a clone, set `REMOTE_MAC_HOSTS` and `REMOTE_WINDOWS_HOSTS` empty in `cicd/config.bash`, the way memory.md says to run stage 7 on one box, and run test.bash.
	- Incorrect behavior [Bug]:
		- 23 checks of the Mac and Windows harness fail, from `[ddg89]` to `[ddgm7]`. Then the last check's setup stops the suite with "mv: cannot stat '.../remote-mac/gitsby-remote-tests'", so nothing after it runs and no totals print. Seen 2026-10-23 on vmDebARM64.
	- Expected behavior [Bug]:
		- The harness checks set their own host lists, so they pass whatever the tree's config.bash names.
	- Possible cause [Bug]:
		- The fixture copies the tree's config.bash and resets only `REMOTE_UNIX_HOSTS`. The checks expect b26, vm925w and b29w from it.
	- Reproduced [Bug]: 2026-10-24 on b23, in a clone with the Mac and Windows lists empty and the Unix list down to vmDebARM64. 25 failed and the suite stopped at the `mv`, as above.
	- Actual cause [Bug]:
		- As guessed, plus a twin. The stage 7 checks in the cicd.bash fixture, `[ddg83]` and `[de4bt]`, read the Unix boxes and targets from the tree's config.bash too. They failed once the Unix list was narrowed.
	- Actual fix [Bug]: `fRemoteBoxes` in test.bash appends the boxes and settings the checks expect to a fixture's config.bash. The harness fixture uses it at each of its 3 copies, and the cicd.bash fixture before its stage 7 checks. Wine is left empty there, since no check runs it.
	- Swept: every `config.bash` copy and `source` in test.bash. The release, keep-build, shellcheck and CodeQL fixtures read no stage 7 setting.
	- Branch: round-20261024
	- Test case: test.bash itself, run with config.bash narrowed. No new check, since the fault is in what the tree's config holds.
	- Verified: 2026-10-24, test.bash in the narrowed clone, 25 failed before and 1677/0 after. 1677/0 in the main tree with config.bash as committed. Gate passed.
	- Acceptance signoff: Self-closed. Reproduced, fails before and passes after, no open choice.
	- Closed: 20261024-064653

- `pr` and `repo create` run `gh` by bare name, so one on PATH that is gitsby runs gitsby
	- ID: 2026102111572785
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. test.bash ran after the fix.
	- Needs external testing: Stage 7. Every spawn now runs by the path the PATH walk found, git included, and that walk is only cross-built for macOS, FreeBSD and Windows.
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261021-115727
	- Opened by: jim-collier
	- Related IDs: 2026101916533300
	- Steps to reproduce [Bug]:
		- Put a link named `gh` to gitsby first on PATH, with no real gh after it, and run `gitsby pr` in a GitHub repo.
	- Incorrect behavior [Bug]:
		- It runs gitsby as `gh pr list`, which prints gitsby's own `pr` syntax help, then "'gh pr list' failed (exit 1)".
	- Expected behavior [Bug]:
		- The same refusal `raw` gives: "Not found in path: gh", naming the entry that is gitsby.
	- Possible cause [Bug]:
		- `hostToolFor`, `mustBeInPath` and the tea lookup ask `exec.LookPath`, and the runners pass the bare name. 2026101916533300 fixed only `raw`. `lookTool` in exec.go could serve them too.
	- Reproduced [Bug]: 20261021, on the build before the fix. `pr` in a GitHub repo gave "'gh pr list' failed (exit 1)", `pr` on another host "'tea pulls list' failed (exit 1)", and `repo create` "Couldn't ask GitHub about me/proj ... Unexpected option in this context: '--json'".
	- Actual cause [Bug]:
		- Every spawn outside `raw` went through `exec.Command` with the bare name, and every "is it installed" asked `exec.LookPath`, both of which find the link that is gitsby.
	- Actual fix [Bug]:
		- One lookup for every program gitsby runs, git included: `toolCmd` and `toolCmdContext` in exec.go build the command from `findTool`, which is `lookTool` asked once per name and PATH. A name found only as gitsby gets a "Not found in path" error that names the entry, and is never started. `inPath` and `mustBeInPath` ask the same lookup, so the gh login checks, the tea probes and `hostToolFor` see a gitsby-only gh or tea as not installed. `pr` says so by name rather than suggesting an install, and `repo create` and `repo connect` refuse through `mustBeInPath`. `raw` uses the same refusal text through `notInPath`. A Go test fails if any other file calls `exec.Command`, `exec.LookPath` and the like, so a new call site can't skip it.
		- design.md "Execution flow" has a bullet for it.
	- Swept: every `exec.Command`, `exec.CommandContext` and `exec.LookPath` outside tests. exec.go's runners (runOut, runOutOK, runOK, inherit, inheritRC, so step and stepAs), show.go (showList, `ssh -G`), githost.go (`tea logins list`, `tea --version` through runOut, teaCommand and hostToolFor through inPath), repo.go (`gh repo view`, `git ls-remote`, `git init`, `git ls-files`, both mustBeInPath("gh")), remote.go (ssh probe, `git fetch`, `git remote set-head`, `git ls-remote`, `gh config get`), account.go (`gh auth token`, `gh api user`, `gh config get`), main.go (`git rev-parse`, mustBeInPath("git"), raw), pr.go (settlePrTool and every pr.cli run). handover still runs the path raw resolved. The frozen bash and pwsh builds were not touched.
	- Test case: test.bash `[de89w]`, `[de89x]`, `[de89y]`; Go `[de89z]` (TestToolCmdSkipsSelf), `[de8a0]` (TestOneSpawnSite).
	- Branch: round-20261021
	- Verified: The 3 new test.bash checks fail on the build before the fix. After it, test.bash 1591 -> 1594, 0 failed. The 2 Go tests fail with toolCmd's refusal taken out and with an `exec.Command` put back in show.go. `go test ./...`, `cicd.bash --gate`, `GOOS=windows go vet ./...`, and darwin, freebsd and windows builds pass.
	- Verified: 2026-10-21, stage 7 passed on b26, vmFreeBSD, vmDebARM64 and vm925w, so every spawn in those suites went through the PATH walk on each OS. The 3 new test.bash checks ran on the 3 Unix boxes, and `[de8a0]` passed on all 4. On vm925w `[de89z]` skips, since it needs symlinks and the exec bit, so the self check itself is untested on Windows. test.bash 1594/0 on b23, in the container and off it.
	- Acceptance signoff: Self-closed: stage 7 passed everywhere, which was all that was left.
	- Closed: 20261021-132100

- test.bash on b26 prints `grep: warning: stray \ before -` 22 times
	- ID: 2026102120365577
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. test.bash ran 1661/0 on 2026-10-22.
	- Needs external testing: No. Stage 7 passed on every box 2026-10-22.
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261021-203655
	- Opened by: jim-collier
	- Target OS: macOS
	- Test environment: b26
	- Incorrect behavior [Bug]:
		- Stage 7's b26 log has the warning 22 times, on 2026-10-21 and 2026-10-22 both. The checks still pass, but it's noise in the log, and a pattern grep warns about may not match what it should.
	- Expected behavior [Bug]:
		- No grep warnings. Each pattern matches the same lines on every box.
	- Actual cause [Bug]:
		- b26 has GNU grep 3.12, which warns about `\-` in a pattern given without `-e`. 17 `fAssertOut` patterns in test.bash escaped their leading dashes so grep wouldn't read them as options. Debian's grep 3.11 here prints nothing for the same patterns.
		- 6 of those patterns also wrote a literal pipe as `\|`, which is undefined in an extended regex. GNU reads it as a pipe, and other greps may read it as alternation, which matches more.
	- Actual fix [Bug]: `fAssertOut`, `fAssertNotOut`, `fAssertPlan` and `fAssertNotPlan` pass the pattern after `--`, as `fPlanRan` and `fGateSays` already did. The patterns drop the backslashes, and a literal pipe is `[|]`.
	- Branch: round-20261023
	- Test case: test.bash `[dea3d]` fails on a backslashed dash anywhere in the 26 pipeline and installer scripts, and `[dea3e]` on a backslashed pipe in a check pattern. Both sit in the `[db712]` loop.
	- Verified: before the fix both new checks fail on cicd/test.bash only, `[dea3e]` on 6 lines. After it all 26 scripts pass both. The 20 changed or neighboring installer and help checks pass when run alone against the real output, and `[dcq73]`'s pattern matches `repo url ftp` output. A `[|]` pattern does not match a line without the pipe. shellcheck, `test-id.bash --check` and the gate pass.
	- Verified: 2026-10-22, a plain full run in the container on b23 passed every stage, with no grep warning anywhere in its log. `[dea3d]` and `[dea3e]` passed for all 26 scripts in the container and on b26, vmFreeBSD and vmDebARM64. test.bash 1660/0 in the container and 1661/0 on b23 off it, 1433/0 on b26 and 1336/0 on vmFreeBSD, each 62 more than on 10-22, and 1646/0 on vmDebARM64, 63 more. Of those, 52 are this item's and the rest are the round's glab and workflow checks. The container, b26 and vmFreeBSD skip `[dea4c]`, since they have no PyYAML. Log: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261022-19253166/run.log`.
	- Swept: every `grep` taking a pattern variable in cicd. parity.bash's 4 `grep -E "${pattern}"` calls get fixed patterns with no leading dash, so they stay. No `\-` anywhere else in the repo. The awk `\|` at test.bash's table reader is awk, not grep, and stays.
	- Acceptance signoff: Self-closed: stage 7 passed everywhere with no grep warning, which was all that was left.
	- Closed: 20261022-201221

- `--no-fuzz` still runs govulncheck and pip-audit
	- ID: 2026102113100100
	- Type: Bug
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261021-131001
	- Opened by: jim-collier
	- Related IDs: 2026102113100000
	- Incorrect behavior [Bug]:
		- The help says `--no-fuzz` skips the fuzz + security stage, but in cicd.bash only fuzz.bash, the native fuzz targets, the spawn counts and the leak checks look at it. govulncheck and pip-audit still run, so `--no-fuzz` doesn't get past a pip-audit stop.
	- Reproduced [Bug]: Yes, 2026-10-21, by [de8q2] against the old cicd.bash.
	- Actual cause [Bug]:
		- govulncheck sat outside the `--no-fuzz` gate on purpose at first (894d857, 2026-08-19). `--quick` then worked by turning fuzz off, and govulncheck ran under it anyway, "because it is a lookup rather than a workload".
		- 81def43 (2026-10-18) made `--quick` skip it, since it reaches vuln.go.dev, and dropped that reason, but left it outside the gate. pip-audit copied its gate on 2026-10-19.
	- Decisions:
		- The reason for the split is gone, and the leakflags item 2026101912030152 already treats `--no-fuzz` as turning off what's in stage 3. So `--no-fuzz` skips the whole stage, as the help says, and also the help stays as it is.
	- Actual fix [Bug]: govulncheck and pip-audit check `--no-fuzz` like the rest of stage 3.
	- Branch: round-20261022
	- Commit: 73d6a98
	- Test case: test.bash [de8q2]. [de54e] and [de54k] had used `--no-fuzz` to skip the rest of stage 3, so they pass `--no-leakcheck` now, with the same IDs.
	- Verified: [de8q2] fails against the old cicd.bash and passes with the fix. test.bash 1597 -> 1598, 0 failed, and `cicd.bash --gate` passes.
	- Swept: the help's stage list and option lines, README (no mention), contributing.md, where `--leakcheck` adding the leak checks back to `--no-fuzz` still holds, config.bash's pip-audit comment, and the history footers of cicd.bash and test.bash. The run in the container already gets `--no-fuzz` as given.
	- Closed: 20261021-194000

- Code Review 20261005 item 3: The help and design.md disagree on which commands are daily
	- ID: 2026100516202618
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: design.md:188 and the UI style guide say commands split by how often they're typed, with `pullcom`, `sync`, `status`, `whoami` and `release` as the daily one-word verbs. The help puts `sync` and `whoami` under "Less common commands" and `release` under "Admin commands", and lists `br create` and `br switch` as common. The README tags `sync` "Do infrequently".
	- Expected behavior [Bug]: One story about how the commands are grouped.
	- Reproduced [Bug]: Yes, `gitsby --help` against design.md and the style guide.
	- Origin: design.md:188 from d446496 (2026-07-26). The help's groups go back to 2.x, 3a97c0e in 2022. No round saw it. Confirmed.
	- Note: The help's groups read true. The one-word split isn't about how often a command is typed, so the design line and the style guide should say what it is. Regrouping the help is the other choice.
	- Actual fix [Bug]: design.md and the UI style guide now call the one-word commands the workflow steps, with everything else under the thing it acts on. The help is unchanged.
	- Branch: direct
	- Commit: e1cc030
	- Test case: none, docs only.
	- Closed: 20261005-190835

- Code Review 20261005 item 4: Help says "GitHub accounts" where an account can be on any git host
	- ID: 2026100516202655
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: The help's `account` line says "Show your configured GitHub accounts", right above 2 examples that use `gitea.com`. The README's `account` row says the same. design.md:249 opens with "Which GitHub account you act as".
	- Expected behavior [Bug]: Say "accounts" where any host is meant.
	- Reproduced [Bug]: Yes, `gitsby --help`.
	- Origin: help.go:62 from fc0ddda (2026-08-08), before accounts took a `host`. No round saw it. Confirmed.
	- Decisions:
		- The README's "Multiple GitHub accounts" heading changes too (2026-10-05). It is "Multiple accounts" now, and so is accounts.md's title.
	- Progress log:
		- 2026-10-05: Asked what the problem is. Answered in the reply.
		- 2026-10-05: OK'd, with the README heading changed as well.
	- Actual fix [Bug]: "accounts" in the help's `account` line, the README's `account` row and design.md's heading. The README section and accounts.md are titled "Multiple accounts", with the TOC entry updated. The prose that says "two GitHub accounts" stays, since GitHub is the usual case.
	- Branch: direct
	- Commit: e1cc030
	- Test case: none, wording only.
	- Closed: 20261005-190835

- Code Review 20261005 item 5: The README's count of subcommands is stale
	- ID: 2026100516202693
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: The README says gitsby has "ten - or 24 counting subcommands". The help lists 25 since `account unset` came in.
	- Expected behavior [Bug]: A number that a check keeps true, or wording with no number.
	- Reproduced [Bug]: Yes, by counting the help's entries.
	- Origin: README:64 from 4ec5fd4 (2026-08-21). `account unset` is 1ed0f3a (2026-09-28). No round saw it. Confirmed.
	- Note: "ten" can keep its number with a check on the help's top-level commands. The subcommand count could say "about two dozen" and claim nothing exact.
	- Actual fix [Bug]: The README says "about two dozen counting subcommands". "ten" stays, and a check holds it.
	- Branch: docfix
	- Commit: f4f624b, 2206206
	- Test case: [ddj3j] in test.bash counts the help's top-level commands and needs 10, with "Gitsby has ten" in the README. Red with the README saying eleven, green as committed.
	- Closed: 20261005-172300

- `account` prints a value with a newline in it across 2 lines
	- ID: 2026100607545812
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261006-075458
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: `account set a name $'n\nemail ..: evil@x'` saves the value quoted and safe. But `account` prints it on 2 lines, and the second one looks like a field of its own.
	- Expected behavior [Bug]: A value prints on one line, with any control character shown escaped.
	- Reproduced [Bug]: Yes, on `fuzzwork`, 2026-10-06. Again on `gover` the same day: the commits row printed `n`, then `email ..: evil@x <?>` on a line of its own. An ESC in a value reached the terminal as is.
	- Actual cause [Bug]: Every display site printed the value as read. Only the plan's `add:` and `becomes:` lines escaped it, since they show the file's own spelling.
	- Actual fix [Bug]: `printable` shows a control character the way the accounts file writes it: `\n`, `\t`, and `\u001B` style for the rest of C0, DEL and C1. Every display site of a config value goes through it. What is stored, and what goes to git config and the fragments, is unchanged. The rule is in the UI style guide under "Words and values".
	- Against: "A path is never re-spelled for display". Only control characters change. Every printable character prints as written, a backslash included, and a byte that isn't UTF-8 passes through, so a path with none in it prints byte for byte the same.
	- Swept: the `account` list (every row, the Account and Ignored keys lines, the shared-rule and stale-rule warnings); the status and `whoami` Account line, its notes (through `noteLines`, which refusals use too), the Config, SSH and Author lines and the loose token file warning; the `account set` and `unset` plans (`was:`, `becomes:`, `add:`, `remove:`); the `account apply` plan, its status lines and refusals, and the unused-fragment line; the `raw` "acting as" line; and the refusals that quote a typed value (account name, key, host, user, protocol, path, GIT_CONFIG_COUNT). `host`, `user` and `protocol` were already held to plain characters, and account names to letters, digits, `.`, `_` and `-`.
	- Note: git drops a newline from an ident itself, so the Author line shows only the ESC escaped.
	- Branch: ctlesc, escall
	- Commit: 2be7d35, 47bcda3
	- Test case: test.bash [ddjz4], [ddjz5] and [ddjz6], and Go `TestPrintableEscapesControlsOnly` [ddjz7], and `TestEveryLineOutIsEscaped` [ddk41].
	- Verified: all 3 suite checks red on `gover`, green here. The Go test fails with the escaping taken out. test.bash 1494/0, fuzz.bash 311/0, parity.bash 29/0, `go test ./...` and the gate pass.
	- Decisions:
		- Anything from a file or another tool gets escaped, with no exceptions to remember. So the escaping moved into the printer's line writers and the error constructors' args, and covers the cwd, remote URL, gh and tea logins, clone folder and config path too. A usage error built from lines keeps its line breaks.
		- A typed `\n` in a value prints the same as an escaped newline. Left that way, since a real control character in a config value is nearly always a mistake or an attack, and doubling backslashes would re-spell every Windows path.
	- Acceptance signoff: jim-collier 2026-10-06
	- Closed: 20261006-104500

- Code Review 20261005 item 2: design.md still states decisions that were reversed or outgrown
	- ID: 2026100516202581
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: design.md says it is revised in place, so what it holds is true now. 5 lines aren't.
		- :536 says displayed paths fold the home folder back to `~`. That was reversed on 2026-09-16. Line 540 and the UI style guide both say a path is never re-spelled. From 919141f.
		- :345 says the engine runs 7 stages. It's 8 behind a stage 0 since 2026-10-04. From fa41f83.
		- :188 names the nouns as `repo`, `br` and `pr`. `account` and `raw` came later, and the UI style guide lists all 5. From d446496.
		- :202 says `pullcom` and `sync` make up a message when none is given, and uses that as the reason `pr create` has a default title. They open git's editor, and make one up only under `-q`. From 0ec08bd.
		- :512 says `gh` is needed for every `pr` form. On Gitea `pr` goes through `tea`, as "Direction decisions" and the README say. From 2835bb7.
	- Expected behavior [Bug]: Each line says what is true now.
	- Reproduced [Bug]: Yes, each line read against the code, the help or the line that reversed it.
	- Origin: the commits named above, 2026-07-26 to 2026-08-20. No round saw these lines. Confirmed.
	- Note: The 20260910 churn audit found this class twice, in its items 8 and 18. A decision reversed in one section and left standing in another. This is the third time. A reversal should grep every doc for the old rule before it merges.
	- Note: :345 is history. Reword it so it doesn't count stages, and there's no number left to drift.
	- Actual fix [Bug]: All 5 lines now say what is true. The run-time tools line names the git host's own tool, `gh` or `tea`, and says a later host brings its own the same way. The stage line no longer counts stages.
	- Swept: the old wording of each line, grepped across every .md in the repo. The other hits are dated history in the changelog and the backlog.
	- Branch: docfix
	- Commit: f4f624b
	- Test case: none, docs only. Nothing in the rewording is a number or a list a check could hold.
	- Acceptance signoff: Self-closed: the item named each line, and each fix only states what the code does.
	- Closed: 20261005-172300

- Stage 7 names b26 as a Windows host to the lock
	- ID: 2026100410340781
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-103407
	- Opened by: jim-collier
	- Related IDs: 2026100312332924
	- Incorrect behavior [Bug]: remote-tests.bash puts every host, b26 included, in the lock's Windows host list. The lock now knows b26 as a host of its own through its other-hosts list, so b26 is listed twice and joins the Windows boxes for `any` and `all`.
	- Expected behavior [Bug]: Mac hosts go in the lock's other-hosts list and Windows hosts in its Windows list.
	- Reproduced [Bug]: Yes, 2026-10-04. The lock's `hosts` lists b26 twice under the stage's setting. Nothing breaks today, since the stage names each host.
	- Origin: remote-tests.bash from item 2026100312332924. The lock gained its other-hosts list the same day. Confirmed.
	- Estimated effort: Low
	- Needs external testing: Optional. A stage 7 run on b26 and a Windows box under the real lock.
	- Actual cause [Bug]: The stage built one host list from the Mac and Windows settings and passed it as the lock's Windows list.
	- Actual fix [Bug]: The Windows list is the Windows hosts only. The other-hosts list is the lock's own, as its `hosts` reports it, plus any Mac not already in it, so the lock's status still lists boxes like vmFreeBSD while the stage runs. An older lock with no other-hosts list refuses the Mac by name, and the stage skips it with that note.
	- Progress log:
		- Verified: against the real lock, read only. Under the old setting `hosts` gives `b26 vm925w b29w b26 vmDebARM64 vmFreeBSD`. Under the new one it gives `vm925w b29w b26 vmDebARM64 vmFreeBSD`.
		- Verified: on a private lock directory with an empty other-hosts list, `wrap b26` exits 2 with "unknown host", which the stage reports as a skip.
		- Verified: test.bash 1401/0. With the old remote-tests.bash, `[ddg8a]` and `[ddga0]` fail, 1399/2.
		- Note: `[ddg8a]` keeps its ID. It used to require b26 in the Windows list, and now requires it once, in the other list.
	- Swept: every reader of the two host settings. cicd.bash only prints them, and config.bash only sets them. The lock's prefix is still taken from its file name.
	- Branch: lockhosts
	- Commit: 2541492
	- Test case: test.bash `[ddg8a]` (lists passed to the lock) and `[ddga0]` (older lock with no other-hosts list).
	- Verified: a full pipeline run on 2026-10-05 passed on every box.
	- Acceptance signoff: OK, 2026-10-05, after the full run.
	- Closed: 20261005-071114

- `TestLockAccountsFile` fails on FreeBSD
	- ID: 2026100416430451
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-164304
	- Opened by: jim-collier
	- Related IDs: 2026100413264100
	- Target OS: FreeBSD
	- Test environment: vmFreeBSD, FreeBSD 15.1 amd64, UFS.
	- Incorrect behavior [Bug]: "unlock removed a lock it didn't make". The test removes the lock, writes a new one at the same path, and unlock removes that one too.
	- Expected behavior [Bug]: unlock leaves a lock file it did not make.
	- Reproduced [Bug]: Yes, 2026-10-04, in stage 7 on vmFreeBSD. It passes on Linux, macOS and Windows.
	- Possible cause [Bug]: unlock tells its own lock by `os.SameFile`, which compares device and inode. UFS hands the freed inode number straight to the new file, so the new lock looks like the old one. Not checked.
	- Actual cause [Bug]: As above, checked on vmFreeBSD 2026-10-04. A file removed and made again at the same path got the same inode number 20 times out of 20 on UFS.
	- Actual fix [Bug]: Each lock gets a random token written into it. Unlock removes the lock only when it still holds this run's token, so a lock another run made after ours is left alone, whatever inode it got. A lock whose token can't be written is removed at once and the run refused, the same as one that can't be made.
	- Progress log:
		- Verified: `TestLockAccountsFile` fails on vmFreeBSD before the fix, three runs of three, and passes after, five of five. All the Go tests pass there after the fix.
		- Verified: `TestUnlockLeavesALockInItsInode` fails on Linux before the fix and passes after. It writes over the lock in place, so the other run's lock keeps our inode on any filesystem.
		- Verified: the gate and `test-id.bash --check` pass. The package vets for Windows and macOS.
		- Note: older builds leave the lock empty, so they and this one never mistake each other's locks.
	- Swept: `os.SameFile`, `Stat_t`, `.Ino` and `ModTime` in src-go. The lock was the only file identity check. Both callers, `account set` and the old-format conversion, only `defer unlock()`, and the signature is unchanged. test.bash's `[dcnk7]` makes an empty lock by hand, which still blocks the create. Not run, since it waits for the full test.bash.
	- Branch: lockid
	- Commit: 0738416
	- Test case: `TestLockAccountsFile` [dcnkb] on FreeBSD, and `TestUnlockLeavesALockInItsInode` [ddgnj] on any platform.
	- Verified: the 2026-10-04 test batch. test.bash on b23 passed 1452 and failed 1, which is 1412 plus this round's 41 new checks. The one failure is `[db712]`, from enhancement 8.
	- Verified: stage 7 on 2026-10-04. vm925w passed its Go tests. vmFreeBSD and vmDebARM64 passed their Go tests, and their test.bash failed only `[db712]`, from enhancement 8. b26 was skipped, since another session held it.
	- Verified: a full pipeline run on 2026-10-05 passed on every box.
	- Acceptance signoff: OK, 2026-10-05, after the full run.
	- Closed: 20261005-071114

- `[ddg72]` fails on the emulated arm64 box
	- ID: 2026100416430456
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-164304
	- Opened by: jim-collier
	- Related IDs: 2026100413264100, 2026100313123988
	- Target OS: Linux arm64
	- Test environment: vmDebARM64, Debian 13 arm64 on an emulated CPU.
	- Incorrect behavior [Bug]: "status in a token-file folder asks gh and ssh together" fails there. Its twin `[ddg75]`, for whoami, passes.
	- Expected behavior [Bug]: the check passes on a slow box when the two probes do run together.
	- Reproduced [Bug]: Once, 2026-10-04, in stage 7 on vmDebARM64. Not rerun.
	- Possible cause [Bug]: the check wants the run under 1.7 s with each probe delayed 1 s. On an emulated CPU the rest of `status` likely takes more than the 0.7 s left. Not checked.
	- Actual cause [Bug]: the time limit. On vmDebARM64 `status` alone takes about 0.5 s, so with the 1 s probe it came to about 1.5 s against the 1.7 s limit. Any load on the box pushed it over. `whoami` is a little faster, which is why it passed in the stage 7 run.
	- Progress log:
		- Verified: on vmDebARM64 with all eight CPUs kept busy, the old `[ddg72]` and `[ddg75]` failed three runs of three. Idle, they passed three of three.
		- Verified: the new checks passed there three of three, idle and busy.
		- Verified: on b23 and on vmDebARM64, the new `[ddg72]` and `[ddg75]` fail on a build that asks ssh only when its line prints. On b23 they also fail on a build that waits for the gh answer before asking ssh, and `[ddg73]` fails on one that asks gh one login at a time. All three pass on the current build.
		- Verified: the gate (lint and Go tests) and `test-id.bash --check` pass.
		- Note: the checks were rewritten, not their rule. The probes still have to run together, per 2026100313123988.
	- Actual fix [Bug]: the fake gh and ssh round trips log when they start and end, and each waits for the others to start before it ends. Asked together they always overlap, and asked in turn the first one ends alone after about 15 s. The checks read that log instead of timing the run.
	- Swept: every check in test.bash that times a run. `[ddg73]` (account list) had the same kind of limit and was changed the same way. `[dcmbe]` times a gate waiting on a lock, and only asks for at least 2 s, which a slow box can't break. Left alone: the Go test `[ddg71]`, which gives a killed probe 10 s, and the prompt polls in the `br prune` checks, which wait up to 10 s. Neither tests that work ran together.
	- Branch: probeov
	- Commit: 773af25
	- Test case: test.bash `[ddg72]`, `[ddg75]`, `[ddg73]`.
	- Verified: the 2026-10-04 test batch. test.bash on b23 passed 1452 and failed 1, which is 1412 plus this round's 41 new checks. The one failure is `[db712]`, from enhancement 8.
	- Verified: stage 7 on 2026-10-04. vm925w passed its Go tests. vmFreeBSD and vmDebARM64 passed their Go tests, and their test.bash failed only `[db712]`, from enhancement 8. b26 was skipped, since another session held it. The three probe checks passed there.
	- Acceptance signoff: Self-closed. The checks failed on a busy box before and pass after, and the twins are covered.
	- Closed: 20261004-182117

- Pushes and remote-only checkouts name a branch short, so a tag can break them
	- ID: 2026100411431800
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-114318
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- With a tag `origin/dev` and `dev` only on origin, check out `dev` through gitsby.
		- Or create a branch whose name a tag already has, and let gitsby publish it.
	- Incorrect behavior [Bug]: `git checkout -b dev --track origin/dev` fails with "ambiguous object name". `git push -u origin <name>` fails with "src refspec matches more than one". The release's `git push origin <tag>` fails the same way beside a branch of the tag's name.
	- Expected behavior [Bug]: These go by full ref. `--track refs/remotes/origin/<name>` and `push -u origin refs/heads/<name>` both set the upstream as usual.
	- Reproduced [Bug]: Yes for the checkout and the branch push, 2026-10-04, with plain git. The release tag push is read only.
	- Note: the plan prints these lines, so the fix changes what users see. `publishBranch` in mutate.go and `checkoutArgs` in branch.go.
	- Actual effort: Low
	- Done: The checkout names `refs/remotes/origin/<name>`. A new branch's first push is `git push -u origin HEAD`, like every other first push here, since it runs right after the checkout. The release pushes `git push origin tag <tag>`, and the "push it" hint says the same.
	- Note: Full refs in every printed line, or `HEAD` for the push, was a question. Chosen 2026-10-04: the full ref only where the line has no shorter safe form. Short names stay where git already resolves them right, such as the back-merge and the delete pushes, which print short and run full.
	- Verified: an old and a new build run side by side on a scratch repo. The old one fails all three cases, and the new one passes all three. test.bash 1412/0, parity 29/0, `cicd.bash --gate`.
	- Branch: fullrefs
	- Commit: a71263d
	- Test case: [ddgf3], [ddgf4], [ddgf5] and [ddgf6] in test.bash.
	- Acceptance signoff: Self-closed: the approach was left to the work, and the tests fail before and pass after.
	- Closed: 20261004-132519

- The dogfood check passes on the release target list too
	- ID: 2026100315501801
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: [ddf1b] looks for `"darwin/universal"` anywhere in config.bash. The release list has it now as well, so the check still passes if dogfood loses that target.
	- Expected behavior [Bug]: The check reads the dogfood target list only.
	- Reproduced [Bug]: Yes, 2026-10-04. With the entry taken out of `DOGFOOD_TARGETS` only, the old check still passed.
	- Origin: [ddf1b] from item 2026100312571262. The release list gained the entry in item 2026100313491873. Confirmed.
	- Estimated effort: Low
	- Actual cause [Bug]: The check grepped the whole file for the line, and `RELEASE_TARGETS` has the same line.
	- Actual fix [Bug]: The check sources config.bash and looks in `DOGFOOD_TARGETS` only.
	- Progress log:
		- Verified: on a copy of config.bash without the dogfood entry, the old check passes and the new one fails. The new one passes on the real file.
	- Swept: the other config.bash checks in test.bash. Each looks for a setting by its own name, and none reads an entry two lists share.
	- Branch: oldshcl
	- Commit: bc18a24
	- Test case: test.bash `[ddf1b]`.
	- Verified: test.bash 1408/0, `go test ./...`, fuzz.bash 301/0 and parity 29/0 on merged gover, 2026-10-04.
	- Acceptance signoff: Self-closed: reproduced, the check failed before and passes after.
	- Closed: 20261004-114742

- A tag named after origin's default branch breaks the default branch read
	- ID: 2026100411344972
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-113449
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- In a clone whose origin/HEAD points at `origin/main`, run `git tag origin/main`.
		- Run `gitsby status`, or any branch command.
	- Incorrect behavior [Bug]: The default branch reads as `remotes/origin/main`. Branch commands refuse, saying it exists neither here nor on origin.
	- Expected behavior [Bug]: The default branch is `main`.
	- Reproduced [Bug]: Yes, 2026-10-04, on the gover build and on branch spawncut.
	- Possible cause [Bug]: `symbolic-ref --short` spells the target the way git shortens it, longer where a tag shares the short name, and the code strips only `origin/`. Reading it without `--short` and stripping `refs/remotes/origin/` would not depend on tags.
	- Cause: Confirmed. origin/HEAD was read with `--short`, and only `origin/` was cut off. The unborn-repo fallback read HEAD the same way, so a tag named like the unborn branch gave `heads/<name>`.
	- Fixed: both read the full ref and cut `refs/remotes/origin/` or `refs/heads/`. A target outside origin falls through to the usual guesses.
	- Swept: `grep -n 'symbolic-ref\|--short\|abbrev-ref\|"origin/"\|refs/remotes' src-go/*.go`. `currentBranch` uses `branch --show-current`, which ignores tags. The branch list cuts full ref names. prune cuts full refs. The upstream's short name is left as git spells it on purpose, since the plan shows what runs. remote.go only tests origin/HEAD for empty. release.go and the back-merge build `origin/<name>` rather than reading it; the back-merge already merges by full ref. The release guard's short names are filed as 2026100411392800.
	- Verified: Go `TestDefaultBranchBesideSameNamedTag` fails on the gover build with `remotes/origin/main` and `heads/trunkish`, and passes after. The two test.bash checks, run by hand outside the suite, fail before and pass after. `go test -race`, `test-id.bash --check`, shellcheck, and spawn-count with no count up.
	- Branch: deftag
	- Commit: b4b0fc1
	- Test case: test.bash [ddgby] and [ddgbz]. Go `TestDefaultBranchBesideSameNamedTag` [ddgbx].
	- Verified: test.bash 1408/0, `go test ./...`, fuzz.bash 301/0 and parity 29/0 on merged gover, 2026-10-04.
	- Acceptance signoff: Self-closed: reproduced, the tests fail before and pass after.
	- Closed: 20261004-114742

- The release guard names branches short, so a tag can stand in for one
	- ID: 2026100411392800
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-113928
	- Opened by: jim-collier
	- Steps to reproduce [Bug]:
		- Tag something `main`, `dev` or `origin/main` in a repo with nothing new to release.
		- Run `gitsby release`.
	- Incorrect behavior [Bug]: The "nothing new" guard passes `main`, `origin/main` and `origin/dev` to `merge-base` and `describe`. git reads a tag of that name before the branch, so the guard can answer about the tag.
	- Expected behavior [Bug]: The guard reads the branches by full ref.
	- Reproduced [Bug]: Yes, 2026-10-04. With unreleased work on main, dev or origin/dev, and an old tag named `main` and `origin/main`, or `origin/dev`, or `dev`, a bare `release` said "Nothing new to release" and stopped.
	- Cause: Confirmed. The guard built short branch names, and git reads `refs/tags/<name>` before `refs/heads/<name>` and `refs/remotes/<name>`.
	- Fixed: the guard reads main, origin's main and dev by `refs/heads/...` and `refs/remotes/origin/...`. It runs nothing the plan prints, so the plan is unchanged.
	- Swept: `grep -n '"git",' src-go/*.go`, looking at merge, merge-base, describe, rev-parse, rev-list, log and diff. The release merges, the dev fast-forward and its ancestor check, the back-merge, `br merge`, the hotfix diff and `branchHasUnpushed` already use full refs. rev-parse, rev-list, log and show.go's diff use `HEAD`, `@{u}` or fixed names. The pull's `merge --ff-only` takes git's own short upstream name, which git already spells as `remotes/origin/<name>` when a tag shares `origin/<name>`, so it stays. Outside that list, pushes by branch name and the `--track origin/<name>` checkout break the same way; filed as 2026100411431800.
	- Verified: Go `TestReleaseGuardBesideSameNamedTags` fails in all three cases with the old release.go and passes after. `go test -race`, `go vet`, gofmt, `test-id.bash --check` and spawn-count with no count up. A bare `release` on a scratch repo still says "Nothing new" with nothing new, and cuts v1.0.1 with tags `main` and `origin/main` beside new work.
	- Branch: reltag
	- Commit: 3517631
	- Test case: Go `TestReleaseGuardBesideSameNamedTags` [ddgc1].
	- Closed: 20261004-114318
	- Acceptance signoff: Self-closed: reproduced, the test fails before the fix and passes after, and the sweep is answered.

- `[ddf5x]` counts git's origin/HEAD repair on git before 2.47
	- ID: 2026100409453281
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-094532
	- Opened by: jim-collier
	- Related IDs: 2026100312332924
	- Target OS: macOS
	- Incorrect behavior [Bug]: On b26, with Apple git 2.39.5, "and asks origin once" counts two asks.
	- Expected behavior [Bug]: The check counts the pull's asks only, on any git.
	- Reproduced [Bug]: Yes, 2026-10-04, in stage 7's run on b26, and by hand with the same fixture. A plain `git fetch` asks once there. With `git remote set-head origin main` run first the count is one.
	- Possible cause [Bug]: The fixture's clone has no origin/HEAD, since it was cloned before origin had a commit. On git before 2.47 the fetch doesn't write one, so `fetchRemote` repairs it with `git remote set-head --auto`, which asks origin again. That repair is by design. Setting origin/HEAD in the fixture first should fix the check.
	- Origin: `[ddf5x]`, from f61adb6 (2026-10-03, Code Review 20261003 enhancement 3). Never run on a git before 2.47. Confirmed.
	- Estimated effort: Low
	- Actual cause [Bug]: As above. The fixture's clone has no origin/HEAD, and on git before 2.47 gitsby's repair of it asks origin a second time.
	- Actual effort: Low
	- Progress log:
		- Verified: on b26, git 2.39.5, the old fixture counts two asks and the new one counts one.
		- Verified: on Linux, git 2.51, the old fixture with `followRemoteHEAD` set to never counts two, and the new one counts one.
		- Verified: stage 7 run alone passes on b26 and vm925w.
	- Actual fix [Bug]: The fixture sets origin/HEAD on the clone before counting. It also sets `followRemoteHEAD` to never, so newer git leaves the ref alone the way old git does, and the check reads the same on any version. The repair in gitsby is unchanged.
	- Swept: `[ddf5z]` counts on the same clone, so the same line covers it. No other check counts asks of origin.
	- Branch: remfix
	- Commit: 6842035
	- Test case: test.bash `[ddf5x]`.
	- Acceptance signoff: Self-closed: reproduced, and the check fails before and passes after on b26.
	- Closed: 20261004-103900

- `TestConfigLoadBackslashes` fails on Windows
	- ID: 2026100409453283
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-094532
	- Opened by: jim-collier
	- Related IDs: 2026100312332924
	- Target OS: Windows
	- Incorrect behavior [Bug]: On vm925w the test fails with "a doubled path rule names \"\", want w". The rule `/srv\work` is listed as not an absolute folder.
	- Expected behavior [Bug]: The test passes on Windows, as it does on Linux and macOS.
	- Reproduced [Bug]: Yes, 2026-10-04, in stage 7's run on vm925w.
	- Possible cause [Bug]: The fixture writes the rule as `/srv\\work`, which is not absolute on Windows, so it is ignored there, as designed. The folder it is matched against goes through `driveFolder` and the rule doesn't. Writing the rule from `driveFolder` too should fix it.
	- Origin: `TestConfigLoadBackslashes`, from ca0e55c (2026-09-24, the move to the shcl 3 beta). No stage ran the Go tests on Windows until stage 7. Confirmed.
	- Estimated effort: Low
	- Actual cause [Bug]: As above. `/srv\\work` is not absolute on Windows, so the rule is ignored there by design.
	- Actual effort: Low
	- Progress log:
		- Verified: on vm925w the old test fails with the same message, and the new one passes.
		- Verified: stage 7 run alone passes on b26 and vm925w, every Go test on both.
	- Actual fix [Bug]: The fixture writes the rule from `driveFolder`, so it is a drive path on Windows. The rule that ignores a folder that isn't absolute is unchanged.
	- Swept: the other Go tests with a `/`-rooted rule all pass on vm925w. None of them matches a folder against the rule.
	- Branch: remfix
	- Commit: 6842035
	- Test case: `TestConfigLoadBackslashes` `[dd2d9]`.
	- Acceptance signoff: Self-closed: reproduced, and the test fails before and passes after on vm925w.
	- Closed: 20261004-103900

- Code Review 20261003 item 5: The style guide says Bash 4.4 is enforced, and nothing checks
	- ID: 2026100313123908
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: style-guide.md says "the script refuses to run below" Bash 4.4. No live script checks the version. The check was in the frozen bash build.
	- Expected behavior [Bug]: Either the pipeline scripts check, or the guide says what's true.
	- Reproduced [Bug]: Yes. No `BASH_VERSINFO` outside legacy/.
	- Origin: style-guide.md from f735649 (2026-07-27), true for the bash build then. Confirmed.
	- Decisions:
		- The floor stays Bash 4.4, and the pipeline scripts check it (2026-10-03). b26, the Mac, has bash 5.
		- gfs-rotate.bash is a shared Bubbles file and is left alone (2026-10-03).
	- Actual cause [Bug]: The guide's sentence came over from the bash build, where gitsby itself checked. The pipeline scripts never did.
	- Estimated effort: Low
	- Actual fix [Bug]: Each of the 16 scripts in cicd/ that is run directly now checks the version as its first command. Below 4.4 it exits 1 with one line naming the version found and the macOS fix. The guide now says that, and names what has no check.
	- Note: install.bash has no check. It runs on stock macOS bash 3.2 by design, which its header and the guide both say, and what it installs needs no shell.
	- Note: n8git_backup-and-publish has no check either. It is a helper shared with other projects, like gfs-rotate.bash. config.bash and the two include files are only sourced.
	- Swept: every tracked bash file outside legacy/, through the same list the shell lint coverage check reads. The test fails a new script that lacks the check.
	- Verified: under a real bash 3.2.57 and 4.3.48 each of the 16 refuses with its line and exit 1, and under 4.4.23 none does. Under 3.2 on `gover` they ran on. The new checks fail 16 of 16 on `gover` and pass here.
	- Branch: lowfix
	- Commit: 29af32f
	- Test case: [ddf4h] in test.bash, one per script, runs a copy with the floor raised and expects the refusal and nothing else. [ddf4j] fails it if the list comes back empty.
	- Acceptance signoff: OK, 2026-10-03, n8git_backup-and-publish included.
	- Closed: 20261003-163955

- Code Review 20261003 item 7: Spawn reports do arithmetic on numbers read from files
	- ID: 2026100313123935
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: spawn-count.bash and spawn-report.bash read counts from tsv files and use them in arithmetic unchecked. That's the subscript-injection trap gfs-rotate was fixed for.
	- Expected behavior [Bug]: A count that isn't digits is refused.
	- Reproduced [Bug]: Yes, 2026-10-03. A recording whose count is `BASH_VERSINFO[$(touch ran)0]` ran the `touch` in spawn-report.bash, for the newest recording and for the one before it, and in spawn-count.bash for the baseline. The scripts write those files themselves, so the risk is low. An unset name such as `x[...]` stops at `set -u` first and runs nothing.
	- Origin: spawn-count.bash:143 from 894d857 (2026-08-19). Same class as the 2026-09-15 gfs-rotate fix. Plausible when filed, confirmed since.
	- Sweep: every live script that reads a number from a file and does arithmetic on it, gfs-rotate.bash excepted.
	- Actual cause [Bug]: The count was used in `(( ))` straight from the file.
	- Estimated effort: Low
	- Actual fix [Bug]: Both scripts check that a count read from a recording is digits before any arithmetic. Anything else exits 1 naming the file, the command and the value. spawn-report.bash's header lists the new exit code.
	- Swept: spawn-count.bash's baseline, and spawn-report.bash's newest and previous recordings, are the only file values that reach arithmetic. The rest read only numbers made by a command: `grep -c`, `wc -c`, `od`, `stat`, `git rev-list --count`, `git log` dates, awk line numbers in release.bash, and the footer dates release.bash cuts down to digits. test-id.bash already checks its value. release.bash's patch bump on a `v*` tag name and keep-build.bash's build number were left alone at first, since a tag can't hold `[` and the number is typed on the script's own command line. Both check for digits since 2026-10-03, after signoff: a tag such as `v1.3.0rc1` stopped the bump with a bare bash error, `v1.3.08` read as octal, and a crafted build number did run a command.
	- Verified: the three new checks fail on `gover`, where the `touch` ran each time, and pass here with nothing run.
	- Branch: lowfix
	- Commit: 8d4cd6c
	- Test case: [ddf4m] and [ddf4n] for spawn-report.bash, [ddf4p] for spawn-count.bash, in test.bash. The last needs strace, like the other spawn-count checks. [ddf84] and [ddf85] for the patch bump, [ddf86] and [ddf87] for keep-build.bash. All but [ddf86], which checks the plain case, fail against the scripts before.
	- Acceptance signoff: OK, 2026-10-03.
	- Closed: 20261003-163955

- Code Review 20261003 item 6: Doc comments sit on the wrong function or name an old one
	- ID: 2026100313123922
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Incorrect behavior [Bug]:
		- In accountcmd.go, `accountNames`' comment sits above `anyHostStated`, and `accountNames` has none.
		- `resolveConfigFile`'s comment calls it `configFile`. `isGitHubHost`'s calls it `githubHosts`.
	- Expected behavior [Bug]: Each comment is on its function and starts with its name.
	- Reproduced [Bug]: Yes, by reading.
	- Origin: a function added between a comment and its target, and two renames that left the comment behind. Confirmed.
	- Actual cause [Bug]: As the origin says.
	- Estimated effort: Low
	- Actual fix [Bug]: `accountNames`' comment moved onto it. The other two now start with the function's own name.
	- Swept: all 514 doc comments on top-level declarations in src-go. No other one names a different function or an old one. 17 outside the tests open with prose, such as "The byte-order mark ..." on `utf8BOM`, and name nothing; they were left as they are. Most test functions open the same way, with the case they cover.
	- Verified: the new test fails on the three comments on `gover` and passes here. `go test ./...` passes.
	- Branch: lowfix
	- Commit: 95acb6e
	- Test case: TestDocCommentsNameWhatTheySitOn. A doc comment that opens with a camelCase word has to name what it sits on, and none may hold a second comment headed by another function's name.
	- Acceptance signoff: Self-closed: mechanical.
	- Closed: 20261003-143901

- Code Review 20261003 item 8: The Origin gate doesn't read new-format items
	- ID: 2026100313150825
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: backlog-check.bash looks for review items in the old format only. With this round's items filed it reports "0 listed", so an item with no `Origin:` row would pass.
	- Expected behavior [Bug]: It finds open review items in both formats.
	- Reproduced [Bug]: Yes, 2026-10-03.
	- Origin: backlog-check.bash from the 2026-09-10 rules, before the new item format. Confirmed.
	- Actual cause [Bug]: It matched only a tab-indented title with a status emoji, and took its Origin row at two tabs.
	- Estimated effort: Low
	- Actual fix [Bug]: It reads both formats. A new-format review item is a top-level title starting "Code Review", open unless its Status row says Done, Canceled, Moot or Deferred. The old emoji stand for three of those, and Moot is new. Its Origin row sits one tab in. The old format also takes a round with a letter after the date, such as 20260819d, which it missed before. All of those are closed.
	- Swept: backlog-check.bash is the only script that reads review items out of the backlog.
	- Verified: on a copy of this backlog with item 8's Origin row taken out, the gate on `gover` said "0 listed" and passed. Here it names item 8 and exits 1, and on the real backlog it lists 14 open items. The two new checks fail on `gover` and pass here.
	- Branch: lowfix
	- Commit: aacb723
	- Test case: [ddf4q] and [ddf4r] in test.bash.
	- Acceptance signoff: Self-closed: the intent was clear, and its tests fail before and pass after.
	- Closed: 20261003-145130

- A full run's container has no name or label, so a stop can't tell it from another project's
	- ID: 2026102307533128
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261023-075331
	- Opened by: jim-collier
	- Requirements [Feature]:
		- The `docker run` in cicd.bash gives its container a name or label that carries the run, such as the start time, so the run can be found and stopped by it alone.
	- Progress log:
		- 2026-10-23: The round's full run got docker's generated names (`inspiring_kepler`, `frosty_sutherland`), next to other projects' containers on the same box.
		- 2026-10-23: The container is named `gitsby-cicd-<start time>-<pid>`, with the same start time as the run's log, and labeled `gitsby.cicd.run=<start time>` and `gitsby.cicd.tree=<repo root>`. The run prints the name under the "runs cicd.bash" line. contributing.md says so.
	- Decisions:
		- Both a name and labels. The name is what `docker stop` takes, and the tree label tells apart two worktrees' runs.
		- The pid is in the name, since two runs started in the same second would otherwise clash on it and the second would fail to start.
	- Branch: round-20261023d
	- Test case: test.bash `[debj1]`.
	- Verified: 2026-10-23, test.bash 1676 -> 1677, 0 failed. With the change taken out, `[debj1]` fails and the other 1676 pass. A real docker took the name and labels, `docker ps --filter label=gitsby.cicd.run=<start time>` found the container, and `docker stop` by name stopped it. `cicd.bash --gate` and shellcheck pass.
	- Swept: cicd.bash has one `docker run`. The other docker calls build, inspect and remove images, and start no container.
	- Acceptance signoff: Self-closed: its own test passed.
	- Closed: 20261023-195210

- The workflow YAML check `[dea4c]` skips in the container and on most boxes
	- ID: 2026102220133673
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261022-201336
	- Opened by: jim-collier
	- Related IDs: 2026102218410000
	- Requirements [Feature]:
		- Add PyYAML to `cicd/container/requirements.txt` so `[dea4c]` runs in the container, and name the test ID in its skip line.
	- Progress log:
		- 2026-10-22: Found by the round's test batch. The check ran only on vmDebARM64 and on b23 outside the container.
		- 2026-10-23: PyYAML 6.0.3 is in the image's lock, on the system python beside Pillow, and the image build fails if it doesn't import. No known advisory against it. The skip line names `[dea4c]`.
		- 2026-10-23: `[de5av]` failed everywhere on the Dockerfile's new lines. It now runs the image's own split patterns over the lock, and the new `[deavy]` holds PyYAML to the same. Both fail on the old lines and on a mutated Dockerfile, and pass now. test.bash 1667 -> 1668, 0 failed on b23.
	- Decisions:
		- No `VER_PyYAML` and no `TOOL_VERSIONS` entry. Its version changes no result, only whether the check runs, and the lock's hash pins it already.
		- Not in `PY_AUDIT_DISTS`, which lists what the demo imports. A box without PyYAML would skip all of pip-audit.
	- Verified: 2026-10-23, the image `gitsby-cicd:e6176a22793a` builds. In it `python3 -I -c 'import yaml'` succeeds, `[dea4c]`'s check passes against the repo mounted read-only and fails on a broken workflow, and pip-audit finds nothing for `pyyaml==6.0.3`.
	- Verified: 2026-10-23, the round's full run in the container on `gitsby-cicd:e6176a22793a`. `[dea4c]` ran and passed there. test.bash was 1666 of 1667, 7 more than on 10-22: the round's 6 new checks and `[dea4c]`, which skipped there before. pip-audit, fuzz 313/0, parity 29/0, CodeQL and the gif passed too. Log: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261023-07353000/run.log`, and `run2.log` beside it for the later stages.
	- Verified: 2026-10-23, test.bash in the container on `gitsby-cicd:e6176a22793a`, 1668/0, with `[dea4c]`, `[de5av]` and `[deavy]` passing. The macOS workflow, run 39974608816, was 1419/0 on both runners, `[de5av]` and `[deavy]` included. Log: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261023-08013000/run.log`.
	- Test case: `[dea4c]` itself, `[deavy]` and `[de5av]` for the image's lines, and the import check in the image build.
	- Swept: test.bash's other `skip:` lines each stand for a group of checks, and their libraries (Pillow, python3, strace, pwsh) are in the image already.
	- Acceptance signoff: Self-closed: `[dea4c]` runs in the container now, and the checks on the image fail on the old lines and pass after.
	- Closed: 20261023-081155

- Check the demo's Pillow and fontTools advisories against Debian's fixes
	- ID: 2026101905585018
	- Type: Task
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261019-055850
	- Opened by: jim-collier
	- Related IDs: 2026101816064794
	- Requirements [Feature]:
		- pip-audit reports 17 advisories against Pillow 11.1.0 and 1 against fontTools 4.57.0. The image has Debian's builds, `11.1.0-5+deb13u4` and `4.57.0-1+deb13u1`, which carry security patches past those versions.
		- Check each against Debian's security tracker. The ones Debian fixed stay on `PIP_AUDIT_IGNORE` in config.bash, with a note naming the fix. For the rest, move the demo to a Pillow and fontTools that fix them.
		- A newer Pillow can change the demo gif's bytes, so the gif is rendered and compared again.
	- Note: The demo draws only its own text, in its own fonts, so none of these reach it through outside input today.
	- Note: Debian's Pillow fixes stopped mattering once the image had the upstream 12.3.0 in place of Debian's build, so those 6 entries came off the list with the other 11.
	- Progress log:
		- 2026-10-19: Checked all 18 against Debian's tracker and the changelogs of the installed builds. 7 are fixed or don't apply: fontTools' one, fixed in `4.57.0-1+deb13u1`, and 6 of Pillow's, fixed in `deb13u1` to `deb13u4` or Windows-only. Each now has a note on `PIP_AUDIT_IGNORE`.
		- 11 Pillow advisories have no trixie fix. Debian marks most "no-dsa, minor issue", and all are fixed upstream in 12.3.0 and in sid's `12.3.0-1`. They're CVE-2026-54058, 54059, 54060, 55379, 55380, 59197, 59198, 59199, 59200, 59204, and 59205. They cover file formats and calls the demo doesn't use, plus paste and crop with coordinates near 2^31, where the demo passes only its own small ones.
		- Moving only Pillow fixes them all, since fontTools is already fixed. That means Pillow 12.3.0 in the image, either as a hash-pinned wheel or as sid's package from the snapshot archive. The wheel brings its own FreeType, so the glyphs may change. Either way the gif gets rendered and compared again, the image's Pillow version pin changes, and a render on the host would no longer match the image's. The renderer also calls one private Pillow method, which 12.x may have changed.
		- Question: should Pillow move to 12.3.0 now, and if so as a wheel or as sid's package? Or should it stay on Debian's build, with the 11 kept on the list until trixie fixes them?
			- Answer (2026-10-19): "Can it be updated in a container? Otherwise OK to upgrade it."
		- 2026-10-19: The image's Pillow is 12.3.0, the hash-pinned wheel from the container's lock, on the system python in place of Debian's. The wheel is cleaner than sid's package, which needs a newer libavif than trixie has, and that pulls in 4 more sid libraries.
		- 2026-10-19: All 17 Pillow entries came off `PIP_AUDIT_IGNORE`. fontTools' one is left, and it's the only advisory pip-audit finds with no list at all.
		- 2026-10-19: The demo gif renders byte for byte the same on 12.3.0, so it didn't change. The renderer's private `Image.Image()._new` call still works there.
		- 2026-10-19: A `--no-container` run on b23, with Debian's 11.1.0, warns about Pillow's version in the lint stage, as before, and its render matches too. A render that differs where Pillow or gifsicle isn't at its recorded version is now a warning, and the committed gif stays.
	- Branch: pyadv, pyfix
	- Commit: 203dca3
	- Test case: test.bash [de5av] for the lock's Pillow and no Debian one, [de5aw] for a demo drawn with another Pillow, and pip-audit's [de54e] and [de54k]. The image build also stops on a Pillow other than the recorded one.
	- Verified: pip-audit in the image passes, and finds only fontTools' advisory with no list. The demo renders the same bytes in the new image and on b23. [de5av] and [de5aw] fail against gover's tree. test.bash 1561 -> 1571, 0 failed, and `cicd.bash --gate` passes.
	- Note: [de54e] wanted at least 2 entries on the list, so its pattern takes any number now, with the same ID.
	- Swept: `TOOL_VERSIONS`, the Dockerfile's Pillow check and apt list, the snapshot comment that named Pillow, the lock's header, and contributing.md's demo prerequisite.
	- Acceptance signoff: Signed off by jim-collier in conversation, 2026-10-19.
	- Closed: 20261019-094958

- Run CodeQL over the demo script and its Python libraries
	- ID: 2026101907065426
	- Type: Enhancement
	- Status: Done
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261019-070654
	- Opened by: jim-collier
	- Related IDs: 2026101816064794
	- Requirements [Feature]:
		- `--leakcheck` runs CodeQL's Python queries over the pipeline's Python files, with the sdists of Pillow, fontTools, pycairo and PyGObject unpacked into the database's root, at the versions the image has.
			- Changed 2026-10-19: the libraries' installed source, as the image has it, in place of the sdists.
		- The same rules as the Go run: style findings in third-party code are dropped, and any other finding fails the run.
			- Changed 2026-10-19: in third-party Python only findings tagged security count. Our own Python is held to the whole suite.
		- The Python bundle is pinned in config.bash and installed in the image, like the Go one.
	- Note: Split from 2026101816064794, which covers the Go code.
	- Progress log:
		- 2026-10-19: A trial run, outside the pipeline, of CodeQL 2.27.2's Python security and quality suite over the 2 pipeline scripts and the 4 libraries. Our own 2 scripts have no findings. The libraries have 648, and 331 of them aren't style by the Go rule. That's 116 in Pillow, 187 in fontTools, and 28 in PyGObject. Too many to set aside one by one, so nothing is built yet.
		- Most of the 331 are tagged reliability only, such as cyclic imports and empty except blocks. Python's quality queries tag nearly everything reliability or maintainability, so the Go rule keeps far more here than it does for Go.
		- Limiting the libraries to the modules the demo's library calls load still leaves 133.
		- Only 2 are tagged security, both a regex character range in fontTools' XML module, which the demo doesn't load.
		- Library code would be the installed Debian builds' own .py files, taken through dpkg, instead of the upstream sdists. They're what the demo runs, with Debian's security patches in, and have no test suites. Their compiled C parts are out of reach of the Python extractor either way.
		- The Python bundle shares every common file with the Go one, byte for byte, so it adds about 66 MB to the image, without its example queries. The trial took 12 s to build the database and 37 s to analyze.
		- Proposal: in third-party Python, count only findings tagged security, and keep the Go rule for Go. The one regex finding goes on `CODEQL_IGNORE` as not reachable. Our own scripts stay held to the whole suite.
		- Question: OK to hold third-party Python to security findings only? The other way is to keep the Go rule and put 185 rule and file pairs on `CODEQL_IGNORE`, or 59 with only the modules the demo loads.
			- Answer (2026-10-19): the proposal is accepted.
		- 2026-10-19: Built. `--leakcheck` runs CodeQL's Python security and quality suite once, over a scratch copy with the pipeline's Python files and, under vendor/, the installed source of the 4 libraries. Pillow's file list comes from its wheel, and the Debian builds' from dpkg.
		- 2026-10-19: codeql-findings.py tells a report's language from the files it extracted, and still holds all the rules. A Python report has to have taken in our files and vendor/.
		- 2026-10-19: The image untars the Python bundle over the Go one, without its examples, checked against its own sum in config.bash.
		- 2026-10-19: The fontTools regex finding still shows against what the image installs, so it's on `CODEQL_IGNORE` as not reachable.
	- Branch: pyql, pyfix
	- Commit: 203dca3
	- Test case: test.bash [de5ap] for the run, [de5am] and [de5an] for the bundle, and [de5aq], [de5ar], [de5as] and [de5at] for how a Python report is read. [de55e] follows the new OK line and report list.
	- Verified: A `--leakcheck` run in the image is clean. It took in 437 Python files, our 2 among them, and the fontTools finding is the only security one in third-party code. A planted `py/empty-except` and `py/comparison-of-identical-expressions` in codeql-findings.py failed it, and after a restore by copy it passes. The new checks fail against gover's tree, and [de5at] and [de5ar] against broken copies of codeql-findings.py. test.bash 1561 -> 1571, 0 failed, and `cicd.bash --gate` passes.
	- Swept: the `--leakcheck` help line and plan line, config.bash's CodeQL comments, the Dockerfile's, codeql-findings.py's header, README and contributing.md.
	- Acceptance signoff: Signed off by jim-collier in conversation, 2026-10-19.
	- Closed: 20261019-094958

- Run on the last Core 2 Duo, and AMD CPUs from that era.
	- ID: 2026101301161852
	- Type: Enhancement
	- Status: Done
	- Needs external testing: Yes, on an old CPU or an emulated one.
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261013-011618
	- Opened by: JC
	- Target OS: Linux, Windows and FreeBSD on x86_64, where this project builds them. Macs that old can't run a current macOS anyway.
	- Requirements [Feature]:
		- Release builds run on the last Core 2 Duo (Penryn, 2008), and on AMD Phenom II and Athlon II, if that's reasonably doable.
			- Penryn has SSSE3 and SSE4.1 but no POPCNT. The AMD ones have POPCNT but no SSSE3. So the shared floor is plain x86-64, also called x86-64-v1.
		- If that isn't doable, the floor is the first Core i3/i5/i7 (Nehalem, 2008), which is x86-64-v2. AMD's first chip at that level is Bulldozer, 2011.
		- Faster code for newer CPUs is still fine, but it's picked at run time by a CPU feature test, never by the build target.
		- Tests run the release build on an emulated Penryn and Phenom II, through Intel SDE or QEMU's `-cpu Penryn` and `-cpu phenom`.
	- Progress log:
		- 20261013: Go builds for plain x86-64 by default (`GOAMD64=v1`), and nothing here sets it, so this may already hold. Pin `GOAMD64=v1` in the release build so a stray environment can't raise it. The standard library already picks faster code at run time.
		- 20261019: Every build pins `GOAMD64=v1` now: release, dogfood and cross builds, the native and demo builds, the remote test builds, and the README's rebuild line. It's Go's default, so the published bytes don't change. The module has no assembly or cgo of its own, and neither does shcl.
	- Decisions:
		- The emulated run was a one-off, and stays out of the pipeline. The pin is what can regress, and the suite watches it. Go's own startup check refuses a CPU below the level a build was made for, so the pin decides which CPUs run it. The CPU emulator would add about 450 MB to the container image to recheck that each run. Revisit if a dependency with its own assembly comes in.
	- Verified:
		- The linux/amd64 release build runs on an emulated Penryn and Phenom II: `--version`, `--help`, `status`, `whoami`, `br list`, `sync` to a local origin, and `br create`. Builds for v2 and v3 are refused on both, and the v3 build runs on an emulated CPU that has v3.
		- Every release target builds to the same bytes with the pin as without it. A `GOAMD64=v3` in the environment, or in `go env -w`, changes the amd64 bytes of an unpinned build and not of a pinned one.
	- Swept: `cicd.bash` (native build, `fCrossBuild` for dogfood and stage 7's Mac build, demo build), `release.bash` `fpCrossBuild` (phases 1 and 3), `remote-tests.bash` `fBuildTests`, README's rebuild line. The container image builds no gitsby binary, only tools, and its stages run the cicd.bash sites above. Windows, FreeBSD and the Mac amd64 half get the same pin through those sites.
	- Branch: oldcpu
	- Test case: [de56v] in test.bash. It fails with the pin dropped from any one build site or from the README.
	- Acceptance signoff: Self-closed: the intent was clear, and the pin changes no published bytes.
	- Closed: 20261019-072414

- Builds between releases show their date after the build number
	- ID: 2026102317400737
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. test.bash ran it.
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261023-174007
	- Opened by: jim-collier
	- Requirements [Feature]:
		- For non-release builds, include " (YYYY-mm-DD)" after the build number.
	- Progress log:
		- 2026-10-23: Done. `gitsby v3.0.0-beta.1-4-ga12019f build dbsh4 (2026-10-23)`. A release build reads as before.
		- 2026-10-23: The date was UTC at first, so an evening build here read as the next day. Changed to local, as answered.
	- Decisions:
		- The date is the commit's, from the same stamp as the build number, so a rebuild still matches its checksum. It's shown in the local time zone of whoever views the version (answer 2026-10-23), so 2 boxes can show one build a day apart.
		- A release build is one whose version is a tag's own, such as 2.1.0 or 3.0.0-beta.1. A version with git describe's `-N-g<hash>` or `-dirty` after it, a bare hash, or 0.0.0 gets the date.
		- An unstamped build has no build number, so no date either.
		- The demo is built at a tag's version, so its gif doesn't change.
	- Branch: round-20261023c
	- Test case: test.bash `[debe8]`. Go `[debe5]`.
	- Verified: 2026-10-23, `[debe5]` fails with every version taken as a release, and with the date in UTC. Release.bash reads the build line only from release builds, which have no date.
	- Closed: 20261023-180940

- gitsby refuses to run under the name of a tool `raw` runs
	- ID: 2026102306584132
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. test.bash ran it.
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261023-065841
	- Opened by: jim-collier
	- Related IDs: 2026101916533300, 2026102306584122
	- Requirements [Feature]:
		- It should error if gitsby is linked to, or renamed, any name that can be reached through `gitsby raw XYZ`.
	- Progress log:
		- 2026-10-23: From testing the b28l loop. tukzedo wanted every bare `gh` to go through gitsby, and wrote a wrapper script for it. First asked whether a link named `gh` should act as `raw gh`. Answered no: refuse instead.
		- 2026-10-23: Done. gitsby checks its own name before anything else and refuses as git, gh, tea, tea-cli, glab, lazygit or tig, with or without `.exe`, in any case. The error says to run `gitsby raw <name>`.
	- Decisions:
		- Every other name still runs. Release files are named like `gitsby-linux-amd64`, and a copy under some other name can't do anything `gitsby` can't.
	- Branch: round-20261023c
	- Test case: test.bash `[debe7]`, a link under each of the 7 names. Go `[debe6]`.
	- Verified: 2026-10-23, `[debe6]` fails 27 ways with the check stubbed out. A bare `gh` through a link answered "Unknown command 'auth'" before.
	- Swept: the names come from `rawTools` plus `tea-cli`, the same list `raw` takes. design.md and the changelog updated.
	- Closed: 20261023-174007

- Code Review 20261005 enhancement 1: Step lines print their arguments unquoted
	- ID: 2026100516202730
	- Type: Enhancement
	- Status: Done
	- Priority|Severity [Feature]: Low
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Requirements [Feature]:
		- A step line quotes an argument the way the plan does. The plan shows `git commit -m "two words; here"`, and the step shows `[ git commit -m two words; here ... ]`. Pasted into a shell, the step line runs `here` as a command.
		- The failure line, `gitsby: '...' failed`, quotes the same way.
	- Origin: `step` in exec.go, from the port. 2.x printed `$*` the same way.
	- Note: parity.bash compares this output with 2.x, so the change needs its carve-out there.
	- Done: Step lines quote an argument that needs it, and quote a `-m` value the way the plan does. The plan's commit message and `pr create` title go through the same quoting, so a message with `"` or `$` in it now shows in single quotes there too. The demo's `sync` step line gains its quotes, so the gif changes at the next full run.
	- Note: parity.bash needed no carve-out. It passed 29 of 29.
	- Branch: docfix
	- Commit: 2206206
	- Test case: [ddj3g] in test.bash, a plan line and its step line must match for `-m 'two words; here'`, red on `gover` and green here. [ddj3f] TestShellWord has a shell read 10 awkward values back unchanged.
	- Acceptance signoff: Self-closed 2026-10-06. Tested, and it follows the plan and the README with no open choice left.
	- Closed: 20261005-172300

- Code Review 20261005 enhancement 2: The help leaves out what the README shows
	- ID: 2026100516202767
	- Type: Enhancement
	- Status: Done
	- Priority|Severity [Feature]: Low
	- Opened: 2026-10-05
	- Opened by: jim-collier
	- Requirements [Feature]:
		- `--yes` is taken but not listed. The help shows `-q, --quiet, -y`.
		- `repo connect [url]`, where it also takes `owner/name`. The README shows `[target]`.
		- `account set` and `account unset` show no arguments. The README shows `<a> <k> <v>` and `<a> <k>`.
	- Origin: help.go, various. No round saw it.
	- Done: The help lists `--yes`, says `repo connect` takes a URL or `owner/name`, and starts the `account set` and `account unset` lines with their arguments.
	- Branch: docfix
	- Commit: 2206206
	- Test case: [ddj3h] in test.bash, help lists `--yes`. Red on `gover`, green here. [ddk4f], [ddk4g] and [ddk4h] check the `repo connect`, `account set` and `account unset` lines, each red against the help before it.
	- Acceptance signoff: Self-closed 2026-10-06. Tested, and the help now matches the README with no open choice left.
	- Closed: 20261005-172300

- `assets/logo.png` is 512x512 and 254 KB for a 128 px README image
	- ID: 2026100519502150
	- Type: Enhancement
	- Status: Done
	- Priority|Severity [Feature]: Low
	- Opened: 20261005-195021
	- Opened by: jim-collier
	- Note: It is also what `gen-winres.bash --icon` reads for `assets/gitsby.ico`, whose largest size is 256.
	- Progress log:
		- 2026-10-05: Scaled to 256x256 RGBA, 84 KB. `gitsby.ico` is left as made from the 512 px original.
		- 2026-10-06: Put back to 512 px, and the README shows it at 512.
	- Decisions:
		- Keep 512 px and show it at full size. It is a cool logo.
	- Swept: README width 128, `gen-winres.bash` (largest size 256), design.md, changelog.md, trademark.md and the backlog's `.ico` note. None state the logo's size or need 512 px.
	- Branch: logo, logo512
	- Commit: ec2564a
	- Test case: None, asset only.
	- Acceptance signoff: jim-collier 2026-10-06
	- Closed: 20261006-072500

- The plan shows `@{u}` where it could name the branch
	- ID: 2026100316463300
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Related IDs: 2026100313124002
	- Requirements  [Feature]:
		- The pull step's plan line names the upstream, such as `git merge --ff-only --autostash origin/feature`, rather than `@{u}`.
		- The step runs with that same name, so the plan still shows exactly what runs.
	- Decisions:
		- The resolved name over `@{u}` (2026-10-03). It reads plainly and says which remote branch comes in.
	- Notes:
		- The plan already reads each branch's upstream with one `for-each-ref`, so this needs no new git call. The spawn-count limits will show if it does.
	- Actual effort: Low
	- Done: The pull step names the upstream the way git shortens it, such as `origin/feature`, in the plan and in the step that runs. For the current branch one `rev-parse` gives both the full and the short name. For the others, the one branch read gives them.
	- Done: A branch the run will check out from origin names origin's copy. Where a tag also answers to the short name, git spells it out further, as `remotes/origin/feature`, and that is what shows and runs. A local upstream whose name starts with a dash goes by its full ref, so git can't read it as an option.
	- Done: A branch with no upstream still shows `@{u}`. Its step is skipped, so there is nothing to name.
	- Done: design.md has the rule, the plan example in style-guide_ui-ux.md shows the name, and parity's mapping of the pull line names it too.
	- Note: No spawn count changed. The same calls ask for one more field each.
	- Note: [dafrs] and [ddf5v] matched `@{u}` and now match the name. What each checks is unchanged.
	- Note: A tag named after origin's default branch breaks the default branch read. That was there before this item and is filed as 2026100411344972.
	- Swept: `grep -n '@{u}' src-go/*.go`. Both runners and every plan line go through `pullArgsFor`. The other `@{u}` uses are reads, such as ahead and behind and the incoming list, not steps the plan shows.
	- Verified: test.bash 1406/0, parity 29/0, `go test -race`, and `cicd.bash --gate`. On the build before this item, [ddf5v], [ddgbf], [ddgbg] and [ddgbh] fail. [ddgbj] passes there too, since the old plan and step both said `@{u}`. With the step handed a different name than the plan, it fails.
	- Branch: spawncut
	- Commit: 7979ffb
	- Test case: test.bash [ddgbf], [ddgbg], [ddgbh], [ddgbj] and [ddgbk]. Go `TestPullArgsFor` [ddf65] and `TestUpstreamNames` [ddgbe].
	- Acceptance signoff: Self-closed: the rule was set by hand on 2026-10-03, and the checks fail before and pass after.
	- Closed: 20261005-072140

- Code Review 20261003 enhancement 7: Go code tidy
	- ID: 2026100313130047
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- `cmdPrune` gets branch names back out of git's argv by index math. Have `leaseDeleteBatches` return them.
		- The account ssh command, the exclusive-create writer and the push-or-set-upstream args are each built in two or three places. Make one of each.
		- `ghState` also keeps the tea and reachability state. Rename it, and read reachability through `isOffline()` everywhere.
		- The flat-line parse is written three times, and `[2]string` keys stand in for a named type.
		- `contains` beside `slices.Contains`, a BOM literal beside `utf8BOM`, a GOOS test beside `isWindows()`.
	- Origin: mostly the work since 20260909: shcl, prune leases, tea support. Confirmed by grep.
	- Actual effort: Low
	- Done: Each delete batch comes back with the branches it deletes, and `pruneRemote` reads them from there. The prune gate and its leases are unchanged.
	- Done: `sshKeyCommand`, `createNew` and `pushArgs` are the one of each. `createNew` takes over from `createAccountsFile`, the conversion's `writeNew`, and the lock's own open. The lock keeps its random token.
	- Done: `ghState` is now `remoteState`, kept on the run as `remote`. Reachability is an `offline` flag, so the zero value is online, and every reader goes through `isOffline()`.
	- Done: The old layout is split into lines once, by `flatLines`, for the load, the conversion and its look ahead. `acctKey` names the account and field pair in both layouts.
	- Done: `contains` is gone for `slices.Contains`, the load trims `utf8BOM`, and the lock's Windows test calls `isWindows()`.
	- Note: The lock file is now synced before it is closed, as the other two creates already were.
	- Note: Two Go tests follow the new names without changing what they check. `TestLeaseDeleteBatches` now also checks the branch names each batch hands back. `TestCreateAccountsFileNeverReplaces` calls `createNew`.
	- Note: Left alone: `publishBranch` and `repo connect`'s add case always push with `-u`, so they don't ask about an upstream. The plan's push lines are display text. Every other `runtime.GOOS` passes the platform to a function so tests can set it.
	- Swept: `grep -n 'IdentitiesOnly\|O_EXCL\|"-u", "origin"\|\.gh\.\|reachable\|\[2\]string\|contains(\|\\ufeff\|runtime.GOOS' src-go/*.go`.
	- Verified: `go test -race ./...`, `go vet` for linux, windows, darwin and freebsd on amd64 and arm64, `cicd.bash --gate`, and spawn-count with every count the same as before. The git, gh and ssh command lines that spawn-count's runs start are the same before and after.
	- Verified: the old and new flat readers and converters agree over about 3.3 million fuzzed inputs.
	- Branch: gotidy
	- Commit: 0114261, 38cc756, cc2c638, 2da34ed, 9580110
	- Test case: The existing suites cover it, since nothing should change. Run: the Go tests and spawn-count. Still to run: test.bash, fuzz.bash and parity.bash.
	- Verified: the 2026-10-04 test batch. test.bash on b23 passed 1452 and failed 1, which is 1412 plus this round's 41 new checks. The one failure is `[db712]`, from enhancement 8.
	- Verified: fuzz.bash 301/0, parity.bash and the spawn counts all pass on gover 2026-10-04.
	- Verified: stage 7 on 2026-10-04. vm925w passed its Go tests. vmFreeBSD and vmDebARM64 passed their Go tests, and their test.bash failed only `[db712]`, from enhancement 8. b26 was skipped, since another session held it.
	- Verified: a full pipeline run on 2026-10-05 passed on every box.
	- Acceptance signoff: OK, 2026-10-05, after the full run.
	- Closed: 20261005-071114

- Code Review 20261003 enhancement 6: Spawns that are repeated or not needed
	- ID: 2026100313124028
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Prereq IDs: 2026100313123975
	- Requirements  [Feature]:
		- `convertibleToHTTPS` asks `gh` for the protocol before a free text test that already says no on an https origin.
		- Two `rev-parse` calls at startup where one would do.
		- The `gitsby.ghTokenFile` lookup runs when the account's own file already gave a token, and runs twice.
		- `origin/HEAD` is read twice after a fetch.
		- Lists start `tput cols` where the ioctl in tty_linux.go would do.
	- Origin: remote.go:320 from 4918b5b (2026-08-19), the rest from the port. Each saves 1 or 2 spawns. Confirmed with strace.
	- Actual effort: Avg
	- Done: `convertibleToHTTPS` does its text tests before asking gh for the protocol, so an https origin asks gh nothing.
	- Done: The startup `rev-parse` also asks for the top level, which settles the folder accounts match against. Outside a work tree git refuses that part after printing the other three answers, so the output is read whatever the exit code. Outside a repo the folder is the working directory, as before.
	- Done: The `gitsby.ghTokenFile` lookup runs only when the account's own token file gave nothing, and then once a run. The account's file comes first in the lookup, so the answer can't change.
	- Done: The fetch's check of origin/HEAD keeps its answer, and the default branch reads it from there.
	- Done: Lists take the width from the kernel on Linux, macOS and the BSDs. tput answers where the kernel says 0, and on Windows.
	- Note: spawn-count's pty runs now get a size, as a real terminal has. An unsized pty reads as width 0, which sends gitsby to tput.
	- Note: Spawn counts, before -> after: status 12 -> 11, whoami 8 -> 7, br list 8 -> 7, account list 8 -> 7, repo url 7 -> 6, pullcom 22 -> 21, pullcom with a fetch 30 -> 28, br switch 27 -> 26, br prune 32 -> 31, status with a fetch 20 -> 17, status in an account folder 23 -> 19, whoami there 18 -> 15, account list with accounts 13 -> 11, status in the https folder 19 -> 15. The expected counts in spawn-count.bash went down to match.
	- Note: design.md says the `gitsby.ghAccount` and `gitsby.ghTokenFile` git-config keys "still win". For the token file, the code has read the account's own file first since the port. That order is unchanged here. v2.1.0 read them in that order too, so design.md was changed to match on 2026-10-04. The accounts file is where an account is set up and what `account list` shows, so a stale global key should not override it.
	- Swept: `grep -n '"tput"\|show-toplevel\|symbolic-ref\|configOwnScope(\|preferredProtocol()' src-go/*.go`. The one `tput`, both `--show-toplevel` reads, the origin/HEAD read (the other `symbolic-ref` reads HEAD for an unborn branch), the one `configOwnScope` caller, and the `preferredProtocol` caller in `convertibleToHTTPS`.
	- Verified: test.bash 1406/0, parity 29/0, `go test -race`, `cicd.bash --gate`, spawn-count, and builds for linux, windows and darwin on amd64 and arm64, plus freebsd. Each of the five new Go tests fails on the build before this item and passes after.
	- Branch: spawncut
	- Commit: 12752d0
	- Test case: Go `TestConvertibleAsksGhOnlyForSSH` [ddgbm], `TestEnterRepoSettlesTopLevel` [ddgbn], `TestAccountTokenAsksGitConfigOnlyWhenNeeded` [ddgbp], `TestFetchReadsOriginHeadOnce` [ddgbq], and on Linux `TestTerminalWidthAsksTheKernel` [ddgbr]. Also the spawn-count limits.
	- Verified: on b26, in a real terminal 40 columns wide, a long line in the `status` list is cut at 40, and at 120 it is not cut. A stand-in `tput` was never run, so the width came from the kernel. 2026-10-04.
	- Acceptance signoff: Self-closed: the intent was clear, every cut has a test that fails before and passes after, and the Mac width read ran.
	- Closed: 20261004-115346

- Code Review 20261003 enhancement 5: Answer branch checks from one read
	- ID: 2026100313123948
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Prereq IDs: 2026100313123975
	- Requirements  [Feature]:
		- Each branch-exists check starts its own `git show-ref`. `br switch` starts 8 and `br prune` 7.
		- Read local and origin branches once per run, and drop that in `forget()` like the rest.
		- `release` works out dev again on its own. Use `mergeTarget()`, which already caches it.
	- Origin: branch.go:47 from 3d22222 (2026-08-17), and release.go. Confirmed with strace.
	- Actual effort: Avg
	- Done: One `for-each-ref` reads every local branch with its upstream, and every branch on origin. Each existence check reads that, where each was a `show-ref` of its own. The prune survey and the default branch fallback take their list of local branches from it too.
	- Done: `forget()` drops it with the rest, so any step reads it again. The fetch drops it too, since the fetch moves origin's branches without being a step.
	- Done: `release` takes dev from `mergeTarget()`, the same answer its plan reads.
	- Note: `br prune`'s delete-time re-check is unchanged. It still asks git right then, with `for-each-ref --merged`, and nothing cached stands in for it.
	- Note: Spawn counts, before -> after: status 14 -> 12, whoami 9 -> 8, br list 9 -> 8, account list 9 -> 8, repo url 8 -> 7, pullcom 25 -> 22, pullcom with a fetch 32 -> 30, br switch 33 -> 27, br prune 39 -> 32, status with a fetch 21 -> 20, status in an account folder 25 -> 23, whoami there 19 -> 18, account list with accounts 14 -> 13, status in the https folder 21 -> 19. The expected counts in spawn-count.bash went down to match.
	- Note: On a case-insensitive file system, `show-ref` could find a loose branch under another case. The list matches names exactly, as git already did for packed branches.
	- Swept: `grep -n 'show-ref\|"--verify"' src-go/*.go`. Every `branchExistsLocal` and `branchExistsRemote` caller, and the back-merge's own `rev-parse --verify` of origin's default branch. The `show-ref` left in repo.go asks about a new clone's folder, not this repo.
	- Verified: test.bash 1406/0, parity 29/0, `go test -race`, `cicd.bash --gate`, and spawn-count. `TestBranchReadsFollowWrites` fails with the fetch's drop taken out, and again with the runners' drop taken out.
	- Branch: spawncut
	- Commit: f9716e4
	- Test case: Go `TestBranchReadsFollowWrites` [ddgbd], and the spawn-count limits.
	- Acceptance signoff: Self-closed: does what the item asked, and its test fails without the fix.
	- Closed: 20261004-113600

- Code Review 20261003 enhancement 8: Pipeline scripts and the style guide against the new Bash rules
	- ID: 2026100313130060
	- Type: Enhancement
	- Status: Done
	- Priority [Feature]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- New with the directives' Bash section, after 20260909. Not regressions.
		- About 40 snake_case variables, most in cicd.bash and fuzz.bash, and private globals with one underscore.
		- Unbraced expansions, most in gfs-rotate.bash, lint-report.bash and spawn-report.bash.
		- test.bash, fuzz.bash and parity.bash print with bare echo. Several scripts define their own echo helpers that differ.
		- `include/gh-account.bash` has no header and nothing sources it. Only a test fixture copies it.
		- style-guide.md's Bash and Go sections lack most of the directive's rules. It also bans new echo wrappers, which reads as banning an error helper, and allows interfaces only for a second implementation, not a test seam.
	- Decisions:
		- config.bash's UPPER_SNAKE settings stay (2026-10-03). They are sourced settings read like environment variables, some are exported, and the directive lets the language's own case convention win.
		- gfs-rotate.bash is a shared Bubbles file. A change there goes to every copy.
		- 2026-10-04: Every copy of gfs-rotate.bash changes, starting from the synced copy as it was changed that day, with dates by printf. Copies in other projects are left uncommitted there.
			- A copy with its own edits, or one that differs from the synced copy by more than its known history, is patched rather than overwritten, and listed.
			- Skipped: git worktrees other than a project's main checkout, anything under `0_archive`, anything under `.git/`, and the `wsl/` copy.
		- 2026-10-04: Another project changed its copy of a shared file to leave symlinks out. If that is in gfs-rotate.bash, it goes to every copy. If it is in another file, that file is not changed here. Either way the `private` link every project has is never left out.
		- 2026-10-04: `include/gh-account.bash` is deleted only if the gate fixture can do without it. Otherwise it gets a header. No existing test is deleted.
		- 2026-10-04: `local -n` nameref names are not renamed. The odd suffixes are on purpose.
	- Origin: directives 2026-09-09 to 2026-10-03, Bash section. Confirmed by a parse of every script.
	- Progress log:
		- Question: the symlink change is in `n8git_backup-and-publish`, not gfs-rotate.bash. slodworld's copy has it (commit 8dd2c57, 2026-10-04). It leaves out of the backup any dir link inside the repo, and any link that points back into the project. The synced copy and gitsby's copy don't have it yet. Every project's `private` link points outside its project, so it is still backed up. Should it go to the synced copy and to gitsby's? Not changed here.
			- Answer: no. It stays in slodworld only for now (2026-10-04).
		- Question: `include/gh-account.bash` shipped in v2.1.0, and changelog.md lists it under Added, as a helper for pipelines that call gh. The gate fixture would run without it, but deleting it drops a released helper with no Removed entry. It got a header instead. Delete it anyway?
			- Answer: no. It stays, with the header (2026-10-04).
		- Note: Left alone. The `fp` prefix on private functions in release.bash and gen-winres.bash is the v2.1.0 habit, and two test.bash checks read those names. cicd.bash's `_dests` is a nameref. `n8git_backup-and-publish` is shared and keeps its five unbraced expansions, so the new check skips it. install.bash's output helpers are unchanged. The report scripts' own output lines still use echo.
		- Note: gfs-rotate.bash copies touched outside this repo, all left uncommitted. Paths are under the dev tree unless shown.
			- Written as the new shared copy: `~/synced/0-0/common/exec/util/linux/bash/include/`, and the `cicd/utility/include/` copy in convert-base-v2, zuid, slodworld, slodworld2 and gitea camhauler.
			- The same, over a 2026-09-15 sync that was never committed there: photopea-local, zfs-auto-snapshot, x9ps1-git, tradeclanker, ti84ce-ish, nano-git-db (`github_floss`), link-repair, bash5-marmot and camhauler-cli. tooblin's copy was untracked.
			- Patched, since each had edits of its own: silkterm, whose spelling fix is now in every copy. shcl and silkterm's `forks/shcl` clone, which keep their own history line; their better names are now in every copy. nemo-anywhere, which keeps its own header with no file-wide disables, so it has two per-function nameref disables.
			- Skipped: the synced `wsl/` copy, `0_archive/rename-foundry`, silkterm's `forks/shcl-v2` worktree, and gitsby's gate snapshot under `.git/`.
	- Done: cicd.bash, fuzz.bash and pre-push.bash use camelCase variables, and a global only the output helpers use starts with two underscores. cicd.bash's helpers come before the option loop, so a bad option goes through `fUsage`. Its two-read lines are split.
	- Done: test.bash, fuzz.bash and parity.bash print through `fEcho_Clean`, and parity's header through `fEcho`. Every helper family under `cicd/` prints with printf, and gen-winres's `fSay` is `fEcho_Clean`.
	- Done: Every expansion is braced. Each script turns on shellcheck's brace rule at the top, so the lint stage fails an unbraced one.
	- Done: gfs-rotate.bash adopts the synced copy's printf dates, and its loop variables have real names. One of them can't be `epoch`, since `_gfs_ts` has a local of that name, and its nameref would set that instead.
	- Done: gh-account.bash has a header, copyright and history.
	- Done: style-guide.md's Go section takes the directive's rules, and allows an interface for a test seam. Its Bash section has the layout, naming, quoting and output rules, and a list of Bash traps. An error helper is the rule now, not banned.
	- Swept: a parse of every pipeline script for snake_case and one-underscore names. Only namerefs, the sourced-file guards and the proxy variables are left. test.bash, fuzz.bash, parity.bash, release.bash, the utility scripts, the Go source and the docs were grepped for every renamed name. Three test.bash checks read cicd.bash's names and were changed to match: `[dbss8]`, `[dbfta]` and `[dd5fn]`.
	- Verified: `[ddgq3]` fails on gover, listing all 22 scripts, and passes here. The three changed checks fail on gover's cicd.bash and pass here. A file with an unbraced expansion fails shellcheck.
	- Verified: shellcheck over every pipeline script, `test-id.bash --check`, `backlog-check.bash` and `cicd.bash --gate` pass. cicd.bash's plan is the same as gover's, with and without `--quick`, and its option errors read and exit as before.
	- Verified: old and new gfs-rotate.bash agree file for file and line for line over 25 rounds of rotation in five time zones, DST gaps included. The bad-count guard still works, and keep-build.bash still rotates with it.
	- Test case: test.bash `[ddgq3]`, every pipeline script turns on shellcheck's brace rule. Renames have no behavior to test; the suites cover them. `[db712]` covers the guarded removal in gfs-rotate.bash.
	- Verified: the 2026-10-04 test batch. test.bash on b23 passed 1452 and failed 1, which is 1412 plus this round's 41 new checks. The one failure is `[db712]`, from enhancement 8.
	- Verified: fuzz.bash 301/0, parity.bash and the spawn counts all pass on gover 2026-10-04.
	- Note: failed in the 2026-10-04 test batch, on b23, vmFreeBSD and vmDebARM64. `[db712]` now finds gfs-rotate.bash's `rm -f "${file}"` in its prune loop. The old unbraced `"$file"` slipped past the check's pattern, so bracing it brought an unguarded removal into view rather than adding one. The fix is a guarded path, such as `${file:?}`, in every copy of the shared file. Left for the next round.
	- Done: gfs-rotate.bash refuses an empty path in its prune, and ends options before it, so a path starting with a dash is not read as a flag. That was its only removal. A history line says so in every copy.
	- Note: the same change went to every copy listed above, patched in place, and left uncommitted outside this repo. The 17 that matched this repo's copy match it again. shcl, silkterm's `forks/shcl` and nemo-anywhere keep their own edits. The same copies were skipped.
	- Swept: a grep of gfs-rotate.bash for `rm`, in every copy. The prune is the only one.
	- Verified: `[db712]` fails on gover for gfs-rotate.bash and passes here. test.bash 1453/0.
	- Verified: old and new copies agree file for file and line for line over 25 rounds of rotation in five time zones, for this repo's copy and the three patched ones. keep-build.bash still rotates with it. shellcheck passes on every copy.
	- Verified: `test-id.bash --check`, `backlog-check.bash` and `cicd.bash --gate` pass.
	- Branch: bashstyle, gfsguard
	- Commit: bcdf93c, 08a22c5, 1fc2982, 0fa9910
	- Acceptance signoff: Self-closed: mechanical. The rest was done and verified earlier, and `[db712]` fails before this fix and passes after.
	- Closed: 20261004-185001

- Rename stage 7 to "Remote tests"
	- ID: 2026100418431100
	- Type: Task
	- Status: Done
	- Priority [Feature]: Low
	- Opened: 20261004-184311
	- Opened by: jim-collier
	- Related IDs: 2026100413264100
	- Requirements  [Feature]:
		- Stage 7 runs on FreeBSD and Linux arm64 boxes too, so "Mac + Windows tests" no longer fits. It becomes "Remote tests".
	- Note: `[ddg83]`, `[ddg84]` and `[ddg85]` read the label and change with it. They keep their IDs.
	- Progress log:
		- Done: cicd.bash's usage, plan line, section, skip, failure and OK lines say "Remote tests", and so do config.bash's stage 7 comment and the README's `--quick` line. The failure line said "Mac or Windows tests failed", so it changed too. The plan line keeps its dot column.
		- Done: `[ddg86]` and the three checks above follow the new text, with the same IDs.
	- Swept: "Mac + Windows", "Mac and Windows" and "Mac or Windows" across the repo, `legacy/` aside. Left alone, since they mean the boxes and not the stage: accounts.md, remote-tests.bash's purpose line, two comments in test.bash, and the dated history footers in cicd.bash and config.bash. The vNEXT changelog doesn't describe stage 7, so it has no entry.
	- Verified: `[ddg83]`, `[ddg84]` and `[ddg85]` fail against gover's cicd.bash and pass against the new one. `[ddg86]` checks for the label's absence, so it passes either way.
	- Verified: test.bash 1453/0, shellcheck, `test-id.bash --check`, `backlog-check.bash` and `cicd.bash --gate`.
	- Test case: test.bash `[ddg83]`, `[ddg84]`, `[ddg85]` and `[ddg86]`.
	- Acceptance signoff: Self-closed: rename.
	- Closed: 20261004-185642
	- Branch: remote-tests-label
	- Commit: 9049ec8

- gitsby should work with glab
	- ID: 2026102209210000
	- Type: Enhancement
	- Status: Done
		- Waits on a person trying the writing `pr` forms on a GitLab repo of their own.
	- Needs local test suite run?: No. test.bash ran 1659/0.
	- Needs hand testing: on a GitLab repo you can write to, `gitsby pr create` from a feature branch, then `gitsby pr ok <n>` on it. Both write to the remote, so they were not run here.
	- Opened: 20261022-092100
	- Opened by: jim-collier
	- Milestone: Pre-next-cut.
	- Requirements [Feature]:
		- gitsby should work with glab. (Now installed on b23.)
	- Progress log:
		- 2026-10-22: First real run, against gitlab.gnome.org as t00mietum (glab 1.53.0, token now in place). `raw glab api user` works and answers as t00mietum, so the account and token reach glab.
		- 2026-10-22: `gitsby pr` in a GNOME clone runs `tea-cli pulls list`, not glab, and fails. `pr` has no glab path.
		- 2026-10-22: `raw glab mr list` and `raw glab repo view` in a GNOME clone fail with "none of the git remotes ... point to a known GitLab host". The remote is `ssh.gitlab.gnome.org`, the API host is `gitlab.gnome.org`, and glab matches them by name. `-R t00mietum/gtk` works when `GITLAB_HOST` is set. gitsby sets `GITLAB_HOST` with an `https://` prefix.
		- 2026-10-22: `raw glab auth status` outside a repo sent the GNOME token to gitlab.com, which answered 401. glab applies `GITLAB_TOKEN` to every host it knows. Fixed on branch glabtoken: gitsby adds `--hostname <account host>` unless one is given. Test.bash `[de9jb]`, Go `[de9ja]`. Inside a GNOME clone no token is passed at all, because the remote is `ssh.gitlab.gnome.org` and the account's host is `gitlab.gnome.org`.
		- 2026-10-22: gitsby warns the token file is readable by other users.
		- 2026-10-22: Fixed on branch glabtoken: a remote on `ssh.<host>` now counts as `<host>` for the account's token and credential helper (`serviceHost` in account.go). Test.bash `[de9k7]`, Go `[de9k6]`. Checked for real: `raw glab mr list -R GNOME/gtk` in a GNOME clone lists the open merge requests as t00mietum.
		- 2026-10-22: `raw glab repo view` with no `-R` still fails in a GNOME clone. glab matches the remote's host (`ssh.gitlab.gnome.org`) to `GITLAB_HOST` itself. Still open, along with `pr`.
		- 2026-10-22: `pr` runs glab on a GitLab host, with the repo passed by `-R` (197677f). Test.bash `[dea15]` to `[dea1a]`, Go `[dea1b]`.
		- 2026-10-22: Fixed: when origin is on the account host's `ssh.` name, `raw glab` sets `GITLAB_HOST` to origin's host and `GITLAB_API_HOST` to the account's, glab's own setting for a git host apart from its API. `pr` is left as it was, since `-R` already works there. test.bash `[de9k7]` reworded with the same ID: the token still goes, and the account's host now reaches glab as the API host.
		- 2026-10-22: `raw glab auth status` still fails, inside a repo or out: glab checks only hosts in its own config file, and refuses one that only `GITLAB_HOST` and `GITLAB_TOKEN` name. glab's own behavior, still on its main branch. gitsby can't fix it without writing glab's config. Upstream draft: `private/claude_simple/upstream/2026102209210000/`.
		- 2026-10-23: The upstream draft won't be filed.
	- Verified: 2026-10-22, in the GNOME gtk clone as t00mietum, read-only: `raw glab repo view -b main`, `raw glab mr list` and `raw glab issue list` with no `-R`, `raw glab mr list -R GNOME/gtk`, `raw glab api user`, `gitsby -NoFetch pr` and `gitsby -NoFetch pr 10551`. A plain `raw glab repo view` there finds GNOME/gtk, then fails on its README, since it asks for the checked-out branch, which is only on the fork. That is glab's, and happens with any branch origin lacks.
	- Verified: 2026-10-22, test.bash 1659/0, 1658 -> 1659, with `[dea3p]` failing on a build without the new call, and nothing else failing. Go `[dea3n]` fails with `glabRemoteHost` stubbed out.
	- Test case: test.bash `[dea3p]` and Go `[dea3n]` for the ssh host, plus the ones named above.
	- Swept: `hostTokenEnv` has 3 callers. `raw glab` gets the new step. `pr` passes `-R`. `raw tea` was not changed: tea finds its login from the remote too, but no Gitea host seen so far puts ssh on `ssh.<host>`. Not checked against a real tea.
	- Acceptance signoff: Won't test. The write path (`pr create`, `pr ok`) on a GitLab repo was left untested by choice, 2026-10-23.
	- Closed: 20261023-064239

- CICD runs on GitHub's free macOS runners
	- ID: 2026102218410000
	- Type: Enhancement
	- Status: Done
	- Needs external testing: No
	- Opened: 20261022-184100
	- Opened by: jim-collier
	- Target OS: macOS
	- Requirements [Feature]:
		- Run CICD on GitHub's free macOS runners.
		- Build, run the tests, and smoke-test the CLI on the built binary.
	- Progress log:
		- 2026-10-22: Logged. This is a GitHub Actions use, set against the standing decision that Actions stay deferred (asked again 2026-10-06). Asked for by hand, so it overrides that for macOS only.
		- 2026-10-22: Intel macOS testing can also use vmKt6m, user `wintest`, in addition to b26. The public key already gets in. Not yet added to stage 7 or the host lock.
		- 2026-10-22: Added `.github/workflows/macos.yml`, on `macos-15-intel` and `macos-latest` (Apple silicon), both free for a public repo. It builds `src-go/gitsby`, runs `go test -race`, smoke-tests the binary (`--version`, `--help`, and `status` in a throwaway repo, which must change nothing), then runs test.bash with Homebrew bash first on PATH. It runs on a push to `gover`, `dev` or `main`, on every PR, and by hand. design.md "Direction decisions" says why, and that it isn't a gate.
	- Decisions:
		- test.bash runs as a plain step, as on b26. Nothing it needs was found missing on the runners, and its setsid, pty, strace and PyYAML checks already skip with a note there. A failure shows as a failed step.
		- Both CPUs, since the free tier has both. Actions are pinned by commit with the tag beside it, and Go comes from go.mod.
		- A push of a round branch doesn't run it. A PR from one does.
	- Verified: 2026-10-22, the workflow lints clean. The build, `go test` and smoke steps pass as written on Linux, and the smoke step fails when it expects the wrong branch.
	- Verified: 2026-10-22, test.bash 1661/0, 1659 -> 1661. `[dea4b]` fails on a tag pin, a fixed `go-version`, or no workflow at all. `[dea4c]` fails on broken YAML or a workflow with no jobs.
	- Verified: 2026-10-22, in the full run, `[dea4b]` passed in the container and on b26, vmFreeBSD and vmDebARM64. `[dea4c]` passed on vmDebARM64 and in test.bash on b23 off the container, 1661/0. The container, b26 and vmFreeBSD skip it, since they have no PyYAML. Log: `/mnt/ext/wip2/wip/tmp/test_gitsby_20261022-19253166/run.log`.
	- Test case: test.bash `[dea4b]` and `[dea4c]` for the workflow files. The workflow itself is the test on the Macs.
	- Branch: round-20261023
	- Verified: 2026-10-22, GitHub run 39895628537 on gover (`fix-macos-find` merge): `macos-15-intel` and `macos-latest` both completed with success, about 11 minutes each, test.bash and the smoke step included. The run before it, 39893939993, failed both on `[de54n]` alone (1411 passed, 1 failed), which is item 2026102220274491.
	- Acceptance signoff: Passed its own test on both runners, no open choice.
	- Closed: 20261022-203900

- `account apply` names fragments by host and login
	- ID: 2026093013031520
	- Type: Enhancement
	- Status: Done
	- Opened: 2026-09-30
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- Each fragment is `<host>_<login>.gitconfig`, in lower case.
		- An account with no login uses its own name there.
		- Two accounts that share a host and login each add their account name.
		- Help and doc examples name accounts the same way.
	- Decisions:
		- A fragment no rule uses any more is named in the output, not deleted. Nothing proves gitsby wrote it.
	- Branch: acct-files
	- Test case: TestFragmentNames, plus two apply checks in test.bash.
	- Closed: 2026-09-30

- `raw gh` loops forever behind a wrapper that clears the environment first
	- ID: 2026102306584127
	- Type: Bug
	- Status: Canceled
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261023-065841
	- Opened by: jim-collier
	- Related IDs: 2026101916533300
	- Target OS: All
	- Steps to reproduce [Bug]:
		- Put a `gh` first on PATH that runs `exec env -u GITSBY_RAW_ACTIVE gitsby raw gh "$@"`, or goes through `sudo`, `su -` or `env -i`, which drop it too. Run `gitsby raw gh --version`.
	- Incorrect behavior [Bug]:
		- Each start loses the chain, so nothing stops the loop. The rig's counter stopped it at 20.
	- Expected behavior [Bug]:
		- Stops after a few starts, like any other wrapper.
	- Reproduced [Bug]: 2026-10-23 on b23, with `private/claude_simple/tools/rawloop-rig.bash`.
	- Possible cause [Bug]:
		- The chain lives only in the environment. A check of the parent processes would catch it, but costs a lookup per platform on every `raw`.
	- Decided against: a fix (2026-10-23). A wrapper that clears the environment first is rare. A parent process lookup needs code for 4 platforms and runs on every `raw`, and a counter file can be fooled by a stale one.
	- Closed: 20261023-174007

- shellcheck crashes now and then on test.bash
	- ID: 2026100410472492
	- Type: Bug
	- Status: Canceled
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-104724
	- Opened by: jim-collier
	- Incorrect behavior [Bug]: shellcheck 0.11.0 on b23 segfaults on `cicd/test.bash` in about half of runs, gover's copy included, though less often there. Smaller scripts never crash. A bigger stack and dropping its cached pages did not help. A lint stage run can fail on this alone.
	- Expected behavior [Bug]: The lint stage passes or fails on what the file says.
	- Reproduced [Bug]: Yes, 2026-10-04, on b23.
	- Actual cause [Bug]: Not in this repo or in shellcheck. Memory on b23 gets corrupted in bursts, and other programs crash in the same windows. What corrupts it is still unknown.
	- Estimated effort: Avg
	- Progress log:
		- Verified: on 2026-10-04 the same binary crashed 9 of 10 runs on test.bash around 10:49, then 0 of 122 between 11:00 and 11:10, on the same file.
		- Verified: python3.13, rustc, rust-lld and opt crashed in that same 10:40-10:53 window, with the same kind of bad pointer fault. There was a similar burst of crashes from system tools on 2026-10-03.
		- Verified: the upstream static 0.11.0 build, made with a different GHC, crashes too. Run side by side in a bad window, it crashed about as often as the Debian one.
		- Verified: the installed binary and its libraries match their package checksums.
		- Every crash is in the GHC garbage collector, following a heap pointer that is not a valid address.
		- Ruled out: the Debian build, the GHC version, a damaged copy of the binary, a single bad CPU core, and test.bash itself. Bisecting test.bash makes no sense, since the same file passes every run outside a bad window.
		- Both builds refuse the GC and stack options, so there is no shellcheck setting to aim at this. A pinned upstream binary would crash the same way, and a retry would only hide a machine fault. Nothing changed in the lint stage.
		- Answered 2026-10-04: try to find it without a reboot.
		- Ruled out on 2026-10-04: swapping. The swap was idle all through the 10:40 burst, and forcing shellcheck's heap through swap crashed nothing.
		- Ruled out on 2026-10-04: CPU tuning registers. The kernel's out-of-spec flag showed another program wrote them on 2026-09-28. Read back as root, none of them holds what that program sets, so it put them back. The flag stays set once raised.
		- Closed 2026-10-04 as not a gitsby bug. The fault is in b23, and a lint run that dies with exit 139 or 135 there is rerun, not read as a finding.
	- Test case: None. The fault is in the machine, and nothing in the repo can check for it.
	- Branch: scsegv
	- Closed: 20261004-135244

- Code Review 20261003 enhancement 9: Measure building without inlining
	- ID: 2026100313140061
	- Type: Enhancement
	- Status: Canceled
	- Priority [Feature]: Low
	- Opened: 2026-10-03
	- Opened by: jim-collier
	- Requirements  [Feature]:
		- `-gcflags=all=-l` made the Linux binary 5.8% smaller, 3.32 MB to 3.13 MB. The timings showed no change, but the box was loaded.
		- Time it on an idle box. Adopt it only if it's no slower.
	- Origin: build flags in config.bash. Size Confirmed, speed Plausible.
	- Progress log:
		- Verified: 2026-10-04, release-style builds of the gover tree with and without the flag, run in alternating pairs in one session, 500 pairs and then 1000 more per command. The two runs agreed. Medians from the 1000-pair run, without -> with the flag:
			- `--version`: 1.32 -> 1.47 ms, 11% slower.
			- `status --no-fetch`: 11.16 -> 11.62 ms, 4% slower.
			- `whoami --no-fetch`: 7.28 -> 7.65 ms, 5% slower.
			- `account list`: 7.15 -> 7.57 ms, 6% slower.
			- The flagged build was the faster of a pair in 6% to 18% of pairs. The gap is several times the spread of each median.
		- Verified: sizes, without -> with the flag. linux/amd64 3.63 -> 3.36 MB, linux/arm64 3.47 -> 3.15, windows/amd64 3.83 -> 3.53, windows/arm64 3.50 -> 3.18, darwin/universal 7.02 -> 6.49, freebsd/amd64 3.54 -> 3.29, freebsd/arm64 3.34 -> 3.15. That is 6% to 9% smaller.
	- Decided against: the flag. Every common command got measurably slower, and the item asked for no slower. About 0.3 MB per binary does not pay for that.
	- Test case: none. Nothing changed in the build, so there is nothing to pin.
	- Acceptance signoff: Self-closed: the item's own rule decided it.
	- Closed: 20261004-170600

- CodeQL flags 2 spots in shcl 2.0.0, the old writer the tests use
	- ID: 2026101906343987
	- Type: Task
	- Status: Canceled
	- Priority [Feature|Enhancement] | Severity [Bug]: Low
	- Opened: 20261019-063439
	- Opened by: jim-collier
	- Related IDs: 2026101816064794
	- Requirements [Feature]:
		- `github.com/jim-collier/shcl/source/go/v2` v2.0.0 is used by the tests only, to write accounts files in the old format.
		- CodeQL's `go/incorrect-integer-conversion` flags shcl.go line 4266. A `strconv.ParseUint(t, 10, 32)` result goes to `int` with no upper bound check, which overflows where `int` is 32 bits.
		- CodeQL's `go/unhandled-writable-file-close` flags line 2625. The error from closing a written file is dropped, after a `Sync` whose error is checked.
		- Fix both in shcl's 2.x line, or decide they don't matter for a writer only the tests use. Fixed, both come off `CODEQL_IGNORE` in config.bash. Not fixed, both stay there with a note saying why.
	- Progress log:
		- 2026-10-19: Waits on a call. Fixing them means a 2.x release of shcl, a sister project, and the tests pin its v2.0.0 tag.
			- Answer (2026-10-19): "Won't fix old code."
		- 2026-10-19: Both stay on `CODEQL_IGNORE`, noted as won't fix.
	- Note: The live shcl module has neither.
	- Decided against: fixing them. shcl's 2.x line is frozen, and only the tests run this writer, to make old-format files.
	- Branch: pyfix
	- Test case: none new. Each entry fails the run once CodeQL stops reporting it, [de55s].
	- Acceptance signoff: Signed off by jim-collier in conversation, 2026-10-19.
	- Closed: 20261019-094958

## Old format

### Bugs

### Features and enhancements

- 🔘 Move the shcl module from its pinned `dev` commit to the tagged 3.0 release.
	- Status: Stalled
		- Waits on shcl tagging 3.0 with a `/v3` module path.
	- Opened: 20260924-132324
	- The pin is `v2.0.0-20261001214152-b10c2009d36c` since 2026-10-01, shcl `dev` at what will be the beta cut. Go sorts it below v2.0.0. Nothing asks for v2.0.0 on the new import path, so nothing picks it over the pin.
	- Go refuses a v3 tag on a module named `.../v2`, so the tag should bring a `/v3` import path. Move the imports in the same commit.
	- `release.bash` should refuse a pseudo-version for shcl, so a release cannot go out on a commit pin.
	- shcl plans the `/v3` path for its 3.0.0 cut, so nothing to report there.
	- Note: blocked. Checked 2026-09-28: shcl has no 3.0 tag yet, and its `dev` go.mod still says `/v2`.
	- Note: moved to the cut candidate on 2026-10-01. A line the file couldn't read is now kept through an edit, and a double-quoted path with a stray escape is listed instead of read with a newline in it. Still `/v2`.
	- Note: checked 2026-10-05 and 2026-10-06, still no 3.0 tag, and `dev` go.mod still says `/v2`.
	- Note: checked again 2026-10-21 and 2026-10-24. Newest tag is still v2.0.0.
	- At the move, read the changelog for format breaks since the beta, and for any API that backs up or converts a file itself. The converter from item 2026100312145843 must not race it.

### Done

#### Done - Bugs

- ✅ `status` says an account came from "gitsby.ghAccount in this repo's git config" when the key reached git through an `account apply` fragment included from the global config. The line also starts with a capital `G`, which no key is spelled with.
	- Closed: 20260928-131013
	- Opened: 20260916-163000
	- Origin: seen on b29w 2026-09-16, not traced to a commit. Confirmed.
	- Fixed: the line names the scope git reports for the key, so a fragment included from the global config reads "your global git config". It starts with "The", which keeps the key's own spelling.
	- Swept: `acct.source` has two other readers, the `account` header and a refusal. Both put it mid-sentence, where "the ... key" reads the same.
	- Verified: the check fails on `gover` and passes here.
	- Test: [dd80c] in test.bash, on the repo that gets the key only through the fragment.

- ✅ `account apply` writes `credential.https://github.com.username` from `ghAccount` for every account. An account with `host` set gets no username for its own host, so plain git there can push as whatever the credential manager holds. With both `ghAccount` and `user` set, the fragment names the first while gitsby's own runs use the second.
	- Closed: 20260928-131013
	- Opened: 20260926-154915
	- Origin: `writeAccountFragment`, read only. `selectAccount` already keys its helper on the account's host and login. Plausible.
	- Fixed: the fragment keys the username on the account's host and gives the login gitsby's own runs use: `user`, else `ghAccount` on GitHub. `accountHost` shares the host rule.
	- Verified: all three checks fail on `gover` and pass here. Confirmed by the same run.
	- Test: [dd80d], [dd80e] and [dd80f] in test.bash: the other host gets its `user`, github.com gets nothing for it, and `user` wins over `ghAccount`.

- ✅ A folder rule of `/` matches no folder, silently. The match looks for the rule plus `/`, which is `//`. `account apply` would write `gitdir/i://` for it too.
	- Closed: 20260928-131013
	- Opened: 20260926-163000
	- Origin: `config.go` folder match and `accountcmd.go` includeIf generation. The match half is Confirmed, the includeIf half Plausible: read.
	- Fixed: a rule ending in a slash, `/` or a drive root, takes no second one, in the matcher and in the includeIf pattern.
	- Swept: the two other prefix tests on a folder. The managed-includes scan now shares the matcher's test. The stale-rule warning keeps a root's slash, so a drive root is not read as a relative rule. `pathContains` drops slashes before matching, so a rule of `/` there is empty and ignored, as before.
	- Note: the test.bash header said a `/` rule covers nothing. That line went, since it described this bug.
	- Verified: all four fail on `gover` and pass here.
	- Test: `TestAccountForDirRootRule` and `TestAccountApplyPlanRootRule` in Go, plus [dd80j] and [dd80k] in test.bash, where plain git reads the rule `account apply` wrote.

- ✅ In `install.bash`, end of input at a terminal prompt exits 1 with no `Aborted.` and no closing blank line. The failing `read` ends the script under `set -e` before the answer is looked at. It is still a no, by accident.
	- Closed: 20260928-131013
	- Opened: 20260926-154915
	- Origin: seen while adding the installer checks. Confirmed: `script -qec "bash install.bash" /dev/null </dev/null` with the stub curl on PATH.
	- Fixed: a failed read leaves the answer empty, which is a no.
	- Swept: install.ps1 already said "Aborted." here, pinned by [dd5e1]. The installer has no other `read`.
	- Verified: the check fails on `gover` and passes here.
	- Test: [dd80m] in test.bash, on the same run as "go installer takes end of input at the prompt as a no".

- ✅ `cicd/release.bash` is committed as mode 100644, though its Syntax line says to run it as `cicd/release.bash [VERSION]`. That gives "Permission denied".
	- Closed: 20260928-131013
	- Opened: 20260926-154915
	- Origin: seen while adding the dry-run checks. Confirmed.
	- Fixed: committed as 100755. `demo-repo.bash` and `install.ps1` had the same mode and a shebang, and are executable now too.
	- Verified: the check listed all three before and passes after.
	- Test: [dd80s] in test.bash reads every script's committed mode from `git ls-files -s`, leaving out `legacy/` and the files that are only sourced.

- ✅ `release.bash --dry-run` still prints "tagged and pushed" and "Released v1.2.4" at the end, for steps it only announced.
	- Closed: 20260928-131013
	- Opened: 20260926-154915
	- Origin: seen while adding the dry-run checks. Confirmed.
	- Fixed: under `--dry-run` phase 2 closes with "dry run, v1.2.4 not tagged" and the run with "Dry run done: v1.2.4 was not released".
	- Verified: all three fail on `gover` and pass here.
	- Test: [dd5en] and [dd5ev] look for the dry-run wording now, and [dd80t] fails on "tagged and pushed" or "Released v1.2.4".

- ✅ `install.bash` checks a tag read from the release redirect for its characters only, so `..` segments pass. A typed `--tag` gets the path check as well. Low exposure, since curl collapses dot segments before it reports the URL.
	- Closed: 20260928-131013
	- Opened: 20260926-154915
	- Origin: seen while adding the installer checks. Plausible: read.
	- Reproduced: with the stub curl, the old script fetched `releases/download/../x/SHA256SUMS`. Confirmed.
	- Fixed: the typed and the resolved tag go through one path check.
	- Swept: install.ps1 had the same gap and fetched `download/../SHA256SUMS` on 5.1, which hands the header back as text. On 7 the header is a `[uri]`, which collapses the `..` first. Fixed the same way.
	- Verified: all four fail on `gover` and pass here.
	- Test: [dd80n] and [dd80p] in test.bash for install.bash, and [dd80q] and [dd80r] for install.ps1.

- ✅ Two test.bash checks on the frozen `install.ps1`, "iex form reaches the plan" and "and refuses without a tty", ask the live GitHub API for the latest release. Several suite runs inside an hour use up the anonymous rate limit, and both go red. The suite's header says it never touches the network.
	- Closed: 20260926-202618
	- Opened: 20260926-154915
	- Origin: seen 2026-09-26 after about fifteen suite runs in an hour. Confirmed: the API answered 403 rate limit exceeded.
	- Test: the two checks are the bug, so there is nothing separate to write. The installer is frozen, so the fix goes in the checks, which should stub `Invoke-RestMethod` the way `fPsInstall` does. To prove it and catch the next one, the suite could run with `HTTPS_PROXY` and `https_proxy` set to a closed local port, like the poisoned `XDG_CONFIG_HOME`. A check that reaches the network then fails on every run, not only after the limit is used up.
	- Cause: since the move to the org, `github.com/jim-collier/gitsby/releases/latest` redirects to the org's URL rather than to a tag. The installer found no tag in it and fell back to the API on every run.
	- Fixed: the checks stub both web cmdlets, and the whole suite runs behind a proxy on a closed port, so a check that reaches the network fails every time. Both checks go red with the stubs taken out.

- ✅ A Windows path with backslashes can read as a different folder. In the block layout, shcl v2 reads `\t` and `\n` as a tab and a newline, quoted or not, so `path: ~\dev\tools` names `~\dev` + tab + `ools` and the rule never matches. `\\` reads as one backslash. The old flat layout is not affected.
	- Closed: 20260924-132324
	- Opened: 20260916-163000
	- Origin: 20260826, the move to the shcl module. Found on b29w while checking the path-spelling feature. Confirmed on Linux and Windows.
	- shcl 3.0, not yet released, reads a backslash outside double quotes as a plain character. Moving to it fixes this, or gitsby reads the key's raw text by the same rule until then.
	- Decided 20260916: wait for shcl 3.0, with no workaround in gitsby. Reopen when shcl's Go module publishes v3.
	- Fixed: moved to the shcl 3.0 beta from its `dev` branch (1f88009), pinned by commit until it is tagged. A backslash outside double quotes is itself. The import moved to `yottacore` with it.
	- Every file reads by the 3.0 rules, including one written under 2.x. A path rule the old module wrote doubled (`~\\dev`) still names its folder, since a rule reads either slash. Only a pre-release build ever wrote this layout, so there is no migration step.
	- Verified: 1 new check in test.bash, 1028 -> 1029, and `TestConfigLoadBackslashes`. Both fail on `gover`. Go tests pass on vm925w, 143/0.
	- Test: [dd2d8] in test.bash, and `TestConfigLoadBackslashes` [dd2d9] in Go.

- ✅ The demo gif runs about two minutes, against a budget of twenty to thirty seconds.
	- Closed: 20260916-140754
	- Opened: 20260914-140251
	- Reproduced: the committed gif loops in 123.8 s over nine scenes. The shortest scene, a one-line `echo`, takes 8.6 s, and `br merge` takes 20.9 s. The holds alone add up to 52.8 s.
	- Note: split from Code Review 20260909 item 16. The budget leaves room for two or three scenes, so this waits on a decision about which ones the README keeps.
	- Fixed: five scenes, 47.7 s and 5.65 MB. `br create` stops on its confirmation and is answered on camera. Captions appear whole instead of being typed.
	- Note: the old target predates showing the confirmation. design.md now puts it at about fifty seconds.
	- Verified: 3 new checks, 1013 -> 1016, each watched red against the code before this.
	- Origin: 1a5a1a3, the first demo, looped in 18.4 s. 12d7d2d took it to 67 s, 7ed0e23 to 84 s and 30af5c5 to 122 s. The directives have asked for twenty to thirty seconds since at least 2026-08-22. Confirmed.
	- Test: [dcq6v], [dcq6w] and [dcq6x] in test.bash, for the answered confirmation. [defp0] holds the committed gif under a minute, added 2026-10-26 and failing on the gif before the fix.

- ✅ The backlog gate says nothing is listed, whatever the backlog holds.
	- Closed: 20260916-075518
	- Opened: 20260916-075518
	- Reproduced: stage 1 prints "Origin: present on every open review item (0 listed)" with twelve open items sitting in the file.
	- Cause: the count's pattern starts `^\t`, and `-E` leaves that escape alone, so it matched nothing. It counted closed items too, had it matched any.
	- Note: found while relabeling two suite checks. The rule itself is enforced by the awk above the count, which reads tabs correctly and was never affected.
	- Origin: 2319e09, the commit that added the gate. Confirmed.
	- Fixed: the pattern carries a real tab, and closed items are left out of the count.
	- Verified: 0 before and 12 after, against the same backlog. shellcheck clean.
	- Test: [defny] in test.bash, added 2026-10-26: two open review items out of four, one in each format. It fails on the script before the fix, and with the count's tab pattern put back.

- ✅ A `core.sshCommand` holding a quote is dropped from every fetch gitsby runs.
	- Closed: 20260915-124019
	- Opened: 20260915-121200
	- Reproduced: with `core.sshCommand = ssh -i "/k y/key"`, plain `git fetch` runs ssh with `-i /k y/key`. The fetch before `status` runs it with `-o ConnectTimeout=3` and no key.
	- Cause: `gitSSHCommand` reads a quoted command as plain `ssh`, which suits the probe it was written for. `remoteEnv` then exports that as `GIT_SSH_COMMAND`, which outranks `core.sshCommand` for the fetch, the origin check and the repo probe.
	- Note: a private repo whose key is only named there fails to fetch, and reads as offline. Pushes are not affected, since they don't go through `remoteEnv`.
	- Note: found while working Code Review 20260909 item 6.
	- Origin: 4918b5b (the port), with its copies gathered into `remoteEnv` by 88ff4ab. No earlier round saw it. Confirmed.
	- Fixed: a quoted ssh command is left for git to run as is, so the fetch uses the repo's key and goes without the connect timeout. Adding the timeout would mean re-shelling the value. Recorded in design.md.
	- Sweep: `remoteEnv` is the only place gitsby exports an ssh command for git. The account's `sshkey` can't carry a quote, and a caller's own `GIT_SSH_COMMAND` was already left alone.
	- Verified: `TestRemoteEnvLeavesAQuotedSSHCommandToGit` fails on `gover`. With the quoted command above, `status` now fetches with `-i /k y/key`.
	- Test: `TestRemoteEnvLeavesAQuotedSSHCommandToGit` [dcnpy] in Go.

- ✅ A failing `py_compile` passes lint stage 1, and the pre-push gate with it.
	- Closed: 20260915-121200
	- Opened: 20260914-130334
	- Reproduced: with a `python3` on PATH that exits 1, a full run exits 0 and prints `OK: py_compile`. `cicd.bash --gate` does the same.
	- Cause: the compile is the first half of an `&&` list. Under `set -e` a failure there neither stops the script nor fires the error trap.
	- Note: the line clears `cicd/utility/__pycache__`, but `py_compile` writes `cicd/utility/demo/__pycache__`, beside the file it compiles, so the cache stays. The same on `gover`.
	- Origin: bbce553, the first pipeline. No earlier round saw it. Confirmed.
	- Fixed: a failed compile stops lint with `FAILED: py_compile`. The cache goes to a temporary folder that is removed after, so nothing is written beside the file.
	- Sweep: no other lint check sits at the head of an `&&` list.
	- Verified: 1 new check in test.bash, the gate failing when `python3` does, which fails on `gover`. 950 -> 953 with item 6's two. A real lint run leaves the tree's own cache untouched.
	- Test: [dcmap] in test.bash, on its `python3` pass, and [dd5fk] for the cache folder.

- ✅ A folder rule with `*`, `?` or `[` in it binds repos in plain git that gitsby never matches.
	- Closed: 20260915-120313
	- Opened: 20260914-145514
	- Reproduced: `path: "<home>/d*"` lists as a folder that can never match, and gitsby names no account in `<home>/dev/work/proj`. After `account apply`, plain git gives that repo the account's email. `pathcontains: "acme-*"` does the same under `.../acme-x/...`, and `pathcontains: "**"` gives every repo on the disk the account.
	- Cause: gitsby compares a rule as literal text, and `account apply` writes it into an includeIf, which git matches as a glob.
	- Note: found while designing Code Review 20260909 item 1, which closes the relative half of the same disagreement.
	- Origin: `accountApplyPlan` since 8da8951 (the port), and the scripted `account apply` before it. No earlier round saw it; fuzz.bash feeds `**` to `pathContains` and asserts only that nothing crashes. Confirmed.
	- Fixed: `account apply` escapes `*`, `?`, `[` and `\` in both kinds of rule, so git reads a rule as the plain text gitsby does. Listing such a rule as ignored was the other choice. It would have dropped a working rule for a real folder with `[` in its name. Recorded in design.md.
	- Sweep: `account apply` is the only place a rule goes to git. An include written by an earlier apply is still recognized as ours and replaced, since that match is on the fragment path.
	- Decided against: a warning for a glob character in a rule. A `path` like `~/d*` already shows as a folder that can never match, and the `account set` help says `pathcontains` is a run of folder names.
	- Verified: 4 new checks in test.bash, all failing on `gover`, for `path` and `pathcontains`. Each binds the folder with `[` in its name and not its twin without. `TestAccountApplyPlanEscapesGlobs` fails on `gover`. On vm925w the escaped rules bind the same folders in plain git, and the Go tests pass.
	- Test: [dcnnq] to [dcnnt] in test.bash, and `TestAccountApplyPlanEscapesGlobs` [dcnp0] in Go.

- ✅ A relative `tokenfile` or `sshkey` is read from whatever folder a command runs in.
	- Closed: 20260915-120313
	- Opened: 20260914-145514
	- Reproduced: with `tokenfile: tok.txt`, `account list` says `token ...: tok.txt` in a repo holding a `tok.txt` and `none` in a repo without one. `sshkey: id_work` goes into the account's git config fragment as `ssh -i id_work`, which ssh reads from each repo's own folder.
	- Note: a repo someone else wrote can then decide which token or key a push uses. Same class as Code Review 20260909 item 1.
	- Origin: `absorb` and `readTokenFile` since 8da8951 (the port), and the scripted builds before it. No earlier round saw it. Confirmed for `tokenfile` and for what `sshkey` writes; the push with a relative key was not run.
	- Fixed: both keys are held to the same absolute-or-`~` test as `path`. A relative one is listed as ignored, reads no token and writes no key. `account set` writes a relative value as the file it names from where it runs. A relative `gitsby.ghTokenFile` in git config reads no token.
	- Sweep: `account set` now checks a key for shell characters after resolving it, since the folder it was typed in can hold a space. No other stored value names a file.
	- Verified: 5 new checks in test.bash, all failing on `gover`, 941 -> 950 with the four above. `TestConfigIgnoresARelativeKeyFile` fails on `gover`. The same results on vm925w. fuzz.bash 301/0, parity.bash 27/0.
	- Test: [dcnnv] to [dcnnz] in test.bash, and `TestConfigIgnoresARelativeKeyFile` [dcnp1] in Go.

- ✅ The Go unit tests fail on Windows.
	- Closed: 20260915-113307
	- Opened: 20260914-152134
	- Reproduced: built for Windows and run on vm925w, `TestCanonPath` and `TestDisplayPath` fail on `gover`, since they expect Linux spellings.
	- Note: no pipeline stage runs the Go tests on Windows, so nothing reports it.
	- Probable fix: spell those fixtures the way each platform writes an absolute path.
	- Origin: `TestCanonPath` since 4918b5b and `TestDisplayPath` since 919141f. No earlier round ran the Go tests on Windows. Confirmed.
	- Sweep: on Windows the accounts file never showed as `~`. The home folder and APPDATA are spelled with backslashes, and the file name goes on with `/`. Confirmed, and fixed here: either slash and any case count there now.
	- Fixed: each fixture is spelled the way the platform running it writes that path, and every assertion checks what it did before. `TestCanonPath` also covers the MSYS drive fold.
	- Verified: all 131 Go tests pass on vm925w, the lock tests and the lease-delete quoting tests included. The two new Windows cases in `TestDisplayPath` fail against `gover`.
	- Test: the Go tests on the Windows box in stage 7, and `TestCanonPath` [dbfr5] for the drive fold. `TestDisplayPath`, with the two Windows cases, went with `displayPath` in 0ad1374, when paths stopped folding to `~`.

- ✅ On Windows, `account apply` refuses to run when the accounts file is named with backslashes.
	- Closed: 20260915-113307
	- Opened: 20260914-152134
	- Reproduced: with `--config C:\Users\<you>\x\wl.shcl`, or `GITSBY_CONFIG` spelled the same way, apply stops with "Couldn't create 'C:\Users\<you>\x\wl.shcl/accounts' for the account fragments". The same file named with forward slashes applies.
	- Cause: `includeDir` cuts the file name off at the last `/`. A path spelled with `\` has none, so the fragments folder goes under the file itself.
	- Probable fix: cut at the last `/` or `\`, as `cmdAccountSet` already does for the file's own folder.
	- Note: found while working Code Review 20260909 item 1.
	- Origin: `includeDir` since 115bb7d (go: repo and account). No earlier round saw it. Confirmed on the `gover` build.
	- Sweep: a `--config` named with no folder failed the same way on every platform, as `wl.shcl/accounts`. A relative include would be wrong anyway, since git reads one from its own config's folder. Confirmed on Linux, and fixed here. `account set` finds the file's folder the same way now.
	- Fixed: the fragments go in the absolute folder holding the accounts file, however the file was named. Apply's two refusals name that folder the way the platform writes it.
	- Verified: 2 new checks in test.bash, both failing on `gover`, 939 -> 941. `TestIncludeDir` fails on `gover` on Linux and on Windows. On vm925w, apply with the file named in backslashes writes the fragment, and plain git then uses the account's email in the rule's folder. parity.bash 27/0.
	- Test: [dcnmt] and [dcnmv] in test.bash, and `TestIncludeDir` [dcnmw] in Go.

- ✅ `br prune` says to run it again for origin's copies it left alone, and the second run can't see them.
	- Closed: 20260915-111338
	- Opened: 20260914-165245
	- Reproduced: with origin unreachable, `br prune` deleted the local branch, kept origin's copy and said "'gitsby br prune' again once online". Once online, the second run said "Nothing to prune" and origin kept the branch. The warning for a branch origin has moved since the last fetch ("takes a fresh look") ends the same way.
	- Cause: prune takes its candidates from local branches, and both warnings print after the local branch is gone.
	- Probable fix: name what deletes that copy on origin once it has been checked, instead of a second run.
	- Origin: the unreachable line from 353f5c9 (Code Review 20260819a item 7), the moved line from Code Review 20260909 item 2. No earlier round saw it. Confirmed.
	- Sweep: `br merge` with origin unreachable said `br prune` clears origin's copy later, and deleted the local branch that prune would need. Confirmed, and fixed here: the branch stays with origin's copy until the merge is pushed.
	- Fixed: prune asks origin before it deletes anything. A copy origin has moved keeps its local branch, so the second run the warning names can look again. When origin can't be reached the local branches still go, as decided 2026-09-14, and the warning prints a leased delete to type for each copy.
	- Keep: offline, prune still deletes the local branch and holds origin's copy.
	- Verified: 5 new checks in test.bash, all failing on `gover`. The first prune's count check now expects one local delete fewer.
	- Verified on Windows, 20260915: in pwsh 7.6 and Windows PowerShell 5.1, each printed delete reaches git as the words it names, for branch names holding quotes, `$`, `;`, `&`, parentheses, backticks, `%`, braces and dots.
	- Test: [dcnm7], [dcnm8], [dcnmj], [dcnmk] and [dcnmm] in test.bash, with [dcmhb] as changed.

- ✅ A tag on origin with a branch's name stops every remote delete in `br prune`.
	- Closed: 20260915-111338
	- Opened: 20260914-165245
	- Reproduced: with branches `amb` and `other` merged and a tag `amb` on origin, the delete push failed with "dst refspec amb matches more than one" and sent nothing. gitsby said it couldn't delete either, and origin kept both.
	- Cause: each delete names the branch by its short name, which git matches against every ref on origin.
	- Probable fix: name each delete by its full ref, `refs/heads/<branch>`.
	- Note: `br merge` names its delete the same way. Read, not run.
	- Origin: cfb6d90 (the port). No earlier round saw it. Confirmed.
	- Sweep: once the tag is fetched, git lists the branch here as `heads/amb`, so prune tried to delete a branch that doesn't exist. Prune's listings and the default-branch lookup now read the name whole. `br merge`'s delete names the full ref too.
	- Fixed: every remote delete names `refs/heads/<branch>`.
	- Verified: 3 new checks in test.bash. Two fail on `gover`; the kept tag is a regression guard.
	- Test: [dcnm9], [dcnma] and [dcnmb] in test.bash.

- ✅ `br merge` merges a tag that has the branch's name, instead of the branch.
	- Closed: 20260915-111338
	- Opened: n/a
	- Reproduced: with a branch `tagged` pushed one commit past `dev` and a tag `tagged` on `dev`, `br merge --no-fetch` merged the tag, and the branch's commit never reached `dev` on origin.
	- Cause: `git merge` reads a short name as a tag before a branch. `git checkout` does the opposite, so the switch before it looked right.
	- Note: found in the sweep for the tag on origin above. The `br merge --no-fetch` fix below leases on the merged tip, which only holds if the branch is what was merged.
	- Origin: `cmdMerge` since 86ca0b1. Confirmed.
	- Sweep: `release` merges `dev`, fast-forwards `dev` and checks ancestry by short name, and the hotfix back-merge merges `main` or `origin/main` the same way. All now name full refs. Checkouts stay as they are.
	- Fixed: `br merge`, `release` and the back-merge name the full ref of what they merge.
	- Verified: 2 new checks in test.bash, both failing on `gover`.
	- Test: [dcnmc] and [dcnmd] in test.bash.

- ✅ `br merge --no-fetch` deletes its branch on origin after someone else pushed to it.
	- Closed: 20260915-111338
	- Opened: 20260914-160947
	- Reproduced: with `feat` pushed from one clone and a further commit pushed to it from a second, `br merge --no-fetch` in the first said "Nothing to push.", merged, pushed `dev` and deleted `feat` on origin. The second clone's commit is on no branch there.
	- Cause: with the fetch declined, the park push reads the local copy of origin and finds nothing ahead, and the delete push removes whatever origin holds.
	- Note: with the fetch on, the pull brings the commit in first and the merge keeps it. Found while designing Code Review 20260909 item 2.
	- Probable fix: ask origin and lease the delete, reusing what `br prune` does for Code Review 20260909 item 2.
	- Origin: `cmdMerge` since 86ca0b1 (go branch commands). No earlier round saw it. Confirmed.
	- Fixed: `br merge` asks origin before deleting its copy, and leases the delete on the tip it merged. A copy holding commits the merge doesn't have is left alone, and the warning names the `br switch` and `br merge` that bring them in. A copy already gone is reported as gone.
	- Verified: 4 new checks in test.bash. Three fail on `gover`, including following the advice; the merge's push is a regression guard. Across the four items test.bash went 925 -> 939, with parity.bash 27/0 and the Go tests green. Linux only.
	- Test: [dcnme] to [dcnmh] in test.bash, and `TestLeaseDeleteLine` [dcnmp] in Go.

- ✅ Two `account set` runs at once on one accounts file keep only one of the two keys.
	- Closed: 20260915-104204
	- Opened: 20260914-171139
	- Reproduced: two runs started together on a file holding one account, one setting `email` and one setting `name`. Both said "Wrote" and exited 0, and in 30 of 30 tries the file held only one of the two keys. Two runs creating the file lose a key the same way.
	- Cause: each run reads the file when it starts and saves the whole file back at the end, so the later save drops what the earlier one wrote.
	- Note: found while designing Code Review 20260909 item 3, which stops the create from replacing a file but leaves two edits as they are.
	- Note: a create stalled between its open and its write loses its key to an edit that runs in between. The edit reads the empty file and saves over it, so a lock has to cover the create as well as the edit.
	- Probable fix: refuse the save when the file changed since the plan read it, and hold a lock beside the file from that check to the save.
	- Origin: 9c6bda8 (`account set`), whose whole-file write the shcl save (8d3f857) kept. No earlier round saw it. Confirmed.
	- Sweep: `account set` is the only writer of the accounts file, and the flat-file conversion saves through the same path. `account apply` writes its fragments whole, but two runs write the same text from one file, and its includeIf edits go through git, which locks its own config.
	- Fixed: `account set` takes a lock beside the accounts file, reads the file again, and refuses if it changed since the plan read it. A create holds the same lock. A lock that stays put is waited on for three seconds, then refused by name, with the command that removes it.
	- Verified: 3 new checks in test.bash, 922 -> 925. With the re-read taken out, two runs at once lost a key in 10 of 10 tries and both new Go tests on it fail. Go tests green, parity.bash 27/0. Linux only so far.
	- Test: [dcnk6], [dcnk7] and [dcnk8] in test.bash, and `TestAccountSetKeepsBothOfTwoEditsAtOnce` [dcnk9] and `TestAccountSetRefusesAFileThatChanged` [dcnka] in Go.

- ✅ A Gitea remote's identity line says tea has no login for the host when tea failed to answer.
	- Closed: 20260914-191247
	- Opened: 20260914-180511
	- Reproduced: with a `tea` whose `logins list` exits 1, `status -NoFetch` on a Gitea remote printed `Git host .....: gitea.example.com (tea): unknown - 'tea login add' has no login for this host`. tea was asked and gave no answer, and the line says there is no login.
	- Cause: `forgeLogin` returns nothing both when tea lists no login for the host and when `tea logins list` fails, and the identity line reads nothing as the first.
	- Probable fix: keep the two apart. When tea fails, say it couldn't be asked and repeat tea's reason.
	- Note: display only. The identity check already reads nothing as unknown, so no refusal acts on it.
	- Note: found in the sweep for Code Review 20260909 item 11.
	- Origin: 9333159 added the tea path and this line. No earlier round saw it. Confirmed.
	- Sweep: `forgeCLIWho`, which the identity check reads, already takes both as unknown, and the two `pulls list` reads in `pr` check whether tea ran. The Git host line also compared its "unknown" text with the ssh key's account, so a write with no tea login printed a NOT-the-key warning. Fixed here.
	- Fixed: the Git host line says tea couldn't be asked and repeats tea's reason when tea fails, and keeps "has no login for this host" for a tea that answered. Only a login tea named is compared with the ssh key's account.
	- Verified: 3 new checks in test.bash, 912 -> 915. Two fail on `gover`, and the no-login check is a regression guard. `TestShowForgeLine` fails on `gover` for the no-login row. Go tests green, parity.bash 27/0. Linux only.
	- Test: [dcmp5], [dcmp6] and [dcmp7] in test.bash, and `TestShowHostLine` [dcpv4] in Go, named `TestShowForgeLine` at the time.

- ✅ With `XDG_CONFIG_HOME` set, `account set` creates a new accounts file that hides one in a `~/.config/gitsby` folder it can't search.
	- Closed: 20260914-192150
	- Opened: 20260914-174736
	- Reproduced: `~/.config/gitsby` at mode 0600 holding a readable accounts file, and `XDG_CONFIG_HOME` pointing at an empty folder. `account set kept email k@example.com` planned `create ~/xdg/gitsby/config.shcl`, wrote it and exited 0. Once the folder could be searched again, `account list` read the new file and showed none of the old accounts. `gover` does the same.
	- Cause: a place whose lookup fails for any reason counts as empty. Only the place being written is safe, through its exclusive open.
	- Probable fix: at the places other than the one written, count a lookup failure other than "no such file" or "not a folder" as something there, and refuse by name.
	- Note: found while reviewing Code Review 20260909 item 3, whose design counts a failed lookup as empty on purpose.
	- Origin: the `XDG_CONFIG_HOME` order from 72e1231 meets the create path from 8d3f857. No earlier round saw it. Confirmed.
	- Sweep: reads, the create check and the refusal after a lost race all look a place up through one probe, so all three changed together. A link whose target can't be looked up read as a link to nothing, and now reads as unknown too.
	- Fixed: a place an accounts file can live that can't be looked in no longer counts as empty. `account set` refuses to create while one is there. It names the file and the reason, and gives `chmod u+x` when the folder the file sits in is the one that can't be searched. Reads still pass over it.
	- Verified: 5 new checks in test.bash. On `gover` the create went ahead and wrote the new file in `XDG_CONFIG_HOME`, and the new Go tests fail there. The link case fails with its half of the fix taken out. The Windows, macOS and FreeBSD builds compile. Linux only.
	- Test: [dcmpe] to [dcmpj] in test.bash, and `TestAccountSetRefusesAPlaceItCantLookIn` [dcmpn] and `TestLookupFix` [dcmpq] in Go.

- ✅ `account set` crashes when the accounts file opens but its read fails.
	- Closed: 20260914-192150
	- Opened: 20260914-171139
	- Reproduced: with `GITSBY_CONFIG=/proc/self/mem`, which opens and then fails to read, `account set work email a@example.com` panics with a nil pointer dereference in `accountSetPlan`, exit 2, before the plan's first line.
	- Cause: the loader records the file before reading it, and a failed read leaves no parsed document for the edit to use.
	- Note: a file on a disk or mount that returns read errors reaches the same place. Found while designing Code Review 20260909 item 3.
	- Probable fix: record the file only once it has been read, and refuse a named file whose read fails the way one that can't be opened is refused.
	- Origin: `load` sets the file ahead of the read since 8da8951 (the port). The edit took the parsed document from it in 8d3f857 (shcl config). No earlier round saw it. Confirmed.
	- Sweep: the SSH line also checks the key file ssh names by opening it. That is display only, and ssh reports its own failure, so it stays. A token file is read in full, and a failed read already counts as no token.
	- Fixed: a file counts as readable only once it reads to the end, and the loader records it only after the read. A named file that fails to read is refused like one that won't open. A found one is passed over by reads and refused by `account set` as a file it can't read.
	- Verified: 2 new checks in test.bash, and with the 5 above, 915 -> 922. On `gover` the named case panics and the found one is taken up, and the new Go test fails there. Go tests green, parity.bash 27/0. Linux only, since the case needs `/proc/self/mem`.
	- Test: [dcmpk] and [dcmpm] in test.bash, and `TestConfigThatFailsToRead` [dcmpp] in Go.

- ✅ Code review 20260909 - the pass against the standing directives. Every defect is closed, and the enhancements are under Done too.
	- Opened: 20260909-184419
	- Fix order: by class, each class across all its sites in one group of commits. 5 with 11 (unknown is listed, unknown is not missing); 9 with 19 (preview follows command, one spawn per run); 3 and 8 without moving the decisions they sit on; 12 and 20 only once reproduced. 15 and 16 early, since the pipeline is what proves the rest.
	- Note: about twelve of the twenty sit in code that rounds 20260819b, c, d and 20260821 declared clean. Those rounds read the Go and grepped the rest.

	- ✅ Code Review 20260909 item 19: `account list` runs one `gh` per configured account.
		- Closed: 20260916-080622
		- The token lookup sits inside the listing loop. One account costs one process and twenty cost twenty, and `account set` pays the same bill before its edit, because it prints the listing first.
		- Origin: 4918b5b; 919e837 widened the listing two days after the 20260818 memoization round. Confirmed, measured.
		- Fixed: the answer is remembered per login for the run, in the same place the ssh logins already were. Nothing logs gh in or out mid-run, and the answer is keyed by the login rather than by whoever gh acts as, so there is no invalidation to get wrong.
		- Note: gh answers about one login at a time, so twenty distinct logins still cost twenty. What is gone is asking twice for the same one - which the listing did for every account sharing a login, and `account set` did by printing the whole listing before its edit.
		- Note: the item said the style guide states the rule this breaks. It does not; that guide covers output.
		- Verified: 1 new check, 1012 -> 1013, watched red against the pre-fix build. Two accounts on one login ask gh once. Go tests green, fuzz 301/0, parity 27/0. Spawn counts unchanged, since that fixture configures no accounts - it guards the listing rather than proving it.

	- ✅ Code Review 20260909 item 18: public documents contradict the code.
		- Closed: 20260915-155308
		- The recipe for checking a published binary against its checksum leaves out the build stamp, so it can never produce the published bytes.
		- Every config file the program creates links to the account documentation on `main`, which still describes the old flat format.
		- The code of conduct's enforcement contact is an empty pair of angle brackets.
		- design.md says everything is published as a full release, while both installers, the release badge and the changelog all handle pre-releases.
		- design.md heads the config-location block with "the place it used to live is never taken away" and says the opposite five lines down.
		- "Uninstalling is deleting it" is wrong on Windows, where the installer also writes a PATH entry.
		- A diagnostic points at a README section that does not exist.
		- The pipeline settings file numbers its stages one lower than the run prints, from stage four on.
		- The backlog still opens by calling itself the run-up to v2.0.0.
		- design.md says the word forge is gone from the whole tool, but it is still in about thirty comments and in design.md itself.
		- The style guide calls its three languages "Both languages", and the private pointer to it still says Bash and PowerShell.
		- Two British spellings in the code of conduct.
		- contributing.md and the code of conduct both advertise being produced by a generator.
		- trademark.md holds a hard-wrapped paragraph, and writes its contact address with a circled letter A in place of the at sign.
		- Origin: mixed. Recipe from 96b3b88, outdated by b283d31. design.md:494 outdated by 20260819a item 12. design.md:356 is the cfgloc heading (72e1231) whose sub-bullets 14e2488 reversed the same day. Code of conduct spellings are from 2b3692f and were fixed on `main` only (5e335f0). Confirmed.
		- Fixed: the recipe carries the build number. The code of conduct has `main`'s contact line and spellings, and neither it nor contributing.md names a generator. design.md says how the installers pick a release, and its config-location heading matches what follows. README names the Windows PATH entry. `account list` with no accounts names `account set`. config.bash numbers its stages as the run prints them. The backlog no longer opens on v2.0.0. The style guide says "All languages", and the private pointer names all three. trademark.md is unwrapped and uses an at sign.
		- Fixed: "forge" is out of design.md's prose and every comment, and design.md now claims only the output and the docs.
		- Decided against: changing the accounts link in a created file. It names `main`, which gets the current `accounts.md` at the first Go release, and nothing released writes that file before then.
		- Kept at the time: code identifiers, the two `GITSBY_FORGE_*` variables, and two suite check labels. All renamed the next day, under "The last forge names".
		- Sweep: every first-party `.md` at the root and under `project/`, the Go sources and tests, and test.bash's comments.
		- Verified: gofmt and vet clean, markdown checks clean, and the new `account list` line prints as written. No suite asserted the old line, and the comparison suite does not run `account list`.

	- ✅ Code Review 20260909 item 17: pipeline housekeeping.
		- Closed: 20260915-153036
		- The two "have I seen this yet" markers live inside the working tree. A clean checkout loses them.
		- The lint report counts a filename as a warning, because one source file has the word error in its name. This is the second time that report has matched something that was never a warning.
		- `run-latest.ps1` is first-party PowerShell that the lint globs do not cover.
		- `git-auto-msg.bash` has no caller. Its header says it is the editor for the publish stage, and nothing sets it as one.
		- Three pipeline files stop their history at 2026-08-19 and have a month of changes since. The release check only inspects two other files.
		- The generator writes copyright 2026 while the program prints 2014-2026.
		- A dev or dogfood build is stamped with the parent commit's version, because the stamp is read before the commit that holds the source.
		- The version banner puts the copyright on the same line, where a separate line was asked for.
		- Origin: mixed. The lint match is bbce553 and this is its second false positive after 20260819a item 17, which added an exclude instead of narrowing the match. `git-auto-msg.bash` has had no caller since bbce553. The banner has always been one line. Confirmed.
		- Keep: narrow the positive match to the tools' own output formats. No third exclude.
		- Fixed: the lint report matches each tool's own output format, and no exclude was added. `run-latest.ps1` is in the PowerShell lint. `git-auto-msg.bash` is gone. cicd.bash, config.bash and release.bash have their missing history entries, and the release check now covers every pipeline and installer script that keeps a history and changed since the last release. The Windows resource takes its copyright years from the program, and both resource files were regenerated for v2.1.0. A build's version is read after the remote sync and says `-dirty` when the source isn't committed. The copyright has a line of its own, and the release notes take the banner's first line.
		- Decided against: moving the seen markers. Each sits beside the logs it records, both are gitignored, and a clean checkout loses the two together, after which the next look correctly reports NEW.
		- Decided against: committing before the builds so the stamp can name the new commit. Publishing stays after every gate, and `-dirty` says what the build is.
		- Sweep: every reader of the banner. The two build-number checks in test.bash and the release notes were the only ones. The release and demo builds are stamped from a tag, not from describe.
		- Verified: 5 new checks in test.bash, all failing on the tree before, 1007 -> 1012. The two build-number checks match the two-line banner. Go tests green. The report still flags the two real warnings in the oldest run log, and passes the three logs that listed errors.go. PSScriptAnalyzer is clean on `run-latest.ps1` in both passes.

	- ✅ Code Review 20260909 item 14: six flaws in install.bash, or shared by both installers.
		- Closed: 20260915-144923
		- An uppercase hash in the checksums file makes it report the asset as absent and then name nothing. The PowerShell one accepts the same file.
		- `--release stable` is accepted, while the help and the error text both say the option takes neither value.
		- `--ref` is accepted and missing from `--help`, against the file's own note that help lists every option.
		- Several exit paths skip the blank line framing: the "publishes no binary for this platform" block, the declined prompt, the pre-release notice, and every error the PowerShell one raises.
		- Neither plan says it will overwrite an existing install.
		- Nothing is said when the installed binary will not run. The run simply ends.
		- Origin: ee3caa0. Five of the six were in the 20260819a notes as seen and not filed. Confirmed against a local mock.
		- Fixed: `SHA256SUMS` is read with either case of hash and with CRLF line ends, and the platforms it lists come through either way. `--release stable` stays, and the help and the refusal say it names the default. `--help` lists `-r` and `--ref`, and install.ps1's `-Help` lists `-Ref`. The no-binary refusal, a declined prompt and the pre-release notice have a blank line either side, in both installers, and so does every error install.ps1 prints when run as a file. Both plans say when they replace an installed copy. install.bash says when the installed binary won't run, with its exit code. Recorded in design.md.
		- Decided against: refusing `--release stable`. It always meant the latest release, which an install without it still takes.
		- Note: run through `iex` or a script block, install.ps1 rethrows and PowerShell prints the error, so only the blank line before it is the installer's.
		- Sweep: both checksum readers, both help texts and both plans. install.bash lowers its own hash too, not just the file's. The help checks read the options off the Bash parser's `case` arms and the PowerShell function's parameters and aliases, so a new option can't be left out again.
		- Changed check: "go installer refuses any other --release" matched "now takes neither", the text for refusing both values. It matches "takes only 'stable'" now, since `stable` was never refused.
		- Verified: 17 new checks in test.bash. 15 fail on the tree before, along with the changed check. Two are regression guards: `--release stable` still installs, and a first install says nothing of replacing. The declined-prompt check needs `script`.

	- ✅ Code Review 20260909 item 13: five more flaws in install.ps1.
		- Closed: 20260915-144923
		- A system install promises write access it never checks, does not elevate, and fails after the download with a raw error. The bash one checks, and says up front that it will use sudo.
		- The documented parameters are unreachable: they sit on the inner function, so help shows a syntax line carrying no options at all.
		- The joined `--target=value` form is refused, though the bash one takes it and the documented spelling uses it.
		- The checksum compare works only because the operator is case-insensitive by default. A case-sensitive one would fail every good install.
		- The message for a binary that will not run is unreachable in the common case, because a launch failure is a terminating error and the outer handler prints raw text instead.
		- Origin: ee3caa0. Four of the five were in the 20260819a notes as seen and not filed. The parameter help is fallout from 20260821 item 2, which bound the help to a script that has no parameters. Confirmed against a local mock.
		- Fixed: a system install that can't write its folder is refused before the plan, naming the folder and saying to run as administrator, or with sudo off Windows. The comment help lists every option in its description, since a script-level `param()` breaks the `iex` one-liner. The Bash installer's long options work, with the value joined by `=` or apart. The checksum compare lowers both sides and says so. A binary that can't start gets the same "would not run" message as one that exits nonzero. Recorded in design.md.
		- Decided against: elevating. The `iex` and script block forms have no file to start again as administrator.
		- Sweep: the plan's "run elevated" line went, since the refusal now comes first. A user-scope install still has no write check; that is the first bullet of enhancement 10.
		- Verified: 9 new checks in test.bash, running whole installs with the web cmdlets stubbed. Eight fail on the tree before, and a tagged install asking for no latest release is a guard. On vm925w, under Windows PowerShell 5.1 and PowerShell 7.6, the long options, both help texts and the script block form all work with the same stubs, and the script block leaves no variable behind. `gover` fails all of those. The system-scope refusal and a binary that can't start were checked on Linux only.

	- ✅ Code Review 20260909 item 12: install.ps1 fails on Windows PowerShell 5.1 in the default lookup.
		- Closed: 20260915-144923
		- Reproduced: on 5.1, against the real releases, the default install stopped with "The resolved release tag ('v2.1.0 v2.0.2 v2.0.1 v2.0.0 v1.0.1 v1.0.0') isn't a plain git tag". PowerShell 7 resolved v2.1.0.
		- Cause: not the one filed. Asked to stop on errors, 5.1 answers the redirect with an error that holds no response, so the header is never read. The list lookup behind it got 5.1's whole array as one item, so every tag name made one tag.
		- Note: the filed cause is real one step on. With no full release, 5.1's 404 carries headers where reading Location as a property is an error under strict mode, and the run ended inside the catch.
		- Note: 5.1 is the shell Windows ships and the documented one-liner path.
		- Origin: ee3caa0; 20260819a item 33 added 5.1 support and missed these lines. Filed as Plausible, since read. Confirmed on 5.1.
		- Fixed: the redirect is asked for without stopping on an error, which on 5.1 hands back the 302 itself. The header is read by name on either version's object, and anything unreadable falls through to the list. The list is assigned before it is wrapped.
		- Sweep: every web call in install.ps1. The `SHA256SUMS` and asset downloads read no header and return one object.
		- Verified: 4 new checks in test.bash, with the stubs answering the way each version does. Three fail on the tree before, and reading 7's redirect is a guard. test.bash 977 -> 1007 with items 13 and 14, the Go tests and the pre-push gate green. On vm925w, 5.1 and 7.6 both resolve v2.1.0 from the real releases and stop at its missing Windows binary, where `gover` on 5.1 stops at the joined tag.

	- ✅ Code Review 20260909 item 8: three flaws in `account set`.
		- Closed: 20260915-132814
		- The refusals are decided inside the preview, so the refusal prints as the plan and it still asks you to confirm. Answering yes fails with the same sentence. Every other command settles its refusals before the plan.
		- A save rewrites the file into the canonical layout, which is the settled decision, but the plan calls it an edit of one line. Space indentation, mixed-case keys, line endings and duplicate blocks are all reshaped with no word.
		- `protocol` takes any value at all. The two it honors are documented in the header of the file it writes, and anything else is quietly ignored later.
		- Origin: 9c6bda8 for the refusals. The plan text is left over from the byte-for-byte decision that 8d3f857 reversed. Confirmed.
		- Keep: saves stay canonical. The plan says so; nothing goes back to byte-for-byte.
		- Reversed 20260925: shcl's 3.0 beta saves an edit and keeps every other line as written. `account set` uses it, and the `also:` line now shows only when the module falls back to a whole-file rewrite.
			- Removed from test.bash: "an edit that respaces the file says so in the plan" and "and a file already spaced that way hears nothing of it". Both pinned the canonical rewrite. The same file now keeps its spacing with no `also:` line, and the plan line is checked on a dotted-line add instead.
		- Fixed: `account set` settles its plan before anything prints, so a refusal comes alone, with no plan and no prompt. The file is read once, not twice with the prompt between. When a save changes more of the file than the key, the plan adds an `also:` line saying so. `protocol` takes `https` or `ssh` in any case and writes it lower case. Any other protocol already in a file, in an account or at the top, is listed as ignored.
		- Sweep: no other plan decides a refusal. `protocol` was the only closed-set value the loader kept unchecked.
		- Verified: 8 new checks in test.bash, 969 -> 977. Seven fail on `gover`, and a plan for a file already in the save's layout is a regression guard. The prompt check needs `script`. Three new Go tests, which don't build on `gover`. `TestAccountSetPreviewShowsTheRefusalsFirstLine` is gone, since a plan can't show a refusal now. The fuzz target's oracle expects nothing kept for a top-level protocol other than https or ssh. fuzz.bash 301/0, parity.bash 27/0. Linux only.

	- ✅ Code Review 20260909 item 20: the hotfix warning about changing shipped code can never fire in anyone else's repo.
		- Closed: 20260915-131144
		- The path it watches is this project's own source folder. In any other repo the check matches nothing and stays quiet.
		- Also, the check cannot tell "nothing changed" from "the comparison could not run".
		- Origin: 353f5c9. Fourth patch to this path (`bin/` -> `src-go/` -> `:(top)src-go/`). Confirmed: a code hotfix outside `src-go/` printed nothing, and so did a comparison that failed.
		- Fixed: the note fires when a hotfix changes anything that doesn't look like documentation by its file name. A repo with no release tags gets no note, and a failed comparison says it couldn't tell. Recorded in design.md.
		- Decided against: watching a named folder, and naming the folder in config.
		- Note: in this project a hotfix to an installer or to `cicd/` now gets the note too, though neither goes into a release asset.
		- Verified: 3 new checks in test.bash and `TestDocsOnly`. The three older warning checks match the new wording. All six fail on `gover`, where `TestDocsOnly` doesn't build, and the docs-only check still passes. 966 -> 969.

	- ✅ Code Review 20260909 item 10: a conflicted `br merge` leaves the merge in progress and says nothing useful.
		- Closed: 20260915-124817
		- Reproduced: a conflicting merge onto the protected branch ended on a bare step failure, with the tree in conflict and the merge still open.
		- Note: the back-merge path in the same file handles the same failure the other way. It aborts, says what got through, and names the command to finish by hand.
		- Origin: 4918b5b; the frozen bash has the same asymmetry. Confirmed.
		- Fixed: a merge stopped by conflicts is aborted, the run goes back to the branch it started on, and the refusal names the commands to settle it there. The target branch is left as it was.
		- Sweep: `release` merges `dev` into the default branch the same way and left it mid-merge too, with nothing tagged. Same fix. The back-merge already aborted, and the other merges are fast-forward only.
		- Verified: 7 new checks in test.bash. Four fail on `gover`: the tree left mid-merge, the branch left behind, the missing advice, and `release` left mid-merge on the default branch. Two refusals and the untouched `dev` are regression guards.

	- ✅ Code Review 20260909 item 9: `repo url` previews a github.com address on every host.
		- Closed: 20260915-124817
		- Reproduced: against a Gitea remote the plan named a github.com URL, and the command then set the Gitea one.
		- Cause: the preview builds its line with the GitHub-only helper while the command uses the host-aware one. The read-only half was widened and the preview was left behind.
		- Origin: 9333159 moved the command to `forgeURL` and left the preview on `githubURL`. Confirmed.
		- Fixed: the plan builds the address the way the command does.
		- Sweep: every preview line against its command. No other plan names a different host, branch or command than the one run. The other `githubURL` callers take `owner/name`, which has only ever meant github.com.
		- Verified: 1 new check in test.bash, which fails on `gover`.

	- ✅ Code Review 20260909 item 7: `release` invents version 0.1.0 in a repo whose tags carry no leading `v`.
		- Closed: 20260915-124817
		- Cause: the tag scan matches a `v` followed by a digit, so a tag like `1.0.0` is invisible and the next version starts from nothing. The duplicate-tag guard below it does see those tags, so the two halves of one command disagree about which tags exist.
		- Note: unattended there is no prompt, and the invented tag is pushed.
		- Origin: 089776d (the port); `legacy/bin/gitsby:2232` has the same scan. Confirmed.
		- Fixed: a tag with no `v` counts too, when it is a whole X.Y.Z, so a date or build number can't restart the numbering. The duplicate guard refuses either spelling. A new tag is spelled like the tag it counts from, and the first one gets a `v`. A typed version is tagged as typed.
		- Note: the first fix gave every new tag a `v`, the way typed versions always had. That left a repo tagged `1.4.2` going on with `v1.4.3`, and a typed `1.4.3` came out as `v1.4.3`. Changed the same day. `cicd/release.bash` always passes a version with the `v`, so this project's tags are unchanged.
		- Sweep: `cicd/release.bash` and the demo stamp scan only this project's own tags, which all carry the `v`. The frozen bash is left as it is.
		- Verified: 3 new checks in test.bash, all failing on `gover`, where `TestNewestReleaseTag` doesn't build. 953 -> 964 with items 9 and 10. The spelling change adds 2 checks, which fail on the first fix along with the count check they change, and `TestNextReleaseTag`, which doesn't build there. 964 -> 966.

	- ✅ Code Review 20260909 item 1: a folder rule typed as `.` binds every repo under the home directory to that account.
		- Closed: 20260914-155309
		- Reproduced: `account set work path .` is accepted and stored as typed. `account list` shows the folder with no warning, because `.` always exists relative to wherever you are standing. gitsby itself then ignores the rule and reports no account for that very folder.
		- Cause: `account apply` turns it into an includeIf rule spelled `./`, and git resolves a leading `./` against the folder holding the config file, which is the home directory. Every repo under home then commits as that account and offers its login to the credential helper.
		- Note: this is the wrong-account commit the whole feature exists to stop, and nothing on screen says it happened. A bare `.` is the natural thing to type from the folder you mean to bind.
		- Probable fix: refuse a `path` that is not absolute, list one as ignored when read, and test the folder's existence against the resolved value rather than against the current directory.
		- Origin: `canonPath` since 8da8951 (the port); no round has handled a relative value. Confirmed.
		- Note: v2.1.0 does the same. The scripted `account apply` writes `gitdir/i:./` for a flat `path = .`, so a file from the release carries it.
		- Note: `account set` resolves a relative path from the folder it runs in rather than refusing it. Only the loader ignores one, since a file cannot say where a value was typed.
		- Sweep: `tokenfile`, `sshkey` and `gitsby.ghTokenFile` take paths too, and a relative one is read from wherever a command runs. Filed as its own bug. A glob character in a folder rule is the other way the two matchers disagree, also filed.
		- Fixed: `account set` writes a relative `path` as the absolute folder it names, and refuses another user's `~`. A relative rule already in a file is listed as ignored and `account apply` never writes one. `account list` warns about one an earlier apply left behind. On Windows a rule for a folder not made yet no longer reads as `c:./work`, which apply handed to git as relative.
		- Verified: 13 new checks in test.bash, 12 red against the tree before and green after, the last a regression guard, 863 -> 876. fuzz.bash 269 -> 301, and eight new Go tests red before and green after. On vm925w the new Go tests pass, `account set` from `C:\` writes `C:/sub`, and `account apply` writes `c:/...` where it wrote `c:./...`. A full Go run there failed eight older tests on `9a81b39`, whose `/srv/...` fixtures name no drive. With a drive in them it fails only `TestCanonPath` and `TestDisplayPath`, which fail on `gover` too. macOS and the BSDs untested.

	- ✅ Code Review 20260909 item 2: `br prune --no-fetch` deletes a branch on origin that origin has moved past.
		- Closed: 20260914-165502
		- Reproduced: with a branch merged locally and one further commit pushed to origin from a second clone, prune deleted it on origin and the pushed commit became unreachable.
		- Cause: the remote half of the plan reads the local mirror of origin, and the delete-time re-check surveys local branches only, so origin is never asked again. `--no-fetch` leaves the mirror as stale as it was.
		- Note: the plan line asserts each branch was re-checked at delete time. With the fetch left on, the same case is handled correctly, so the flag is the trigger, and its help text gives no hint that it makes this command unsafe.
		- Probable fix: ask origin about each remote candidate before the delete push, or send the delete with a lease so git refuses on stale information.
		- Origin: cfb6d90 (the port). The remote half has always read the local mirror, and the plan line from 4918b5b has overclaimed since. Not fallout from the 20260821 re-check rework. Confirmed.
		- Note: the same unasked origin drops every remote delete when one branch is already gone there, and under `--no-fetch` reports an unreachable origin as branches "already gone". Both are fixed with this item.
		- Sweep: `br merge` deletes its branch on origin the same way under `--no-fetch`, filed as its own bug. `pr ok` leaves the delete to the git host after it merges, so no local copy of origin decides it.
		- Decided against: checking whether origin's merge target was rewritten since the last fetch. Telling needs objects the run declined to fetch, and gitsby never rewrites a shared branch.
		- Fixed: just before the delete push, prune asks origin where its branches point, and leases each delete on the value it checked. A branch origin has moved is left alone with a warning. One already deleted there is named as gone and left out of the push. If origin does not answer, no remote delete goes out and the existing unreachable line prints. The plan line names the lease.
		- Verified: 13 new checks in test.bash, 876 -> 889. Ten fail on `gover`, and so does the plan check's new pattern. The other three are regression guards: the unmoved branch still goes, origin is not asked when nothing goes there, and the local delete still happens without origin. The prompt check needs `script`, so the total is 888 without it. The four new Go tests don't build on `gover` and pass on the branch. fuzz.bash 301/0, parity.bash 27/0, and the quick pipeline and the pre-push gate are green. `br prune` in the spawn-count fixture goes 35 -> 39, recorded as the new baseline. The ask is three processes, and the fourth is the `core.sshCommand` lookup a fetch would otherwise have made. On vm925w the four Go tests pass. There the `gover` build deletes a moved branch on origin, drops every delete when one branch is gone, and blames the branch when origin is away, and the branch build gets all three right. macOS and the BSDs untested.

	- ✅ Code Review 20260909 item 3: a config file that exists but cannot be read is replaced instead of refused.
		- Closed: 20260914-174903
		- Reproduced: with the accounts file mode 0200, `account set` printed a plan saying "create", truncated the file and wrote a fresh one. The login and token path that were in it are gone.
		- Cause: a candidate that fails the readable test is skipped, so an empty answer means both "no file anywhere" and "a file that could not be read".
		- Note: mode 0000 fails cleanly, so the window is a file that is writable and not readable.
		- Probable fix: keep the two cases apart and refuse the second by name. Open the create so it cannot truncate.
		- Origin: 8d3f857 (shcl) meets the older decision that a discovered unreadable file is skipped, not refused. Confirmed.
		- Keep: reads still skip an unreadable candidate. Only the create path refuses when a candidate exists and cannot be read.
		- Note: with `XDG_CONFIG_HOME` set, the new file goes ahead of the unreadable one instead, and every later command reads the new one. A link to a file that isn't there is written through. On Windows the same state is a file another program holds open, where the write fails too and the message blames permissions.
		- Sweep: two `account set` runs at once on one file keep one key, and a file that opens but can't be read through crashes `account set`. Both filed as their own bugs.
		- Fixed: `account set` won't create an accounts file while anything is at a place gitsby looks for one. A file it can't read, a file that turned up during the run, a link to nothing and a folder in the way each get their own refusal, naming the file, the reason and the fix, and nothing is written. The create opens the file so it can't replace anything. Reads still pass over a file they can't read.
		- Verified: 10 new checks in test.bash, 889 -> 899. Nine fail on `gover`, and the read check is a regression guard. Nine new Go tests: the eight on new behavior fail on `gover` and pass on the branch, and the read test is a guard. Two runs creating one file at once: `gover` said "Wrote" and lost a key in 30 of 30 tries, and the branch lost none, with one run refusing each time. On vm925w the held-open Go test fails on `gover` and passes on the branch. There the branch refuses and keeps a file another program holds open, where `gover` blamed permissions, and a file with a deny-read entry, which `gover` truncated. A full Go run there fails only `TestCanonPath` and `TestDisplayPath`, which fail on `gover` too. parity.bash 27/0, and the quick pipeline and the pre-push gate are green. macOS and the BSDs untested.

	- ✅ Code Review 20260909 item 4: the pipeline cannot finish, because the committed Windows resources no longer match their generator.
		- Closed: 20260910-072019
		- Reproduced: the resource check fails for both architectures, and stage 1 stops the run.
		- Cause: the copyright change edited the string the generator writes, and the two resource files were not regenerated.
		- Note: a release still passes its first phase, which tolerates a stale resource by design, so only ordinary runs are stopped.
		- Note: regenerating publishes whichever marker is in the generator into the Windows file properties, where a user reads it. See enhancement 1, which has to be settled first.
		- Fixed: the generator writes the plain copyright again, which is what both resource files already held. The check passes, and nothing needed regenerating.

	- ✅ Code Review 20260909 item 5: a key indented one level too deep is dropped, and the line listing what was ignored does not mention it.
		- Closed: 20260914-190531
		- Reproduced: an `sshkey` written one tab further in than the keys around it does not apply, and `account list` reports only the unknown key beside it.
		- Note: over-indent the key that picks the ssh key or the token file and the account applies without it, silently. The listing that always says, says nothing.
		- Probable fix: walk the children of each key as well as the children of each block, and add whatever turns up to the ignored list.
		- Origin: 8d3f857 (the shcl parser). Third instance of malformed input dropped silently, after 20260819d item 3 and the 20260821 fuzz find. The flat parser has ignored-list tests; this path has none. Confirmed.
		- Sweep: every level the shcl loader walks, with a test per level.
		- Sweep: every level the loader walks has a test: top-level keys, protocol, both account spellings, their fields, and anything under those at any depth. A stacked list and a raw block are not listed. A key inside a block with a refused name stays covered by the block's own entry.
		- Fixed: the loader lists every key it does not read, at any depth. A key indented under another key is named by the path that reaches it and the key it sits under, such as `account[w].email.sshkey (indented under email)`. The key above it still applies. A stacked list and a raw block list nothing.
		- Verified: 6 new checks in test.bash, 899 -> 905. Four fail on `gover`, and two are regression guards: the key above still applies, and a stacked list lists nothing. Two new Go tests and a fuzz target. The table fails on `gover` for every nested row and passes there for a stacked list, a raw block and a refused name. The depth cap test and every fuzz seed fail on `gover`. `FuzzConfigLoadDoc` passes over a 60 s run. fuzz.bash 301/0, parity.bash 27/0, and the quick pipeline and the pre-push gate are green. On vm925w the same Go tests fail on `gover` and pass on the branch. macOS and the BSDs untested.
		- Reviewed before merge: nothing found.

	- ✅ Code Review 20260909 item 6: a whitespace-only ssh command crashes the program.
		- Closed: 20260915-121200
		- Cause: an ssh command taken from the environment or from git config is passed through whenever it is not empty and carries no quotes, so a single space survives. Splitting it yields nothing, and the first element is read anyway.
		- Note: it fires where a push is compared against the account, and for a write through gh. `sync` with an account named panicked before its plan, with the blank command set either way.
		- Origin: 3d22222 (the port). Filed as Plausible, since read from the identity block; reproduced through the identity check instead. Confirmed.
		- Fixed: a blank ssh command counts as none, so the probe and the fetch use plain `ssh`. The probe also falls back to `ssh` if a split ever comes back empty.
		- Sweep: the other splits of a command line either check the length first or only loop over the words.
		- Verified: 2 new checks in test.bash on the `sync` comparison, one per spelling, both failing on `gover`. `TestGitSSHCommandBlank` fails on `gover`.

	- ✅ Code Review 20260909 item 11: being offline reads as "that repo doesn't exist".
		- Closed: 20260914-190531
		- Cause: the remote probe answers missing for any failure. A comment a few lines above it says unknown must not collapse into missing, and the GitHub-side probe honors that by reading the error text.
		- Note: offline, `repo connect` says a repo that exists does not, and points at the command that would create a second one.
		- Probable fix: read the error text, keep "could not tell" as its own answer, and give it its own message.
		- Origin: 4918b5b. The same bug was fixed in `ghRepoState` (20260818 item 7), same file, and this sibling was missed. Confirmed.
		- Sweep: every caller that turns a tool failure into an answer.
		- Sweep: every place a tool's failure is read as an answer was checked. A tea that fails reads as having no login for the host; filed as its own bug. The rest either say unknown already, refuse on the answer they assume, or read local state that fails loudly a step later.
		- Fixed: `repo connect` reads what git said, not only that it failed. Only git's words for a host that was reached and said no count as missing. Anything else refuses before the plan, says there is no telling whether the remote exists, repeats git's reason, and names no command. The missing message is reworded, and an answer nobody listed refuses instead of connecting.
		- Verified: 7 new checks in test.bash, 905 -> 912. Four fail on `gover`, and three are regression guards: it refuses, nothing is set up, and a credential in the url is not printed. The credential check stays in the suite, and a Go row covers the same case. Two new Go tests, which don't build on `gover`. fuzz.bash 301/0, parity.bash 27/0, and the quick pipeline and the pre-push gate are green. On vm925w both Go tests pass. There an unreachable https remote reads as no telling whether it exists on the branch, where `gover` names `repo create`, and a missing local path reads as missing. macOS and the BSDs untested.
		- Reviewed before merge: an ssh key refusal reads as unknown, which is right, but the message said the remote couldn't be reached, and ssh had reached it. It now says "Couldn't get an answer from". A Go row covers the refusal, and the message check fails on the wording before. test.bash 912/0, parity.bash 27/0, Go tests green.
		- Decided against: masking the reason git repeats. git hides a credential in its own messages, and ssh has none to print.

	- ✅ Code Review 20260909 item 15: there is no fast gate and no pre-push hook.
		- Closed: 20260914-134906
		- The standing directive asks for a quick mode that checks formatting, lints with warnings as errors and runs the unit tests, registered as a pre-push hook, so nothing reaches dev or main unverified outside a full run.
		- Nothing like it exists, and the hooks directory holds only the stock samples.
		- Note: the full pipeline is the only gate today, it takes minutes, and it is currently red.
		- Origin: new requirement from the 2026-09-07 directives. Not a regression.
		- Fixed: `cicd/cicd.bash --gate` runs every lint check and the unit tests, and nothing else. `--install-hook` installs a pre-push hook that runs it on each commit pushed to a branch, as committed, never on the working tree. A push from a subdirectory with a relative `--work-tree` is gated too.
		- Verified: 42 new checks, 810 -> 852. 41 of them fail on `gover`; the full-run check is a regression guard. The relative `--work-tree` check fails against the hook as it was, and each of the five later checks fails with the path it covers broken. The pipeline is green at 852/0, with parity 27/0 and fuzz 269/0. The real gate passes in 11.6 s. In a scratch clone the hook passes a good push, 11.6 s cold and 10.3 s warm, and refuses a gofmt violation. A failing commit is refused through 22 push forms. Nothing is installed in this repo. Linux only: Windows, macOS and the BSDs are untested.

	- ✅ Code Review 20260909 item 16: the demo gif is rebuilt and recommitted on nearly every commit.
		- Closed: 20260914-144550
		- Cause: every command prints the version and build number above its output, and the first scene captures one. The version moves with every commit, so the render always differs and an eleven megabyte file is replaced.
		- Note: three places state the opposite, that an unchanged binary and scenario reproduce the same bytes.
		- The run also lasts about two minutes against a twenty to thirty second budget, and its closing black is two seconds where three was asked for.
		- The quiet flag reaches every other child of the pipeline and not the demo generator.
		- Probable fix: stamp a fixed version for the demo build, or keep the banner out of the demo run.
		- Origin: b283d31 (build number) put a per-commit banner on `status`, which the demo captures. Confirmed.
		- Note: the length half of the third bullet is filed as its own bug at the top of this section. This item covers the rebuild on every commit, the closing black and the quiet flag.
		- Fixed: the demo renders from a build of its own, stamped with the newest release tag and that tag's commit time rather than the commit. The banner on camera now reads `gitsby v2.1.0 build db8ey` and stays put until the next release. `-q` reaches the generator, and the loop ends on three seconds of black. The committed gif is the new render, and the three comments and the design.md sentence name the release stamp.
		- Verified: two builds of one source, stamped like two consecutive commits, rendered to gifs that differ. 11 new checks, 852 -> 863. Nine fail on `gover`, and the other two, `-y` alone and the repeat render, are regression guards. The two build-site pins now count four sites and fail on `gover`. With `versionsort.suffix` taken out, the release-candidate check fails. The render is 960x540 and 12412356 bytes, loops in 124.84 s on the 20 ms grid, and ends on 3 s of black. A pipeline run regenerated the gif in 47 s. The next run, on the commit holding the gif, left it unchanged in 87 s, with the suite at 863/0 and parity 27/0. Linux only: Windows, macOS and the BSDs are untested.

- ✅ A release tag whose patch number is too large to hold overflowed into a negative version.
	- Opened: n/a
	- Closed: 20260822-113804
	- `strconv.Atoi` answers overflow with the clamped maximum, not zero, so the bump wrapped it negative. Found by the new fuzz targets on their first full pipeline pass; crasher committed as a regression seed.
	- Fixed: an unreadable patch number starts the count over at zero, as the comment beside it already claimed.
	- Test: `FuzzNextVersion` [dbjws] in Go, which replays the committed seed `6f637a04714948cb` on every `go test`.

- ✅ `account set`'s syntax block hung its indent off the `gitsby:` prefix, which is on one line only.
	- Opened: n/a
	- Closed: 20260821-150802
	- Everything below the first line sat at eight spaces, so the whole block read as one flat wall - the placeholders, the example and the sentence introducing it all at the same depth.
	- Fixed: it nests two spaces at a time. The written line is under `Syntax:`, the placeholders under that, `Examples:` alongside them and the commands one deeper.
	- Second example added, for picking an account by a run of folder names rather than an absolute path - the case a person with one employer folder full of repos actually has.
	- That example spells `pathContains` with a plain `my-employer/github`, not a glob: the matcher takes a run of folder names, so a `*` in the example would teach a pattern language that isn't there and a rule that never fires.
	- Test: `TestAccountSetUsageNests` [dd5g6] in Go, and [dbjnc] in test.bash for the example that is not a glob.

- ✅ `account set`'s syntax line named three placeholders and defined none of them.
	- Opened: 20260821-132716
	- Closed: 20260821-133346
	- Real output: `Syntax: gitsby account set <account> <key> <value>   (e.g. gitsby account set work host gitea.com)`.
	- The only person who ever reads it is the one who just typed the command wrong, and it left them to work out what an account is, which keys exist, and what a value looks like.
	- Fixed: a block. It names the line that gets written - `account.<account>.<key> = <value>` - then defines each placeholder, and lists all ten keys off the same constant the unknown-key refusal reads.
	- The example is now two commands on one account name, a folder and a login, since that repetition is what `<account>` means.
	- Test: [dbjkh], [dbjkj] and [dbjkk] in test.bash.

- ✅ `account list`'s header raised more questions than it answered.
	- Opened: n/a
	- Closed: 20260821-122605
	- Real output, in a Gitea folder with nothing set up yet: `Here .........: C:\opt\...\gitea.com\work\proj` over `Resolves to ..: (nothing configured - gh's own account)`.
	- "Resolves to" names no actor, so the first thing it prompts is "resolves by whom?". "Here" is a second word for the directory `status` calls `Directory`.
	- And `gh` has no business in that answer on a Gitea host. It is wrong wherever `gh` does not serve, and it answers a question about git's own fallback that nobody asked.
	- Fixed: `Here` is now `Current dir`, `Resolves to` is now `Account` - the label `status` already puts on the same answer - and an unconfigured folder gets `(nothing configured)`, full stop.
	- An account that resolves but names no login no longer asserts `gh` either: it names whichever tool serves that account's own host, and names none where there is none.
	- `status` and `whoami` said `Directory` for that same value, so they moved to `Current dir` too - one label, one constant, shared by all four places that print it.
	- Test: [dbjhe] to [dbjhh], [dbjhm] and [dbjhn] in test.bash.

- ✅ On Windows, `account list` printed the same directory two ways on the one screen.
	- Opened: n/a
	- Closed: 20260821-105738
	- Real output: `Here .........: C:\opt\...\dev\gitea.com\work\proj` above `folder ..: c:/opt/.../dev/github.com/work`.
	- The folder rules are held in the form paths are matched in - lower case, forward slashes - and that form was going straight to the display. Same disk, same tree, two spellings.
	- Fixed: every path printed anywhere is spelled the platform's way, which on Windows means backslashes and an upper-case drive letter. The internal form is untouched, so nothing about matching changed.
	- Covers the config file, `Here`, the folder rules, the machine-free `anywhere` rules, the ssh key, and a token file. No effect off Windows.
	- Test: `TestWindowsPath` [dbjep] in Go. Only Windows shows it, so the suite has no check of its own.

- ✅ The Account line explained an account it could not apply in a single run-on clause nobody could act on.
	- Opened: 20260820-160751
	- Closed: 20260820-162154
	- Real example: "(no login named) (from config 'work-gitea') - NOT applied: this remote is on gitea.com, and that account names no host, so it counts as a github.com one. Add 'host = gitea.com' to it." Two parentheticals back to back, then a clause long enough to wrap wherever the terminal ended.
	- Nothing in it could be acted on: which config, added where, what "NOT applied" covered, what "counts as" meant.
	- Worse, it was wrong twice. The line it told you to add is not a line the file accepts - keys are `account.<name>.<field>`, so a bare `host = ...` is reported as one gitsby doesn't understand. And "NOT applied" was false: the ssh key and the commit identity apply outside the credential decision, so it contradicted the SSH and Author lines printed directly underneath.
	- Fixed: the line says who and what happened, and an indented `Why:` / `Kept:` / `Fix:` / `File:` block underneath says why, which half did apply, exactly what to type, and which file to type it in. Wrapped at a fixed 78 columns rather than at the terminal, so it reads the same in a transcript as on screen.
	- "(no login named)" is gone from both the status line and `account list`; an account that names no login is now named by its own name, which is the thing you have to go and edit.
	- Second pass: `(from config 'work')` is gone from the applied line too. It named neither the file nor which config, and there are two of those in play - `gitsby.ghAccount` is a git config key and the account blocks are not. Every account now gets `From:` (the variable, the git config key, or the account block) and `File:` (the accounts file), on their own lines under the answer.
	- Displayed config paths fold a leading home directory back to `~`, so the file reads as somebody would type it rather than filling the line.
	- Test: [dbhbs], [dbhbt], [dbhbv], [dbhcb] and [dbhfs] to [dbhfx] in test.bash.

- ✅ The account display never learned about `host` and `user`, so a Gitea account was reported as a GitHub one that had nothing set.
	- Opened: 20260820-132706
	- Closed: 20260820-133645
	- Found on the first real Gitea repo: `status` named "(no GitHub account named)" and said the account was on github.com, which nothing in the config had said.
	- Four places read `ghAccount` alone. The status line and `account list` both named only the GitHub field; the "no token" case was keyed on it too, so a correctly declared Gitea account with no token said nothing at all and read as applied.
	- Fixed: all four ask the account's login on the account's own host. An unstated host is now reported as unstated and names the key that fixes it, and `account list` shows the host, marked `(default)` where the file never said.
	- Test: [dbh6m] to [dbh6w] in test.bash, and `TestAccountListNamesTheHost` [dbh6x] and `TestAccountListHidesTheHostWithOneGitHost` [dcptz] in Go.

- ✅ `repo clone` resolves its account from the folder you are standing in, not the one it is cloning into.
	- Opened: 20260819-092526
	- Closed: 20260819-094134
	- Every other command is about the folder you are in. A clone's repo lands somewhere else, so a clone launched from a work repo used the work account whatever tree it was cloning into.
	- Three ways in, all now closed: the folder rules read the current directory, `gitsby.ghAccount` was read off the surrounding repo, and the owner of that repo's origin stood in when nothing else answered.
	- Fixed: the destination folder decides. The surrounding repo's git config is not asked (a destination has no config yet, and an includeIf on gitdir cannot answer for a repo that does not exist), and no owner is guessed - with no rule for the destination, gh stays on its own account.
	- Noticed while making clone accept the `owner/name` shorthand; left alone there because it changes which credentials a clone uses, not just what it accepts.
	- Test: [dbfj9] to [dbfjf] in test.bash.

- ✅ Accounts and arguments, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-181826

	- ✅ `account apply` ordered its rules the opposite way from the way gitsby matches them.
		- Cause: gitsby takes the longest matching folder; git applies includes in file order and the last match wins. The rules were written grouped by account, in declaration order.
		- Note: so a tree nested inside another account's tree got whichever account happened to be declared later, and plain git and gitsby then disagreed about one directory - the single thing `apply` exists to prevent.
		- Fixed: shortest path first, so the longest match is written last and wins in git too. Folder is the tie-break, so the order is deterministic.
		- Verified both ways: with the old build, plain git in the nested folder used the outer account's email while gitsby resolved the inner account. Both now say inner.

	- ✅ Bash accepted `--config` naming a directory: shell error, no accounts, exit 0. PowerShell's matching hole was an unreadable file, passed over silently.
		- Fixed: both now require a readable regular file, and refuse by name. A *discovered* config is still skipped rather than refused - nobody asserted that one was there.
		- Note: PowerShell has no readable bit, so the test is opening the file.

	- ✅ `GITSBY_ACCOUNT` matched an account name case-sensitively in Bash, case-insensitively in PowerShell.
		- Cause: Bash's loader lowercases the whole key on the way in, but the lookup lowercased only the key half and left the account name as typed - so it could miss what it had just stored.
		- Fixed: lowercase both halves, which makes Bash self-consistent and matches PowerShell.

	- ✅ Only `-q`, `-y` and `--config` could precede `raw`, and the error blamed the wrong thing.
		- Note: worse than recorded - the message was "Unknown command 'raw'", which is false. Only the passthrough's own scan runs before `raw`, so an option it didn't take left the main parser looking at a command by that name.
		- Fixed: the scan takes gitsby's whole option vocabulary, spelled and normalized the same way the main parser does it. The ones with nothing to act on in a passthrough are inert. `-h` and `-v` still fall through to the main parser, and a genuinely unknown option is refused by its own name.

	- ✅ PowerShell `raw` could not pass `--`, git's pathspec separator.
		- Cause is not what was recorded, and matters: PowerShell's binder reads a bare `--` as an empty parameter name and fails *before the script runs at all*. Nothing in the passthrough can intercept it. Five param-block shapes were tested; a script with no `param()` block receives `--` fine.
		- Fixed as far as it can be: `` `-- `` survives binding, and is handed to the tool as `--`. Documented in `accounts.md`.
		- Note: dropping the `param()` block would fix this and the joined-option binding together. Not taken - it is a large change to a documented option surface.

	- ✅ `account apply` ended in a raw operating-system error, a different one in each build.
		- Note: not the no-config case, which already reports itself properly. The trigger is the include directory being unusable - something else already at that path.
		- Fixed: check the directory before writing anything, and fail in gitsby's own voice. Nothing partial was ever written, and still isn't.

- ✅ Installers, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-160521

	- ✅ A Windows install finished with the program not on `PATH`.
		- Fixed: the PowerShell installer adds the install directory to the account (or system) PATH, and says so in the plan before you agree. Idempotent, and it leaves the current shell alone.
		- `PATHEXT` deliberately left alone, and the original reasoning for it was wrong. PowerShell already resolves a bare `gitsby` to `gitsby.ps1` on `PATH` without it - verified with `PATHEXT` cut back to `.COM;.EXE;.BAT;.CMD`. It would only affect `cmd.exe`, which still cannot run a `.ps1` even with the entry, because that needs a file association - and the default association opens the script in an editor rather than running it. Adding it buys nothing and risks that.

	- ✅ Both installers installed anyway when `SHA256SUMS` was absent, and said nothing at all on the `--release dev` path.
		- Fixed: the plan states which of the two you are about to get, before the confirmation.
		- Fixed: where the plan promised verification and it can't happen, the install now stops instead of noting it in passing - separately naming the two causes, no published checksum and no sha256 tool here. `--ref TAG` takes it unverified, as an explicit choice.
		- Note: the release-asset fallback to the tagged tree was the same broken promise and stops the same way.
		- Verified against the real v2.0.2 release, both installers: plan promises verification, checksum verifies, correct version installed.

- ✅ Pipeline, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-153506

	- ✅ The pipeline had no remote-sync stage, so the pull at publish time could carry in changes nothing had tested.
		- Cause: the only pull was in the publish stage, which runs last - after lint, tests and fuzz have all passed against the older tree.
		- Fixed: stage 0 in both engines. Fetch, fast-forward when only behind, and stop when diverged. No upstream or an unreachable origin warns and carries on; `--no-sync` (`-NoSync`) skips it. Publish keeps its own pull as the late guard.
		- Note: the fast-forward is `--autostash`, so a dirty tree rides over it. Verified against throwaway repos in all five states, both engines.

- ✅ Documentation, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-152949

	- ✅ `design.md` stated the opposite of itself in two places, each time because a later decision was added without revising the earlier one.
		- Fixed: the Architecture bullet now says no *state* of its own, and names the accounts config as the one read-only exception. The `--no-fetch` bullet no longer calls itself offline, which is what the code and the offline rule below it already said.

	- ✅ The `Status: Passing` badge was a fixed image wired to nothing, so it read the same on a broken branch.
		- Fixed: removed. The pipeline is local, so there is no build to report; the remaining badges all resolve to something real.

	- ✅ README was about four times the length it should be, and the first runnable example was well over half way down.
		- Fixed: 535 lines to 273. Install and a worked example are now the first two sections, above the fold.
		- Fixed: the headline names folder-based accounts, which is the strongest thing in the release and went unmentioned.
		- Fixed: the long material moved to `accounts.md` and `workflows.md` rather than being deleted, so the README reads as a landing page and the depth is one click away.

	- ✅ README wording: a missing verb and a doubled letter in the workflow comparison, and a bullet with no full stop in Compatibility.
		- Fixed: all three, in the moved text.

- ✅ Code review 20260821 - a full pass over the whole tree, docs and installers included. Suite 773 -> 776, fuzz 269/0, parity 27/0, all green; every new check fails against the build or file that preceded its fix.
	- Opened: 20260821-174646
	- Closed: 20260821-182749

	- ✅ Code Review 20260821 item 1: the installers trusted GitHub's list order in the fallback release lookup.
		- The list is ordered by publish date, so a fix backported after a newer release would have resolved as latest and installed a downgrade. Both installers now take the highest version among the candidates; a numeric tie keeps the newer-listed one.
		- The bash one also stopped depending on GitHub pretty-printing the JSON - the scrape was line-anchored, and a packed payload matched nothing and then blamed rate limiting.
		- The new suite check runs the backport case against a stub serving a one-line payload; the previous installer fails it both ways.

	- ✅ Code Review 20260821 item 2: `Get-Help` on install.ps1 showed an auto-generated stub.
		- Comment help was binding to the first function. A blank line under the shebang and two above the function fix the binding, and a comment says to keep them.
		- Also gone: the one `+=`-in-a-loop, and the `iex` one-liner's inability to take flags is now documented in the README with the script-block form.

	- ✅ Code Review 20260821 item 3: `br prune`'s delete-time re-check forked git once per branch.
		- Now one `for-each-ref --merged` survey, same as the plan-time one, asked per target ref only while a candidate is still unconfirmed - so one branch costs one call and eight branches cost the same. The first cut cost one extra call at n=1, and the spawn counts caught it before it landed.

	- ✅ Code Review 20260821 item 4: no native Go fuzz targets existed.
		- Five now cover the pure parsers (remote URLs, forge tables, tags, config keys, URL masking); the pipeline hunts briefly past the seed corpus each full pass, capped like the builds.
		- They paid immediately: a "host" carrying whitespace was matched against account rules instead of reading as unparseable, and `account.<name>.` with no key half-parsed instead of landing with the ignored lines. Both fixed; the crashers are committed as regression seeds.

	- ✅ Code Review 20260821 item 5: error chains were stringified at the two places a usage error carries a cause.
		- `usageWrapf` keeps the cause on the chain for `errors.Is`/`As`, message text unchanged. `errorlint` and revive's `early-return` now gate what was until now only convention, and the dozen bare `_` discards each carry a one-line reason.

	- ✅ Code Review 20260821 item 6: three pipeline steps ignored the half-the-cores budget the builds keep.
		- `go test`, `golangci-lint` and vet/staticcheck now run under `BUILD_JOBS`; `go test` also gained `-race`, cheap on a tree with no goroutines and armed for the day one appears.

	- ✅ Code Review 20260821 item 7: `-q` and `-y` behaved identically, against their own help text.
		- The quiet variable was set and never read. Harness quieting now keys on `-q`; `-y` is unattended and full-volume, as documented. release.bash gained `-q` and hands it to the pipeline. Stage 0 also printed "0/6" in an eight-header run; it says 0/7 now.

	- ✅ Code Review 20260821 item 8: nothing existed to run the newest build the way the pipeline dogfoods it.
		- `cicd/utility/run-latest.ps1`: pooled timestamped copies outside PATH, week-long age-out, args forwarded, exit code returned. A rebuild never fights a running copy.
		- `cicd/utility/spawn-report.bash`: the newest recorded spawn counts with deltas, `--check` marker-gated like lint-report's, so the startup look at profiler output has a tool to call.

	- ✅ Code Review 20260821 item 9: docs swept.
		- Backlog: completed items moved out of Future, empty headings gone, older round numbering unified, example names and paths anonymized. README: sponsor badge and a short support section, the `br prune` exactness paragraph, install subsections in the TOC, the script-block install form, stage numbering matched to what the run prints, count fixes. design.md: table of contents, one duplicated sentence deduplicated. style-guide.md: a Go section for the conventions gofmt can't see. Remaining British spellings fixed, code_of_conduct.md matched back to its upstream text.

- ✅ Code review 20260819d - a third adversarial pass, aimed at what a run inherits from the machine it runs on.
	- Opened: 20260819-174102
	- Closed: 20260819-180413

	- Three defects, all in account selection or in what proves it. The first was found by the third: the suite went red on this machine the day it grew a real config of its own, which is what exposed the other two. Four new suite checks (699 -> 703) and two Go tests. Suite 703/0, fuzz 268/0, parity 27/0, spawn counts unchanged.

	- ✅ Code Review 20260819d item 1: the test suite reads the accounts of whoever runs it.
		- Cause: the blocks that test config discovery opt out of the file-scope `GITSBY_CONFIG` pin and fake `HOME` instead. `XDG_CONFIG_HOME` is tried before `HOME` and `APPDATA` after it, and neither was covered.
		- Note: harmless until this machine had a gitsby config of its own, at which point thirty checks failed against it. Not a false alarm to wave through either - it is the block that would catch an account regression.
		- Note: same shape as the symlink rule the round before - one side of a pair normalized and the other left alone.
		- Fixed: every discovery input emptied in one place, so `HOME` stays the candidate under test. Six env strings went through it. The thirty failures clear with no product change.

	- ✅ Code Review 20260819d item 2: an account named through `GITSBY_ACCOUNT` applies nothing unless it names a GitHub login.
		- Cause: the test was whether the account had a `ghAccount` key, not whether the file defined the account at all.
		- Note: an account can be a commit identity and an ssh key and nothing else, and a folder rule has always applied one - so asking for the same account by name got you less than not asking. The key fell back to whichever one ssh picks, which is the wrong-person push the feature exists to stop.
		- Note: it also reported the account's own name as the GitHub login the run acts as, which the push-identity gate would then compare against the real one and refuse on.
		- Fixed: a name the file defines is a configured account either way. Same correction where a repository sets `gitsby.ghAccount` itself - an account naming no login disagrees with nothing, and was being dropped along with its key.

	- ✅ Code Review 20260819d item 3: a byte-order mark eats the config file's first key.
		- Cause: the mark was left on the front of the first line, so the key it belonged to parsed as one nothing understands.
		- Note: the ignored-keys line printed the mark as part of the name, so the one diagnostic meant to explain the loss named a key that looks perfectly valid. Windows editors write a mark by default.
		- Fixed: stripped on the way in. One Go test and two suite checks.

- ✅ Code review 20260819c - a fresh adversarial pass over the rewritten Go, after the refactor settled.
	- Opened: 20260819-150417
	- Closed: 20260819-152223

	- Went in over the same ground as the round before it, looking for what a whole-file rewrite could have carried across unchanged rather than for anything the linters would see. gofmt, vet, staticcheck, golangci-lint and govulncheck were clean and the suite was 694/0 going in, so none of the four defects below is tool-visible. Five new suite checks (694 -> 699) and three Go tests, every one of them run against the build that preceded its fix.

	- Item 1 is the one that matters. The other three are narrower, and two of them were transcribed faithfully from the frozen 2.1.0 script rather than introduced here.

	- ✅ Code Review 20260819c item 1: a folder rule written through a symlink claims nothing, and nothing says so.
		- Cause: only the Windows build resolved link spellings. `git rev-parse --show-toplevel` answers with the tree's real path, so on Linux and macOS a rule spelled the way it was typed was compared against the resolved one.
		- Note: this is the failure the whole feature exists to prevent - the run acts as the wrong account while the listing looks right. `account list` made it worse: the folder is real, so its "this rule can never match" note stayed quiet and gave a false all-clear.
		- Note: a synced folder, a stable name pointing at a dated one, a home that is itself a link - all ordinary ways to write a rule.
		- Fixed: resolution through the nearest ancestor that exists now runs on every platform, not just Windows. A destination that does not exist yet still canonicalizes, which is what `repo clone` needs. Two Go tests and two suite checks.

	- ✅ Code Review 20260819c item 2: the hotfix "changes shipped code" warning goes missing unless you run it from the top of the tree.
		- Cause: the pathspec naming the shipped source was written bare, and git reads one relative to the current directory.
		- Note: from anywhere else it matched nothing, git exited 0 with no output, and the warning simply did not appear. Every existing check ran from the repo root, so all of them passed.
		- Fixed: anchored at the repo root with `:(top)`. Suite check added that runs the whole thing from a subdirectory.

	- ✅ Code Review 20260819c item 3: an account's commit name replaces one the repo had pinned for itself.
		- Cause: both identity keys were gated on a single question about `user.email`, so a repo that set only `user.name` locally passed the gate and had that name overridden.
		- Note: these entries reach git the way `-c` does, which outranks the local config - so the override was silent, and it contradicted the rule the same code states.
		- Note: transcribed from the 2.1.0 script, which has it too. Not a hotfix: the name is display, the email is what attributes a commit, and that half was already right.
		- Fixed: asked per key, in one call rather than two. A repo-local value is honored and the account fills in only what the repo left unset. Two suite checks.

	- ✅ Code Review 20260819c item 4: a two-line answer read as one string kept the interior carriage return.
		- Cause: `runOut` trims the end of the whole capture; only `runLines` trimmed each line. Four places split a capture themselves and skipped it - `pr ok` reading the PR's head branch among them, where the branch name would then match no ref anywhere.
		- Note: hardening rather than a reproduced failure - the tools involved write LF today. It was already the reason `runLines` exists, applied in some places and not others.
		- Fixed: one `splitLines` helper, used by `runLines` and by all four. Go test added.

	- Nothing came out of the rest. Naming, comments, the linter set, the optimization levels, the pipeline stages, the demo and both installers were gone over in the three rounds before this one and needed no change. Two housecleaning items did: a code-review bullet still filed under features, and a block of generator boilerplate left in `contributing.md`.

- ✅ Code review 20260819b - a full adversarial pass over the rewritten Go, plus a re-check of the ground the earlier rounds covered.
	- Opened: 20260819-120120
	- Closed: 20260819-145236

	- The rewrite of 20260818 moved every command onto one run struct and gave every failure an error to return, so this went looking for what that shifted rather than for what it left behind. gofmt, vet, staticcheck, golangci-lint and govulncheck are clean and the suite was 684/0 going in, so none of the five defects below is tool-visible. Ten new suite checks (684 -> 694) and two Go tests; seven of the twelve fail against the build or the tree that preceded them.

	- Most areas needed nothing this round - naming, comments, the linter set, the optimization levels, the seven pipeline stages, the demo, the housecleaning sweeps and both installers were all gone over in the two rounds before this one. Items 6 and 7 are what did come out of them.

	- ✅ Code Review 20260819b item 1: the pre-command fetch drops its connect timeout for the accounts that configure an ssh key.
		- Cause: the timeout was added only when `GIT_SSH_COMMAND` was unset, so a caller's own choice would be left alone. The account selector sets that same variable a moment earlier, from the config file's `sshKey` - so the test saw a value and stood down.
		- Note: it goes missing for exactly the setups it exists for. An unreachable host then hangs for the full TCP wait rather than three seconds, on every command that starts with a fetch, which is nearly all of them.
		- Fixed: the run records whether the variable was already set when it started, and one helper builds the environment for both places that reach origin - the fetch, and `repo connect`'s probe. A value the caller chose is still left exactly as typed.

	- ✅ Code Review 20260819b item 2: on macOS and the BSDs, `/dev/null` passes for a terminal.
		- Cause: only Linux and Windows asked the real question. Everything else fell back to "is this a character device", which `/dev/null` is.
		- Note: that test decides the fail-closed rule - with no terminal to confirm on, a mutating command refuses rather than prompt into the void. The end state stays safe, since the prompt reads end-of-file and aborts, but the message is the wrong one. macOS and FreeBSD are published targets now rather than someday ones.
		- Fixed: `tty_bsd.go` asks the same ioctl the Linux file asks, under this family's name for it. Still nothing installed. The character-device fallback now covers only platforms nothing here is built for.

	- ✅ Code Review 20260819b item 3: `~` in a config value expands to nothing on native Windows.
		- Cause: four places resolved it through `HOME`, which a shell sets and Windows does not.
		- Note: a `tokenFile = ~/...` then reads no token and falls back to gh's own account, and a `path = ~/...` folder rule matches nothing - which reads exactly like no rule at all. `accounts.md` says the `~/.config` location works on Windows too, and it did not.
		- Fixed: one helper, `HOME` first so a shell that sets one still wins. What it cannot resolve is left as typed, rather than turned into a path that names somewhere real.

	- ✅ Code Review 20260819b item 4: one branch git won't delete stops the whole of `br prune`.
		- Cause: the deletes go out in a single call, which is what made prune cheap. Git deletes the branches it can and still exits nonzero for the rest - one checked out in another worktree, most often - and that status was returned.
		- Note: the run then ended with some branches already deleted, origin untouched and no count printed, on the one command whose whole answer is a count.
		- Fixed: non-fatal, the way the remote half beside it already was. It counts what actually went, names what it could not delete, and holds that branch's remote copy back so nothing is left here with nothing behind it on origin.

	- ✅ Code Review 20260819b item 5: an account fragment left readable stays readable through every re-apply.
		- Cause: the file is written 0600, but a mode only applies where the write creates the file.
		- Note: the fragment names the account and points at the token file, and `account apply` is the command someone re-runs after tightening permissions.
		- Fixed: the mode is set explicitly.

	- ✅ Code Review 20260819b item 6: the lint and audit tools gate at whatever version this machine happens to have.
		- Note: a finding that appears - or stops appearing - on a tree nobody touched is usually a tool that moved rather than code that did.
		- Fixed: `GO_TOOL_VERSIONS` in `config.bash` records the four, read back with `go version -m` since they spell `--version` four different ways and one has no such flag at all. Stage 1 warns on drift. Not a gate and not an installer - this pipeline installs nothing.

	- ✅ Code Review 20260819b item 7: nothing published says the builds are reproducible.
		- Note: a checksum is worth having because anyone can rebuild the bytes it covers, and that was recorded in a comment in `config.bash` and nowhere a reader would look.
		- Fixed: a short Install subsection with the command, verified to produce the same bytes as the pipeline's own build.

- ✅ Code review 20260819 - the installers, back at the repo root. Six findings, none of which reach the binary.
	- Opened: 20260819-103518
	- Closed: 20260819-111554

	- Pass over the installers that came back to the repo root. All six findings are in the two new files; none of them reach the binary. The first two are the serious ones - they end a default install with no output at all.

	- ✅ Code Review 20260819 item 1: a wget-only box could never install.
		- Cause: the latest-release lookup declines the redirect and reads the tag out of the header, and wget answers a declined redirect with exit 8 whether or not it printed what was asked for. Under `set -e` an assignment carries its command's status, so the run ended there - after the lookup had already succeeded.
		- Note: the one-liner printed nothing and exited 8. No message, no fallback, nothing to go on.
		- Fixed: `|| true` on the lookup, which is the only thing that ever wanted the status.

	- ✅ Code Review 20260819 item 2: any curl failure did the same thing, and hid the fallback.
		- Cause: same assignment rule. DNS, a proxy, a rate limit - anything that made curl exit nonzero ended the run, so neither the API fallback nor the message that names rate-limiting could be reached.
		- Fixed: `|| true` on both, and on the API fallback beside them.

	- ✅ Code Review 20260819 item 3: `-Arch` refused the machines it was written to explain itself to.
		- Cause: detection assigned back to the parameter, and assigning to a parameter re-runs its own `ValidateSet`. On x86 or 32-bit ARM the detected value isn't in the set, so the binder error arrived instead of the message naming what the release does publish.
		- Fixed: detection lands in its own variable.

	- ✅ Code Review 20260819 item 4: `-Tag` had the same shape, one layer deeper.
		- Cause: the scraped tag assigned back to `$Tag` re-ran its `ValidatePattern`, which made the explicit check below it dead code. Through the API fallback the throw was caught and reported as rate-limiting, which it wasn't.
		- Fixed: resolved into its own variable, so the check that was written for it is the one that runs.

	- ✅ Code Review 20260819 item 5: persisting PATH on Windows flattened it.
		- Cause: `[Environment]::GetEnvironmentVariable` hands back the expanded PATH. Reading that and writing it back turned entries like `%USERPROFILE%\bin` into literals - permanently, on a PATH we only meant to append one directory to. Worse under `-System`, where the whole machine's PATH goes through it.
		- Fixed: read raw from the registry with `DoNotExpandEnvironmentNames`, written back with the kind it already had.

	- ✅ Code Review 20260819 item 6: the captive-portal check read the whole binary to look at one byte.
		- Fixed: one byte off the stream.

	- ✅ Code Review 20260819, coverage: nothing exercised the release lookup, which is why items 1 and 2 got through green.
		- Fixed: two checks stand the network up as stubs - a curl that always fails, and a wget-only PATH where the stub prints the header and exits 8. Both fail against the build before the fix. The two PowerShell findings need the hardware or the network to reproduce, so they are pinned in the source the way the SHA256SUMS decode already is. Suite 613 -> 617.

- ✅ Code review 20260819a - the whole tree, top to bottom. Forty-three numbered items, plus the pass that preceded them.
	- Opened: 20260819-105954
	- Closed: 20260819-144325

	- Item 30, the last one open and the only one that needed a decision first. Fourteen new checks, nine of which fail against the tree that preceded them; the suite went 668 -> 682. That closes the round at 43 of 43.

	- ✅ Code Review 20260819a item 30: Windows binaries carry no icon and no version details.
		- Needs a Windows resource (.syso) beside the source. Two ways in: `goversioninfo` from a checked-in JSON template plus an .ico, which is the standard route and is well tested; or writing the COFF resource ourselves, which keeps the zero-dependency character but cannot be proved right from here - a malformed one links cleanly and fails on the machine that runs it.
		- Decided: `goversioninfo`, installed outside the tree, probe-gated in the pipeline and required by `release.bash`.
		- Done. `cicd/utility/gen-winres.bash` writes one `.syso` per published Windows target from a spec it generates, and the two are committed - they are linked into binaries whose checksums we publish, so rebuilding a release from its tag must not need a tool installed.
		- Which is why they carry the last released version rather than the working tree's describe output: a file that changed every commit could not be committed. A release stamps them with the version it is cutting - in phase 1 for the assets, then restored, and again in phase 2 where it lands in the bump commit beside the changelog heading.
		- `assets/gitsby.ico` is a committed asset too, regenerated by hand from `logo.png` (`gen-winres.bash --icon`) when the logo changes. Six sizes: 16/32/48 stay BMP so pre-10 Explorer draws them, 64/128/256 are PNG quantized to 256 colors - 134 KB down to 48 KB for a difference the eye cannot find at icon size.
		- Verified rather than assumed: both Windows targets link the resource and no other platform does, two cold-cache Windows builds are byte-identical with it in place, and the string and numeric version fields both read 2.1.0 out of the built `.exe`.

	- The documentation, 34-41. The suite went 666 -> 668.

	- ✅ Code Review 20260819a item 34: batching the branch deletes in `br prune` is the largest speed win available, and it changes the output.
		- One push per branch, each forking three processes. Eight branches cost 24 of the command's 81.
		- Deleting them in one call collapses the per-branch status and warning lines into one, so it needs a decision and a suite carve-out before it can be done.
		- Done, and the call was made here rather than deferred: the win is large and the output change is smaller than the finding suggested - one plan line and one status line instead of eight of each, which reads better. Measured on eight branches: 77 spawns down to 42, with the cached branch lookups from item 16 in the same figure. The local re-check still runs per branch before anything is handed to git, and a partly-failed remote delete counts what actually went rather than writing the batch off. Parity needed no carve-out.

	- ✅ Code Review 20260819a item 35: ten statements in the public docs are no longer true.
		- The command count is one short in three places, including the repo blurb.
		- The README and contributing both send a new contributor to a branch that has no Go code on it.
		- The README still describes a suite that runs against two implementations.
		- design.md documents a folder, a test leg and a pipeline engine that were all removed, and its release section describes work that shipped, wrongly.
		- Two smaller ones: a flag that only ever existed on the deleted engine, and a command spelled the old way.
		- Fixed, all ten: the counts (ten, and 23 with subcommands), the branch a contributor is sent to (named nowhere now - `git clone` then `cd src-go` is the whole of it), the suite that ran against two implementations, design.md's folder list, testing section and release section, `bin/gitsby` in the style guide, `-NoSync` in contributing, and the old command spelling in the one-liners. The dogfood caveat is in the README too - those destinations are one machine's paths.

	- ✅ Code Review 20260819a item 36: the Install section has no sub-headings.
		- Nothing in the contents leads a reader to "is this in my package manager", though the answer is written a few lines down.
		- The development section does not say the pipeline commits and pushes at the end, which will surprise someone running it on a fork.
		- Fixed: Install now has "Is it in my package manager?" (the answer was already there, four paragraphs down), "The one-liners", "Where it goes", "Without the installer" and "Coming from 2.x". The pipeline is described as eight numbered steps, and step 8 says in bold that it commits and pushes.

	- ✅ Code Review 20260819a item 37: several of the strongest features are buried.
		- One static binary with nothing alongside it is the third bullet of a compatibility list.
		- That every mutating command shows the exact git commands and asks first is the main safety argument and appears once, near the bottom.
		- `repo create` listing what it is about to publish, the offline behavior, and `account apply` teaching plain git the same rules are each a clause inside a longer paragraph.
		- Nothing anywhere says gitsby keeps no state of its own.
		- The repo blurb needs the same count fix, a homepage, and its topics refreshed - it still says bash and powershell.
		- Fixed in the docs: the three arguments - it shows its work, it keeps no state of its own, it is one file - are their own short list in "What it is", where nothing else competes with them. The offline behavior, the publish list and `account apply` each became a point of their own instead of a clause. The tagline names the show-and-ask promise.
		- Left to do by hand: the repo blurb, homepage and topics are GitHub settings rather than files here, and changing them edits the public repo page. `gh repo edit --description ... --homepage ... --add-topic go --remove-topic bash` is the one command.

	- ✅ Code Review 20260819a item 38: design.md has no goals and non-goals section, and no header.
		- The non-goals are the most interesting thing about the project and they are scattered across three sections and another document.
		- Everything else about the file is right. It is a decision log with rejection rationale recorded inline, which is the correct form here - do not restructure it.
		- Fixed: a "Goals and non-goals" section, with the seven non-goals gathered from the three places they were scattered across, plus a short note on what kind of document this is. Nothing else was restructured - it is a decision log and that is the right form for it.

	- ✅ Code Review 20260819a item 39: twenty-five finished items are still sitting in the open sections.
		- The Bugs section reads as fourteen open bugs, all of which are done.
		- The review items also want their outcome bullet labeled, so the finding and the fix can be told apart at a glance.
		- Fixed: 25 finished items moved into the matching Done subsections, and Bugs now says "None open" rather than reading as fourteen open bugs. Every review item's outcome bullet is labeled - "Fixed:", "Done:", "Decided:" - so the finding and what happened to it can be told apart at a glance.

	- ✅ Code Review 20260819a item 40: about twenty British spellings across the docs, scripts and code comments.
		- Not in the code of conduct or contributing - those reproduce upstream text and should stay as published.
		- Fixed: 23 of them across the docs, the pipeline scripts and the demo notes. `code_of_conduct.md` and contributing.md's DCO notice are untouched - both reproduce published text. Two of the 23 are in the shared `cicd/utility/include/` files, so a future re-sync from their source could bring them back.

	- ✅ Code Review 20260819a item 41: five paragraphs run long enough to be hard to scan.
		- The worst is 620 characters. All five are ideas that want to be bullets.
		- Fixed, all five plus the tagline: each became two or three short paragraphs, or a lead-in and bullets. The longest line left in the published docs is the tagline, and that one is an HTML cell rendering as three separate lines.

	- The pipeline, 17-18 and 26-32 (bar 30), plus 42 and 43. Eleven new checks, each verified against the pipeline that preceded them; the suite went 649 -> 666.

	- ✅ Code Review 20260819a item 17: the lint summary reports warnings on a perfectly clean run.
		- Its filter matches the test harness's own check labels, so a green pipeline reports seven warnings that do not exist.
		- A warning that fires when nothing is wrong is worse than no warning.
		- Fixed: the harness lines are excluded by shape (`ok:` / `FAIL:`) rather than by wording, so a check label about warnings stops reading as one. A clean log now reports CLEAN, and a real finding still reports.

	- ✅ Code Review 20260819a item 18: `--quick` still cross-builds three platforms.
		- It skips fuzz and the gif, which are not the slow part.
		- Fixed: `--quick` narrows the dogfood list to the native target. The other two cross-builds were the slow part it was meant to be skipping.

	- ✅ Code Review 20260819a item 26: the published binaries cannot be rebuilt to the same checksum.
		- Version control stamps go into the binary, and the release builds its assets before it cuts the tag - so the published binaries carry the previous revision and nobody can reproduce the checksums we publish.
		- Also wants the build id cleared, the native build built the same way as the cross-builds, and the toolchain pinned. Once it holds, say so in the README.
		- Fixed: `-buildvcs=false`, `-buildid=` and `CGO_ENABLED=0` on every build site, from one place in config.bash. Verified: two builds from a cold cache are byte-identical, and `go version -m` shows no revision. The ordering worry dissolves with the stamps gone - the changelog bump does not touch the source, so a phase-1 asset is the tagged commit's asset. The release toolchain is named in config.bash, since go.mod's line is a minimum rather than a pin.

	- ✅ Code Review 20260819a item 27: no build step limits itself to half the cores.
		- The compiler defaults to all of them, in every build and in the eight-target release loop.
		- Fixed: `BUILD_JOBS` is half the cores rounded up, and `-p` is on all four build calls.

	- ✅ Code Review 20260819a item 28: nothing in the pipeline looks at the standard library for known problems.
		- With no third-party dependencies, that is the only library code there is to check.
		- Fixed: `govulncheck` in stage 3, probe-gated like staticcheck. It runs even under `--quick` - it is a lookup, not a workload.

	- ✅ Code Review 20260819a item 29: no profiling step exists.
		- A flamegraph would be the wrong instrument here - the program spends its life blocked waiting on git, so a sampling profile is a flat wall with no leaders.
		- What carries signal is counting spawns per command against a fixture repo, and failing on a regression. The rotation and the seen-marker patterns already exist and can be reused as they are.
		- Done as spawn counting, per the recommendation: `cicd/utility/spawn-count.bash` measures eight commands against a restored fixture (origin included), compares with the newest previous run, and fails on a rise beyond a small tolerance. GFS-rotated like the lint logs.

	- ✅ Code Review 20260819a item 31: `-q` reaches the publisher but not the three test harnesses.
		- None of them accepts an option at all, so a quiet run still prints every one of 617 check lines.
		- Fixed: all three take `-q`, and the engine hands it on for an unattended run. Header, failures and totals stay.

	- ✅ Code Review 20260819a item 32: `--target=` and `--release=` are not accepted with an equals sign.
		- Fixed: both spellings of every option that takes a value.

	- ✅ Code Review 20260819a item 42: no script exists to run an older build alongside the current one.
		- Worth less here than in the projects it comes from: gitsby exits immediately, so nothing is ever held open. The real use is keeping timestamped builds around to bisect a behavior change.
		- Done: `cicd/utility/keep-build.bash` archives the current binary with a timestamp, lists what is kept, runs one by number, and diffs one against the current build on the same arguments. GFS-rotated.

	- ✅ Code Review 20260819a item 43: the demo script file is stale in two ways beyond the renamed commands.
		- It points a future editor at the deleted Windows engine, twice. Fix it in the same pass as the regeneration.
		- Fixed: the notes no longer point at the deleted Windows engine, and the scenario uses the current command names, so the next render publishes those rather than the old ones. The regeneration itself is still pending - it needs a full pipeline run.

	- The installers, 12-15 and 33. Ten new checks, each verified against the installers that preceded them.

	- ✅ Code Review 20260819a item 12: the installers cannot find a release that is only a prerelease.
		- Both the main route and the fallback ask the same endpoint, and that endpoint skips prereleases. So there is no fallback.
		- The failure message blames rate limiting, which sends anyone debugging it the wrong way.
		- Latent today, live the first time a version ships as a prerelease.
		- Fixed: the fallback lists the releases instead, newest first, taking the newest full one and saying so when only a candidate exists. The failure message names rate limiting as one possibility among several, and points at `--tag`.

	- ✅ Code Review 20260819a item 13: `install.ps1` has no `--help`, and the README tells people to use it.
		- Fixed: `-Help`, plus `--help` recognized before the binder sees it - which is what the README documents and what anyone types.

	- ✅ Code Review 20260819a item 14: `install.ps1` can report success over a binary that failed to run.
		- The verification step's exit code is never read, and a native command's failure does not stop the script on its own.
		- Fixed: `$LASTEXITCODE` is read, and a binary that will not run is reported as that rather than as a finished install.

	- ✅ Code Review 20260819a item 15: both installers write straight to the final path.
		- An interrupt mid-copy leaves a truncated executable in place that passed its checksum under a different name.
		- Re-installing over a copy that is currently running fails on both platforms.
		- Staging in the destination directory and renaming over the target fixes both at once.
		- Fixed: both stage in the destination directory and rename over the target. On Windows the incumbent is renamed aside first, since Windows will not overwrite a running executable but will rename one.

	- ✅ Code Review 20260819a item 33: decide whether `install.ps1` should run on Windows PowerShell 5.1.
		- It refuses below 7 on purpose, and the reason is sound. But 5.1 is what a fresh Windows install actually has, so the documented one-liner fails there.
		- The syntax is already 5.1-clean. Lifting it needs a fallback for three variables that do not exist in 5.1, one parameter spelled differently, plus forcing TLS and basic parsing.
		- Decided: yes. 5.1 is the machine most likely to be installing this for the first time. The three variables get a fallback, TLS 1.2 is switched on, every request asks for basic parsing, and the byte read is spelled each version's way. `PSUseCompatibleSyntax` against 5.1 now gates in the pipeline.

	- The defects, 1-20. Eighteen new suite checks, each verified against the build that preceded the fix; the suite went 617 -> 636.

	- ✅ Code Review 20260819a item 1: a second `account apply` deletes the rules and then gives up.
		- Two accounts claiming the same folder produce the same rule key twice. The first removal takes both, the second finds nothing, and git's "nothing to remove" is read as a failure.
		- End state is worse than before it ran: no rules at all, and an error.
		- Nothing warns that two accounts claim one folder in the first place.
		- Fixed: the key list is deduped, and git's exit 5 ("nothing to remove") is read as the end state it is rather than as a failure. `account list` now names any folder more than one account claims.

	- ✅ Code Review 20260819a item 2: gitsby and plain git can resolve the same folder to different accounts.
		- The two tie-breaks disagree when two accounts declare the same path. Gitsby goes by declaration order, git goes by what sorts last.
		- That disagreement is the exact thing `apply` exists to prevent.
		- Fixed: the plan is ordered by declaration index, reversed, so the rule gitsby keeps is the last one git sees. Checked both ways in the suite.

	- ✅ Code Review 20260819a item 3: a bare repo, or a `.git` directory, passes the in-a-repo check.
		- The question is asked of a command that answers in text and exits zero either way.
		- `status` there prints a full state block ending in "working tree clean", which it has no business claiming. `pullcom` prints its whole plan, gets confirmed, then dies in git.
		- Fixed: one `rev-parse` call answers all three questions in text; a bare repo and the `.git` directory are each refused by name, whatever the command.

	- ✅ Code Review 20260819a item 4: a token read from a file is never checked against the account it claims.
		- The name comes from the config key, so a stale token file reports the right name and pushes as the wrong one.
		- That is precisely the mistake the identity block exists to catch. With no `gh` installed at all it still names an account.
		- Fixed: a token from gh's own store still short-circuits; one from a file is probed with the token exported, and the block says either who it really belongs to or that it couldn't be checked.

	- ✅ Code Review 20260819a item 5: `--any-identity` quietly drops the commit identity and key.
		- Account selection is skipped entirely, but the Account line still names the account as if it had been applied.
		- Commits get authored by whatever git falls back to. The help only mentions the key mismatch, not the authorship.
		- Fixed: the Account line says the selection was skipped and what that leaves in place. Behavior is unchanged - what it did was never the problem.

	- ✅ Code Review 20260819a item 6: `raw` names an account for a repo you only cloned.
		- The gate accepts the remote-owner guess, so cloning someone else's repo prints "acting as <them>" - untrue, nothing was applied, and it tells a single-account user the feature exists.
		- Fixed: the same test the identity block uses, so nothing is claimed for a name merely inferred from the remote's owner.

	- ✅ Code Review 20260819a item 7: `br prune` tries to delete remote branches while offline.
		- `br merge` holds its remote delete back; prune has no such check.
		- Each failed push is reported as "already gone", blaming the branch for a network problem, and the summary reads as if it finished.
		- Fixed: the remote half is skipped while origin is unreachable and says so by name; the local deletes still happen.

	- ✅ Code Review 20260819a item 8: `release` in a repo with no origin cuts a tag nobody can fetch, silently.
		- The offline check never trips, because with no remote there is nothing to find unreachable.
		- `sync` gets this right and says so; release just ends on "Done."
		- Fixed: refused up front, naming `repo connect`. No tag is cut.

	- ✅ Code Review 20260819a item 9: the pre-command fetch may refresh a remote nothing else reads.
		- With no remote named, git follows the branch's own tracking remote. Every existence check afterwards reads origin.
		- Fixed: the fetch names origin. Caught by a repo whose branch tracks a second remote.

	- ✅ Code Review 20260819a item 10: the ssh-login cache ignores which remote it was asked about.
		- One slot, no key, three different callers. Reachable through `repo connect` from outside a repo, where it produces a mismatch warning about an origin that does not exist.
		- Fixed: keyed by remote URL. No dedicated check - reaching it needs three remotes and a stubbed ssh in one run, and the shape is the same one the other caches already use.

	- ✅ Code Review 20260819a item 11: `br switch` assumes a single remote.
		- With two remotes carrying the same branch name git refuses to guess, and the up-front check does not notice because it only ever looks at origin.
		- Fixed: one helper decides how a branch gets checked out, and the plan prints what the command will run. Applies everywhere a remote-only branch can be checked out, not just `br switch`.

	- ✅ Code Review 20260819a item 16: an unresolvable default branch is re-derived on every ask.
		- The two branch lookups are the only cached values in the codebase with no "we already asked" flag, so a repo where the answer is empty repeats the whole five-command ladder each time.
		- Measured: 38 processes for one `status`, 25 of them the same five commands over and over.
		- Fixed: every cached answer now pairs a value with a "we already asked" flag, so an empty answer is remembered like any other. Came free with the shape work in item 21.

	- ✅ Code Review 20260819a item 19: the hotfix warning watches a folder that no longer exists.
		- It was written when the deliverable was `bin/gitsby`. A hotfix to the code that actually ships gets nothing.
		- Fixed: it watches `src-go/`, named once beside the reason. The two suite checks were pointed at the same place.

	- ✅ Code Review 20260819a item 20: file permissions are never checked, and one directory is created wide open.
		- A token file readable by everyone loads without comment. ssh and gh both refuse or warn on that.
		- The folder holding the per-account identity fragments is created 0777 and relies entirely on umask.
		- A malformed inherited `GIT_CONFIG_COUNT` is read as zero, which half-overwrites whatever the caller set up. That variable is injected by the terminal here, so it is not hypothetical.
		- Fixed: the fragment directory is 0700 and the fragments 0600; a token file other users can read is called out by name; a GIT_CONFIG_COUNT that isn't a count stops the run instead of half-overwriting the caller's block.

	- The Go shape items, 21-25. One problem wearing four hats: gathering the run's state into a struct is the change the other three followed from.

	- ✅ Code Review 20260819a item 21: the Go reads as a shell script transcribed into Go syntax.
		- State is passed through about 120 package-level variables. Several functions take nothing and return nothing, and work only by mutating them.
		- Not one function returns an error. Failure is a hard exit called from inside leaf helpers, which is also why nothing can be unit tested.
		- Records are packed into tab-delimited strings and re-parsed to sort them.
		- All of that is one problem wearing four hats. Gathering the run's state into a struct passed to the command functions is the change the other three follow from.
		- Note against the old builds: only input and output parity matters now, so mirroring their structure is not a reason to keep any of this.
		- Done: the run's state is a struct passed to the command functions; every failure returns an error and main is the only place that exits; the tab-delimited sort became typed records. 4529 lines rewritten, output byte-identical (617/268/27 all green, parity unchanged).

	- ✅ Code Review 20260819a item 22: there are no Go tests at all.
		- The whole suite is external. The pure string functions - remote parsing, config values, path canonicalization, tag matching - have a lot of edge cases and nothing exercises them directly.
		- Done: unit tests for the parsing, the config and folder matching, the URL shapes, the version bump, the includeIf ordering and the output framing. `go test ./...` gates in stage 2.

	- ✅ Code Review 20260819a item 23: add a linter config so the review findings become gates.
		- gofmt, vet and staticcheck are clean and gated already. A config file would add the checks that caught the rest: unchecked errors, shadowed builtins, and the naming convention below.
		- Done: `src-go/.golangci.yml` - errcheck, ineffassign, predeclared, unconvert, revive (var-naming, redefines-builtin-id, and three flow rules). Probe-gated in stage 1 like staticcheck.

	- ✅ Code Review 20260819a item 24: internal names do not follow Go's convention for initialisms.
		- Twenty-six of them, all unexported, all internal. No effect on output or arguments.
		- Done: URL, SSH and HTTPS spelled the Go way throughout. No effect on output or arguments.

	- ✅ Code Review 20260819a item 25: five discarded errors want either handling or a reason.
		- Three of them set environment variables that decide the whole account selection.
		- Done: the three that decide account selection now stop the run; the temp-dir removal and the readability probe say in one line why they discard theirs.

	- Also in the same round, and unnumbered: the defects a first pass turned up.

	- From the first 20260819a pass. Everything below was checked against the code, not inferred. gofmt, vet, staticcheck and the suite (617/0) are all clean, so none of this is tool-visible.

	- ✅ Twenty regression checks reported on the terminal they were run from, not on the code.
		- The harnesses pinned git's config files and gitsby's own config file. Two inputs outrank all of those and arrive from any ordinary working terminal: `GIT_CONFIG_COUNT` with its numbered keys beats every config file, a repo-local one included, and an inherited `GH_TOKEN` is what a gh call reports back.
		- Ten checks per implementation, the same ten on both, which is what showed it was not a port difference. Five gh checks that can only pass when no token is held, and five identity checks that read a commit address back through a config file.
		- Nothing was wrong with the product. The same suite and the same builds pass standalone, and pass under the pipeline once the environment is clean.
		- Fixed in all three harnesses. `fuzz.bash` was also the only one never pinning gitsby's config file.
		- Pinned in the source of each harness. The two runtime companions are labeled as regression guards: on a clean machine they pass against a harness that isolates nothing.

	- ✅ `demo-repo.bash` removed whatever directory it was pointed at, without checking whose it was.
		- It took a root path as its first argument and `rm -rf`'d it before doing anything else. A mistyped or inherited argument took whatever lived there, and the script then reported success.
		- Reproduced against the previous version: a directory holding an unrelated file was passed as the root, and came back empty with an exit code of 0.
		- Fixed by stamping the directories it builds. Only a stamped one is removed; a relative path, the filesystem root, a symlink and anything containing `..` are all refused up front.
		- Checked against the previous version. The filesystem-root case is pinned in the source rather than run, since running it against a build without the guard is `rm -rf /`.

	- ✅ Every other recursive or forced removal now fails closed on an unset variable.
		- All of them name a path the script itself created, but they were spelled so that an unset variable would have widened the target rather than stopped it.
		- Ten sites across both installers, the pipeline engine and all four harnesses. The suite checks the whole set, so a new unguarded one is caught.

	- ✅ The publish preview leaked its throwaway git directory when a run was interrupted.
		- The Bash build removed it on the way out of the function that made it, so a Ctrl-C while the preview was still on screen stranded an empty directory in temp. The PowerShell build already covered this.
		- Moved to the exit path, which already runs on interrupt. Checked by driving the cleanup hook directly - a real Ctrl-C could not be staged, since Git Bash defers the signal until the native child returns.

	- ✅ Twelve regression checks were testing nothing on Windows.
		- The suite handed PowerShell its own MSYS paths. .NET has no mount table, so `/tmp/x` and `/c/x` were read against the current drive root - `Set-Location`, the script lookup and `ReadAllBytes` all failed and the commands under test never ran.
		- Seven reported red. The other five passed because they forbid something that also never happened, which is the worse half. Among them the guard for the working-directory bug, which had been guarding nothing.
		- Fixed with an `fWinPath` helper, the same conversion the folder-account block already needed. Two smaller ones alongside: Git Bash rewrites a unix-absolute argument before the native pwsh sees it, so the `-Ref` refusal was being triggered by the wrong rule; and the system install location is the platform's own, not `/usr/local/bin`.
		- Windows now runs 850/0, matching Linux. Checked the repaired guard fails against the code that predates the working-directory fix, so it discriminates rather than merely passing.

	- ✅ The identity probe ignored the ssh key git was configured to push with.
		- It ran a bare `ssh`, so a repo selecting its key through `core.sshCommand` was reported as the default key's account. Where that matched gh's account the mismatch check passed with both halves wrong - green in exactly the setup it exists for.
		- Fixed to follow git's own precedence, `GIT_SSH_COMMAND` then `core.sshCommand`. The identity line takes the key file from the same source, so it can't name the right account beside the wrong key.
		- Same override was overriding the key on `fetch` and the remote probe, which made a private repo reachable only via that key look like being offline.

	- ✅ The PowerShell build died on the identity line whenever no ssh command was configured.
		- `Get-GitSshCommand` returns a list, but PowerShell unwraps a one-element return to a bare string - and under StrictMode, reading `.Count` off a string throws. One element is the ordinary case: a plain `ssh` with nothing configured.
		- So any repo with an ssh remote and no `core.sshCommand` failed with "The property 'Count' cannot be found", which is most of them. The Bash build was never affected; bash arrays don't unwrap.
		- Found by running the suite's PowerShell leg on Windows, which until now had only ever run on Linux. It would have failed there too - it had simply never been run since the identity work landed.

	- ✅ gh acted as whatever account was last switched to, regardless of who owns the remote.
		- Now picks the owner's account for the run when gh already holds it, via `GH_TOKEN`, leaving gh's active account alone. Only when the owner can be named and the token is held - an org or someone else's repo is left untouched rather than refused.

	- ✅ On Windows, a local-path remote was read as an ssh host named after the drive letter.
		- `C:/path/to/repo.git` matched the `host:path` shape, so every command ran an ssh identity probe against a machine called `C` and reported an account for it.

	- ✅ PowerShell: a joined `-Config=FILE` failed silently.
		- PowerShell can't bind a joined option through `-File`. Ahead of a command it ate the next word as the value, so `br list` arrived as `list`; after one it overflowed the positional slots.
		- The first case printed the help and exited 1, which `-q` silenced entirely - the reported symptom was a command that appeared to do nothing.
		- Now refused by name from any position, naming `-Config FILE` and `-Config:FILE`. Bash keeps taking the joined form, and so does `raw`, which reads the real command line.

	- ✅ `--config ""` silently used the default config instead of refusing.
		- The check asked whether the value was non-empty, not whether the option was typed, so an empty one was indistinguishable from never passing it.
		- That fell back to the default file, which decides the account - a script whose variable came out empty would push as the wrong identity and say nothing. Both builds.
		- An empty `GITSBY_CONFIG` still falls through on purpose: an unset environment variable and an empty one are the same thing, unlike a typed option.
		- Found by the new fuzz vectors on their first run.

	- ✅ `repo clone` refused to re-run, and `repo connect` refused a matching URL, on Windows.
		- Git stores a local-path remote in the platform's own spelling: hand it `/c/tmp/x` and it gives back `C:/tmp/x`. Both commands compared their own argument against git's copy as plain text, so the same directory read as a different one.
		- Both now compare local paths as paths. These were the two long-standing Windows-only failures in the suite.

	- ✅ The PowerShell installer never verified the checksum, and said the release had none.
		- Found by running both documented one-liners against the current release: the Bash one reported the checksum verified, the PowerShell one reported no `SHA256SUMS` for the same release, which does publish one.
		- Cause: GitHub serves that file as binary, and PowerShell returns a response body as raw bytes for anything it doesn't treat as text. Read as lines, bytes match nothing, so no checksum was found and the download was installed unverified.
		- The message made it look settled rather than broken, so the default install had gone unverified since the check was added. The Bash installer was never affected.
		- Fixed: the body is decoded before it is read. Verified against the published release - the checksum is found, compared, and matches the installed file.

	- ✅ Every install command in the README 404s, because `main` is still the 2022 tree.
		- `main` holds no `install.bash`, `install.ps1`, `install-dev.*` or `bin/gitsby.ps1`, so all six documented one-liners fail at the download.
		- Cutting v2.0.0 fixes it outright: the merge to `main` puts the files there, and `releases/latest` stops resolving to the 2022 `v1.0.1`, which is a dead end for the default install path (that tag predates the `bin/` layout).
		- Until then the working incantation is the `dev` URL plus `--release dev` / `-Release dev`. Left undocumented on purpose rather than pointing strangers at `dev`.

	- ✅ The SSH identity line named the local login instead of the account being acted as.
		- It asked `ssh -G` about the bare host. With no user in the target, ssh answers with the OS login name, so a push as the second account displayed as `<os-login>@github.com`.
		- That value is neither of the two real ones: the connect user is `git`, and the account is whatever the key authenticates as. On a personal machine it looks plausible enough to be believed, which is worse than showing nothing.
		- The probe now uses the connect target, so an explicit user in the remote URL is honored the way git honors it. Host alias resolution is unaffected - the user part only overrides `User` in `~/.ssh/config`.
		- The line also leads with the account now, resolved by asking the host. That is what it existed to answer; the connect user is identical for every GitHub account, and the key shown is only ssh's first readable candidate, not necessarily the one that authenticates. Offline it says `unknown` rather than guessing, and skips the round trip.
		- Every other test uses a local-path origin, which has no ssh identity, so the whole line had shipped untested. It now has a fake ssh that reproduces the real defaulting behavior.

	- ✅ A byte-order mark on the three PowerShell files broke both installer one-liners and direct execution.
		- `irm` keeps the BOM, so `iex` and `[scriptblock]::Create` saw it glued to the shebang and the first line stopped being a comment. Both documented one-liners failed for every user, on every platform.
		- The same BOM sat ahead of `#!` in `bin/gitsby.ps1`, so `./gitsby.ps1` fell through to the shell instead of running.
		- `bin/gitsby.ps1` already carried a suppression saying a BOM would break the shebang, so it had been there against the file's own stated intent since the files were written.
		- The tests couldn't see it: they read the source with `Get-Content`, which drops a BOM silently. They now decode the bytes, and each file's first two bytes are checked.

	- ✅ `install.ps1` sent a failed download to the Bash installer, which fails the same way.
		- Both resolve the same stale `releases/latest`, so the advice was a loop. It names `-Release dev` now, matching what `install.bash` already said.

	- ✅ An unreachable remote did not make the parking push safe.
		- `update` and `sync` degraded properly, but `br create`, `br switch`, `br hotfix`, `pr create` and `release` all failed on `git push` with raw git text.
		- Split by what each command is for. The ones that mean something locally now skip the push and say so, naming the branch and `sync` from it as the way to publish later. The ones that exist to publish - `sync`, `pr create`, `pr ok`, `release` - refuse up front, before the plan promises a push, and name what to do instead.
		- `br land` needed more than a skipped push: with the merge unpublished, origin's copy of the work branch is its only ref to those commits, so the remote delete is held back too. The hotfix back-merge has the same shape - it merges `origin/main` normally, which unpublished is the stale one, so it falls back to the local branch.
		- Decided against making `--no-fetch` mean this. The flag declines the incoming round trip, which is a perfectly good thing to want against a reachable remote, and the suite itself uses it that way throughout. Offline is a state the pre-command fetch discovers, not a flag.

	- And the shape-and-process half of it.

	- ✅ The demo gif demonstrates an account changing on a partial folder match higher in the path.
		- Folder-based accounts are the headline feature and the demo never showed them. Three scenes were added to the end of the existing demo rather than made into a second gif, so the one loop tells the whole story.
		- The throwaway world now has two repos in trees that differ from their first folder down, and a gitsby config matching on `github.com/acme-corp` and `github.com/mika-rivers`. Different roots are the point: a shared root would not show that the match is a run of folder names rather than a prefix.
		- The closing scene runs the same command in the second tree, with no flags and nothing configured per repo, and the account has changed. The six scenes before it were already acting as the work account and now say so on their identity line.
		- The prompt shows the folder the command runs in. A demo about folders that hides the folder proves nothing.
		- The identity the accounts set is deliberately not exported into the demo's environment. It had been, and an exported `GIT_AUTHOR_EMAIL` supplies exactly what the folder rules are meant to supply - the demo would have been showing something it had not proved.
		- 2632 frames, 122.5 seconds, 11.06 MB, up from 2007 / 84.9 s / 9.97 MB. Read time is free; the growth is the three scenes' own output and typing.

	- ✅ The demo gif has a readable script, and its tooling lives in one place.
		- What the demo shows was only ever recorded as a scenario table of captions, commands and timing numbers, next to a renderer full of constants. Changing it meant reading both.
		- `cicd/utility/demo/script.txt` now describes it in plain language: the format, the set, the throwaway repo, and one section per scene with its caption, its typed line and how long it holds. That file is the one to edit.
		- The scenario file stays as the machine version and points at it. Nothing parses the script - keeping the two in step is deliberate habit, not a mechanism.
		- The renderer, the repo builder and the scenario moved from `cicd/` and `cicd/utility/` into `cicd/utility/demo/` alongside it. Both pipeline engines needed their paths and lint globs updated by hand, since neither discovers files.

	- ✅ The fuzz suite can pass on Windows.
		- Three vectors clone into a directory named `*`, `?` or `v*`. Win32 forbids those characters in a path, so native git cannot create such a work tree at all and the check could never pass there.
		- They are skipped on Windows now, with a line saying why. The suite already skipped four PowerShell vectors there for the same kind of reason.
		- Not a gitsby bug: MSYS `mkdir` will happily make one of those directories, which is what makes the first guess wrong.

	- ✅ The PowerShell build verified on Linux.
		- It had shipped without ever being executed there, which was one of the stated requirements. Run against the full suite on Debian, both legs.
		- One check failed, for an environment reason rather than a real one: with `gh` absent, `pr create` refuses over the missing tool before it gets to the offline refusal the check is about. It uses a stub now, so it tests the same thing everywhere.

- ✅ Code review 20260818 - the first full review of the Go code. Eighteen items: thirteen defects, five of shape and speed.
	- Opened: 20260818-181424
	- Closed: 20260819-124128

	- From a full review of the Go code, 20260818. gofmt, vet, staticcheck and the suite (530/0) are clean; these are what the tools don't see. Several are inherited from the frozen bash build - latent there, but live in the shipping binary.

	- ✅ Code Review 20260818 item 1: `pr ok` can destroy never-pushed commits.
		- Standing on the PR's own branch with no upstream configured, the lost-work guard asks `@{u}` and gets silence, so it passes. gh then merges what origin has and deletes the branch with `-D`.
		- The stronger per-branch check only runs when standing somewhere else.
		- Inherited from the bash build.
		- Asked of the PR's own branch by name wherever you are standing. `@{u}` answers nothing at all for a branch pushed without `-u`, which is the one arrangement that lost the commits.

	- ✅ Code Review 20260818 item 2: `repo create`/`repo connect` never actually select the target account.
		- The late re-selection is a no-op behind the already-applied guard, so publishing happens as gh's active account, silently. The comment at the call site says the opposite.
		- Inherited from the bash build.
		- The target named on the command line resolves the account, ahead of the validation that itself talks to gh. The late re-selection behind the already-applied guard is gone.

	- ✅ Code Review 20260818 item 3: the "gh's active account is 'X'" identity line can never print truthfully.
		- The token is exported before the probe that asks who was active, so the probe answers as the new account and the line stays dark. With a tokenFile whose token belongs to a different login, it prints a wrong name instead.
		- Inherited from the bash build.
		- The probe runs before the token is exported, so it can still answer with the account being replaced.

	- ✅ Code Review 20260818 item 4: `account apply` can't clean up rules under folder paths with a space.
		- The managed-includes scan splits each config line at the first space, so such keys are never recognized as ours. Re-runs append duplicates, and a rule removed from the config file keeps applying forever.
		- Inherited from the bash build.
		- Reads the rules with `--null`, so a key holding a folder path with a space comes back whole.

	- ✅ Code Review 20260818 item 5: `account apply` reports success no matter what.
		- The fragment truncate error is discarded and every `git config` exit code is ignored; "Wrote ..." and "Done." print regardless, exit 0.
		- The one command that writes outside the repo is the one that can silently no-op.
		- Every write is checked; the first failure stops the run and names what was left incomplete.

	- ✅ Code Review 20260818 item 6: `pr ok` with a dead PR number sails through preflight.
		- A failed `gh pr view` silently falls back to the current branch, so the plan is confidently about the wrong thing and the run dies after confirmation - the shape preflight exists to prevent.
		- Head branch and state come back in one call. A number gh can't resolve is refused, and so is a PR that is no longer open.

	- ✅ Code Review 20260818 item 7: offline reads as "repo doesn't exist" in `repo connect`/`repo create`.
		- Any `gh repo view` failure is taken as absence and stated as fact, with advice that derails further. These two skip the pre-command fetch (no origin yet), so offline is never discovered for them.
		- gh's stderr tells a name that resolves to nothing apart from an API it couldn't reach; the second is repeated back rather than stated as absence.

	- ✅ Code Review 20260818 item 8: `--offline` is a hidden third spelling of `--no-fetch` - and pushes still go out.
		- Contradicts the design rule that offline is a discovered state, never a flag. `sync --offline` publishes work.
		- Call to make: drop the alias, or make that one spelling refuse outgoing traffic too. Inherited from the bash build, undocumented in help.
		- Dropped, and refused by name with a pointer to `--no-fetch`. A flag that also stopped the pushes would only simulate a state the fetch already discovers, and nothing outside the source ever documented the spelling. Reasoning in design.md.

	- ✅ Code Review 20260818 item 9: the `sshkey` config value reaches shell-executed strings unquoted.
		- Concatenated into `GIT_SSH_COMMAND` and written into `core.sshCommand`; git hands both to a shell. The config is trusted input, but the file is redirectable by flag/env, and the repo-local sshCommand path already refuses quoting tricks - this path should match it.
		- A key path carrying whitespace or a shell character is dropped and listed as unusable, rather than quietly falling back to whatever key ssh picks.

	- ✅ Code Review 20260818 item 10: branch names from a cloned repo can reach git as leading options.
		- A repo whose default branch is named `-something` makes checkout/merge/branch/push parse it as flags. Bounded to breakage, not code execution. `--` separators fix it; the ssh probe paths already have them.
		- A dash-led name is refused before it reaches git in a leading argument position - checkout, merge, branch delete.

	- ✅ Code Review 20260818 item 11: a handed-over repo's own `.git/config` can pick gitsby's identity and token file.
		- `gitsby.ghAccount`/`gitsby.ghTokenFile` are honored from local config, so a foreign repo can have an arbitrary readable file loaded into the token env for child processes. No exfiltration channel exists - the credential helper is host-scoped - so this is identity confusion plus file read, not theft. Consider honoring tokenFile from global/folder config only.
		- `gitsby.ghTokenFile` is honored from global/system scope only. `gitsby.ghAccount` still reads repo-local: naming a login there is an ordinary thing to do, and the account still has to be one you hold.

	- ✅ Code Review 20260818 item 12: the wrong-account warning talks about pull requests on commands with no gh involvement.
		- The ssh-key-mismatch case appends the "gh does the pull request work..." sentence to plain push commands, and can name '?' when gh is absent - right at the y/n moment.
		- The gh sentence prints only where gh is the one acting.

	- ✅ Code Review 20260818 item 13: the push-identity gate fires for commands that push nothing.
		- Keyed on mutating, not pushing, so `pullcom -q` under a mismatched key is refused outright and pays a live ssh probe, for a local-only commit.
		- Keyed on whether the command pushes, named by exception so a mutating command added later stays covered until it says otherwise.

	- ✅ Code Review 20260818 item 14: skip the identity network probe when no identity block will print.
		- Every token-configured run paid a live `gh api user` round trip; `br list`, `account list` and bare `pr` never show what it feeds.
		- One predicate now answers "does this run reach the identity block", and both the probe and the later prime read it.
		- Measured with an account configured: `br list` 12 -> 11 spawns, `account list` 14 -> 11, `repo url` 13 -> 10. The one dropped from each is the network call.

	- ✅ Code Review 20260818 item 15: cache the handful of git answers asked repeatedly per run.
		- Origin's url, the current branch, upstream state, ahead/behind, git's ssh command, the context directory and the terminal width are each asked once now.
		- Ahead and behind came from two separate calls asking git the same thing; one call answers both.
		- Invalidated centrally by the runners that execute a step, not by each writer by hand - a step is exactly what can make an answer stale, and a future one gets it for free.
		- Measured: `status` 20 -> 17 spawns, `sync` 32 -> 25, `pullcom` 28 -> 24.

	- ✅ Code Review 20260818 item 16: two per-branch spawn loops left in `br prune`.
		- The survey's remote-existence check was already answered by the merged map beside it, and the delete loop re-verified the same target refs once per branch.
		- Dropping the verify costs nothing: merge-base against a ref that has gone fails, which is the same answer.
		- Measured on five merged branches: 69 -> 52 spawns, and the gap widens with the branch count.

	- ✅ Code Review 20260818 item 17: least-surprise paper cuts, one sweep.
		- `release` with nothing new exits 1 where every sibling's nothing-to-do exits 0 - and the About text promises idempotent re-runs.
		- `gitsby -q` alone: "Unknown command ''" instead of help.
		- `pr <n> extra` is the one place a trailing argument is silently ignored.
		- `pr create` with an unquoted title doesn't give the quote-your-message hint `pullcom` gives.
		- `repo clone owner/name` fails only after confirmation; `create`/`connect` both accept the shorthand.
		- "yes" at the y/n prompt aborts.
		- An option typed between `raw` and the tool is called an unknown subcommand.
		- All seven fixed. Nothing-to-do is a success for `release` too; a command list answers a bare option; `pr` refuses its trailing argument and hints at quoting; `repo clone` takes `owner/name` before the plan, not after; `yes` is a yes; an option before the tool says where ours go.
		- The overflow message picked up the quote-it hint as well - the ceiling is four slots, so an unquoted message of three words or more never reached the per-command hint.

	- ✅ Code Review 20260818 item 18: dead code and stale comments, one sweep.
		- Unreachable option-value arm plus its dead variable in the parser; two dead branches in the prompt helper; an empty-message fallback nobody passes; a handover error message a preceding check makes unreachable; a comment describing a superseded key-splitting contract; a near-verbatim duplicated comment in main. (The prune survey's redundant re-check went with item 16.)
		- All six gone. The handover kept its branch but not its claim: it named a cause the preceding check had already ruled out, so it reports what actually failed.
		- Also found: the three help printers each returned early under `-q`, which is why `-q --help` printed nothing. Removed with item 17's bare-option fix.

- ✅ Code review 20260813 - the folder-name rules, the release script and the removal audit.
	- Opened: 20260813-121029
	- Closed: 20260813-164625

	- Light pass over the folder-name rules, the release script, the changelog template guard and the removal audit, plus what they knocked loose elsewhere. Nothing wrong with the changes themselves; all four findings are things around them that went stale or were missed.

	- ✅ Code Review 20260813 item 1: the README stopped saying where it installs to, or that the download is checked.
		- Cause: the section was folded down to two one-liners so they could be pasted and run as-is. Dropping the flag table was the point; the locations and the checksum went with it by accident. The sentence left behind also had a stray plural and said "options" twice.
		- Note: both are reasons to trust the installer, and neither is visible until you have already run it.
		- Fixed: restored in the same place, without the flags - what you need Git and a shell for, what gets checked, a small table of the four install locations, the PATH note on Windows, and a pointer to `--help` for the rest.

	- ✅ Code Review 20260813 item 2: the changelog described a README that no longer exists.
		- Cause: it claimed install and the worked example are the first two sections. Both have since moved down, below the commands and the accounts material.
		- Fixed: the entry names the order the page actually has.

	- ✅ Code Review 20260813 item 3: markdown under `project/design_docs/` was not linted.
		- Cause: both engines list `*.md` and `project/*.md`, and the directory is a level below that. It arrived after the globs were last set.
		- Fixed: the directory added to both engines. The file in it was already clean.

	- ✅ Code Review 20260813 item 4: the PowerShell installer read its own temp path as a wildcard when cleaning up.
		- Cause: the removal took the path positionally. Every other removal in the tree names it literally, and this one was missed when they were hardened.
		- Note: only bites on a temp path containing a bracket, so nothing to reproduce in ordinary use.
		- Fixed: named literally, and skipped outright when the path was never set.

- ✅ Code review 20260812 - against the coding, performance, pipeline, housecleaning, marketing and installer standards.
	- Opened: 20260812-150636
	- Closed: 20260812-181826

	- Full review against the coding, performance, pipeline, housecleaning, marketing and installer standards. What is fixed here is listed below; the rest is filed above as open items.

	- ✅ Code Review 20260812 item 1: git over https authenticated with an empty password.
		- Cause: the token was supplied only when it replaced a different active account, while the helper that reads it was installed either way. The helper sets aside any credential manager configured ahead of it, so nothing was left to answer.
		- Note: worst on the setup needing no configuration - one account, logged in to gh, pushing over https.
		- Fixed: supply the token whenever one is found.

	- ✅ Code Review 20260812 item 2: a trailing comment in the config file became part of the value.
		- Cause: `#` started a comment only at the start of a line, and the documented example writes them at the end of one.
		- Note: a folder rule carrying a comment could never match, and a rule that never matches reads exactly like no rule at all.
		- Fixed: a `#` after whitespace ends the value. Quote the value to keep a literal one.

	- ✅ Code Review 20260812 item 3: an account name could name a file outside the include directory.
		- Cause: the name went into a path with nothing checking it, so a name containing a path sent `account apply` elsewhere - as far as the global git config.
		- Fixed: hold the name to letters, digits, dot, dash and underscore, and report anything else as an unread key.

	- ✅ Code Review 20260812 item 4: PowerShell read a repo with its own ssh key configured using the default key instead.
		- Cause: the fetch and the probe replaced git's ssh command to add a connect timeout, rather than adding to it.
		- Note: a private repo only the account's key can reach reported as unreachable, and the publishing commands then refused.
		- Fixed: add the timeout to git's own command, as the Bash build already did.

	- ✅ Code Review 20260812 item 5: `origin/HEAD` was healed after every fetch, at the cost of a second query to the remote.
		- Fixed: only when there is nothing to read locally. git 2.47 and newer write one at clone.

	- ✅ Code Review 20260812 item 6: the passthrough asked gh which account was active, over the network, on every call.
		- Note: the answer only named the account being replaced, on a line the passthrough does not print.
		- Fixed: skip it where no identity block is shown.

	- ✅ Code Review 20260812 item 7: a bare GitHub login got no identity line, in the command that exists to answer who a push goes out as.
		- Cause: the line asked whether some configured value had been used. A bare login names no account and sets no key, so it satisfied none of those tests - though it does select the token git authenticates with.
		- Note: `GITSBY_ACCOUNT` documents the bare-login spelling, and `raw` already reported it on stderr, so the two disagreed.
		- Fixed: an account asked for by name is enough on its own. One merely inferred from the remote's owner still prints nothing, so a single-account machine sees no change.

	- ✅ Code Review 20260812 item 8: the test suite read whatever accounts the person running it had configured.
		- Cause: it isolates git config and the commit identity, but not gitsby's own config file, which decides the account a command acts as.
		- Note: found by running it - a single `protocol = ssh` line in a real config failed three checks per implementation, because the repo commands then built a different remote URL than the check expected.
		- Fixed: point `GITSBY_CONFIG` at an empty file for the whole run. The account block, where discovery through `HOME` is the thing being tested, opts back out.

- ✅ Code review 20260731.
	- Opened: 20260731-104703
	- Closed: 20260731-110307

	- Delta review of the branch-display and status-label rounds. One finding, both implementations.

	- ✅ Code Review 20260731 item 1: `br list` refused to run in a repo whose default branch can't be told.
		- The default-branch gate exempted only `status` and the `repo` commands, so `br list` - read-only, and the other command you'd run to look around - errored out. The `Default branch: unknown` fallback it had just gained could never print.
		- Fixed: `br list` joins the gate exemption. Mutating commands still refuse up front.

- ✅ Code review 20260730.
	- Opened: 20260730-160015
	- Closed: 20260730-162216

	- Delta review of what landed since the 20260727b round: the offline handling, the BOM fix, the installer message, and the SSH identity line. Three findings, all in the offline messages, all in both implementations.

	- ✅ Code Review 20260730 item 1: an offline hotfix land pointed at a recovery that leaves the hotfix unshipped.
		- The warning said `sync` publishes the merge, but a hotfix land ends on `dev` after the back-merge - `sync` from there publishes `dev` and leaves origin's default branch stale. That is the one branch a hotfix exists to fix, and following the advice would read as success.
		- Fixed: the hotfix warning names both steps, `br switch <default>` then `sync` - the switch's parking push publishes `dev` on the way, so the pair covers both branches. A normal land still just names `sync`, which is right there because the command ends on the target.

	- ✅ Code Review 20260730 item 2: parking offline claimed committed work awaits even when there was nothing to push.
		- A clean, in-sync branch got "Your work is committed locally" with no work at all; online, the same state correctly said "Nothing to push."
		- Fixed: nothing ahead of the last-known origin means "Nothing to push.", offline or not.

	- ✅ Code Review 20260730 item 3: the skipped-push warning said `sync` publishes it, during commands that then leave that branch.
		- `br switch` and `br land` park the current branch and move off it, so a `sync` from where you end up publishes a different branch.
		- Fixed: the warning names the branch it means, and says `sync` from it.

- ✅ Code review 20260727b.
	- Opened: 20260727-090659
	- Closed: 20260727-201925

	- Full pre-release review, run across nine lenses with every finding independently checked before it was accepted. Fifty-three held up; the ones that changed behavior are below. Deep evidence is kept out of the repo.

	- ✅ Code Review 20260727b item 1: a conflicted tree was committed, and pushed (both implementations).
		- `git pull --ff-only --autostash` exits 0 even when reapplying the stashed work conflicts - it only warns - and `git add --all` then marks the conflict resolved.
		- So the most ordinary case there is, your edit plus a teammate's push to the same lines, committed the `<<<<<<<` markers, reported "(working tree clean)" and "Done.", and `sync` sent them to origin.
		- Fixed: nothing is staged while any path is unmerged. The conflicted files are listed, and the message points at the stash git kept.

	- ✅ Code Review 20260727b item 2: PowerShell read one repository and wrote to another.
		- Git was started without a working directory, so it ran in the directory pwsh was launched from, while `Set-Location` had moved only PowerShell's own idea of where it was.
		- Reading state therefore used the repo you were in and committing used the other one: it reported the right directory and the right changes, then committed an unrelated file from elsewhere and exited 0.
		- The suite could not see it, because every check moves directory in bash before starting pwsh, which makes the two agree.
		- Fixed: git is given the current location explicitly. New checks move location inside the pwsh session instead.

	- ✅ Code Review 20260727b item 3: `pr ok <n>` destroyed unpushed commits on the PR's branch (both implementations).
		- The guard asked whether the branch you were standing on had unpushed work. Accepting a PR from `dev` - the way it is normally used - asked about the wrong branch entirely.
		- gh merges what origin holds and then deletes the branch with a force delete, so commits that never reached origin went with it and were reachable from no ref afterwards.
		- Fixed: the PR's own branch is checked, whichever branch you are on, and the advice names it and how to push it from where you are.

	- ✅ Code Review 20260727b item 4: a default branch that is neither `main` nor `master` was invented rather than resolved (both implementations).
		- With no `origin/HEAD` to read, the answer fell back to the literal `main`. On a `trunk` repo that named a branch which does not exist, so the branch was judged unprotected, work was auto-committed to it (and pushed, when it had an upstream), and the command then died on a checkout of the invented name.
		- Worse when a stale local `main` existed alongside the real default: `br land` exited 0 having merged into the wrong branch, with no diagnostic at all.
		- Fixed: `trunk` joins the conventional names, a repo with a single local branch resolves to it, and an unborn repo still answers with the name it will get. When it genuinely cannot be told, commands refuse before anything is committed - `status` alone continues, and says "unknown" rather than a name it does not have.

	- ✅ Code Review 20260727b item 5: the documented PowerShell install one-liner never worked, and declining it closed your shell.
		- `iex` evaluates a top-level `param()` block in the caller's scope, where the allowed-values attribute is checked against its own empty default and fails immediately - so the install path the README leads with died before printing anything.
		- The other documented form did run, and `exit` inside it ended the calling session; strict mode and the error preference leaked into it on success.
		- A non-tty stdin also proceeded unasked, because the prompt's empty answer at end-of-input is not the empty string.
		- Fixed: both installers are a function that is called, they refuse rather than exit, they check for PowerShell 7 before anything reads a variable that 5.1 lacks, and end-of-input counts as no. Both documented shapes now bind their options.

	- ✅ Code Review 20260727b item 6: `--ref` was interpolated into a download URL unchecked (both installers).
		- A path-shaped value walked out of this repository, so a posted one-liner could install somebody else's script - and run it - while the printed plan still named this project. It reads as a harmless branch selector, which is why the confirm prompt was no protection.
		- Fixed: refs must look like refs, in both installers, and the tag resolved from GitHub's redirect is checked the same way before it reaches a URL.

	- ✅ Code Review 20260727b item 7: credentialed remote URLs were masked in the plan and printed in full when the command ran.
		- A token in a clone or connect URL reached the terminal, and any log or CI capture of it, on the execution line and again in the failure line.
		- Fixed: the display copy of every argument goes through the existing masking helper; what git receives is untouched. Three messages that echoed the URL raw alongside a masked copy of the same URL were fixed too.

	- ✅ Code Review 20260727b item 8: `-v` alongside a command silently did nothing (PowerShell).
		- The switches bind from any position under pwsh, so `update -v` printed the version and exited 0 - a caller or CI step saw success with the work not done.
		- Fixed: `-v` is refused when a command is present, matching Bash. `--help` went the other way on purpose: it now works after a command in both builds, since asking a subcommand for help is the reflex every git user has.

	- ✅ Code Review 20260727b item 9: a commit message starting with a dash was impossible in Bash and accepted in PowerShell.
		- Fixed in Bash: a value the parser is already waiting for is that value, whatever it looks like. `-m '-Wall added to CFLAGS'` now commits.

	- ✅ Code Review 20260727b item 10: PowerShell handed a remote URL to git unquoted in the pre-flight probe.
		- PowerShell expanded `*` and `?` against the current directory first, so the probe answered about a different target than the one git was later given - a URL that should have been refused was classified as an empty remote, and the working tree was committed and a bogus remote configured before the push failed. Bash refused before touching anything.
		- Third recurrence of that class, so the two display-only ssh probes were quoted at the same time.

	- ✅ Code Review 20260727b item 11: PowerShell's `pr ok` used a bare fetch where Bash used the guarded one.
		- No credential-prompt suppression (so it could stop and ask mid-command), no ssh connect timeout, and no `origin/HEAD` heal - and a blip there reported the whole command as failed after the merge had already landed on the server.
		- Fixed: one helper mirrors the Bash version and both fetch sites use it.

	- ✅ Code Review 20260727b item 12: `release` was the one command with no undo and no idempotency (both implementations).
		- A version it invented was cut even when the target would gain nothing, so a repeated run quietly added tags all pointing at the same commit.
		- Worse after a failed push: the tag existed locally, and the natural re-run bumped again, so the first version was stranded forever.
		- Fixed: an invented version with nothing new to release refuses, and names the tag to push if a previous one never left the machine. A version you type, and promoting a candidate, are deliberate and still work on an already-released commit. Uncommitted or unpushed work counts as something to release, since `release` parks first.

	- ✅ Code Review 20260727b item 13: `br land` would delete a leftover `main` or `master` (both implementations).
		- Landing ends in a branch delete, and the protected-branch rule that `br prune` honors was not applied here.
		- Fixed: refused up front, before a plan containing that delete is shown and confirmed.

	- ✅ Code Review 20260727b item 14: `--public` and `--private` together meant opposite things in the two builds.
		- Fixed: refused as a contradiction. Silently picking one would publish a repo the caller believes is the other.

	- ✅ Code Review 20260727b item 15: the identity probe caches never took effect in Bash.
		- Every use sits inside a command substitution, so the cache filled there was thrown away and the next call probed again - two `gh api user` calls and two `ssh -T` round trips per command, on a link that may be slow or dead. PowerShell was already correct.
		- Fixed: primed once in the shell that owns the variables.

	- ✅ Code Review 20260727b item 16: `install.bash --target system` failed with a raw `install` error when `/usr/local/bin` did not exist.
		- The user branch created the directory and the sudo branch did not.
		- Fixed: both create it, with `mkdir -p` rather than `install -d`, which would reset the mode of a directory that already exists. The plan says when a directory will be created.

	- ✅ Code Review 20260727b item 17: `br switch <the branch you are on>` previewed an add, commit and push it then did not do.
		- Nothing is lost, but the confirmed plan said otherwise, which is the one thing the preview exists to prevent.
		- Fixed: that case previews only the pull. Parking was deliberately not added instead - on a protected branch it would auto-commit, which the design forbids.

	- ✅ Code Review 20260727b item 18: every check named "plans X" was satisfied by the execution echo instead of the plan.
		- The preview is the product's central promise - it is what you read before answering the prompt - and it could have stopped listing the checkout, the back-merge or the push with the suite still fully green.
		- Fixed: assertions about the plan now match against the plan only, sliced out of the run. Eight checks were pointed at it.

	- ✅ Code Review 20260727b item 19: the three fuzz checks whose job is "these option combinations are accepted" passed if the options were refused.
		- They used the survive-any-outcome helper, so a valid spelling that stopped being recognized looked fine.
		- Fixed: a helper that requires exit 0, and the combinations respelled so the shared ones are valid in both ports.

	- ✅ Code Review 20260727b item 20a: the stronger fuzz assertion immediately found port drift that had been hidden: `-q -y` together was refused in PowerShell.
		- Both spellings were aliases of one parameter, and PowerShell rejects a parameter given twice. Bash takes either or both.
		- Fixed: `-y` is its own switch that means the same thing, so every combination the Bash build accepts is accepted.

	- ✅ Code Review 20260727b item 20: `sync`'s commit message had no coverage.
		- It takes a message positionally like `update`, and could have silently fallen back to the auto-generated timestamp with both suites green.

	- ✅ Code Review 20260727b items 21-27: the smaller ones, gathered.
		- PowerShell had no version gate where Bash has one, so a Windows PowerShell 5.1 run failed partway through a command on an undefined variable. It now says what to install, up front.
		- `status`, `br list` and `pr <n>` silently ignored trailing arguments while every other command rejected them - a typo looked like it did what you meant.
		- An option or positional typo printed an internal call stack. That is reserved for real crashes; these are usage errors.
		- `gh pr create` was announced with one command line and run with another. It is now announced by hand, matching both its own preview and the way `gh pr review` is already announced.
		- PowerShell's `pr view` blamed the wrong command on failure, and could not see `gh pr list` fail at all. Each call reports itself now.
		- PowerShell dropped the trailing blank line on error and abort exits that Bash prints on every path.
		- The installers say when they fell back to an unverified copy from the tree, rather than quietly downgrading from a checksum-verified release asset.
		- Two first-party shell files were outside the shellcheck gate and one glob in the list matched nothing; the gate now covers all 13, and shellcheck is clean across them.
		- `cicd.bash` printed with `echo -e`, which would animate backslash escapes and ANSI sequences out of a commit message the user typed. It uses `printf` now, like `bin/gitsby` already did - as does the crash dump, which can carry a filename or message.
		- Template leftovers in the argument parser: an instruction addressed to whoever instantiates the template, non-ASCII markers, a kaomoji, an over-long section rule, and a typo.

	- ✅ Code Review 20260727b: perf findings reviewed and deliberately not acted on.
		- Measured rather than assumed, with a counting `git` shim: `br list` is 6 git processes and `status` 13, both constant at 41 branches. Only `br prune` scales - about 5.5 per branch, 264 at 41 branches, and still 0.57s. The second containment check per branch is the deliberate re-check at delete time.
		- Nothing on the everyday path forks per item, so there is no problem to fix here. Noted so the next reader doesn't re-derive it.

- ✅ Code review 20260727.
	- Opened: 20260726-115807
	- Closed: 20260727-004615

	- Review of the hotfix branches, the gh/ssh identity check, and the docs pass that went with them.

	- ✅ Code Review 20260727 item 1: `pr ok <n>` decided where a PR lands from whatever branch you were standing on (both implementations).
		- Nothing asked gh which branch the PR proposes, so accepting a hotfix PR from `dev` skipped the back-merge that keeps the fix from being undone by the next release.
		- The reverse also happened: accepting an ordinary PR while sitting on a hotfix branch merged the default branch into `dev` for no reason.
		- Fixed: the head branch is read from gh up front and drives both the landing target and the hotfix decision. Falls back to the current branch if gh can't say.

	- ✅ Code Review 20260727 item 2: the back-merge merged a stale local default branch (both implementations).
		- Found while testing item 1. `pr ok` lands the hotfix on the server, so the local `main` never receives it and merging that branch did nothing at all - silently.
		- `br land` was unaffected, because it checks `main` out and merges into it itself.
		- Fixed: the back-merge uses the fetched `origin/<default>` when there is one, which is the same commit after `br land` and the correct one after `pr ok`. Previews show the ref that actually gets merged.

	- ✅ Code Review 20260727 item 3: the ssh identity was read only when the greeting was the first line (Bash).
		- ssh writes host-key and missing-identity-file warnings ahead of it, and both streams are captured, so a match anchored to the whole output missed the greeting.
		- It failed safe (unknown, proceed) but that meant the check quietly stopped working for the multi-account setups it exists to protect.
		- Fixed: matched per line. PowerShell matched anywhere, which had the opposite risk, and is now anchored per line too, so both behave the same.

	- ✅ Code Review 20260727 item 4: nothing said gitsby needs bash 4.4, and on macOS it could never get it.
		- `bin/gitsby` was the only file pinned to `#!/bin/bash`. macOS keeps that at 3.2 permanently, so installing a newer bash would not have helped.
		- Too old a bash died on `inherit_errexit` with a raw shell error, and `install.bash` (deliberately 3.2-compatible, for macOS) installed it anyway and only failed at its own verify step.
		- The README Compatibility section covered tool interop and remotes but never the runtime requirement.
		- Fixed: shebang resolves bash through `PATH`; both `gitsby` and `install.bash` refuse early with advice per platform (Homebrew/MacPorts, `pkg`/`pkg_add`, or the package manager), and point at the PowerShell build as the no-bash option. README states the requirement per platform.

	- ✅ Code Review 20260727 item 5: the "hotfix changes shipped code" note missed the ordinary case (both implementations).
		- It read the branch tip before `br land` committed the working tree, so a hotfix whose `bin/` edit was still uncommitted - the usual way of making one - got no warning.
		- Fixed: checked after the push.

	- ✅ Code Review 20260727 item 6: PowerShell's gh login probe could prompt (PowerShell); `br land` carried a duplicate variable (Bash).
		- Fixed: `GH_PROMPT_DISABLED` set around the call as the Bash side already did, and the duplicate dropped.

- ✅ Code review 20260726.
	- Opened: 20260726-125534
	- Closed: 20260726-133354

	- Release-prep pass over what changed since the last review: the noun grouping, `pr create`, and dropping bare `commit`/`pull`.

	- ✅ Code Review 20260726 item 1: `br switch` from a dirty protected branch tells you to run a command that no longer exists (both implementations).
		- The refusal offered `gitsby commit` as the deliberate way to keep the work where it is. That command was dropped, so following the advice is a second error.
		- Fixed: it now names `update`, which commits on the current branch. Regression test asserts the suggested command is a real one.

	- ✅ Code Review 20260726 item 2: offline only reached the pull in `update` and `sync` (both implementations).
		- `br create`, `br switch`, `br land`, `pr ok`, and `release` each pull as one of their steps, and those pulls ignored `--no-fetch` and an unreachable remote.
		- So the flag documented as "work offline" still went to the network in five of the seven commands that pull, which is exactly the thing the design note says it must not do.
		- Fixed: every in-command pull goes through one helper that applies the same rule. Regression test compares a `--no-fetch` switch (must not advance) against the same switch online (must).

	- ✅ Code Review 20260726 item 3: built-in help drifted from the command set (both implementations).
		- `update` was still described as commit-then-pull, `--no-fetch` as skipping only the fetch, and the PowerShell parameter help still listed `pull` and `commit` as commands.
		- The `br create` line said it parks current work first, which is what it does from a feature branch but not from `main`/`dev`, where it carries the work along instead.
		- Also "stash only if dirty" in the summary blurb, describing a manual stash that no longer exists.
		- Fixed: all of the above, in both implementations.

	- ✅ Code Review 20260726 item 4: the README command count was stale.
		- It said 13, from before the regroup and before `commit` and `pull` were dropped.
		- Fixed: 7 commands, or 15 counting subcommands, which is what the table below it lists.

	- ✅ Code Review 20260726 item 5: the offline test passed on the PowerShell side for the wrong reason.
		- It spelled the flag `--no-fetch`, which PowerShell has no parameter for, and then matched output against a pattern that the resulting complaint about the flag also matched.
		- So the check went green on a command that had failed outright, and no offline behavior was ever exercised there.
		- Fixed: `-NoFetch`, which both implementations accept, and the pattern now matches only the skip message itself.

	- ✅ Code Review 20260726 item 6: `br prune` could say "leaving it alone" and still delete the branch's remote copy (both implementations).
		- The delete-time re-check only guarded the local delete; the remote loop ran regardless.
		- Fixed: a branch kept by the re-check keeps its remote copy too.

	- ✅ Code Review 20260726 item 7: a merged current branch vanished from `br prune`'s output (both implementations).
		- It was rightly never deleted, but appeared in neither the plan nor the Keeping list.
		- Worst case: it was the only merged branch, and the output claimed nothing was merged at all.
		- Fixed: the plan, the no-op path, and the closing summary all say it is kept because you are standing on it.

	- ✅ Code Review 20260726 item 8: the README claimed 100% GitLab compatibility.
		- Every `pr` form, `repo create`, and `repo connect` with an `owner/name` go through `gh`, so they are GitHub-only. That is up to six of the sixteen subcommands.
		- Fixed: the claim now says any Git remote works and names the gh-backed exceptions.

	- ✅ Code Review 20260726 item 9: "no version: bump the patch" was only one of three release paths (docs and help, both implementations).
		- A candidate tag resolves to its own release (`v2.0.0-rc1` -> `v2.0.0`), and a repo with no tag at all starts at `v0.1.0`. Neither is a patch bump.
		- Fixed: docs and help now say the next version after the latest tag. A regression check pins the help line.

	- ✅ Code Review 20260726 item 10: `br create` still overpromised, in the opposite direction from item 3.
		- Item 3 changed the help from "parks current work" to "brings current work along". Both are half right: work is carried only from `main`/`dev`, and committed and pushed to the current branch otherwise.
		- Fixed: docs and help say carried or parked, and name which case is which. A regression check pins the help line.

	- ✅ Code Review 20260726 item 11: the dev installers required a bash version gitsby does not.
		- Both told you gitsby itself needs bash 5+. The real floor is 4.4, set by `inherit_errexit`; design.md already said 4.4 and was the one that was right.
		- Fixed: both installers now check and report 4.4.

	- ✅ Code Review 20260726 item 12: smaller doc corrections found in the same pass.
		- design.md said `gh` was needed for "the two commands that need it" - it is three.
		- The Direct-install one-liners never created the target directory, and the PowerShell one wrote to a *nix path inside the Windows section.
		- The README options list omitted `--public`/`--private` and never mentioned that the PowerShell version takes PowerShell-style parameter names.
		- "Every mutating command fetches first" ignored `repo clone` and `--no-fetch`. `br prune` was described as deleting every merged branch, which skips the current-branch and protected-branch exceptions. `repo create`'s steps were listed in the wrong order.
		- design.md's folder list omitted `reference/` and described `assets/` as holding only the demo.

	- ✅ Code Review 20260726 item 13: the pre-command fetch could stop and ask for credentials (both implementations).
		- `fpProbeRemote` sets `GIT_TERMINAL_PROMPT=0` for exactly this reason. The fetch that runs ahead of every command did not, so an https remote you can't authenticate to blocks the command at a username prompt - before any of gitsby's own checks get to run, including the ones that would have refused the command anyway.
		- Only shows up with a terminal attached. Without one git fails instantly, which is why the suites were green and silent.
		- Fixed: the fetch disables prompts too. A regression check records the environment the fetch actually receives, since the behavior is invisible without a tty.

	- ✅ Code Review 20260726 item 14: two suite checks reached the real github.com.
		- The `repo create refuses when origin is already set` check reuses a fixture whose origin is a real `https://github.com/me/proj.git`, but dropped the `insteadOf` rewrite that every neighboring check sets. Confirmed by the server's own "Repository not found" reply.
		- design.md says neither suite touches the network, so this was also the thing that surfaced item 13 in the first place.
		- Fixed: the rewrite is back on that check.

	- ✅ Show gh's account in the pre-flight, and refuse a gh write that acts as someone else.
		- gh authenticates with its own token and ignores ssh config, so `pr create`/`pr ok`/`repo create` act as gh's account while `git push` acts as the remote alias's key. With per-account aliases those differ, and the pre-flight was naming only the ssh one - the wrong identity for exactly those commands.
		- Found live: in a repo on the second account, gh reports the first with READ permission, so a `pr create` there would act as an account that can't do it.
		- Three outcomes, not two. Unknown (no agent, https remote, deploy key, gh logged out) is reported and never blocks - otherwise every CI runner breaks. Only a difference both sides confirm counts.
		- Interactive: warning directly above the confirm prompt. Unattended: error, nothing runs. `--any-identity`/`-AnyIdentity` proceeds, and the mismatch still shows on the identity line.
		- Decided against a general gh-config validator: policing another tool's setup isn't gitsby's job and would turn working commands into refusals.
		- 26 new checks across both implementations, driven by a fake ssh that answers the greeting GitHub really sends and doubles as the git transport. Verified they fail against the pre-feature build.

	- ✅ Extend the identity check to `repo create` and `repo connect owner/name`.
		- The first pass skipped them for having no origin to compare. That was wrong: gh never uses a host alias, so the url it is about to set is always `git@github.com:owner/name.git` and the identity is knowable before anything is created. Design note revised rather than appended to.
		- Refuses before `gh repo create` and before `git init`, so a mismatch leaves no remote and no repository behind. Verified against the pre-feature build, which created both.
		- An https protocol means git will use a credential helper rather than a key, so there is no second identity and nothing to compare.
		- Deliberately does not rewrite the remote to a matching host alias. Guessing which alias serves an account means inferring the user's ssh setup, and a wrong guess points the repo at the wrong key. `repo connect <full url>` already covers anyone who wants their alias.

	- ✅ PowerShell: gh's account was read from a stale exit status.
		- `gh api user | Select-Object -First 1` stops the native command early, so `$LASTEXITCODE` is left over from whatever ran before - in a plain directory that is the failed repo probe, so the login was discarded and every identity came back unknown.
		- Only showed up once `repo create` started needing the login, since that is the one command that runs outside a repository.
		- Fixed by collecting the output with `@()` before selecting, in all three places that read a native command this way. A regression check runs `repo create` from a plain directory and asserts the account resolves.

- ✅ Code reviews 20260725 and 20260723.
	- Opened: 20260723-190151
	- Closed: 20260725-171015

	- ✅ Code Review 20260725 item 1: `release` pushes only the tag when the default branch has no upstream (both implementations).
		- The branch push is gated on an upstream; the tag push is not.
		- Origin ends up holding the release commits as tag payload while its `main` still points at the previous release.
		- Same shape as item 2 of the previous review, which was fixed in `land` but not here.
		- Fixed: an upstream-less default branch is published with `git push -u origin HEAD` before the tag goes up. Regression test added.

	- ✅ Code Review 20260725 item 2: `release` refuses a duplicate tag only after it has already committed and pushed (both implementations).
		- The check sat inside the command, past the plan, the confirmation, and the "park current work" step.
		- Nothing is lost, but the run mutates the repo and then dies on something knowable up front.
		- Fixed: the tag-exists check moved next to the version resolution, before anything is shown or run. Regression test added.

	- ✅ Code Review 20260725 item 3: `gobr` refuses a dirty protected branch only after the plan is confirmed (both implementations).
		- Same class as item 2, and the same fix as code review 20260723 item 35 applied to the other branch arguments.
		- Fixed: the refusal moved up front, alongside the other branch-argument checks. Regression test added.

	- ✅ Code Review 20260725 item 4: `newbr` shows a plan it does not follow when run from `main`/`dev` (both implementations).
		- The preview always listed the commit-and-push steps, but on a protected branch the tree is carried to the new branch instead.
		- The preview is the safety feature, so it misreporting in exactly the case that was special-cased is the wrong way round.
		- Fixed: the plan now branches on protected state and shows the checkout-and-carry steps. Regression test added.

	- ✅ Code Review 20260725 item 5: `pr ok <n>` run from the branch that PR came from ends in a failed pull (both implementations).
		- `gh` deletes the branch on the remote through the API, which leaves the local `origin/*` copy in place, so the upstream still looks alive.
		- The trailing `git pull --ff-only` then asks for a branch the remote no longer has, and the whole command reports as failed.
		- Fixed: prune first, and if the branch we are standing on is the one that just went away, check out the merge target and pull that instead. The plan shows the extra step. Regression test added, with the fake `gh` restoring the stale ref so the real condition is reproduced.

	- ✅ Code Review 20260723 item 1: `pull` failure strands the autostash (both implementations).
		- Dirty tree gets stashed, then a failed `git pull --ff-only` (diverged or offline) aborts before `git stash pop`.
		- Work vanishes from the tree into the stash with no message; re-runs see a clean tree and never pop it.
		- Contradicts the "never risk losing work" promise; worst finding of the review.
		- Fixed: replaced the manual stash dance with `git pull --ff-only --autostash`; a failed pull now leaves the tree intact. Regression test added.

	- ✅ Code Review 20260723 item 2: `land` can delete the remote work branch before the merge ever reaches origin (both implementations).
		- Push of the merge is gated on the target having an upstream; the remote branch delete is not.
		- With a local-only `dev`, the merge stays local but `git push origin --delete <branch>` still removes origin's only ref to those commits.
		- Fixed: an upstream-less target is published first (`git push -u origin HEAD`) before the remote delete. Regression test added.

	- ✅ Code Review 20260723 item 3: `newbr`/`gobr` from a dirty `main`/`dev` commit and push WIP straight to the protected branch (both implementations).
		- The "park current work" step is commit+push on whatever branch you're on - including main/dev, with an auto message in quiet mode.
		- Contradicts the tool's own opinions ("don't push to dev, main, or master").
		- Fixed: `newbr` carries dirty work to the new branch (no commit on the base); `gobr` refuses with guidance instead of auto-committing; sync preview now names the branch being pushed. Regression tests added.

	- ✅ Code Review 20260723 item 4: a commit message containing `-h`/`-v` as a word makes the bash version silently no-op with exit 0.
		- The early help check scans the whole joined argv, so `gitsby commit "add -v flag"` prints the banner and skips the commit.
		- Bash only; the pwsh port checks just the command slot.
		- Fixed: -h/-v now only recognized in the command slot, matching the pwsh port. Test added.

	- ✅ Code Review 20260723 item 5: non-tty stdin silently auto-confirms all mutating commands (both implementations).
		- Piped/cron/redirected input behaves as implicit `-q`: release/land/sync run with zero confirmation, even `echo n |` is ignored.
		- Should fail closed like the installers do (require explicit flag when no tty).
		- Fixed: mutating commands with no tty and no -q abort with guidance; read-only commands keep the implicit quiet. Tests added.

	- ✅ Code Review 20260723 item 6: unquoted two-word positional message silently drops the second word (both implementations).
		- `gitsby commit Fixed bug` commits as "Fixed"; three words error but two don't.
		- Fixed: a non-empty third positional is rejected with "quote your commit message" (both implementations). Test added.

	- ✅ Code Review 20260723 item 7: git failures print the raw trap dump instead of a plain error (bash).
		- Diverged pull shows "Signal: ERR / Message: '--ff-only' / Command#: '"${@}"'" - reads as a gitsby crash.
		- The pwsh port already prints a clean one-liner; match it.
		- Fixed: fRun reports a plain one-liner ("'git ...' failed (exit N)") and exits; the trap dump stays for real script errors. Tests added.

	- ✅ Code Review 20260723 item 8: `echo -e` in fEcho_Clean expands escapes in user data (bash).
		- Mangles commit messages/filenames in the preview; a hostile repo's filenames (raw ESC bytes, C-quoted by git) can spoof the confirm display.
		- Switch to `printf '%s\n'`.
		- Fixed: fEcho_Clean uses printf '%s\n'; escape bytes in user data stay inert.

	- ✅ Code Review 20260723 item 9: pwsh branch-name comparisons are case-insensitive.
		- `-eq` treats 'Main' = 'main'; newbr can branch off the wrong base. Use `-ceq`/`-cne` at the seven branch compares.
		- Fixed: -ceq/-cne at the branch compares; 'ok' and prompt answers stay case-insensitive.

	- ✅ Code Review 20260723 item 10: pwsh `release` crashes under strict mode when the newest v* tag isn't X.Y.Z.
		- `v1.2` or `v2020` throws on array indexing; bash handles the same input gracefully.
		- Fixed: split parts padded before arithmetic (v1.2 -> v1.2.1, v2020 -> v2020.0.1); bash pads the same way now too. Verified on both.

	- ✅ Code Review 20260723 item 11: install.ps1 downloads to a predictable temp filename.
		- `gitsby-install-$PID.ps1` in shared temp; race window before install. install.bash already uses mktemp - mirror it.
		- Fixed: downloads into a fresh random private subdirectory; recursive cleanup in finally.

	- ✅ Code Review 20260723 item 12: remote URLs print verbatim, leaking embedded credentials (both implementations).
		- An `https://user:token@host/...` origin echoes the token on every run, including CI logs. Mask the userinfo part.
		- Fixed: userinfo masked in the displayed URL (https://***@host) in both implementations. Tests added.

	- ✅ Code Review 20260723 item 13: default-branch detection trusts a possibly missing/stale local origin/HEAD (both implementations).
		- Ref goes stale on upstream master->main renames and can be absent on git < 2.47; release then tags the wrong branch.
		- Cheap fix: `git remote set-head origin --auto` alongside the existing fetch.
		- Fixed: successful fetch now runs git remote set-head origin --auto, healing a missing or stale origin/HEAD; local read remains the offline fallback.

	- ✅ Code Review 20260723 item 18: fMustBeInPath shells out to external `which` (bash).
		- `which` is absent on some minimal distros, making every command abort with "Not found in path: git". Use builtin `command -v`.
		- Fixed: builtin command -v; dropped the stray second fThrowError argument.

	- ✅ Code Review 20260723 item 21: `pull` stashes a dirty tree before checking for an upstream (both implementations).
		- No-upstream + dirty = pointless stash push/pop that rewrites every file's mtime. Check upstream first. (Goes away if item 1 lands as `--autostash`.)
		- Moot: item 1's `--autostash` fix removed the manual stash entirely; no upstream now means no stash is touched at all.

	- ✅ Code Review 20260723 item 23: fetch without `--prune` leaves stale origin/* refs that existence checks trust (both implementations).
		- Stale refs make gobr check out dead branches, land abort on the remote delete, newbr refuse reusable names.
		- Fetch with `--prune`; make land's remote delete tolerant of "remote ref does not exist".
		- Fixed: fetch uses --prune, and land's remote delete warns-and-continues instead of dying if the branch is already gone.

	- ✅ Code Review 20260723 item 24: pwsh skips native exit-code checks in the pr/read-only paths.
		- `gh pr view` failure isn't caught before `gh pr diff` runs; `listbr`/`status` exit 0 even if git fails.
		- Fixed: gh pr view checked before the diff; listbr throws on git failure.

	- ✅ Code Review 20260723 item 25: pwsh parses Windows drive-letter remotes (`C:\...`) as ssh hosts.
		- Pre-flight then shows a bogus SSH identity line. Treat a single-letter-colon prefix as a path, like git does.
		- Fixed: single-letter-colon prefixes are treated as drive paths, not ssh hosts.

	- ✅ Code Review 20260723 item 26: `ssh -G` called without `--` on a host string derived from .git/config (both implementations).
		- Option-shaped "hosts" from a hostile config parse as ssh options. Currently fails closed, but add `--`.
		- Fixed: -- added in both implementations.

	- ✅ Code Review 20260723 item 27: install-dev.ps1 passes an option-shaped `-Directory` straight to `git clone`.
		- Binds as a real clone option (`--config=...`). install-dev.bash already rejects `-*`; mirror it (and/or pass `--` before the path).
		- Fixed: option-shaped -Directory rejected, same wording as the bash guard.

	- ✅ Code Review 20260723 item 28: install.ps1 lacks the downloaded-content sanity check install.bash has.
		- No shebang check before install+execute; wrong-content 200s (captive portal, truncation) get installed. Mirror the `^#!` test.
		- Fixed: first line must match ^#! before install, mirroring install.bash.

	- ✅ Code Review 20260723 item 29: gitsby.ps1 sets GIT_MERGE_AUTOEDIT process-wide, persisting in the caller's pwsh session.
		- The var is redundant anyway (merges pass `-m`); just delete the line.
		- Fixed: line deleted (merges pass -m, so it was redundant).

	- ✅ Code Review 20260725 item 6: `release` with no version bumps the patch of a candidate tag's base, skipping that base version (both implementations).
		- After `v2.0.0-rc1`, a bare `release` proposed `v2.0.1` rather than `v2.0.0`.
		- Fixed: a candidate's own version is now what comes next, so `v2.0.0-rc1` leads to `v2.0.0`.
		- The tag scan also needed `versionsort.suffix=-`, since git's default version sort ranks `v2.0.0-rc1` above `v2.0.0` and would otherwise propose an already-cut version once the real release exists.
		- Regression tests cover both halves: the candidate's version is taken, and the release after it bumps normally.

	- ✅ Code Review 20260723 item 14: bound the unconditional pre-command fetch and add an offline escape hatch (both implementations).
		- A dead/black-holed remote blocks every command for the full TCP/ssh timeout before the "offline?" warning.
		- Add a connect timeout on the fetch and a `--no-fetch`/offline flag.
		- Done: ssh fetches get ConnectTimeout=3 (user GIT_SSH_COMMAND respected), and --no-fetch/-NoFetch skips the fetch entirely.

	- ✅ Code Review 20260723 item 15: cache per-run-constant git facts (both implementations).
		- Measured: 12 git spawns for `status`, 45 for `land`, 55 for `release`; upstream/branch/ahead-behind re-queried repeatedly in one display block.
		- Resolve once after the fetch, pass down; keep live re-checks only where state actually mutates. Matters most on Windows.
		- Done: default branch and merge target now resolve once per run post-fetch; branch/upstream/ahead checks stay live since checkouts change them mid-command.

	- ✅ Code Review 20260723 item 16: close the test-suite gaps that hid this review's bugs.
		- Failed-pull-with-dirty-tree, no-remote fixtures, slash branch names, `-m`/`-m=` flag forms, option-like words in messages, release from a feature branch.
		- Done so far: failed-pull-with-dirty-tree, upstream-less land, dirty-protected-branch newbr/gobr fixtures.
		- Done: all listed fixtures added (failed pull, no-remote sync/newbr/land, feat/x names, -m and -m= forms, option-like message words, release from a feature branch). Suite 140 -> 199 checks.

	- ✅ Code Review 20260723 item 17: README has no Commands/Usage section.
		- The pitch is "Gitsby has 11" commands, but they're never listed or demonstrated. Add the help table plus a worked newbr -> update -> land example.
		- Done: Commands section added (table of all 11, options, a typical-day flow, gh note for pr/release).

	- ✅ Code Review 20260723 item 19: installer checksum + version pinning - confirms the already-open installer item below.
		- Publish SHA256SUMS from cicd, verify in both installers, allow pinning an exact tag; document that `--ref` skips verification.
		- Done: installers verify release-asset downloads against a SHA256SUMS release asset when published (note-and-continue when absent); cicd/utility/gen-checksums.bash generates it for release cuts; --ref/-Ref pins a tag but skips verification (documented in README).

	- ✅ Code Review 20260723 item 20: "latest release" lookup uses the unauthenticated GitHub API (60 req/hr).
		- Shared-NAT/CI installs will 403. Read the tag from the `releases/latest` redirect Location header instead; keep the API as fallback.
		- Done: tag read from the releases/latest redirect (curl url_effective / wget Location / pwsh 302 handling); API scrape kept as fallback; rate-limit mentioned in the error.

	- ✅ Code Review 20260723 item 22: fIsAhead materializes the whole ahead-range log just to test emptiness (both implementations).
		- Use `git rev-list -n 1 '@{u}..'` (or the cached ahead count from item 15).
		- Done: git rev-list -n 1 in both implementations.

	- ✅ Code Review 20260723 item 30: needless external `head`/`wc` pipeline stages (bash).
		- Use `mapfile -n 1` / array counts, minding that a bare `read` returns nonzero on empty input under strict mode.
		- Done: tag lookup via mapfile -n 1; the stash wc pipelines were already removed by item 1.

	- ✅ Code Review 20260723 item 31: positional parameter binding in the ps1 files (style guide requires named).
		- gitsby.ps1 one spot (`Get-Command ssh`); install.ps1 and install-dev.ps1 throughout (Join-Path, Move-Item, Test-Path, Get-Command).
		- Done: named parameters at the flagged sites in all three ps1 files.

	- ✅ Code Review 20260723 item 32: no comment-based help on any gitsby.ps1 function.
		- Either add `.SYNOPSIS` to the non-trivial functions, or scope the style-guide rule to script-level + exported functions.
		- Done: style-guide rule scoped to script level + exported/public functions; private helpers take a terse ## comment.

	- ✅ Code Review 20260723 item 33: installer output ends without the trailing blank line the style guide requires (all four installers).
		- Done: all four installers end with a blank line.

	- ✅ Code Review 20260723 item 34: rename fpPreview's `p` padding variable to `pad` (matches the pwsh twin).
		- Done: renamed.

	- ✅ Code Review 20260723 item 35: branch-argument validation runs after the status display and confirm prompt (both implementations).
		- `newbr` with a bad/missing name shows a nonsense plan ("git checkout -b ") and only errors after "y". Hoist checks next to the existing pr/release ones.
		- Done: newbr/gobr arguments validate right after the release-version check, before status/preview/prompt; command functions no longer duplicate the checks. Test added.

	- ✅ Code Review 20260723 item 36: `gitsby help` / `gitsby version` are unknown-command errors (both implementations).
		- Alias the bare words to the -h/-v paths; one case entry each.
		- Done: bare words route to the same paths as -h/-v (both implementations). Tests added.

	- ✅ Code Review 20260723 item 37: usage errors carry "Reverse call stack: fMain()" noise (bash).
		- Suppress the stack line for expected validation errors; keep it for real internal failures.
		- Done: fThrowError_Usage variant skips the stack line; all user-facing validation errors use it. Real script errors keep the stack.

	- ✅ Code Review 20260723 item 38: accept `-y`/`--yes` as a prompt-skip alias (both implementations).
		- Installers teach -y, gitsby only takes -q; and -q's real function is "assume yes", not quiet. Keep -q, add -y, fix the help wording.
		- Done: -y/--yes (bash) and -y/-yes (pwsh) alias -q; help wording now says "assume yes". Test added.

	- ✅ Code Review 20260723 item 39: README typos.
		- Line 82 "devoted to to", line 100 "besome", line 218 "cononical".
		- Done: all three fixed.

	- ✅ Add a PowerShell badge to README.md.
		- Added next to the bash badge in the header block, linking to the PowerShell docs.

#### Done - Features and enhancements

- ✅ Rework the fuzz suite. Much of what it proves becomes structurally impossible with no shell in the path; figure out what remains meaningful.
	- Opened: 20260817-115422
	- Closed: 20261006-075458
	- Done: audited every vector group against the Go build. The old suite assumed a shell between user input and git; the Go build runs git, gh and tea through argument arrays, so most old vectors can no longer inject. They stay as cheap regression guards against a shell-out creeping back. Added checks that drive the spots where a user value still reaches a real tool, each through the real consumer: a clone directory derived from an option-shaped URL tail (argument injection into git), a ref that is also a revision ('br switch HEAD'), a shell-bearing 'sshkey' through a real ssh, 'account apply' escaping glob characters in a folder rule and dropping a shell-bearing host or user, and a junk GIT_CONFIG_COUNT on the 'git credential fill' path. The credential-helper vector already drove the real consumer and still does. 301 -> 311.
	- Done: two product bugs the new vectors caught, fixed in the same branch. 'repo clone' now passes '--' before the derived directory, so a URL tail like '--upload-pack=...' can't reach git as an option. origin/HEAD is no longer counted as a branch, so 'br switch HEAD' refuses up front instead of committing and pushing the working tree to park it and then failing.
	- Decided against: deleting any existing vector. With no shell in the path most are inert, but each still guards against a regression to a shell-out, so none was removed and backlog-check needs no deletion entry. Also against duplicating the native Go fuzz targets, which already cover the pure parsers.
	- Note: a config value with a newline in it is quoted safely in the file and never injects, but `account` prints it across lines. Filed as its own item, 2026100607545812.
	- Test case: new checks [ddjyb] clone-dir argument injection, [ddjyc] 'br switch HEAD' leaves the repo untouched, [ddjyf] shell-bearing sshkey never reaches ssh, [ddjyd] apply escapes folder-rule globs, [ddjye] apply drops a shell-bearing host or user, [ddjyg] junk GIT_CONFIG_COUNT refused - all in fuzz.bash.
	- Swept: the git/gh call sites that take a user-controlled leading argument - clone dir, refs into checkout/switch, sshkey and host/user into the credential helper key and the includeIf fragments, and GIT_CONFIG_COUNT. The helper reads its username from the environment, so nothing is interpolated into the shell string git runs.
	- Verified: fuzz.bash 311/0, test.bash 1491/0, parity.bash 29/0 on the branch. Each new check was watched red by breaking the Go code it guards. `go test ./...` and the gate pass.
	- Note: the 2 product fixes are filed as their own items, 2026100607545802 and 2026100607545807.
	- Acceptance signoff: Self-closed: tests only, and no existing check changed meaning.

- ✅ `repo clone` names the folder it clones into in full.
	- Opened: 20260928-132933
	- Closed: 20260928-132933
	- Done: the plan's "Clone into" line and the "Cloned into" status showed the folder as typed, or as worked out from the URL, relative. Both print it in full now, per the path rule in the UI style guide. The git command keeps the typed form.
	- Test: [dd81f] and [dd81g] in test.bash.
	- Verified: both fail against `gover`.

- ✅ Code review 20260909 - enhancements from the same pass.
	- Opened: 20260909-184419
	- Closed: 20260928-144045

	- ✅ Code Review 20260909 enhancement 2: there is no `account unset`. Setting a key to an empty value prints the syntax block, so the only way back is the hand edit that `account set` exists to avoid.
		- Origin: new. Confirmed.
		- Closed: 20260928-144045
		- Done: `account unset <account> <key>` removes every line of the key from every block of that name, and the plan lists each one. A key nothing reads can go where the block has one. A key or account that isn't there is nothing to do, exit 0. A value after the key is refused, since it would read as removing only that one.
		- Note: it never needed the shcl 3.0 move. The pinned module already had `Remove`, and it keeps lines on save.
		- Test: [dd83p] to [dd83v] in test.bash, and `TestAccountUnset*` and `TestSortCommandAccountUnset` in Go.
		- Verified: five of the six suite checks fail against `gover`. "The rest of the file is as typed" is a regression guard.
		- Swept: every site that names `account-set` by command name, in main.go, mutate.go, preview.go and show.go, takes `account-unset` too.

	- ✅ Code Review 20260909 enhancement 3: `--about`, `--donate` and `--version` are honored only as the first word, while `--help` works at any position. The help screen lists all four on one line.
		- Origin: new. Confirmed.
		- Closed: 20260928-132933
		- Done: they work at any position after the command, as `--help` does. A value after `-m` is still a message, and `-v` still counts only as the first word, so it cannot turn a mutating command into a no-op.
		- Test: [dd80x], [dd80y], [dd80z] and [dd810] in test.bash, and `TestParseArgsInfoFromAnyPosition` in Go.
		- Verified: the three that print fail against `gover`. "And the command does nothing" is a regression guard, since `gover` refused the option.

	- ✅ Code Review 20260909 enhancement 4: two of the six README badges are shields the repo grants itself and assert nothing outside the README. The language badge names no version.
		- Origin: new.
		- Closed: 20260928-132933
		- Done: "Lifecycle: Stable" went, and "Support: Maintained" became a last-commit badge. The Go badge reads the version from `src-go/go.mod`. It errors on `main` until the Go build is released there, which is when this README reaches `main`.
		- Test: [dd812] in test.bash. It fails on the old README.

	- ✅ Code Review 20260909 enhancement 5: three things the README leaves out.
		- The build number, which every command prints and which comes from the commit rather than the clock.
		- How to ask for a pre-release, which is what the first Go publication will be.
		- The real check counts. "Several hundred" rounds down from eight hundred and ten, plus the fuzz and comparison suites.
		- Origin: new.
		- Closed: 20260916-132641
		- Decided 20260916: the first Go publication is v3.0.0-beta.1, published as a pre-release. release.bash reads that off the tag's semver suffix, so there is no flag to pass. design.md's release policy is rewritten rather than amended, since it argued the other way.
		- Counts measured on gover, not carried over: 1013 regression, 301 fuzz, 27 comparison.

	- ✅ Code Review 20260909 enhancement 6: record that goreleaser is not being adopted, and why, so the question stops coming back. The hand-rolled build is already byte-identical from one flag set, goreleaser would have to be talked out of its own stamps, and packaging is the only thing it would add.
		- Origin: the 2026-09-07 directives ask for the decision to be recorded.
		- Closed: 20260928-132933
		- Done: recorded in design.md under "Direction decisions".
		- Test: none, since this records a decision.

	- ✅ Code Review 20260909 enhancement 7: `--quick` still runs the two slowest harnesses in full. Neither takes a flag to shorten itself.
		- Origin: the 2026-09-07 directives.
		- Closed: 20260928-132933
		- Decided against: test.bash takes about 73 s over 1240 checks, with no hot spot. The one block worth skipping is the PowerShell installer at 16 s, and a quick run would then not test the one piece of PowerShell that ships. `--quick` already skips fuzz entirely.
		- Done: config.bash said `--quick` skips the comparison harness, which it never did. The comment is fixed.
		- Test: none, since nothing changed in what runs.

	- ✅ Code Review 20260909 enhancement 8: tool pinning covers the four Go tools and silently skips the one that is not on the path. Six other tools that shape results are pinned nowhere.
		- Origin: the 2026-09-07 directives.
		- Closed: 20260928-132933
		- Done: the Go tools are found where `go install` puts them, as gen-winres finds goversioninfo. On b23 goversioninfo is under GOPATH and not on PATH, so its version was never compared. `TOOL_VERSIONS` records shellcheck, markdownlint, PSScriptAnalyzer, gifsicle, Pillow and strace, compared and warned about the same way.
		- Test: [dd813] and [dd814] in test.bash. [dd5fh] now matches the wider warning.
		- Verified: both fail against `gover`.

	- ✅ Code Review 20260909 enhancement 9: the release's final build compiles the working tree rather than a checkout of the tag. The two match in the ordinary case, and the comment above it claims the stronger thing.
		- Origin: new. Plausible: read.
		- Closed: 20260928-132933
		- Done: phase 3 exports the tag with `git archive` and builds that. The temp folders now go on any exit.
		- Test: [dd815] in test.bash pins it in the source, since no dry run reaches phase 3.

	- ✅ Code Review 20260909 enhancement 10: smaller points in the installers.
		- No writability check for a user-scope install, so it fails after the download the way the system scope does.
		- sudo is promised without checking it exists.
		- The two scripts leave the installed file in different modes, and the PowerShell one takes the umask.
		- The PowerShell plan does not mention creating the destination folder, or clearing its own leftovers.
		- The README does not say how to pass a flag to the bash one-liner, though the script knows the answer in a comment nobody sees.
		- The two release sorters have no tie-break between two pre-releases of one version. It was unreachable while every publication was a full release. From 20260916 a suffixed tag publishes as a pre-release, so a v3.0.0-beta.2 following beta.1 reaches it; re-check whether a comment is still enough.
		- Origin: the writability and sudo bullets were in the 20260819a notes as seen and not filed; the tie-break was the 20260909 round's own deferral. Plausible: read.
		- Note: since item 13, install.ps1 checks write access for a system install before the plan. The user scope can reuse that check.
		- Closed: 20260928-132933
		- Done: both installers check a user install can write its folder before the plan. The Bash one checks sudo exists before promising it. The PowerShell one installs 755, and its plan names the folder it creates and the leftovers it clears. The README shows `bash -s --` with a flag.
		- Decided against: a real tie-break between pre-releases. The newer-listed one wins a tie, and release.bash publishes in order, so both sorter comments now say that instead.
		- Test: [dd817], [dd818], [dd819], [dd81a], [dd81b], [dd81c] and [dd81d] in test.bash, plus [dd816] for the tie.
		- Verified: all but the tie check fail against `gover`. That one is a regression guard.

	- ✅ Code Review 20260909 enhancement 11: preallocate the slices whose size is already known, about fourteen of them. The style guide could also use a Go performance section, and its package-variable rule needs widening: five variables that Go cannot express as constants currently read as standing violations.
		- Origin: new. The five package variables were flagged by 20260819a items 21-25 and left as the ones Go cannot make constants.
		- Closed: 20260928-132933
		- Done: the prealloc linter finds six sites now, three in tests. The other three are a cold usage printer, a per-batch slice that resets, and a loop whose total is not known, so none changed. The style guide gained a Go performance section, and its package-variable rule names what Go cannot make a constant.
		- Test: none. A prealloc gate would need `//nolint` on the three sites above.

	- ✅ Code Review 20260909 enhancement 12: `.gitignore` covers the pipeline's own output and nothing a contributor's machine drops.
		- Origin: the 2026-09-07 directives.
		- Closed: 20260928-132933
		- Done: `.gitignore` covers OS files, editor swap files and folders, and go test output.
		- Test: [dd81e] in test.bash, which also fails if the repo tracks anything ignored.

- ✅ The Go unit tests print a line per test, with its test ID.
	- Opened: 20260927-112000
	- Closed: 20260927-114500
	- They showed as one `OK: go test` line. A full run and `--gate` now print one line per top-level test, and nothing for subtests. The rest of `go test -v`'s output shows only when a test fails.
	- Verified: test.bash 1220 -> 1222. Both new checks fail against the old pipeline. The real gate printed 153 lines on Linux, one per test. The one Windows-only test doesn't run here.

- ✅ Every check line in a pipeline run shows its test ID.
	- Opened: 20260927-105500
	- Closed: 20260927-111500
	- The suites already printed them. Native fuzz targets now print the ID from their func line. Spawn counts had none, so each command got one, dated from when it was first measured, and test-id.bash checks them.
	- The baseline file keeps plain labels, so older baselines still match.
	- Verified: test.bash 1219 -> 1220. Five checks fail against the old scripts. test-id.bash flags a measure with its ID taken out.

- ✅ A pipeline run shows every regression, fuzz, parity and spawn check, one line each.
	- Opened: 20260926-204500
	- Closed: 20260926-215000
	- Fixed: a `-q` run passed `-q` on to the suites, so only the totals showed. The pipeline no longer passes it to any of them. Each native fuzz target gets a line too. Only the demo generator still takes `-q`.
	- spawn-count printed bare counts, and a verdict only for a change. Each command now gets one line with its count and verdict, `ok` included.
	- Verified: test.bash 1217 -> 1219. Both new checks fail against the old scripts. A `-q` run printed 1561 check lines, all passing.

- ✅ Every closed backlog item has a regression check, where one makes sense.
	- Opened: 20260926-144000
	- Closed: 20260926-154915
	- Audited every closed item against test.bash, fuzz.bash, parity.bash, the Go tests and the lint gates. About sixty had no check that would fail if the fix were undone. The rest were covered, or were docs, decisions, frozen code, or need a live host or a Windows box.
	- Added: 8 Go tests, and test.bash checks for the account and identity paths, branches and prune, the installers, and the pipeline itself. The pipeline gets its first runs of stage 0, stage 3, dogfood, the publish message, the real backlog gate, spawn-count and `release.bash --dry-run`.
	- The suite now runs with a poisoned `XDG_CONFIG_HOME` and `APPDATA`, so a block that fakes HOME and forgets to clear them goes red on any box.
	- "option typo prints no call stack" looked for text only the bash build printed. It now looks for a Go panic.
	- Verified: test.bash 1031 -> 1208, every new check seen to fail against its fault. Seven bugs found on the way are filed under Bugs.

- ✅ The pre-push gate runs on every branch push, not just `main`.
	- Opened: 20260924-092200
	- Closed: 20260924-093000
	- Fixed: only a push to `main` is gated. Other branches, deletes and tags go out without it.
	- Verified: test.bash 1027 -> 1028. The new check fails against the old hook.
	- Removed: "a branch pushed from elsewhere is gated at its own commit" and "one commit under two branch names is gated once". Both assumed any branch was gated. They are now "main pushed from another branch is gated at that commit" and "main pushed beside another branch is gated once".

- ✅ Paths are spelled more than one way between the config file and the screen.
	- Opened: 20260916-110027
	- Closed: 20260916-164500
	- Decided 20260916: a path is never re-spelled for display. One gitsby worked out itself prints in full, one the config file holds prints as the file holds it. The accounts file line stops folding to `~`, which reverses the display half of 807aa30.
	- Decided 20260916: the config file takes `~`, `${HOME}` and `%USERPROFILE%` as the same thing on every platform, and either slash in any rule. Closed set of variables, expanded by gitsby, never through a shell. One this machine does not set makes the rule ignored and listed. No drive-letter mapping across platforms.
	- Already handled on read: `\` to `/`, `~`, `~/`, `~\`, and `/c/x` to `C:/x` on Windows. New: the variables, and keeping the text as written.
	- Work: `displayPath` only folds, so it collapses into `nativePath` at 28 call sites. The value model has to keep the as-written text beside the canonical form, since a value is normalized on read - `a\tb` reads back as `a/tb` today. Four checks assert a printed `~` (test.bash 2412, 2776, 2824, 2850) and change with the code; their labels do not.
	- Note: the guide states the new rule already, so it and the program disagree until this is done. Closing that is what this item is.
	- 20260916: built on `pathspell`, all Linux suites green. Go tests pass on b29w with and without HOME, and a real `account list` and `account apply` there take all three spellings.
	- Either slash does not hold yet for a backslash before `t` or `n`. Filed under Bugs, since it predates this item.

- ✅ Bring the output into line with the UI and UX style guide.
	- Opened: 20260915-154529
	- Closed: 20260916-142242
	- Seen while writing the guide: `WARNING:` lines are bracketed in some places and bare in others. `account list` prints `token ...: none` beside `github ..: (none)`. Most `Syntax:` lines name their placeholders without saying what they mean; only `account set` does.
	- Syntax lines: every `Syntax:` refusal now defines its placeholders under the line, the way `account set` does. Ten sites, one shared helper.
	- `(none)`: the token line says `(none)` like the github line.
	- Warnings: no code change. Every warning a step prints as it runs is already bracketed, and every one inside a plan or a listing already is not. The guide says so now.
	- Verified: suite 1016 -> 1021, all green, and the five new checks fail on the tree before. Gate clean. Linux only.

- ✅ The last forge names, in the code and the suite.
	- Opened: 20260916-074956
	- Closed: 20260916-074956
	- Item 18 left the code names, the two credential variables and two check labels saying forge. They say host now.
	- The Go names are `hostName`, `hostURL`, `hostTool`, `hostToolFor`, `hostCLIHint`, `hostCLIWho`, `hostAnswer`, `hostLogin`, `hostState` and `showHostLine`. `forge.go` and `forge_test.go` are `githost.go` and `githost_test.go`, and `parseForgeTable` is `parseTeaTable`, which is whose output it reads.
	- The credential variables are `GITSBY_HOST_TOKEN` and `GITSBY_HOST_USER`. Nothing outside gitsby sets or reads either.
	- Relabeled: "a Gitea remote with no forge CLI refuses" is now "a Gitea remote with no host CLI refuses", and "but a config with one forge in it is never shown the key" is now "but a config with one git host in it is never shown the key".
	- The style guide file is `project/style-guide_ui-ux.md`, titled to match, with every link to it followed.
	- Verified: suite 1012/0, Go tests green, gofmt, vet and markdownlint clean. Both relabeled checks pass, and so does the one that watches for the word in the identity block. Linux only.

- ✅ No UI and UX style guide exists, and README points at none.
	- Opened: 20260914-122353
	- Closed: 20260915-154529
	- Done: `project/style-guide_ui-ux.md` holds the output, prompt and error rules from design.md, the diagnostics decisions, and what the program does today. README, contributing.md and design.md's UI section link to it.

- ✅ Code review 20260909 - the closed enhancements from the same pass. The rest are still open under Features and enhancements.
	- Opened: 20260909-184419

	- ✅ Code Review 20260909 enhancement 1: decide whether the identity marker belongs in the Windows file properties.
		- Closed: 20260910-072019
		- The copyright change put it into the string Windows shows on the Properties tab of the executable, which is a product-facing string rather than a source header. The standing rules exempt two other projects' Windows version strings and keep the plain form there.
		- Bug item 4 waits on this: regenerating the resource files publishes whichever answer is given.
		- Kept out. The Properties tab shows the plain copyright, and the source headers keep the ID.

- ✅ macOS builds no longer need a Mac or an SDK.
	- Opened: 20260817-115422
	- Closed: 20260818-181424
	- `darwin/amd64` and `darwin/arm64` cross-compile from this box, so both are in the release matrix. Signing and quarantine on real hardware are a separate question, still open.

- ✅ `.shcl` goes hierarchical via a real module, replacing the hand parse.
	- Opened: 20260826-152000
	- Closed: 20260826-153701
	- The file is read and written through the shcl Go module: one block per account, folders as a list, the old flat layout still read and converted by the first `account set`. A created file carries a key header and the format's footer.

- ✅ Dogfood destinations tidied. The Linux fallback is `~/.local/bin`, the same dir the installer defaults to, and it only applies to the target matching the box doing the build. Dropped a second macOS entry that spelled out a home directory.
	- Opened: 20260826-155615
	- Closed: 20260826-160101

- ✅ `--about` and `--donate`.
	- Opened: 20260826-122906
	- Closed: 20260826-123436
	- `--about` is the copyright block, the description the help screen carries, and a link to the project. `--donate` is the build line, two sentences, and the sponsorship link.
	- Both answer outside a repository, both take a bare word as well as the flag, and neither reads any configuration.
	- Help lists both on the line that already names `--help` and `--version`.

- ✅ A build number, printed next to the version and on every command's output.
	- Opened: 20260826-114339
	- Closed: 20260826-120037
	- Minutes from the start of 2000, Crockford base32, lower case. Five characters until 2063, and no letters that get misread when one is read back over the phone.
	- Taken from the commit's date rather than the clock at build time. A clock-derived number changes on every rebuild, which would mean a published binary could never be rebuilt to its published checksum.
	- Commands print `gitsby <version> build <build>` above their output. Not under `-q`, and never on `raw git`/`raw gh`, which hand their tool's output back untouched. `--version` and the help screen gained the build number on the version line they already had, rather than a second line repeating it.
	- The release cross-builds twice as a result: phase 1 as a compile gate, phase 3 from the tagged commit for the bytes that get uploaded. The release notes name the build number, read out of the built binary so the two cannot disagree.
	- An unstamped build (a hand-run `go build`) reports no build number at all.

- ✅ Port the mutating commands (`update`/`sync`, `br create`/`land`/`prune`, `pr`, `repo`, `account apply`). Four slices, one branch each.
	- Opened: 20260818-090334
	- Closed: 20260818-140234
	- ✅ The mutating frame plus `update`, `sync`, `br prune`. The frame is the shared part: state, plan, confirm, run, state again, "Done." - and the commit/pull/push core the rest compose from. `br prune` now deletes rather than stopping at its plan. Go leg 249/189 -> 285/153.
	- ✅ `br create` / `hotfix` / `switch` / `land`, with the hotfix back-merge and the shipped-code warning. Also the up-front branch-name and dirty-protected-branch refusals, and the `New branch ...:` state line. Go leg 285/153 -> 345/93.
	- ✅ `pr create` / `pr ok`, and `release` with its version resolution and the nothing-new guard. Also the `GitHub (gh)` identity line, which only gh-backed commands print, and the gh-write account comparison behind it. Go leg 345/93 -> 385/53.
	- ✅ `repo clone` / `create` / `connect` / `url`, and `account list` / `apply` - the includeIf writer, the fragment files, and the smaller no-repo headers (clone, connect-from-plain-dir, files-to-publish). With this the whole command surface is ported. Go leg 385/53 -> 438/0.

- ✅ Rename `update` -> `pullcom` and `br land` -> `br merge`, keeping the old spellings as aliases. After slice four.
	- Opened: 20260818-144709
	- Closed: 20260818-165649
	- `sync` keeps its name; only its help line changes, to say it goes both ways.
	- Aliases are permanent - the Go build stays compatible with the 2.1.0 surface. `pullcom` also answers to `update`, `pull`, `pullc`, `pullco`, `pullcomm`, `pullcommit`; `br merge` also answers to `br land`.
	- Why: `update` reads like it updates gitsby itself, and says nothing about direction, where `pullcom` names both halves in the order they run. `merge` is what people reach for before `land`.
	- Go build only. The scripts keep their current spelling and stand as the reference.
	- The old spellings still work, so the demo gif stays correct - regenerate it once the Go build is release quality, not for this.
	- Done: renamed in the parser, the help, the four messages that named a command, and the internal tokens. The offline `sync` refusal now says the pull is the half that gets skipped. Run output is byte-identical to the frozen build under either spelling. The suite's go leg carries the checks for the new names and the aliases; two shared checks that pinned the old wording now take either. Go leg 438/0 -> 455/0.

- ✅ New command: `identity`.
	- Opened: 20260818-144709
	- Closed: 20260818-165649
	- The identity half of `status` on its own - account, ssh key and who it authenticates as, commit author, gh login - without the branch and working-tree state.
	- Same lines, same code as `status`, so the two can't drift. Answers outside a repository too, which is where you ask it before cloning or creating.
	- Read-only, so no confirmation and no plan. No alias; `whoami` and `who` were left alone rather than spent, since every alias is permanent.
	- Superseded 2026-08-21: the command is now `whoami`, with `who` and `identity` as permanent spellings of it. The two names that were held back were held back for this.

- ✅ Sweep the published docs for the renamed commands, and add `identity` to them.
	- Opened: n/a
	- Closed: 20260818-165649
	- Done: README.md command table (`pullcom`, `br merge`, new `identity` row) plus the prose around it, workflows.md, git_notes_and_oneliners.md. A short paragraph says the old spellings are permanent, and the PowerShell paragraph now names the one place the builds differ - the scripts predate both new names.
	- Safe to do now: this all sits on `gover`, which nothing ships from until the Go build releases. The published README is whatever `main` holds.
	- Historical changelog entries keep the names they shipped with; only vNEXT gets the new ones.
	- The `identity` row became `whoami` in the same docs on 2026-08-21; nothing else in the sweep changed.
	- `demo-scenario.toml` deliberately left on the old spellings. The aliases keep it correct, and changing text the scenario prints makes the committed gif stale, which the pipeline compares byte for byte. It rides along with the gif regeneration at release.

- ✅ Per-platform release artifacts with a checksum each.
	- Opened: n/a
	- Closed: 20260818-181424
	- Six targets: linux, windows and macOS, amd64 and arm64 each. Published as `gitsby-<goos>-<goarch>` (`.exe` on Windows) with one `SHA256SUMS` over the set. The list lives in `cicd/config.bash`.
	- Free because the module is pure stdlib with no cgo, so every target cross-builds from one box - macOS included, with no SDK and no Mac.
	- `--arch` becoming real belongs to the installer, which does not exist yet. See the installer item below.

- ✅ Retire the scripted implementations, and make the pipeline Go-specific.
	- Opened: 20260818-165649
	- Closed: 20260818-181424
	- `legacy/` holds the six frozen deliverables and nothing else: both builds and the four installers of that era, plus a README saying what they are. No copy of the pipeline - the v2.1.0 tag is a better hotfix tree than any copy could be, since it holds the scripts, the pipeline that built them and the installers all in their original places, unmodified.
	- A hotfix therefore starts at `git switch -c hotfix/2.1.1 v2.1.0`, ships from that branch with its own tag, and is never merged back to `main` - those paths do not exist there.
	- `cicd-win.ps1` deleted. One engine, everywhere, which also ends the hand-synced lint globs.
	- `parity.bash` kept and repointed, rather than dropped as originally planned. Comparing this build against the frozen one is exactly the backwards-compatibility question worth asking, and the harness for it already existed. It is stage 4 of the pipeline now, and it also checks that `update` and `br land` still route where they always did.
	- The suite runs one leg. The 58 checks that were never about an implementation - the installers, the frozen builds' own platform gates, the source pins on this pipeline's files - stayed, repointed at `legacy/`; they had only ever ridden the Bash leg because that was the leg that always ran. Counted before and after so none went missing: 530 pass, against 513 + 455 across the old three legs.
	- Pipeline is seven stages now: lint, build + test, fuzz, backwards compatibility, dogfood, demo gif, publish. The Go toolchain is required rather than probed.

- ✅ Installer for the Go build, and the README install section that documents it.
	- Opened: 20260819-095014
	- Closed: 20260819-103518
	- `install.bash` and `install.ps1` are back at the repo root, so the two documented one-liners resolve again once this reaches `main`. The `install-dev.*` pair was dropped rather than ported - a Go checkout needs only Go.
	- Both pick the binary by `<goos>-<goarch>`, which is what makes `--arch` real. `--ref` became `--tag`, since it names a published release rather than any git ref; both old spellings still bind.
	- The PowerShell one was kept. It is the only shell every Windows machine already has, and the only thing that puts the install directory on PATH. PSScriptAnalyzer came back into the lint stage with it, having been dropped when the scripted build was frozen.
	- `--release dev` is gone. It installed the tip of a branch, which a compiled product has nothing to offer; typing it says so and names the two routes that exist.
	- Every route is a release asset now, so every route is verified - the unverified branch of the plan no longer exists. `SHA256SUMS` is fetched before the plan is printed, because it is what says whether this platform has a binary at all, and it names the ones that do when this one doesn't.
	- FreeBSD joined the release matrix rather than being documented as an exception; it cross-builds for free. OpenBSD and NetBSD still fall through to the build-from-source message.
	- README: badges, "Compatibility" and "Install" rewritten for one binary and no runtime. The stale paragraph about the PowerShell build's option spellings is gone, replaced by a short note for anyone coming from 2.x.
	- Suite 582 -> 613. The new checks stop at the network: parsing, every refusal, the Windows hand-off, and pins on what a live run would reach. Verified end to end by hand against a fake release served locally - both installers, plus the tampered, intercepted, missing-release and wrong-architecture paths.
	- Left stale on purpose: design.md "Automating a release" still describes writing a version into two builds. That predates the Go round, not this one - filed below.

- ✅ design.md "Automating a release" still described the two-script era: a version written into both builds, footers in `bin/gitsby` and `bin/gitsby.ps1`, and phase 1 comparing two version strings.
	- Opened: n/a
	- Closed: 20260819-103518
	- Already current when this was checked. The section describes the three phases as they run, and says outright that the version lives in the tag and nowhere else - naming the two-build design as what it replaced, and why.

- ✅ Regenerate the demo gif. Stale twice over: the renamed commands moved text the scenario prints, and the pipeline now renders it from the Go build rather than the dogfooded script.
	- Opened: n/a
	- Closed: 20260821-181037
	- Done, and it needed the fixture fixed first: the real `gh` was answering as the rendering machine's own login, and the fake tokens' permissions put a warning on every scene. Both were on camera.

- ✅ Dogfood location change.
	- Opened: n/a
	- Closed: 20260821-181037
	- Three targets built and placed every run: linux to `util/linux/bin`, windows to `util/mswin/cli/by-self/win64`, macOS to `util/macos/bin`. Windows and macOS each carry a second spelling of the same share, for when the run is happening on that platform instead.
	- The old bash build is still sitting in `util/linux/bash` and nothing removes it. Worth clearing by hand.

- ✅ Release ordering: the build matrix runs before the release is cut, so a failed build never leaves a half-published release.
	- Opened: n/a
	- Closed: 20260821-181037
	- All six binaries are built in phase 1, alongside the pipeline gate. A target that stops compiling fails where nothing has been changed; found in phase 3 it would have left a pushed tag with no release behind it.

- ✅ The accounts file now lives where each platform keeps one.
	- Opened: 20260821-125351
	- Closed: 20260821-130130
	- One search order was used everywhere - `$XDG_CONFIG_HOME`, then `~/.config`, then `%APPDATA%` - which is the Linux convention applied to Windows and macOS as well.
	- Windows now reads `%APPDATA%\gitsby\config.shcl` and nothing else, macOS `~/Library/Application Support/gitsby/config.shcl` and nothing else. Linux and FreeBSD are unchanged.
	- Each platform's variable is read on that platform alone: `XDG_CONFIG_HOME` on Linux and the BSDs, `APPDATA` on Windows. Both used to be read everywhere, which let an MSYS session answer for a Windows run, and put a name Wine or Samba can leave set on a Linux run's credential search path.
	- `~/.config` is a Linux spelling too, so neither Windows nor macOS reads it any more - only where the native location can't be worked out at all. Users upgrading on either have a one-line move, called out in the changelog.
	- One ordered list now answers both "where do we look" and "where does a new file go", instead of three copies of the order in three files.

- ✅ `identity` is now `whoami`, and its help line says what it shows.
	- Opened: 20260821-104756
	- Closed: 20260821-105738
	- The command is a question, and the old name was a noun. Every shell already has a `whoami` that means this.
	- `who` and `identity` both still work, permanently. Those were the two names held back when the command was added.
	- The help line was "Who commands here act as: ..." - a sentence fragment where every other line starts with a verb. Now "Show account, ssh key, commit author, git host login."
	- The block it prints is still the identity block; only the command changed.

- ✅ The account diagnostic answers its own questions, and offers the fix as a command.
	- Opened: 20260820-174958
	- Closed: 20260820-182956
	- Read on a real Gitea repo, the block raised more questions than it settled: `'work-gitea' - no token applied` never said what token, applied to what, or what that string even was, and "that account doesn't say which forge it is for" used a word for people who already knew the answer.
	- The headline now names the token and the host it wasn't used for. `From:` says what kind of thing the name is and which of the several possible sources produced it, rather than repeating the name.
	- "Forge" is gone from the whole tool. The status line is `Git host`, and the notes say "git host" or name the host outright.
	- The notes read as sentences - capitalized, `SSH` spelled one way throughout.
	- `Kept:` names only the lines actually on screen. It said "the SSH and Author lines" whichever half applied, sending readers after an SSH line that was never printed.
	- `Fix:` names one command instead of a config line to copy: `gitsby account set <account> <key> <value>`, new, which makes the edit itself.
	- It stops short of making the edit unasked, and says why: all it knows is that the file never named a host, which is not the same as knowing the account belongs to this one - and guessing wrong hands one host's token to another.

- ✅ `account set` writes one key of one account into the accounts file.
	- Opened: 20260820-174958
	- Closed: 20260820-182956
	- Shows the edit and asks first; `-q` proceeds. Replaces that key's line, adds one, or creates the file.
	- Refuses a key nothing reads, and a value the loader would drop - a line written past either lands in the file and is ignored on every load, so the file says one thing and every command does another.
	- Everything else in the file comes back byte for byte: comments, spacing, a Windows byte-order mark, CRLF endings.
	- A key already present twice is refused rather than guessed at. `path` is repeatable by design.

- ✅ Other Git hosts are first-class; `gh` is reached for only when the remote is actually GitHub's.
	- Opened: 20260819-193000
	- Closed: 20260819-195612
	- Gitsby began as a GitHub program and asked `gh` for things Git could answer on its own, so a Gitea remote got GitHub errors about a repo `gh` was never looking at.
	- Where `origin` points is now established first, aliases resolved. `gh` serves github.com and `GH_HOST`; `tea` serves Gitea and Forgejo, under `tea-cli` as well - Debian renames it.
	- Everything answerable with Git alone works on any host with no forge client installed. `repo url` was the clearest case: it only rewrites text, and refused everywhere but github.com purely because of the URL parser.
	- Accounts gained `host` and `user`, so a token is applied only where it can be used and a non-GitHub token never goes out as `GH_TOKEN`.
	- A remote whose host can't be named still falls through to `gh`, deliberately - "couldn't tell" is not "definitely not a forge".
	- `repo create` and `repo connect owner/name` stay GitHub-only, being about GitHub specifically.
	- The tea path is written against tea's real command surface but has not been exercised against a live Gitea instance; the suite drives it through a stub.
	- Defect found and fixed before dogfooding: giving the credential helper a username interpolated the login into a string Git hands to a shell, so a `;`, a backtick or a `$()` in `ghAccount`/`GITSBY_ACCOUNT` ran as a command the moment an HTTPS push needed credentials. Both the token and the username now come from the environment. Fuzz gained four vectors driven through a real `git credential fill`; three of four fired on the pre-fix build.
	- Follow-up done: the identity gate covers non-GitHub hosts too. A tea write is compared against the ssh key like a gh write, and the push-side check reads the account's login on the host rather than `ghAccount`. Both were verified against the pre-fix build - a mismatched `pr create` went through and pushed.

Go port, round one. Rationale and route: `design_docs/20260813_golang-port.md`. Work top to bottom; everything happens on branches off `gover`, nothing touches the scripted implementations yet.

- ✅ Go scaffolding.
	- Opened: 20260817-113400
	- Closed: 20260817-115833
	- Module, `src-go/` tree, builds from the Linux cicd engine.
	- Version is a build-time value, not a line in the source.
	- Done: stub binary that owns only `version`; test stage builds it fresh each run, dev builds carry the git-describe version.

- ✅ Third suite leg in test.bash for the Go binary.
	- Opened: 20260817-115833
	- Closed: 20260817-170407
	- Mirrors the pwsh leg: a shim path, same fixture, same checks.
	- Skipped when no binary exists; failures don't fail cicd until the leg is expected to pass everything. Pass counts print either way so progress is visible per run.
	- Done: leg prints its own counts and stays out of the totals and the exit code. First run 162/279 - the passing side is mostly refusals a stub satisfies, so the failed count is the real distance.

- ✅ Go tooling in the lint stage.
	- Opened: 20260817-170407
	- Closed: 20260817-201711
	- gofmt, go vet, staticcheck. Shellcheck and PSScriptAnalyzer keep covering the pipeline and installers.
	- Done: stage 1 runs gofmt (list mode) and go vet as gates, staticcheck when installed. Keyed off `src-go/` existing, no globs, so nothing to mirror in the Windows settings yet. Verified the gate fails a misformatted file by name.

- ✅ Port the shared layer first.
	- Opened: 20260817-170407
	- Closed: 20260817-201711
	- Argument parsing, output helpers, and the process runner. Commands run from an argument list, no shell between.
	- Config read (`.shcl` stays flat and hand-parsed for now) and account resolution, same order and same env-only application.
	- Done: one file per concern in `src-go/`. `raw git`/`raw gh` shipped with it as the layer's first consumer, proving the whole chain - prescan, config, resolution, env-only application, hand-over - against the real suite. Verified side by side with the bash build: same messages, same credential helper, same commit identity. Leg moved 162/279 -> 182/259; the one new-code failure is the `--` check handing the go leg the PowerShell spelling, which is the known leg-name sweep in the command-slice item.

- ✅ Port a first command slice: `version`, `help`, `status`, `br list`.
	- Opened: 20260817-201711
	- Closed: 20260818-055519
	- Read-only commands, so the suite leg starts passing real checks with no mutation risk.
	- Note: any command named in an error message or help must be one the parser accepts.
	- Done: help/version/status/br list, plus the full command-sort validation so every known command refuses bad arguments with the script's own message before saying it isn't built yet. Status carries the whole identity block (account, config-ignored, SSH probe, author) and the capped change/incoming lists. Verified byte-identical against the bash build across status, br list, help, and every refusal path. test.bash leg-name branches now split pwsh from everyone else; the leg moved 182/259 -> 236/202, and every remaining failure in this area is prep leaning on a command from the next slice.

- ✅ Port the remaining read paths: `br prune` preview, `pr list`, default-branch resolution.
	- Opened: 20260818-055519
	- Closed: 20260818-090334
	- Done: `br prune` runs its whole survey and shows the real plan (including the empty-plan answers and the keep reasons); only the deleting half still says it isn't built. Bare `pr` lists and `pr <n>` views with diff; create/ok wait for the writers, and pr's argument shapes refuse with the script's messages. Default-branch resolution itself landed with the previous slice - what this adds is the refusal gate for commands that need a confirmable branch. Config-file errors now match the scripts' one-trailing-blank shape (they throw inside a command substitution there). All verified byte-identical against the bash build; the leg moved 236/202 -> 249/189, and every remaining failure in these areas needs the mutating half.

- ✅ Accounts, parity and release automation, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-181826

	- ✅ On Windows a folder rule spelled the way this shell spells paths resolved in one build and not the other.
		- Cause: the PowerShell build folded the drive letter *after* asking the filesystem, and .NET reads a `/c/...` path against the current drive - which never exists. So nothing resolved, and short names and junctions were left as written.
		- Fixed: fold the drive letter first. All four spellings now resolve identically in both builds, short names included.
		- Known limit, and now visible rather than silent: an MSYS *mount* path such as `/tmp/...` has no meaning to the native build and never can, since only the shell knows its own mount table. `account` marks any folder rule that resolves to no directory, which shows that up along with ordinary typos.

	- ✅ The identity lines reported the account that was resolved, not the one that was applied.
		- Fixed: an account with no token available now says so on the line. It is still resolved, but gh goes on using its own account - and the block whose whole job is answering "who does this go out as" was naming the wrong one.
		- Only for a configured or explicitly asked-for account; one inferred from the remote's owner is not a claim that we can act as it.

	- ✅ `sync` compared no identities before it pushed.
		- Fixed: the commands that push with git, rather than writing through gh, now ask whether the folder's account is the one origin will actually authenticate as. A warning interactively, a refusal unattended, and `--any-identity` says it was intended.
		- The https half is covered by the item above: gitsby supplies the token itself, so the push goes out as the resolved account or says it could not.

	- ✅ `account apply` wrote identity and key but nothing about credentials.
		- Fixed: the fragment now sets `credential.https://github.com.username`, so a credential manager looks up that account's entry rather than any entry for the host.

	- ✅ Added a parity suite: `cicd/parity.bash`, wired into the test stage of both engines.
		- It asks whether the two builds *answer the same* for one input, where `test.bash` asks whether each behaves correctly. A behavioral check written per implementation passes on both while they quietly disagree - which is what every port defect that reached users actually was.
		- Covers path spellings, option forms, string case and file encoding: 23 comparisons.
		- It earned its place while being written, finding two real divergences: the `/tmp` mount limitation above, and PowerShell answering an unknown option with the entire help text - and under `-q` with nothing at all but an exit code - where Bash named the option.

	- ✅ `br prune` asked about one branch at a time.
		- Fixed: `git for-each-ref --merged` answers for every branch in one call per target ref, instead of two ancestry questions per branch. The delete-time re-check stays per branch, deliberately: that one is the safety net, not the survey.
		- Verified on a 33-branch repo - the same 30 merged branches pruned, the same 3 unmerged kept.

	- ✅ Fully automated releases, end to end: `cicd/release.bash`, to the three-phase shape in `design.md`.
		- Phase 1 verifies and changes nothing, phase 2 is the only one that pushes, and phase 3 publishes and then proves the result the way a user meets it - by running the documented installer against the published release.
		- Both guards exist because the thing they check has already gone wrong: the two builds' version strings drifting apart, and the history footers going a whole release with no entry.
		- `--dry-run` says what each phase would do and changes nothing. Writing it that way immediately caught a bug in the script itself: a loose version match picked a version-shaped string out of a comment, which phase 2 would then have rewritten instead of the real declaration.

- ✅ Multiple GitHub accounts, chosen by which folder you are in, for both git and gh.
	- Opened: n/a
	- Closed: 20260808-105027
	- People with two accounts already keep a folder per account. A config file maps a folder tree to an account, and everything under it acts as that account - gh, git's credentials, the ssh key, the commit identity.
	- The platform's own config location - `%APPDATA%` on Windows, `~/Library/Application Support` on macOS, `$XDG_CONFIG_HOME` or `~/.config` elsewhere - flat `key = value` lines, overridable with `--config FILE` or `GITSBY_CONFIG`. With no config file at all, nothing changes.
	- The ssh-key-and-host-alias trick is no longer needed: over https, git authenticates with the account's own token. Keys stay fully supported for anyone who wants them.
	- `repo url [https|ssh]` converts an existing remote, which is the only thing between an ssh repo and a token.
	- `account` explains what is configured and which account applies here. `account apply` writes the same rules into the global git config, so plain `git` matches.
	- `raw git` and `raw gh` run either tool as the folder's account, verbatim, so scripts can use gitsby as a drop-in prefix.

- ✅ A Windows-native CI/CD pipeline, so the whole thing can be run from Windows and not only from Linux.
	- Opened: n/a
	- Closed: 20260808-095515
	- `cicd/cicd-win.ps1` runs the same six stages as `cicd/cicd.bash`, with the same options under PowerShell spelling and the same output shape, so the two read side by side.
	- The publish stage is a native port of `n8git_backup-and-publish`, minus the rar version archive - skipped by request, since git carries the history.
	- The demo gif is compared, never regenerated. Reproducing it byte for byte depends on fontconfig, the installed fonts and the pinned optimizer, none of which Windows matches - a render here would land a file the next Linux run flips straight back.
	- Stages whose tool is missing warn and skip, as they already do on Linux. On a stock Windows box that is markdownlint and the demo gif.
	- Settings are carried in the script rather than read from `config.bash`; only the dogfood destinations genuinely differ.

- ✅ Run the PowerShell leg of both suites on Windows, not just on Linux.
	- Opened: n/a
	- Closed: 20260808-095515
	- It had never run there, and it found a real defect the Linux-only habit had been hiding for as long as the identity work existed.
	- Two things blocked it. PowerShell finds a shebang stub on PATH but starts nothing and reads the silence as empty output, so every stub gained a `.cmd` sibling that hands the body back to bash. And the confirmation checks needed `setsid`, which Windows has none of - unnecessary there, since PowerShell reads redirected stdin and never reaches for a terminal.
	- Fuzz keeps a plain stub and skips four checks on that leg instead. Its arguments are hostile on purpose, and `cmd.exe` re-parses an unquoted `&` or `>`: a vector would partly run for real, and be reported as an injection gitsby never had. A skip that says so beats a pass that isn't one.
	- The ssh probe now starts the ssh PowerShell itself resolves rather than letting `ProcessStartInfo` search PATH its own way - which on Windows reached the real `ssh.exe` and would have gone to github.com, against the suite's promise never to touch the network.

- ✅ Say what a branch is branched from, wherever a branch is named.
	- Opened: 20260731-080041
	- Closed: 20260731-083030
	- Reported against `br hotfix` run from `dev`: the current-branch line read `dev` while the plan directly under it checked out `main`. Both were correct and nothing connected them.
	- Branch names now render as `base :: branch` - `dev :: feature/retries`, `main :: hotfix/readme`. `main`, `master` and `dev` stay bare; they are not off anything you would work from.
	- `br create` and `br hotfix` gained a `New branch` line naming what they will make and its base, so the answer is on screen before the plan is read. Pre-flight only - after the run the branch exists and the question is gone.
	- The repo's default branch moved to its own line instead of riding along in parentheses, and `br list` now states it too.
	- The base shown is where the branch lands. Git records no fork point, and for anything gitsby made the two are the same by construction.

- ✅ Show the file list before first publication (`repo create`, `repo connect` from a plain directory).
	- Opened: n/a
	- Closed: 20260728-073221
	- Every other command shows what it is about to touch; the one that hands a whole directory over for the first time did not.
	- The list is what `git add --all` will really add, asked through a throwaway git dir outside the work tree - so `.gitignore` and `core.excludesFile` are honored, and answering "n" leaves the directory exactly as it was found.

- ✅ `br hotfix <name>`: a branch that targets the default branch instead of `dev`, for corrections to published material.
	- Opened: n/a
	- Closed: 20260727-000406
	- The branching model is written up in `design.md`; this is the command that carries it.
	- Branches off the default branch, pushed as `hotfix/<name>`. The prefix is the marker, so it survives a clone and shows in a branch listing. A name given with the prefix already on it is accepted rather than doubled.
	- `br land`, `pr create`, and `pr ok` recognize a `hotfix/` branch and target the default branch, then merge it back into `dev`. `br create` still comes off `dev`, so feature work is untouched.
	- A back-merge that conflicts aborts and leaves `dev` alone, reporting that the hotfix landed and naming the two commands to finish by hand. Conflict surgery stays raw-git territory.
	- Landing warns when the branch touched `bin/`: the default branch would then carry code no tag contains, so the latest release's downloads no longer match it.
	- Implemented as `fBranchTarget` / `Get-BranchTarget` alongside the existing merge target, rather than by changing `fMergeTarget` - "where new branches come from" and "where this branch lands" are different questions, and only the second one varies.
	- 30 new checks across both implementations. Verified the pre-feature build rejects `br hotfix` outright.

- ✅ Release-prep sweep over the docs and the built-in help.
	- Opened: 20260726-125534
	- Closed: 20260726-130242
	- The help still described `sync` as commit-then-pull. That order changed when the bare `pull` command was dropped, and this line was missed. The README already had it right.
	- A regression check pins the wording, so the same drift can't come back quietly.
	- Also two stale references in the project notes: a command name that was renamed, and a description of argument parsing from before the noun grouping.

- ✅ `br prune`: delete branches already merged into the merge target, local + remote.
	- Opened: 20260726-110940
	- Closed: 20260726-112615
	- Nothing cleaned up after a PR merged from the web UI or another machine, or after an abandoned branch. `br land` and `pr ok` only ever delete the one branch they just merged.
	- Kept safe by what the tool already enforces: every landing is a real merge commit, so ancestry is an exact test. Unmerged branches are listed and left alone, and there is no `--force`.
	- The remote copy is only deleted once origin's own merge target contains it, so an unpushed landing can't strand work.
	- Verified the safety gates discriminate: a version with the ancestry check removed deletes an unmerged branch, and one without the origin-side check deletes origin's only ref to unpushed work.
	- Deletes with `git branch -D` behind our own check. Deferring to `git branch -d` was tried first and was wrong both ways: it warns about HEAD on every branch when pruning from anywhere but the target, and it flatly refuses a merged branch that was never pushed, so the plan promised a deletion that silently didn't happen.
	- Closes with a count (`Pruned 3 local, 3 on origin`) and names what it kept, so a wall of git output still ends in a plain answer.

- ✅ Drop the bare `commit` and `pull` commands - both work around the opinionated workflow.
	- Opened: 20260726-101513
	- Closed: 20260726-102919
	- `commit` alone leaves work committed but unshared. `pull` alone was the only place the tool took upstream changes without parking your own, unlike every other command.
	- Reversible in one direction only: dropping now is free, adding back later breaks nobody, removing later would.

- ✅ `update`/`sync` pull before they commit (bug this exposed, present on dev).
	- Opened: 20260726-101513
	- Closed: 20260726-102919
	- Committing first guaranteed divergence whenever the remote had moved, so the ff-only pull refused - in the most ordinary case there is. `pull` had been the accidental workaround.
	- Verified against the pre-fix build: it fails, the fixed one lands the work on top and keeps history linear.

- ✅ An unreachable remote warns and skips the pull instead of failing; `--no-fetch` means offline and skips the pull too.
	- Opened: n/a
	- Closed: 20260726-102919
	- Needed because `update` is now the only way to commit; a genuine non-fast-forward still fails hard.

- ✅ Group the infrequent commands under nouns: `repo clone|create|connect`, `br list|create|switch|land`, `pr create|<n>|ok <n>`.
	- Opened: 20260726-095211
	- Closed: 20260726-100901
	- Daily verbs stay one word. The extra word only lands where you type it rarely, and it buys a discoverable set instead of a flat list of abbreviations.
	- One verb across all three nouns (`create`, never `new` in some places). `new` and `go` still work but aren't published.
	- Landed before v2.0.0 on purpose: every name being changed was unreleased, so it cost nothing now and would have cost a permanent alias later.

- ✅ Split the old `connect` into `repo create` and `repo connect`.
	- Opened: 20260726-095211
	- Closed: 20260726-100901
	- Creating a remote is the one irreversible, outward-facing step, so it gets its own verb instead of happening as a side effect.
	- Each refuses the other's case and names it, so a wrong guess costs one line of output.

- ✅ Drop every pre-2.0 command alias (`scommit`, `spull`, `scompul`, `saveup`, `spush`, `mkbranch`, `chbranch`, `mtm`, `list`).
	- Opened: 20260726-095211
	- Closed: 20260726-100901
	- v2 is a clean break under a new tool name, and not all of the old commands worked. The suite now asserts they're rejected, so none creeps back.

- ✅ `pr new [title]` opens a pull request, so the whole PR round trip lives in gitsby instead of half in `gh`.
	- Opened: n/a
	- Closed: 20260726-092038
	- Pushes the branch first - GitHub can only diff what the remote has.
	- Targets `dev` when the repo has one, else the default branch. Refuses from that branch, since there is nothing to propose.
	- No title given: the last commit subject, which is already a description of the work. The preview shows it before anything happens.
	- An already-open PR for the branch reports its number instead of letting `gh` error.

- ✅ `pr ok <n>` refuses while the current branch has uncommitted changes or unpushed commits.
	- Opened: n/a
	- Closed: 20260726-092038
	- Merging deletes the branch local and remote, so work that never reached origin was outside both the PR and the merge.
	- Every other mutating command already parked work first; this was the one that did not.

- ✅ The installers' default "latest release" lookup skips anything flagged as a pre-release on GitHub.
	- Opened: n/a
	- Closed: 20260726-082146
	- GitHub's `releases/latest` returns the newest full release, so a pre-release-only repo resolves to the last full one - for this repo, the 2022 release.
	- Decided: publish releases as full releases rather than adding a `--pre` flag. The semver suffix still marks a candidate for anyone reading the tag, and the one-liner installs keep working with no extra arguments.
	- `--ref`/`-Ref` remains the way to install a specific tag or branch, and is already documented.
	- Reversed 20260916: a tag with a semver suffix publishes as a pre-release. Both installers read the release list now instead of the `releases/latest` redirect, so the reason this decision existed is gone. See enhancement 5 and design.md's release policy.

- ✅ CICD process (full spec in private notes):
	- Opened: 20260724-142509
	- Closed: 20260726-082146

	- Done: every stage below is live and runs on each publish. The pipeline is local by design - no cloud service, no account to pay for.

	- ✅ `cicd.bash`: `-q|--quiet`, `-m|--msg|--message`, prompt for commit message when neither given (CTRL+C aborts); silkterm output style; `fEcho`/`fParseArgs` conventions.

	- ✅ Linting stage: shellcheck (+ markdownlint), no auto-format for Bash; output GFS-rotated to `cicd/artifacts/lint/`; zero-error goal.
		- Everything gates clean now, including `bin/gitsby` (the refactor cleared its ~80 legacy findings; report-only list emptied). PSScriptAnalyzer gates the three `.ps1` files.

	- ✅ Dogfood install stage: copy to first existing preferred dir (bash + pwsh lists).
		- Both legs live since the pwsh port landed.

	- ✅ Regression tests; keep updated as features/bugs land.
		- `cicd/test.bash`: throwaway repos (bare origin + two clones), every command plus failure guards, run once per implementation - 140 checks.

	- ✅ Adversarial fuzz/security testing (our input surface + what we depend on).
		- Done: `cicd/fuzz.bash` - bombards the command slot, options, and branch/message/version/pr args with malformed + injection vectors, per implementation (bash + pwsh). Asserts three invariants: no internal crash (bash/pwsh error-dump signatures), no shell/command injection (a canary side-effect never fires), and inputs-that-must-refuse exit nonzero leaving the repo unchanged. 191 checks. Found + fixed two real pwsh-port bugs (see next items). Scope is gitsby's own input, not upstream git.
		- Fuzz-found bug (fixed here): the pwsh port passed user-supplied values to native git UNquoted, so PowerShell wildcard-expanded `*`/`?` against the filesystem before git saw them - `newbr '*'` slipped past `check-ref-format` and created a branch named after a file. Quoted the user values in the direct git/gh calls (branch validation, clone-dir, gh target), mirroring the bash port. bash was never affected (always quoted).

	- ✅ pwsh: `Invoke-Git` splatted an argument array (`git @GitArgs`), and PowerShell wildcard-expands any element that is a bare `*`/`?`/`[...]` matching files in the cwd - so a commit message of exactly `*` globbed to filenames.
		- Done: `Invoke-Git` now runs git via `System.Diagnostics.ProcessStartInfo` + `ArgumentList` (a literal argv - no PowerShell reshell or globbing), `UseShellExecute=$false` with no redirection so git output still shows inline. Tried and rejected: quoting splat elements (splat drops quoting), `[WildcardPattern]::Escape` (git receives the backtick), `Start-Process -ArgumentList` (re-splits multi-word elements like a spaced message). Verified messages with `*`, spaces, `?`, `[ab]`, `;$(...)`, quotes, and emoji all land verbatim; exit codes propagate; no injection. Locked with `fMsgLiteral` verbatim-message vectors in `cicd/fuzz.bash` (both implementations). Fuzz 183 -> 191; test.bash still 269/0; PSSA clean.

	- ✅ Automated demo GIF (fake terminal, `--quick` skips); copy `gen-demo-gif.py` from convert-base-v2; embed `assets/demo.gif` in README.
		- Done: scenario `cicd/demo-scenario.toml` + repo builder `cicd/utility/demo-repo.bash`; embedded in README top with a commented YouTube placeholder. Single hero `land` command (state block + full plan + commit/push/merge/cleanup) in an anonymized throwaway repo built offline; runs real gitsby so it can't go stale. 960x540 (the tool's default, a blessed alternative in the private note; not 640x360, and the tool has no fixed-fps knob). Pinned commit dates make it byte-deterministic so cicd only regenerates on real change. 18.4s loop, 823 KiB.
		- Follow-up: one command was too thin a story, so the scenario now runs a whole feature end to end - `status`, `newbr`, `update`, a real edit typed at the prompt, `sync`, `land` - with a short comment line introducing each. Two generator fixes came out of it: stderr now shares the stdout pipe (git writes its progress there, so it was all landing after the program's own output instead of under the step that produced it), and the palette pads to the next power of two rather than a flat 256 (same pixels, ~12% smaller file).
		- Follow-up: the smooth scroll and the cursor glide were never actually running. Both stepped once per 80ms frame, and a line of scroll is 21px, so any scroll rate over ~275 px/s finished a line in a single frame - a hard jump, and the rate knob did nothing (325, 520 and 820 all rendered byte-identical). Frame interval is now 20ms (50 fps) and the cursor glide follows it, so both move as intended. A smooth scroll redraws the whole text block every frame, which is expensive, so a new per-step `clear = true` starts each command on a fresh screen and roughly halves how far the view ever travels. 60.0s loop, still byte-deterministic.
		- Follow-up: cicd now runs the render through `gifsicle -O3` when it is installed, before the compare, so the committed file is the optimized one (`DEMOGIF_OPT_CMD` in config.bash; silently skipped when absent). Worth about 9% - 7.3 -> 6.6 MiB. Less than it sounds like it should be: the renderer already crops each frame to what changed, so most of the win was banked, and the lossy modes buy almost nothing on a 35-color text demo.

- ✅ New commands for getting connected: `clone` (get an existing repo) and `connect` (publish work that only exists locally to a new or empty remote).
	- Opened: 20260724-133000
	- Closed: 20260724-141714
	- `clone <url> [dir]`: derives the dir from the URL, checks out `dev` when the repo has one, re-run is a no-op.
	- `connect [target]`: init if needed, commit, push. URL to an existing empty remote, or `owner/name` creates the GitHub repo via gh (`--public`/`--private`). Refuses remotes with history and won't change an existing origin.
	- Done: both implementations, previewed + confirmed like the rest; tests 207 -> 241.
	- Follow-up: logically validated (no bugs) and exhaustively tested. Closed the "gh paths untested offline" gap with a hermetic fake gh (create / add https+ssh / refuse-nonempty), plus clone edges (no-dev, pre-existing empty dir, different-url refuse) and connect edges (empty inited repo, matching-url re-connect). Tests 241 -> 269, both implementations.

- ✅ One-liner installers for Bash and PowerShell: download the release, verify the checksum, install the script. Idempotent, and they state the plan and ask before touching anything. Documented in README under "Installation", including a "Direct" subsection with the commands and the install locations.
	- Opened: n/a
	- Closed: 20260731-141354

	- Done: `install.bash` and `install.ps1` cover it. Checksum verification against a published `SHA256SUMS` landed with code review item 19, and the README "Direct" subsection lists both the commands and the paths each installer uses.

	- Note on the spec's option names: `--arch` doesn't apply, since gitsby is a script rather than a compiled binary. `--release dev|stable` is spelled `--ref`, and `--target user|system` is spelled `--system` (user is the default).

	- Note on install paths: gitsby is a single file, so it goes straight to `~/.local/bin` or `/usr/local/bin` rather than into a program directory with a symlink.

- ✅ Rename `saveup` to `update`.
	- Opened: 20260723-140731
	- Closed: 20260723-141405
	- Done in both implementations; `saveup` stays as a hidden alias like the other old names. Docs and changelog swept.

- ✅ Script output starts and ends with a blank line (breathing room between prompt text).
	- Opened: n/a
	- Closed: 20260723-141405
	- Trailing blanks already existed on every exit path; added the leading one (both implementations). Error paths were already blank-wrapped.

- ✅ After `release` merges dev to main, bring dev up to include the release merge and tag.
	- Opened: n/a
	- Closed: 20260723-141405
	- Done via `git merge --ff-only main` on dev (then push), not `git branch -f dev main`: same result normally, but if dev gained commits mid-release it skips with a warning instead of discarding work. Previews updated; tests cover it.

- ✅ 'git_notes_and_oneliners.md': Move the current commands under a "Bash" section, and add a "PowerShell" section below it, with pwsh v7 parity versions of the same one-liners.
	- Opened: 20260723-133000
	- Closed: 20260723-135833
	- Two mirrored sections, same task headings in the same order, so the two are easy to compare side by side.
	- The PowerShell section opens with the three gotchas that bite when translating from Bash: `&&`/`||` need pwsh 7, `@{u}` has to be quoted, and staged-change tests read `$LASTEXITCODE`.
	- Every pwsh one-liner was run against throwaway repos, not just eyeballed. Two spots deviate on purpose: no `less` (git pages its own diff), and `Remove-Item` deletes outright since there is no cross-platform `trash`.
	- Also swapped the stale sister-tool reference in the Bash "push local changes" one-liner for `gitsby update`.

- ✅ All potentially destructive or conflict-producing commands - or anything that will reveal a user identity on the remote - should:
	- Opened: n/a
	- Closed: 20260723-134733
	- Show what's going to change (including a list of changed files, piped through an internal equivalent of `... | less -FX` if necessary)
	- git status without line-breaks, and SSH connection info. And a prompt to continue. All with standard 1 blank line where appropriate.
	- Every mutating command already previewed its plan and prompted; this added the identity and change detail. `status` shows the same block.
	- SSH line resolves the remote URL through `ssh -G`, so a `~/.ssh/config` host alias shows the real host and key behind it - the point being to catch acting as the wrong account before you push. (It later grew the account itself, which is the part that actually answers that; see the bug above.) Author line shows what git will actually stamp on the commit.
	- Changes list one file per line (short form), truncated to the terminal width and capped at 25 with an "and N more" tail - the `less -FX` idea without depending on a pager. Incoming section lists what a pull would change, and the branch line carries ahead/behind.

- ✅ Better command names; dev-aware merging; PR and release commands (both implementations).
	- Opened: 20260722-200007
	- Closed: 20260722-201054
	- Renames: scompul->saveup, spush->sync, scommit->commit, spull->pull, mkbranch->newbr, chbranch->gobr, list->listbr, mtm->land. Old names still work as hidden aliases.
	- newbr/gobr/land now branch off / land on dev when the repo has one, else main/master. land refuses to run from the default branch.
	- New: pr (bare = list, n = view + diff, ok n = approve + merge, via gh), release (merge dev into main --no-ff, tag, push; no version = patch bump on the latest v* tag).

- ✅ PowerShell port of gitsby (style guide already covers pwsh; dogfood pwsh leg activates when it lands).
	- Opened: 20260722-182703
	- Closed: 20260722-183557
	- `bin/gitsby.ps1`: same commands, checks, and flow as the bash version. Regression suite now runs once per implementation (78 checks total); PSScriptAnalyzer joined the lint stage (gates all three .ps1 files); dogfood pwsh leg live. Not in a release yet - README says to use `-Ref dev` until one is cut.

- ✅ Create a release-install script per platform (`bash` and \[`pwsh` or `cmd`\]), runnable via a single `curl`/`wget` (etc.) and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort. Update README.md with one-liner for both local and system-level installs.
	- Opened: n/a
	- Closed: 20260722-181311
	- `install.bash` + `install.ps1` at repo root; plan-then-confirm, `--system`/`-y`/`--ref`; README Installation one-liners filled in (user + system, curl and wget). Resolves the latest release tag, prefers a release asset, falls back to the tagged tree. The 2022-era releases predate the `bin/` layout so the release path activates for real once a v2 release is cut (`--ref main`/`--ref dev` works today); the pwsh installer says the port hasn't shipped and points at the bash one until then.

	- ✅ Do the same thing for a dev-branch install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort. Update README.md with one-liner for both local and system-level installs.
		- `install-dev.bash` + `install-dev.ps1`: clone, check out `dev`, check tooling (offers package-manager install where one is found), verify, print next steps. Documented in README "How to develop" + contributing.md "Your First Code Contribution". Bash installers run on macOS stock bash 3.2.

- ✅ Get original commands and options working. At some point some just kind of broke (pre-git), and were never fixed.
	- Opened: n/a
	- Closed: 20260722-165821
	- All commands work and are regression-tested; the commit/save/sync/land family takes -m or a positional message, newbr/gobr validate their branch argument.

- ✅ Integrate these rules and ideals: `reference/git.txt` (in this repo), including:
	- Opened: n/a
	- Closed: 20260722-165821
	- Push hygiene (stash / pull --ff-only / stash apply / add / commit / push) is now the core of pull/saveup/sync; branch workflow lives in newbr/gobr/land.
	- Work on feature branches
	- PRs to merge to develop
	- Commit frequently
	- Pull frequently, push infrequently
	- Push hygene:

		~~~bash
		git stash
		git pull --ff-only
		git stash apply
		git add .
		git commit -m ""
		git push
		~~~

- ✅ Make sure everything done with git:
	- Opened: n/a
	- Closed: 20260722-165821
	- Every command verifies state first and is idempotent: stash only if dirty (pop only what was pushed), pull only with an upstream, push only if ahead, commit only if changes; main/master detected from origin HEAD, not hardcoded. All covered by the regression tests.

	- Is done safely. E.g. before stashing, verify safely in a robust way that makes no assumptions, that there is anything to pull. `n8git_backup-and-publish` has examples.

	- Never make assumptions about the local and/or repo state. Verify first for every command, whatever is relevant for the command.

	- Everything must be idempotent.

- ✅ Refactor the bash script:
	- Opened: n/a
	- Closed: 20260722-165821
	- Rewritten 2142 -> ~620 lines on the current template generation (same one as `n8git_backup-and-publish`): strict mode, trap suite, arg parser, minified header trio.

	- ✅ Use newer, easier-to-maintain Bash template/boilerplate/common functions. (E.g. from sister project silkterm.) But even those examples need to be cleaner (don't change anything outside of repo.)

	- ✅ Modernize function and variable naming convention. Be descriptive with names, but not too long. Use of one-letter variables in small loop structures is OK.

	- ✅ Remove dead code.
		- Dropped the unused ~1400-line generic library (ping, symlink, editor pickers, sudo plumbing, glob-permutation engine, platform detection).

	- ✅ Refactor to maximize usefulness of idiomatic Bash 5 features.
		- Argument arrays instead of eval (which also retired the curly-quote message mangling), `[[ -v ]]`, parameter transforms, arithmetic conditionals.

- ✅ Work on dev branch. Push releases to main.
	- Opened: n/a
	- Closed: 20260722-165821

	- ✅ `dev` branch created from `main` and pushed; feature branches now merge to `dev`, `main` is release-only.

- ✅ Create PRs rather than pushing directly (for this project).
	- Opened: n/a
	- Closed: 20260722-165821
	- Feature branches now go up as PRs to `dev` and land via merge commit; direct local merges retired.

- ✅ Delete stale branch from 2020.
	- Opened: n/a
	- Closed: 20260722-165821
	- `20201003-074416_jc_rewrite-in-golang` (abandoned golang rewrite) deleted from origin.

### Deferred

Waiting on hardware, an upstream module, or a decision.

- ✋ The repo's blurb, homepage and topics still describe the Bash and PowerShell product.
	- Opened: 20260819-142046
	- They name both scripts and give the old command count, and the topics say `bash` rather than `go`.
	- Deferred until the Go build is released on `main`. Until then the description would be ahead of what a visitor can actually download, which is worse than being behind.
	- One command when the time comes: `gh repo edit --description ... --homepage ... --add-topic go --remove-topic bash`.

- ✋ macOS signing and quarantine on real ARM hardware: does a terminal download need either?
	- Opened: 20260817-115422
	- All that is left of the old macOS item. The build half is settled and filed under done.
	- Also untested on Apple silicon: the universal binary running at all. Its arm64 half has a valid ad-hoc signature, checked on b26 2026-10-05, but b26 is Intel.

- ✋ GitHub Actions and platform packaging (.deb/.rpm/.exe installer), deferred to the port by decision.
	- Opened: 20260817-115422
	- The port is underway now, so this is decidable rather than deferred. Two calls: whether a bare workflow (vet, test, build on push and PR) is worth the dependency on a hosted service, and whether a release packager earns its place by bringing the Linux packages with it.
	- Against the packager: the release already proves itself by downloading, checksumming and running the asset, which is more than it would do. For it: the packages come free.
	- Note: stays deferred, asked 2026-10-06. The project should lean on any one git host as little as it can.

### Canceled

## Template

### Old format

- 🔘 Not started

- 🛠️ Started, and/or partially complete

- 🔬 Testing not started or finished

- ✋ Defer

- ✅ Complete

- 🚫 Canceled

### New format

- Notes:

	- Only use rows that you actually need or expect will be filled in. Always fill in the title, ID, Type, Status, Opened and Created by.

	- The ID is the local time to the hundredth of a second. Opened is when it was written down, which may differ. (Use a keyboard macro and possibly something like project 'zuid' to generate.)

	- Status values meaning: Testing means the fix is in and checks are running or still to run. Waiting on signoff means automated testing passed. Moot means something else changed that made it irrelevant. Canceled means it still applies but was decided against. Waiting on automated testing means the fix is in and waits on a test run with no person needed. Waiting on a partial CICD run means it waits on a run of some stages, started by a person or automatically. Waiting on a full CICD run means the same for the whole pipeline, including a remote test host. Waiting on UAT means a person has to try it, such as on a box only they have. Can't reproduce means a real attempt to reproduce it failed.

	- An item waiting on signoff that is hard to test by hand is closed once the fix is sure and a regression test covers it, where one can be written.

	- As issues are worked, and statuses change, place them in correct sorting order within the list:
		- First by status: Waiting for answers, Waiting on signoff, Testing, Waiting on automated testing, Waiting on a partial CICD run, Waiting on a full CICD run, Waiting on UAT, Can't reproduce, Stalled, Started, Queued, Done, Deferred, Canceled, Moot
		- Then by severity|priority: Critical, High, Avg, Low
		- Then by type: Bugs, [not bugs together]

	- Rows marked [Bug] are for bugs only, and rows marked [Feature] for features and enhancements. Priority and Severity share one row and one scale. Priority is for a Feature or Enhancement, and Severity for a Bug. Children are not nested. They sit at the top level and point back with Parent ID.

Template:

- Title
	- ID: YYYYmmDDHHMMSSNN
	- Type: [Bug|Feature|Enhancement|Task]
	- Status: [Queued|Waiting for answers|Waiting on signoff|Waiting on automated testing|Waiting on a partial CICD run|Waiting on a full CICD run|Waiting on UAT|Started|Testing|Stalled|Can't reproduce|Moot|Canceled|Deferred|Done]
	- Needs local test suite run?:
	- Needs external testing:
	- Priority [Feature|Enhancement] | Severity [Bug]: [Critical|High|Avg|Low]
	- Opened:
	- Opened by:
	- Assigned to:
	- Parent ID:
	- Prereq IDs:
	- Related IDs:
	- Target OS:
	- Test environment:
	- Version and build:
	- Requirements  [Feature]:
		- Hierarchical bulleted list.
	- Steps to reproduce [Bug]:
		- …
	- Incorrect behavior [Bug]:
	- Expected behavior [Bug]:
	- Reproduced [Bug]: [No, or when, where and how]
	- Possible cause [Bug]:
	- Actual cause [Bug]:
		- …
	- Estimated effort: [High|Avg|Low]
	- Actual effort: [High|Avg|Low]
	- Progress log:
		- …
	- Decisions:
		- …
	- Actual fix [Bug]:
	- Branch:
	- Commit:
	- Test case: [Reason not applicable, or CI test case #]
	- Acceptance signoff:
	- Superseded by ID:
	- Closed:
