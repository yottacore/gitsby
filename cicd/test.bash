#!/usr/bin/env bash

#  shellcheck disable=2317  ## 'Can't reach.' False hits on functions invoked indirectly.

##	Purpose:
##		- Regression tests for the compiled build in src-go/.
##		- Run by cicd.bash stage 2, which builds the binary first, or standalone
##		  after a 'go build' by hand.
##		- Carries a second set of checks that are not about the implementation at
##		  all: the installers, the frozen v2.1.0 scripts' own platform gates, and
##		  source pins on this pipeline's files. They used to ride the Bash leg
##		  because that was the leg that always ran; they were never about Bash.
##		- Builds throwaway repos (a bare 'origin' + two clones) under mktemp;
##		  never touches the real repo or network.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404 )); then
	printf '%s\n' "${0##*/}: needs bash 4.4 or newer, and this is bash ${BASH_VERSION}. On macOS, install one with 'brew install bash' and put it first on PATH." >&2; exit 1
fi
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
## Resolved, because the build reports a folder with its links resolved. On macOS mktemp answers
## under /var, a link to /private/var, and with a doubled slash when TMPDIR ends in one.
work="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gitsby-test.XXXXXX")" && pwd -P)"
trap 'rm -rf -- "${work:?}"' EXIT

## Keep test commits hermetic (no reliance on the user's git config).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

## Same reasoning, for gitsby's own config: whoever runs this may have accounts configured, and
## that file decides which account a command acts as. A single 'protocol = ssh' line in it is
## enough to make the repo commands build a different remote URL than the check expects. The
## account block below sets its own HOME and opts back out of this with an empty value.
export GITSBY_CONFIG="${work}/no-accounts.shcl"; : > "${GITSBY_CONFIG}"

## The blocks that test config DISCOVERY opt out of the pin above and fake HOME instead, so they
## have to neutralize the other two candidates by hand: XDG_CONFIG_HOME is tried before HOME and
## APPDATA after it, and on a machine where either is set it answers for the real user. Emptied
## rather than pointed somewhere, so HOME stays the candidate under test. Without this those
## blocks quietly read whatever accounts the person running the suite had configured, and went
## red the day they configured any.
acNoDiscovery="GITSBY_CONFIG= XDG_CONFIG_HOME= APPDATA="
## So every run behaves like one on a machine with accounts configured: a block that drops the
## pin and forgets the line above finds an account covering every folder the suite makes, under
## a login no check expects, instead of passing on a clean box and failing on a real one.
poisonRoot="${work}"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) poisonRoot="$(cygpath -m "${work}")" ;; esac
mkdir -p "${work}/poison-config/gitsby"
printf 'account: poison\n\tpath: %s\n\tghaccount: poisonacct\n' "${poisonRoot}" > "${work}/poison-config/gitsby/config.shcl"
export XDG_CONFIG_HOME="${work}/poison-config" APPDATA="${work}/poison-config"

## Nothing here may reach the network. A check that did passed until a few runs in an hour used up
## GitHub's anonymous API limit, then failed for reasons that had nothing to do with the code. A
## proxy on a closed port makes curl, git over https, gh and pwsh's web cmdlets fail on every run.
export HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 all_proxy=http://127.0.0.1:9
unset NO_PROXY no_proxy

## Two more inputs the lines above do NOT cover, both of which reach us from an ordinary
## working terminal rather than from a config file:
##   - GIT_CONFIG_COUNT/KEY_n/VALUE_n outrank every config FILE, including a repo-local one
##     and the GIT_CONFIG_GLOBAL set above - so pinning the files is not isolation on its own.
##   - GH_TOKEN and friends are what the fake gh reports back, so an inherited one makes every
##     "gh was left alone" check read as "gh was handed a token".
## Neither shows up as a failure you can act on: the suite just reports checks that were never
## about the thing they name.
fUnsetInheritedGitConfig(){
	local -i i=0
	for (( i = 0; i < ${GIT_CONFIG_COUNT:-0}; i++ )); do unset "GIT_CONFIG_KEY_${i}" "GIT_CONFIG_VALUE_${i}"; done
	unset GIT_CONFIG_COUNT
}
fUnsetInheritedGitConfig
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_HOST GH_CONFIG_DIR GITSBY_ACCOUNT

## -q silences the per-check line and leaves the header, the failures and the total. The
## pipeline doesn't pass it, even on its own -q runs.
declare -i quiet=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet) quiet=1; shift ;;
		-h|--help)  echo "Usage: $(basename "${BASH_SOURCE[0]}") [-q|--quiet]"; exit 0 ;;
		*)          echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

declare -i pass=0 fail=0
fOk(){   pass=$((pass+1)); ((quiet)) || echo "  ok: $*"; }
fFail(){ fail=$((fail+1)); echo "  FAIL: $*"; }
## Assert the command succeeds / fails (output discarded; -q keeps gitsby promptless).
fAssert(){     local desc="$1"; shift; if   "$@" >/dev/null 2>&1; then fOk "$desc"; else fFail "$desc"; fi; }
fAssertFail(){ local desc="$1"; shift; if ! "$@" >/dev/null 2>&1; then fOk "$desc"; else fFail "$desc"; fi; }
## Assert the command's output matches an extended regex (for the pre-flight display).
## Capture rather than pipe: 'grep -q' would close the pipe early and pipefail would call that a failure.
fAssertOut(){  local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if grep -qE "$pat" <<< "${out}"; then fOk "$desc"; else fFail "$desc"; fi; }
fAssertNotOut(){ local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if ! grep -qE "$pat" <<< "${out}"; then fOk "$desc"; else fFail "$desc"; fi; }
## Matches against the PLAN only, not the whole run. Every "plans X" assertion against full
## output is also satisfied by the execution echo of the same command, so it cannot tell a
## preview that lists a step from one that silently stopped listing it. Plan lines are indented
## under "Going to do"; the first execution line starts at column 0 with '[', in both ports.
fPlanOf(){ awk '/Going to do/{p=1;next} p&&/^\[/{exit} p' ;}
## Windows can't start a shebang script by name, and the PowerShell build looks its commands up
## the Windows way - so every stub gets a .cmd sibling that hands the body straight back to bash.
## Without it the pwsh leg finds the stub, runs nothing, and reads the silence as empty output.
isWindows=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) isWindows=1 ;; esac
## The config folder under a home, which is the one place each platform looks. macOS reads its
## own and nothing else, '~/.config' included. confRe is the same for a regex.
isMac=0; confRel=".config/gitsby"
[[ "$(uname -s)" == Darwin ]] && { isMac=1; confRel="Library/Application Support/gitsby"; }
confRe="${confRel//./\\.}"
fStubShim(){ ((isWindows)) && printf '@echo off\r\nbash "%s" %%*\r\n' "$1" > "$1.cmd"; return 0 ;}
## Write a stub from stdin, runnable by both builds.
fStub(){ cat > "$1"; chmod +x "$1"; fStubShim "$1" ;}
## PowerShell and .NET have no MSYS mount table, so '/tmp/x' and '/c/x' resolve against the root
## of the current drive - 'C:\tmp\x', 'C:\c\x'. Any path interpolated into a pwsh command line
## needs the platform's own spelling, or the statement fails and the check reports on nothing.
fWinPath(){ if ((isWindows)); then cygpath -m "$1"; else printf '%s' "$1"; fi ;}

## Checks that reach a confirmation need it to refuse rather than wait: stdin at EOF, and nothing
## for the prompt to fall back to. setsid guarantees that. Windows has no setsid, but PowerShell
## only ever reads redirected stdin, so </dev/null alone is enough there - which is why the pwsh
## one-liners below run either way. install.bash does fall back to /dev/tty, so its plan checks
## additionally need that open to fail.
declare -a noTty=()
canNoTty=0 shNoTty=0
if command -v setsid >/dev/null 2>&1; then noTty=(setsid); canNoTty=1; shNoTty=1
elif ((isWindows));                     then canNoTty=1; { : </dev/tty; } 2>/dev/null || shNoTty=1
fi
## A pty for the two checks that have to ANSWER the prompt rather than have it refuse: the plan
## is only printed to someone who could say yes, and the word accepted there is the point of one
## of them. No 'script' (Windows) means those two are skipped; the no-tty gate covers the rest.
hasPty=0
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then hasPty=1; fi
fAnswerPrompt(){ local answer="$1"; shift; printf '%s\n' "${answer}" | script -qec "$*" /dev/null 2>&1 || true ;}
## A file's permission bits and inode number, from GNU stat or BSD stat. Exported, since most
## checks that need them run inside 'bash -c'.
fMode(){  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" ;}
fInode(){ stat -c %i "$1" 2>/dev/null || stat -f %i "$1" ;}
export -f fMode fInode

## Runs PowerShell source TEXT the way the documented one-liners do (iex / scriptblock), with
## stdin at EOF so a confirmation prompt refuses instead of blocking.
fPwshText(){ "${noTty[@]}" pwsh -NoProfile -Command "$1" </dev/null 2>&1 ;}
## install.ps1 as a script file, with the web cmdlets replaced by the functions in <dir>/stubs.ps1,
## which PowerShell finds before a cmdlet of the same name. <shape> picks how releases/latest
## answers: as 7 or 5.1 answer a redirect, nofull as 5.1 answers the 404 of a repo with no full
## release, or pre, which is nofull with only pre-releases listed. Each URL asked for goes to
## <dir>/calls.
fPsInstall(){ local dir="$1" home="$2" shape="$3" inst="$4"; shift 4; : > "${dir}/calls"; mkdir -p "${home}"
	env HOME="${home}" FAKE_DIR="${dir}" FAKE_SHAPE="${shape}" "${noTty[@]}" pwsh -NoProfile -Command ". '${dir}/stubs.ps1'; & '${inst}' $*" </dev/null 2>&1 ;}
## Succeeds when a help text for install.ps1 names every parameter and alias of the function that
## does the work. <which> is -Help for the installer's own, or get-help for its comment help.
# shellcheck disable=SC2016  ## pwsh's own variables; pwsh does the expanding.
fPsHelpNamesAll(){ local inst="$1" which="$2" help="" opts="" opt=""
	opts="$(PS_FILE="${inst}" pwsh -NoProfile -Command '$fn = [Management.Automation.Language.Parser]::ParseFile($env:PS_FILE, [ref]$null, [ref]$null).Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Install-Gitsby" }, $true)
		foreach ($p in $fn.Body.ParamBlock.Parameters) { $p.Name.VariablePath.UserPath; foreach ($a in $p.Attributes) { if ($a.TypeName.Name -eq "Alias") { $a.PositionalArguments.Value } } }')"
	if [[ "${which}" == get-help ]]; then help="$(PS_FILE="${inst}" pwsh -NoProfile -Command 'Get-Help $env:PS_FILE -Full | Out-String -Width 300')"
	else help="$(pwsh -NoProfile -File "${inst}" -Help 2>&1)"; fi
	[[ -n "${opts}" ]] || return 1
	while IFS= read -r opt; do
		grep -qE -- "(^|[^A-Za-z])-${opt}([^A-Za-z]|\$)" <<< "${help}" || { echo "not in ${which}: ${opt}"; return 1; }
	done <<< "${opts}"
}
## Succeeds when install.bash's --help names every option its argument loop takes.
fBashHelpNamesAll(){ local inst="$1" help="" opts="" opt=""
	help="$(bash "${inst}" --help)"
	opts="$(sed -n '/^while \[\[ \$# -gt 0 \]\]; do/,/^done/p' "${inst}" | sed -n 's/^[[:space:]]*\(-[^)]*\)).*/\1/p' | tr '|' '\n' | sed 's/=\*$//')"
	[[ -n "${opts}" ]] || return 1
	while IFS= read -r opt; do
		grep -qE -- "(^|[ ,])${opt}([ ,=]|\$)" <<< "${help}" || { echo "not in --help: ${opt}"; return 1; }
	done <<< "${opts}"
}
## Succeeds when the command's output, both streams, starts and ends on a blank line.
fFramed(){ local out=""; out="$("$@" 2>&1; printf x)"; out="${out%x}"; [[ "${out}" == $'\n'* && "${out}" == *$'\n\n' ]] ;}
## Succeeds when the first output line matching <pattern> has a blank line either side of it.
fBlankAround(){ local pat="$1"; shift; { "$@" 2>&1 || true; } | tr -d '\r' | PAT="${pat}" awk '
	seen && !found { found = 1; ok = ok && $0 == "" }
	$0 ~ ENVIRON["PAT"] && !seen { seen = 1; ok = NR > 1 && prev == "" }
	{ prev = $0 }
	END { exit !(found && ok) }' ;}
## Succeeds when the first output line matching <pattern> has a blank line after it.
fBlankAfter(){ local pat="$1"; shift; { "$@" 2>&1 || true; } | tr -d '\r' | PAT="${pat}" awk '
	seen && !found { found = 1; ok = $0 == "" }
	$0 ~ ENVIRON["PAT"] { seen = 1 }
	END { exit !(found && ok) }' ;}
fAssertPlan(){    local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if     grep -qE "$pat" <<< "$(fPlanOf <<< "${out}")"; then fOk "$desc"; else fFail "$desc"; fi; }
fAssertNotPlan(){ local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if ! grep -qE "$pat" <<< "$(fPlanOf <<< "${out}")"; then fOk "$desc"; else fFail "$desc"; fi; }

## Fixture: bare origin with an initial commit on main, plus two clones.
fMakeFixture(){
	local -r fixDir="$1"
	mkdir -p "${fixDir}"
	origin="${fixDir}/origin.git"; cloneA="${fixDir}/a"; cloneB="${fixDir}/b"
	git init --quiet --bare -b main "${origin}"
	git clone --quiet "${origin}" "${cloneA}" 2>/dev/null
	(
		cd "${cloneA}"
		echo one > file1.txt
		git add --all; git commit --quiet -m "initial"
		git push --quiet -u origin main
	)
	git clone --quiet "${origin}" "${cloneB}"
}

## The pre-push gate's fixture: the real pipeline engine and its config, with every tool and
## harness it calls replaced by a stub that logs its own command line and fails when a marker
## file of its name exists. The checks then see which steps a mode runs, and where it stops.
## $1 the stub, $2 its marker name, $3 a line run before the verdict.
fGateStub(){
	fStub "$1" <<-EOF
		#!/usr/bin/env bash
		printf '%s\n' "\$(basename "\$0") \$*" >> '${gateCalls}'
		${3:-}
		[[ ! -e "${gateFail}/$2" ]]
	EOF
}
fMakeGateFixture(){
	local s
	mkdir -p "${gateDir}/cicd/utility/include" "${gateDir}/cicd/utility/demo" "${gateDir}/bin" "${gateDir}/home" "${gateDir}/src-go" "${gateFail}"
	cp "${root}/cicd/cicd.bash" "${root}/cicd/config.bash" "${gateDir}/cicd/"
	cp "${root}/cicd/utility/include/gfs-rotate.bash" "${root}/cicd/utility/include/gh-account.bash" "${gateDir}/cicd/utility/include/"
	## Empty, so the lint globs and PY_LINT_FILES resolve, and stage 6 finds a scenario.
	: > "${gateDir}/install.bash"; : > "${gateDir}/install.ps1"; : > "${gateDir}/cicd/utility/demo/gen-demo-gif.py"
	: > "${gateDir}/cicd/utility/run-latest.ps1"
	cp "${root}/PSScriptAnalyzerSettings.psd1" "${gateDir}/"
	: > "${gateDir}/cicd/utility/demo/demo-scenario.toml"
	echo "# Fixture" > "${gateDir}/README.md"
	for s in test fuzz parity; do fGateStub "${gateDir}/cicd/${s}.bash" "${s}"; done
	for s in gen-winres backlog-check spawn-count; do fGateStub "${gateDir}/cicd/utility/${s}.bash" "${s}"; done
	fGateStub "${gateDir}/cicd/utility/n8git_backup-and-publish" n8git_backup-and-publish
	for s in markdownlint staticcheck golangci-lint govulncheck; do fGateStub "${gateDir}/bin/${s}" "${s}"; done
	## The demo generator writes a gif header to its --out, and the optimizer, called as
	## 'gifsicle -O3 IN -o OUT', copies IN to OUT, so stage 6 has a file to compare. py_compile
	## passes no --out.
	fGateStub "${gateDir}/bin/python3" python3 "o=''; for a in \"\$@\"; do [[ \"\${o}\" != 1 ]] || printf GIF89a > \"\${a}\"; o=''; [[ \"\${a}\" != --out ]] || o=1; done"
	fGateStub "${gateDir}/bin/gifsicle" gifsicle "cp -f -- \"\${2:-}\" \"\${4:-}\""
	## The probe answers yes whatever the marker says, so a failure is the tool's finding and
	## not "not installed". pwsh probes for its module in the same call as the lint, and exits 3
	## when it has none.
	fGateStub "${gateDir}/bin/shellcheck" shellcheck "[[ \"\${1:-}\" != --version ]] || exit 0"
	fGateStub "${gateDir}/bin/pwsh" pwsh "[[ ! -e '${gateFail}/pwsh-nomodule' ]] || exit 3"
	## gofmt reports by listing files, exiting 0 either way; the engine reads the list.
	fGateStub "${gateDir}/bin/gofmt" gofmt "if [[ -e '${gateFail}/gofmt' ]]; then echo main.go; fi; exit 0"
	## go fails by subcommand (go-vet, go-test, go-build), and 'version -m' names no module. A
	## passing build leaves its -o file behind, so the demo stage has a build to remove.
	fGateStub "${gateDir}/bin/go" "go-\${1:-}" "[[ \"\${1:-}\" != version ]] || exit 0; if [[ ! -e \"${gateFail}/go-\${1:-}\" ]]; then o=''; for a in \"\$@\"; do [[ \"\${o}\" != 1 ]] || : > \"\${a}\"; o=''; [[ \"\${a}\" != -o ]] || o=1; done; fi"
}
## The fixture's engine with the stubs first on PATH. HOME is the fixture's as well: the engine
## puts ~/.local/bin ahead of PATH, and a real markdownlint there would answer for the stub.
fGateRun(){ (cd "${gateDir}" && HOME="${gateDir}/home" PATH="${gateDir}/bin:${PATH}" ./cicd/cicd.bash "$@") ;}
## True when the run exits with exactly $1. An unknown option exits 2, so a plain nonzero test
## would pass a build that never heard of the option. Output lands in ${gateOut}, and the calls
## log starts empty.
fGateStatus(){
	local want="$1" rc=0
	shift
	: > "${gateCalls}"
	fGateRun "$@" </dev/null >"${gateOut}" 2>&1 || rc=$?
	[[ "${rc}" == "${want}" ]]
}
## As above, and the output matches the extended regex $2.
fGateSays(){ local want="$1" pat="$2"; shift 2; fGateStatus "${want}" "$@" && grep -qE -- "${pat}" "${gateOut}" ;}
## fGateSays on --gate, for the fixture with the real pwsh. The module dir is the caller's.
fGatePwshSays(){ PSModulePath="${gatePsModules}" fGateSays "$1" "$2" --gate ;}
## True when every extended regex given matches a line of the calls log.
fGateCalled(){ local p; for p in "$@"; do grep -qE -- "${p}" "${gateCalls}" || return 1; done; return 0 ;}
fGateFullRun(){
	fGateSays 0 'CI/CD: done\.' -y --quick --no-sync --no-publish --no-dogfood \
		&& fGateCalled '^go vet' '^go build' '^go test -race' '^test\.bash' '^parity\.bash'
}
fGateQuietSuites(){
	fGateSays 0 'CI/CD: done\.' -q --no-sync --no-publish --no-dogfood --no-demogif \
		&& fGateCalled '^test\.bash $' '^fuzz\.bash $' '^parity\.bash $' '^spawn-count\.bash $'
}
## --install-hook hands over to the installer: the hook is in place, and no stage or gate header
## was printed on the way.
fGateInstallHook(){
	fGateSays 0 '^pre-push: installed ' --install-hook \
		&& grep -qxF '## gitsby pre-push gate - installed by cicd/cicd.bash --install-hook' "${gateDir}/.git/hooks/pre-push" \
		&& ! grep -qE '[0-9]/[0-9]  ' "${gateOut}"
}
## Stage 6 on its own against the fixture, run with $1 (-y or -q). True when it exits 0.
fGateDemoRun(){ fGateStatus 0 "$1" --no-sync --no-lint --no-test --no-fuzz --no-parity --no-dogfood --no-publish ;}
## The last run's calls-log line for the demo's build, and for its generator. Empty when absent.
fGateDemoBuild(){ grep -E -- "^go build .* -o ${gateDir}/src-go/gitsby-demo( |\$)" "${gateCalls}" || true ;}
fGateDemoGen(){ grep -E -- '^python3 cicd/utility/demo/gen-demo-gif\.py ' "${gateCalls}" || true ;}
## A commit in the demo fixture dated $1, changing one file.
fGateDemoCommit(){
	echo "$1" >> "${gateDir}/commits.txt"
	git -C "${gateDir}" add commits.txt
	GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "${gateDir}" commit --quiet -m "$1"
}
## Stage 6 with -y: the demo build line holds the text $1, the generator line the text $2, and
## the output matches the extended regex $3. $2 and $3 may be left out.
fGateDemoStamp(){
	fGateDemoRun -y && [[ "$(fGateDemoBuild)" == *"$1"* && "$(fGateDemoGen)" == *"${2:-}"* ]] \
		&& { [[ -z "${3:-}" ]] || grep -qE -- "$3" "${gateOut}" ;}
}
## Stage 6 with -y: the demo build line is exactly $1, which is not empty, and the gif was left alone.
fGateDemoSame(){ fGateDemoRun -y && [[ -n "$1" && "$(fGateDemoBuild)" == "$1" ]] && grep -qF 'OK: demo gif unchanged' "${gateOut}" ;}
## Stage 6 run with $1: the generator ran, and $2 of its lines (1 or 0) carry -q.
fGateDemoQuiet(){ local gen=""; fGateDemoRun "$1" && gen="$(fGateDemoGen)" && [[ -n "${gen}" && "$(grep -cE -- ' -q( |$)' <<< "${gen}")" == "$2" ]] ;}
## Stage 6 with -y while the build fails: the run warns, and the generator never runs.
fGateDemoBuildFails(){ fGateDemoRun -y && grep -qF 'WARNING: demo build failed' "${gateOut}" && [[ -z "$(fGateDemoGen)" ]] ;}
## The gate passes, and says nothing about lint tool versions.
## Go tools only: the fixture pins those, and the rest are whatever this box has.
fGateNoDrift(){ fGateStatus 0 --gate && ! grep -qE 'tool versions differ.* (staticcheck|golangci-lint|govulncheck|goversioninfo) ' "${gateOut}" ;}
## One -y run with every stage skipped but those named in $1 (sync lint test fuzz parity dogfood
## demogif publish), the rest passed on. Its exit status lands in ${gateRc}, output in ${gateOut},
## and the calls log starts empty.
fGateOnly(){
	local keep=" $1 " s
	local -a skip=()
	shift
	for s in sync lint test fuzz parity dogfood demogif publish; do [[ "${keep}" == *" ${s} "* ]] || skip+=("--no-${s}"); done
	: > "${gateCalls}"; gateRc=0
	fGateRun -y "${skip[@]}" "$@" </dev/null >"${gateOut}" 2>&1 || gateRc=$?
}
## After fGateOnly: the run exited $1, and every extended regex after it matches the calls log.
fGateRanCalling(){ local want="$1"; shift; [[ "${gateRc}" == "${want}" ]] && fGateCalled "$@" ;}
## After fGateOnly: the run exited $1, and its output matches the extended regex $2.
fGateRanSaying(){ [[ "${gateRc}" == "$1" ]] && grep -qE -- "$2" "${gateOut}" ;}
## A commit pushed to the pipeline fixture's origin from a second clone, adding the line $1 to the
## file $2, upstream.txt when left out.
fGateUpstream(){
	local file="${2:-upstream.txt}"
	echo "$1" >> "${gateOther}/${file}"
	git -C "${gateOther}" add "${file}"
	git -C "${gateOther}" commit --quiet -m "$1"
	git -C "${gateOther}" push --quiet 2>/dev/null
}
## A push from $1, the rest being its arguments. Output lands in ${hookOut}; the gate log starts empty.
fHookPush(){ local dir="$1"; shift; : > "${hookLog}"; git -C "${dir}" push "$@" >"${hookOut}" 2>&1 ;}
## One digest of every file under $1, names and contents, to show a directory was left as it was.
fTreeDigest(){ (cd "$1" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum) ;}
## The release fixture's HEAD, tags, what its origin holds and whether its tree is clean, as one string.
fRelState(){ { git -C "${relRepo}" rev-parse HEAD; git -C "${relRepo}" tag; git -C "${relRepo}" ls-remote origin; git -C "${relRepo}" status --porcelain; } 2>&1 ;}
## release.bash in that fixture with the stubs first on PATH. Output lands in ${relOut}, its exit
## status in ${relRc}, and the calls log starts empty.
fRelRun(){ : > "${relCalls}"; relRc=0; (cd "${relRepo}" && PATH="${rel}/bin:${PATH}" bash cicd/release.bash "$@") </dev/null >"${relOut}" 2>&1 || relRc=$? ;}
## config.bash's glob array $1 expanded the way the engine does it, from the repo root: the files,
## sorted, one per line. With $2 set to 'empty', the globs that match no file instead.
fLintGlobs(){
	(
		cd "${root}" || exit 1
		# shellcheck source=/dev/null
		source cicd/config.bash
		local -n lgGlobs="$1"
		local g f n
		shopt -s nullglob
		for g in "${lgGlobs[@]}"; do
			n=0
			for f in $g; do
				if [[ -f "${f}" ]]; then n=$((n + 1)); [[ "${2:-}" == empty ]] || printf '%s\n' "${f}"; fi
			done
			if [[ "${2:-}" == empty ]] && ((n == 0)); then printf '%s\n' "${g}"; fi
		done
	) | LC_ALL=C sort -u
}
## The files named on stdin that the glob array $1 leaves out, or with $2 set to 'both', also the
## files it names that are not on stdin. Empty stdin answers with a line, so a lookup that found
## nothing cannot read as full coverage.
fLintUncovered(){
	local listed=""
	listed="$(LC_ALL=C sort -u)"
	if [[ -z "${listed}" ]]; then echo "(nothing listed)"; return 0; fi
	if [[ "${2:-}" == both ]]; then LC_ALL=C comm -3 <(printf '%s\n' "${listed}") <(fLintGlobs "$1")
	else LC_ALL=C comm -23 <(printf '%s\n' "${listed}") <(fLintGlobs "$1"); fi
}
## Tracked files outside legacy/ that are bash by name or by shebang, so a script without the
## extension is not missed.
fTrackedBash(){
	local f first
	(cd "${root}" && git ls-files ':!legacy') | while IFS= read -r f; do
		first=""
		if [[ -f "${root}/${f}" ]]; then IFS= read -r first < "${root}/${f}" || true; fi
		if [[ "${f}" == *.bash || "${first}" =~ ^#!.*[/[:space:]]bash([[:space:]]|$) ]]; then printf '%s\n' "${f}"; fi
	done
}
## Whether the script $1 refuses a bash below its floor before running anything: a copy with the
## floor raised past any real bash, named as the original, has to exit 1 with the one line. A
## copy the raise didn't change has no floor and is not run, since some of these do real work.
fBashFloorRefuses(){
	local dir="${work}/bash-floor/${1//\//_}" out="" rc=0
	mkdir -p "${dir}"
	sed 's/< 404 ))/< 9999 ))/' "${root}/$1" > "${dir}/${1##*/}"
	if cmp -s "${root}/$1" "${dir}/${1##*/}"; then return 1; fi
	out="$(cd "${dir}" && bash "./${1##*/}" </dev/null 2>&1)" || rc=$?
	[[ "${rc}" == 1 && "${out}" == "${1##*/}: needs bash 4.4 or newer, and this is bash ${BASH_VERSION}."* && "${out}" != *$'\n'* ]]
}

## The whole suite, against whatever ${gitsby} points at.
fRunSuite(){
	echo "suite: $1 (${gitsby})"

	## Help + bad input surface
	fAssert     "[EknhbCC] help exits 0"                 "${gitsby}" --help
	fAssert     "[EknhbCD] version exits 0"              "${gitsby}" -v
	fAssert     "[EkyT3Lk] bare 'help' word works"       "${gitsby}" help
	fAssert     "[EkyT3Ll] bare 'version' word works"    "${gitsby}" version
	fAssertOut  "[ElA8dDE] help keeps the pull-then-commit order" 'sync .*: Pull, commit, and push' "${gitsby}" --help
	fAssertOut  "[ElAGF7I] help doesn't promise a bare patch bump" 'release .*: .*next after latest tag' "${gitsby}" --help
	fAssertOut  "[ElAGF7J] help doesn't overpromise br create"    'br create .*: .*carried or parked'   "${gitsby}" --help
	## Asking for help after a command is the reflex every git user has, and both builds must
	## answer it the same way. -v is the opposite case: alongside a command it used to make the
	## PowerShell build print the version and exit 0, doing none of the work it was asked for.
	fAssert     "[ElHKNmy] --help works after a command"     "${gitsby}" update --help
	fAssert     "[ElHKNmz] --help works after noun and verb" "${gitsby}" br create --help
	fAssert     "[ElHKNn0] -h works after a command"         "${gitsby}" update -h
	fAssertFail "[ElHKNn1] -v after a command is refused"    bash -c "cd '${cloneA}' && '${gitsby}' -q update -v"
	fAssertOut  "[ElHKNn2] and says which option"            'Unexpected option'  bash -c "cd '${cloneA}' && '${gitsby}' -q update -v 2>&1"
	fAssert     "[EkyT3Lm] -y alias accepted"            bash -c "cd '${cloneA}' && '${gitsby}' -y status"
	## Every run says which build produced it, so a bug report carries that without being asked.
	## Not on the two paths that already print a version line, not under -q, and never on 'raw',
	## which hands its tool's stdout straight back to whatever is reading it.
	fAssertOut    "[Eo59IMa] output names the build it came from"  '^gitsby v[0-9]' \
		bash -c "cd '${cloneA}' && '${gitsby}' -NoFetch status"
	fAssertNotOut "[Eo59IMb] -q leaves it out"                     '^gitsby v[0-9]' \
		bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	fAssertNotOut "[Eo59IMc] 'raw' adds nothing to its tool's output"  '^gitsby v[0-9]' \
		bash -c "cd '${cloneA}' && '${gitsby}' raw git rev-parse --abbrev-ref HEAD 2>/dev/null"
	## Said once on the paths that were already saying it, rather than a banner above a copyright
	## line that repeats it.
	fAssert "[Eo59IMd] --version names the build once"  \
		bash -c "[[ \"\$(cd '${cloneA}' && '${gitsby}' --version | grep -cE '^gitsby v[0-9]')\" == 1 ]]"
	fAssert "[Eo59IMe] --help names the build once"     \
		bash -c "[[ \"\$(cd '${cloneA}' && '${gitsby}' --help | grep -cE '^gitsby v[0-9]')\" == 1 ]]"
	## --about and --donate are the two informational flags. Both answer outside a repo, and each
	## exists to hand over links, so the links are what get asserted.
	fAssertOut  "[Eo5Hqng] --about names the project page"   'github\.com/yottacore/gitsby' \
		bash -c "cd '${work}' && '${gitsby}' --about"
	fAssertOut  "[Eo5Hqnh] --donate names the sponsor page"  'github\.com/sponsors/jim-collier' \
		bash -c "cd '${work}' && '${gitsby}' --donate"
	fAssertOut  "[ErTuVvi] --donate names the Ko-fi page"    'ko-fi\.com/jimcollier' \
		bash -c "cd '${work}' && '${gitsby}' --donate"
	fAssertOut  "[Eo5Hqni] --donate names the build"         '^gitsby v[0-9]' \
		bash -c "cd '${work}' && '${gitsby}' --donate"
	fAssert     "[Eo5Hqnj] bare 'about' word works"          bash -c "cd '${work}' && '${gitsby}' about"
	fAssert     "[Eo5Hqnk] bare 'donate' word works"         bash -c "cd '${work}' && '${gitsby}' donate"
	fAssertOut  "[Eo5Hqnl] help lists both of them"          '\-\-about.*\-\-donate'  "${gitsby}" --help
	## Help lists all four on one line, and only --help worked past the first word.
	fAssertOut  "[ErCP1Qd] --version works after a command, as --help does"  '^gitsby v[0-9]' \
		bash -c "cd '${cloneA}' && '${gitsby}' br create infoflag --version"
	fAssert     "[ErCP1Qu] and the command does nothing"  bash -c "cd '${cloneA}' && ! git rev-parse --verify -q refs/heads/infoflag"
	fAssertOut  "[ErCP1R9] and --about"   'github\.com/yottacore/gitsby'      bash -c "cd '${cloneA}' && '${gitsby}' status --about"
	fAssertOut  "[ErCP1RM] and --donate"  'github\.com/sponsors/jim-collier'  bash -c "cd '${cloneA}' && '${gitsby}' sync --donate"
	fAssertFail "[EknhbCE] no args exits nonzero"        "${gitsby}"
	fAssertFail "[EknhbCF] unknown command rejected"     bash -c "cd '${cloneA}' && '${gitsby}' -q frobnicate"
	fAssertFail "[EknhbCG] unknown option rejected"      bash -c "cd '${cloneA}' && '${gitsby}' -q status --bogus"
	fAssertOut  "[ElHNo4G] --public with --private refused"  'mutually exclusive'  bash -c "cd '${cloneA}' && '${gitsby}' -q --public --private repo create me/x 2>&1"
	fAssertFail "[EknhbCH] outside a repo rejected"      bash -c "cd '${work}' && '${gitsby}' -q status"
	## Read-only commands used to ignore trailing arguments while everything else rejected them,
	## which makes a typo look like it did what you meant.
	fAssertFail "[ElHl6Oe] status with a trailing argument rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q status extra"
	fAssertFail "[ElHl6Of] br list with a trailing argument rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q br list extra"
	fAssertOut  "[ElHl6Og] and says what takes no arguments"  'takes no arguments'  bash -c "cd '${cloneA}' && '${gitsby}' -q status extra 2>&1"
	## An option or positional typo is a usage error, not a crash - no internal stack dump.
	fAssertNotOut "[ElHl6Oh] option typo prints no call stack"  'panic:|goroutine [0-9]+ \['  bash -c "cd '${cloneA}' && '${gitsby}' -q status --bogus 2>&1"

	## Grouped-noun grammar: spelled-out nouns, hidden verb aliases, and refusals
	fAssert     "[El9QuEe] 'branch' spells out 'br'"        bash -c "cd '${cloneA}' && '${gitsby}' -q branch list"
	fAssert     "[El9QuEf] 'br new' aliases 'br create'"    bash -c "cd '${cloneA}' && '${gitsby}' -q br new grammar1 && git -C '${cloneA}' branch --show-current | grep -qx grammar1"
	fAssert     "[El9QuEg] 'br go' aliases 'br switch'"     bash -c "cd '${cloneA}' && '${gitsby}' -q br go main && git -C '${cloneA}' branch --show-current | grep -qx main"
	fAssertFail "[El9QuEh] unknown br subcommand rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q br frobnicate"
	fAssertFail "[El9QuEi] unknown repo subcommand rejected" bash -c "cd '${cloneA}' && '${gitsby}' -q repo frobnicate"
	fAssertFail "[El9QuEj] bare 'repo' rejected"             bash -c "cd '${cloneA}' && '${gitsby}' -q repo"
	fAssertFail "[El9QuEk] internal token not typeable"      bash -c "cd '${cloneA}' && '${gitsby}' -q br-create nope"
	fAssertFail "[El9QuEl] extra positional rejected"        bash -c "cd '${cloneA}' && '${gitsby}' -q br switch main extra"
	( cd "${cloneA}" && git branch -D grammar1 >/dev/null 2>&1; git push --quiet origin --delete grammar1 2>/dev/null || true )

	## Read-only commands
	fAssert "[EknhbCI] status runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssert "[EknhbCJ] br list runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q br list"
	fAssertFail "[El9QuEm] dropped v1 alias 'list' rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q list"

	## Pre-flight display: who we act as, and a compact list of what changes
	fAssertOut "[EksmH56] status names the commit author"  'Author \.+:'            bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	## One label for one thing: status called the current directory "Directory" while 'account
	## list' called it "Here", and both print it from the same tool a few lines apart.
	fAssertOut "[Enc2nqq] status names the current directory"  '^Current dir \.+: '  bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "[Enc2nqr] and whoami uses the same label"      '^Current dir \.+: '  bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch whoami"
	fAssertOut "[EksmH57] clean worktree says so"          '\(working tree clean\)' bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	( cd "${cloneA}" && echo probe > probe.txt )
	fAssertOut "[EksmH58] changed file listed"             '\?\? probe\.txt'        bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	## A long change list is capped rather than scrolling the rest of the display away.
	local many="${work}/$1-manyfiles" manyN
	git init --quiet -b main "${many}"
	for ((manyN = 1; manyN <= 30; manyN++)); do echo "${manyN}" > "${many}/f${manyN}.txt"; done
	fAssertOut "[Er1LxRY] a long change list ends in a count of the rest"  '^    \.\.\. and 5 more$'  bash -c "cd '${many}' && '${gitsby}' -q status"
	fAssert    "[Er1LxRZ] and shows no more than 25 of them" \
		bash -c "cd '${many}' && [[ \"\$('${gitsby}' -q status 2>&1 | grep -cE '^    \?\? f[0-9]+\.txt$')\" == 25 ]]"
	fAssertOut "[EksmH59] mutating command previews first" 'Going to do'            bash -c "cd '${cloneA}' && '${gitsby}' -q update 'probe'"
	( cd "${cloneA}" && git reset --quiet --hard HEAD~1 )

	## update: commits everything and pulls; idempotent when clean. There is no bare
	## 'commit' or 'pull' any more - both would leave you in a state gitsby exists to avoid.
	( cd "${cloneA}" && echo two > file2.txt )
	fAssert "[EknhbCK] update commits new file"         bash -c "cd '${cloneA}' && '${gitsby}' -q update 'add file2'"
	fAssert "[EksszJY] worktree clean after update"     bash -c "cd '${cloneA}' && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert "[EknhbCL] update message recorded"         bash -c "cd '${cloneA}' && git log -1 --format=%s | grep -qx 'add file2'"
	fAssert "[EknhbCM] update again (nothing to do) ok" bash -c "cd '${cloneA}' && '${gitsby}' -q update 'noop'"
	## sync takes its message positionally like update, and nothing checked that it lands - the
	## message could quietly be replaced by the auto-generated timestamp with the suite still green.
	( cd "${cloneA}" && echo s > s.txt )
	fAssert "[ElHQEx6] sync records the message it was given"  bash -c "cd '${cloneA}' && '${gitsby}' -q sync 'synced by name' && git log -1 --format=%s | grep -qx 'synced by name'"
	fAssertFail "[El9W15k] dropped 'commit' command rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit 'no such command'"
	## 'pull' went away in v2 because it let you skip the commit. The compiled build takes the
	## word again as a spelling of the command that pulls AND commits, which structurally can't.
	( cd "${cloneA}" && echo alias > alias.txt )
	fAssertFail "[EkoUJUG] dropped v1 alias 'scommit' rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q scommit 'via alias'"
	( cd "${cloneA}" && echo upd > upd.txt )
	fAssert "[EksszJZ] update sweeps in leftover work"  bash -c "cd '${cloneA}' && '${gitsby}' -q update 'add upd'"
	fAssertFail "[El9QuEn] dropped v1 alias 'saveup' rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q saveup"
	local v1Alias
	for v1Alias in scompul spull spush mkbranch chbranch mtm newbr gobr listbr; do
		fAssert "[Er1LxRa] dropped alias '${v1Alias}' rejected as an unknown command" \
			bash -c "cd '${cloneA}' && out=\"\$('${gitsby}' -q ${v1Alias} 2>&1)\"; [[ \$? != 0 ]] && grep -qF \"Unknown command '${v1Alias}'\" <<< \"\${out}\""
	done

	## sync: publishes; remote matches local
	fAssert "[EknhbCN] sync runs"            bash -c "cd '${cloneA}' && '${gitsby}' -q sync 'push file2'"
	fAssert "[EknhbCO] remote main matches"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"

	## remote moved ahead + local dirty -> update commits the local work, then fast-forwards
	(
		cd "${cloneB}"
		git pull --quiet --ff-only
		echo bee > fileB.txt
		git add --all; git commit --quiet -m "from B"
		git push --quiet
	)
	( cd "${cloneA}" && echo dirty >> file1.txt )
	fAssertOut "[EksmH5A] behind count on the branch line"  'behind 1'   bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "[EksmH5B] incoming changes previewed"       'Incoming'   bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "[EksmH5C] incoming file named"              'fileB\.txt' bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssert "[EknhbCP] update with dirty tree + remote ahead"  bash -c "cd '${cloneA}' && '${gitsby}' -q update 'local edit'"
	fAssert "[EknhbCQ] remote commit arrived"                  bash -c "cd '${cloneA}' && [[ -f fileB.txt ]]"
	fAssert "[EknhbCR] local edit survived, committed"         bash -c "cd '${cloneA}' && grep -q dirty file1.txt && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert "[El9W15l] and it sits on top of the remote work"  bash -c "cd '${cloneA}' && git merge-base --is-ancestor origin/main HEAD"
	fAssert "[EknhbCS] nothing stranded in the stash"          bash -c "cd '${cloneA}' && [[ -z \"\$(git stash list)\" ]]"

	## br create: branches off default, publishes with upstream; dirty work on the
	## protected base is carried to the new branch, never committed to the base
	## update now commits, so main sits ahead of origin here; pin its sha instead of
	## comparing to origin, and assert the WIP never landed on it.
	( cd "${cloneA}" && echo dirty2 >> file1.txt && git rev-parse main > "${work}/$1-mainsha" )
	fAssert "[EknhbCT] br create feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q br create feat"
	fAssert "[EknhbCU] now on feat"            bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssert "[EknhbCV] feat has upstream"      bash -c "cd '${cloneA}' && git rev-parse --abbrev-ref 'feat@{u}' >/dev/null"
	fAssert "[EknhbCW] dirty edit carried uncommitted"  bash -c "cd '${cloneA}' && grep -q dirty2 file1.txt && ! git diff --quiet"
	fAssert "[EkyNtdA] no WIP commit on main"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(cat '${work}/$1-mainsha')\" ]] && ! git show main:file1.txt | grep -q dirty2"
	( cd "${cloneA}" && git add --all && git commit --quiet -m "carried" )
	fAssertFail "[EknhbCX] br create existing name rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q br create feat"
	fAssertFail "[EknhbCY] br create bad name rejected"       bash -c "cd '${cloneA}' && '${gitsby}' -q br create 'bad name'"
	fAssertFail "[EknhbCZ] br create no name rejected"        bash -c "cd '${cloneA}' && '${gitsby}' -q br create"
	fAssertNotOut "[EkyT3Ln] bad branch arg dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q br create 'bad name'"

	## gobr: switch back and forth; bogus target rejected
	fAssert "[EknhbCa] br switch (default: main)"  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch"
	fAssert "[EknhbCb] now on main"           bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "[EknhbCc] br switch feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
	fAssert "[EknhbCd] back on feat"          bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssertFail "[EknhbCe] br switch nonexistent rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch nosuch"

	## gobr refuses to auto-commit WIP sitting on a protected branch, before showing a plan
	( cd "${cloneA}" && git checkout --quiet main && echo wip >> file2.txt )
	fAssertFail   "[EkyNtdB] br switch from dirty main refuses"           bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
	fAssertNotOut "[El5IQZM] and dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
	## The way out it offers has to be a command that still exists (it named the dropped 'commit')
	fAssertOut    "[El9bc7s] and points at a real command"  'deliberately \(.*(update|pullcom)\) first'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
	fAssert "[EkyNtdC] wip left uncommitted on main"      bash -c "cd '${cloneA}' && ! git diff --quiet && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"
	## newbr carries that same tree instead, so its plan must not promise a commit on main
	fAssertNotPlan "[El5IQZN] br create from main previews no commit"  'git add --all'  bash -c "cd '${cloneA}' && '${gitsby}' -q br create wipcarry"
	fAssert "[El5IQZO] wip carried to the new branch"  bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == wipcarry ]] && ! git diff --quiet"
	( cd "${cloneA}" && git checkout --quiet -- file2.txt && git checkout --quiet feat
	  git branch --quiet -D wipcarry && git push --quiet origin --delete wipcarry )

	## land: merge feat into main --no-ff, then delete it local + remote
	( cd "${cloneA}" && echo feat > feat.txt )
	fAssert "[EknhbCf] br land merges feat into main"  bash -c "cd '${cloneA}' && '${gitsby}' -q br land 'merge feat work'"
	fAssert "[EknhbCg] now on main after land"      bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "[EknhbCh] merge commit is --no-ff"     bash -c "cd '${cloneA}' && git log -1 --merges --format=%s | grep -qx 'merge feat work'"
	fAssert "[EknhbCi] feat deleted locally"        bash -c "cd '${cloneA}' && ! git show-ref --verify --quiet refs/heads/feat"
	fAssert "[EknhbCj] feat deleted on origin"      bash -c "cd '${origin}' && ! git show-ref --verify --quiet refs/heads/feat"
	fAssert "[EknhbCk] main pushed after land"      bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"
	fAssertFail "[EknhbCl] br land from main rejected" bash -c "cd '${cloneA}' && '${gitsby}' -q br land"

	## dev-aware targeting: with a dev branch, newbr bases off dev and land merges to dev
	( cd "${cloneA}" && git checkout --quiet -b dev && git push --quiet -u origin dev )
	fAssert "[EkoUJUH] br create feat2 bases off dev"   bash -c "cd '${cloneA}' && '${gitsby}' -q br create feat2 && [[ \"\$(git merge-base feat2 dev)\" == \"\$(git rev-parse dev)\" ]]"
	( cd "${cloneA}" && echo feat2 > feat2.txt )
	fAssert "[EkoUJUI] br land merges feat2 into dev"  bash -c "cd '${cloneA}' && '${gitsby}' -q br land 'merge feat2 work'"
	fAssert "[EkoUJUJ] now on dev after land"       bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert "[EknhbCm] feat2 landed on dev not main"  bash -c "cd '${cloneA}' && [[ -f feat2.txt ]] && ! git ls-tree --name-only main | grep -qx feat2.txt"
	fAssert "[EkoUJUK] br switch with no arg goes to dev"  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch main && '${gitsby}' -q br switch && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssertFail "[EkoUJUL] br land from dev rejected"    bash -c "cd '${cloneA}' && '${gitsby}' -q br land"
	fAssertFail "[EkoUJUM] br land from main rejected (dev repo)"  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch main && '${gitsby}' -q br land; rc=\$?; git checkout --quiet dev; exit \$rc"
	## Landing ends in a branch delete, so a protected branch must be refused before the plan is
	## shown - not after the user has confirmed 'git branch -d main'.
	fAssertNotOut "[ElHNo4H] and refuses before showing a plan that deletes it"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch main >/dev/null && '${gitsby}' -q br land 2>&1; git checkout --quiet dev"

	## release: merge dev into main, tag, push; then auto-bump patch on the next one
	fAssert "[EkoUJUN] release 1.2.3 runs"        bash -c "cd '${cloneA}' && '${gitsby}' -q release v1.2.3"
	fAssert "[EkoUJUO] tag v1.2.3 on main"        bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse v1.2.3^{commit})\" == \"\$(git rev-parse main)\" ]]"
	fAssert "[EkoUJUP] release merged dev to main"  bash -c "cd '${cloneA}' && git ls-tree --name-only main | grep -qx feat2.txt"
	fAssert "[EkoUJUQ] main pushed with tag"      bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]] && git ls-remote --tags origin | grep -q 'refs/tags/v1.2.3'"
	fAssert "[EkoUJUR] back on dev after release"  bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert "[EksszJa] dev fast-forwarded to the release"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse dev)\" == \"\$(git rev-parse main)\" ]]"
	fAssert "[EksszJb] dev pushed after release"           bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse dev)\" == \"\$(git rev-parse origin/dev)\" ]]"
	fAssertFail   "[EkoUJUS] release same version rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssertNotOut "[El5IQZP] duplicate tag dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssertFail "[EkoUJUT] release bad version rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q release bogus"
	( cd "${cloneA}" && echo more > more.txt )
	fAssert "[EkoUJUU] release with no version bumps patch"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.2.4 >/dev/null"

	## A candidate's own version is what comes next, and once it's cut the bump resumes from it
	( cd "${cloneA}" && git tag -a v1.3.0-rc1 -m rc1 && echo cand > cand.txt )
	fAssert "[El5iyls] release after a candidate takes the candidate's version"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.3.0 >/dev/null"
	fAssert "[El5iylt] it did not skip past to a later patch"                    bash -c "cd '${cloneA}' && ! git rev-parse -q --verify refs/tags/v1.3.1 >/dev/null"
	( cd "${cloneA}" && echo post > post.txt )
	fAssert "[El5iylu] the next release bumps off the full version, not the candidate"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.3.1 >/dev/null"

	## An invented version with nothing to release is a tag for no release, and re-running after
	## a failed push would cut a second one on the same commit, stranding the first forever.
	fAssert     "[ElHNo4I] bare release stands down when there is nothing new"  bash -c "cd '${cloneA}' && '${gitsby}' -q release"
	fAssertOut  "[ElHNo4J] and says so"  'Nothing new to release since v1\.3\.1'  bash -c "cd '${cloneA}' && '${gitsby}' -q release 2>&1"
	fAssertOut  "[ElHNo4K] and names the tag to push if it never landed"  'push it: git push origin v1\.3\.1'  bash -c "cd '${cloneA}' && '${gitsby}' -q release 2>&1"
	fAssert     "[ElHNo4L] and cut no tag doing so"  bash -c "cd '${cloneA}' && ! git rev-parse -q --verify refs/tags/v1.3.2 >/dev/null"
	## A version you typed is deliberate, so it still works on an already-released commit.
	fAssert     "[ElHNo4M] an explicit version still releases the same commit"  bash -c "cd '${cloneA}' && '${gitsby}' -q release v1.4.0 && git rev-parse -q --verify refs/tags/v1.4.0 >/dev/null"

	## Tags with no 'v' were invisible to the scan, so release started over at 0.1.0 and pushed it.
	local bt="${work}/$1-baretag"
	git init --quiet --bare -b main "${bt}/origin.git"
	git clone --quiet "${bt}/origin.git" "${bt}/c" 2>/dev/null
	( cd "${bt}/c" || exit 1; echo a > a.txt && git add --all && git commit --quiet -m init && git tag -a 1.4.2 -m 1.4.2 && git push --quiet -u origin main --tags && echo b > b.txt )
	fAssert     "[EpyIe9A] release counts on from a tag with no v"  bash -c "cd '${bt}/c' && '${gitsby}' -q -NoFetch release && git rev-parse -q --verify refs/tags/1.4.3 >/dev/null && ! git rev-parse -q --verify refs/tags/v0.1.0 >/dev/null"
	## Every new tag used to gain a 'v', so a repo tagged that way went on with mixed spellings.
	fAssert     "[EpyLprE] and spells the new tag without one too"  bash -c "cd '${bt}/c' && ! git rev-parse -q --verify refs/tags/v1.4.3 >/dev/null"
	fAssertFail "[EpyIe9B] a typed version already tagged with no v is refused"  bash -c "cd '${bt}/c' && '${gitsby}' -q -NoFetch release 1.4.2"
	fAssertOut  "[EpyIe9C] and names that tag"  "Tag '1\.4\.2' already exists"  bash -c "cd '${bt}/c' && '${gitsby}' -q -NoFetch release 1.4.2 2>&1"
	fAssert     "[EpyLprF] a typed version is tagged as typed"  bash -c "cd '${bt}/c' && '${gitsby}' -q -NoFetch release 2.0.0 && git rev-parse -q --verify refs/tags/2.0.0 >/dev/null && ! git rev-parse -q --verify refs/tags/v2.0.0 >/dev/null"
	## git merge reads a tag ahead of a branch with the same name, so a tag called 'dev' on an
	## older commit would be released in dev's place.
	local rtag="${work}/$1-reltag"
	git init --quiet --bare -b main "${rtag}/origin.git"
	git clone --quiet "${rtag}/origin.git" "${rtag}/c" 2>/dev/null
	(
		cd "${rtag}/c" || exit 1
		echo a > a.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev
		echo rel > rel.txt && git add --all && git commit --quiet -m rel && git push --quiet -u origin dev
		git tag dev HEAD~1
	)
	fAssert     "[Er1LxRb] release merges the dev branch, not a tag with its name" \
		bash -c "cd '${rtag}/c' && '${gitsby}' -q release v1.0.0 >/dev/null 2>&1; git -C '${rtag}/origin.git' ls-tree --name-only main | grep -qx rel.txt"

	## release started from a feature branch returns there; slash branch names work
	fAssert "[EkyQnOK] br create relfeat"  bash -c "cd '${cloneA}' && '${gitsby}' -q br create relfeat"
	( cd "${cloneA}" && echo rel > rel.txt )
	fAssert "[EkyQnOL] release from a feature branch runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q release"
	fAssert "[EkyQnOM] returns to the feature branch"       bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == relfeat ]]"
	fAssert "[EkyQnON] br create with a slash name"  bash -c "cd '${cloneA}' && '${gitsby}' -q br create feat/x && [[ \"\$(git branch --show-current)\" == feat/x ]]"
	fAssert "[EkyQnOO] br switch back to dev"         bash -c "cd '${cloneA}' && '${gitsby}' -q br switch && [[ \"\$(git branch --show-current)\" == dev ]]"
	## Already on the target: no checkout and no park happen, so the plan must not list them.
	( cd "${cloneA}" && echo swp > swp.txt )
	fAssertNotPlan "[ElHNo4N] br switch onto the current branch plans no commit"  'git commit'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch dev"
	fAssertPlan   "[ElHNo4O] and still plans the pull"  'git merge --ff-only @\{u\}'            bash -c "cd '${cloneA}' && '${gitsby}' -q br switch dev"

	## Detached HEAD guard
	fAssertFail "[EknhbCn] mutating command on detached HEAD rejected"  bash -c "cd '${cloneA}' && git checkout --quiet HEAD~0 --detach && '${gitsby}' -q update x"
	( cd "${cloneA}" && git checkout --quiet dev )

	## Messages with quotes pass through unmangled (no eval, no curly-quote games)
	( cd "${cloneA}" && echo q > q.txt )
	fAssert "[EknhbCo] message with quotes survives"  bash -c "cd '${cloneA}' && '${gitsby}' -q update \"don't \\\"quote\\\" me\" && git log -1 --format=%s | grep -qx \"don't \\\"quote\\\" me\""

	## Message handling: -m and -m= forms; option-like words stay words; extra bare word rejected
	( cd "${cloneA}" && echo m1 > m1.txt )
	fAssert "[EkyQnOP] update -m flag form"     bash -c "cd '${cloneA}' && '${gitsby}' -q update -m 'via -m flag' && git log -1 --format=%s | grep -qx 'via -m flag'"
	( cd "${cloneA}" && echo m2 > m2.txt )
	fAssert "[EkyQnOQ] update -m= joined form"  bash -c "cd '${cloneA}' && '${gitsby}' -q update -m='via -m= flag' && git log -1 --format=%s | grep -qx 'via -m= flag'"
	( cd "${cloneA}" && echo m3 > m3.txt )
	fAssert "[EkyQnOR] message containing -v commits"           bash -c "cd '${cloneA}' && '${gitsby}' -q update 'add -v flag' && git log -1 --format=%s | grep -qx 'add -v flag'"
	## A message that STARTS with a dash: '-m' is waiting for a value, so the next token is that
	## value whatever it looks like. There is no other way to write one, and the ports disagreed.
	( cd "${cloneA}" && echo m4 > m4.txt )
	fAssert "[ElHKNn3] message starting with a dash commits"    bash -c "cd '${cloneA}' && '${gitsby}' -q update -m '-Wall added to CFLAGS' && git log -1 --format=%s | grep -qx -- '-Wall added to CFLAGS'"
	fAssertFail "[EkyQnOS] unquoted two-word message rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q update Fixed bug"

	## Non-tty: mutating commands fail closed without -q; read-only ones just go quiet
	( cd "${cloneA}" && echo nt > nt.txt )
	fAssertFail "[EkyQnOT] mutating without -q and no tty refuses"  bash -c "cd '${cloneA}' && '${gitsby}' update ntmsg < /dev/null"
	fAssert "[EkyQnOU] file left uncommitted"                       bash -c "cd '${cloneA}' && git status --porcelain | grep -q nt.txt"
	fAssert "[EkyQnOV] read-only without -q still runs non-tty"     bash -c "cd '${cloneA}' && '${gitsby}' status < /dev/null"
	( cd "${cloneA}" && "${gitsby}" -q update "nt cleanup" >/dev/null 2>&1 )

	## Credentialed remote URLs display masked (-NoFetch keeps it off the network; also lowercases to bash --nofetch)
	( cd "${cloneA}" && git remote set-url origin 'https://user:sekrit@127.0.0.1:1/x.git' )
	fAssertNotOut "[EkyQnOW] no-fetch skips the fetch"           '\[ git fetch' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	fAssertOut    "[EkyQnOX] remote URL masks credentials"       '\*\*\*@127\.0\.0\.1' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	fAssertNotOut "[EkyQnOY] credential itself never shown"      'sekrit' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	( cd "${cloneA}" && git remote set-url origin "${origin}" )

	## pr needs gh; syntax errors surface without it doing anything
	fAssertFail "[EkoUJUV] pr with bad number rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q pr bogus"
	fAssertFail "[EkoUJUW] pr ok with no number rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q pr ok"

	## land with an upstream-less target: the merge must reach origin before the remote work branch dies
	local fx2="${work}/$1-land2"
	local o2="${fx2}/origin.git"; local c2="${fx2}/a"; local c3="${fx2}/b"
	mkdir -p "${fx2}"
	git init --quiet --bare -b main "${o2}"
	git clone --quiet "${o2}" "${c2}" 2>/dev/null
	(
		cd "${c2}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev  ## local-only dev: no upstream
		git checkout --quiet -b feat9; git push --quiet -u origin feat9
		echo work > w.txt; git add --all; git commit --quiet -m "work"; git push --quiet
	)
	fAssert "[EkyNtdD] br land with upstream-less dev runs"      bash -c "cd '${c2}' && '${gitsby}' -q br land 'merge feat9'"
	fAssert "[EkyNtdE] merge reached origin (dev published)"  bash -c "cd '${o2}' && git show-ref --verify --quiet refs/heads/dev && git ls-tree --name-only dev | grep -qx w.txt"
	fAssert "[EkyNtdF] feat9 deleted on origin after publish" bash -c "cd '${o2}' && ! git show-ref --verify --quiet refs/heads/feat9"

	## release with an upstream-less main: the branch must reach origin, not just the tag
	local fx3="${work}/$1-rel2"
	local o5="${fx3}/origin.git"; local c5="${fx3}/a"
	mkdir -p "${fx3}"
	git init --quiet --bare -b main "${o5}"
	git clone --quiet "${o5}" "${c5}" 2>/dev/null
	(
		cd "${c5}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev; git push --quiet -u origin dev
		echo d > d.txt; git add --all; git commit --quiet -m "dev work"; git push --quiet
		git branch --unset-upstream main  ## however it got lost, main now tracks nothing
	)
	fAssert "[El5IQZQ] release with an upstream-less main runs"  bash -c "cd '${c5}' && '${gitsby}' -q release v9.0.0"
	fAssert "[El5IQZR] origin main advanced, not just the tag"   bash -c "cd '${o5}' && git ls-tree --name-only main | grep -qx d.txt"
	fAssert "[El5IQZS] tag reached origin too"                   bash -c "cd '${c5}' && git ls-remote --tags origin | grep -q 'refs/tags/v9.0.0'"

	## diverged pull with a dirty tree: fails, but work stays in the tree and out of the stash
	git clone --quiet "${o2}" "${c3}"
	( cd "${c3}" && git checkout --quiet dev && echo remote >> f.txt && git add --all && git commit --quiet -m "remote side" && git push --quiet )
	( cd "${c2}" && echo localc > localc.txt && git add --all && git commit --quiet -m "local side" && echo precious >> w.txt )
	fAssertFail "[EkyNtdG] diverged update fails"      bash -c "cd '${c2}' && '${gitsby}' -q update 'local work'"
	fAssert "[EkyNtdH] the work is still there"        bash -c "cd '${c2}' && grep -q precious w.txt"
	fAssert "[EkyNtdI] nothing stranded in the stash"  bash -c "cd '${c2}' && [[ -z \"\$(git stash list)\" ]]"
	fAssertOut    "[EkyQnOZ] pull failure reads plainly"   'failed \(exit' bash -c "cd '${c2}' && '${gitsby}' -q update"
	fAssertNotOut "[EkyQnOa] no trap dump on git failure"  'Signal \.'     bash -c "cd '${c2}' && '${gitsby}' -q update"

	## An unreachable remote must not turn a good commit into a failed command - update is the
	## only way to commit now. A bogus local path fails instantly, so this needs no network.
	local off="${work}/$1-offline"
	git clone --quiet "${origin}" "${off}" 2>/dev/null
	( cd "${off}" && git remote set-url origin "${work}/nosuch-remote.git" && echo offline > off.txt )
	fAssert    "[El9W15m] update succeeds with an unreachable remote"  bash -c "cd '${off}' && '${gitsby}' -q update 'offline work'"
	fAssert    "[El9W15n] the work was committed anyway"               bash -c "cd '${off}' && git log -1 --format=%s | grep -qx 'offline work'"
	fAssertOut "[El9W15o] and it says why it skipped the pull"  'remote unreachable' bash -c "cd '${off}' && echo more > more.txt && '${gitsby}' -q update 'more offline work'"
	## --no-fetch means offline on purpose: commit, and don't reach for the network at all
	## -NoFetch, not --no-fetch: pwsh has no such parameter and would fail, and the old pattern
	## matched its complaint about the flag - green for the wrong reason. Bash takes either.
	fAssertOut "[El9W15p] no-fetch skips the pull too"  'Skipping the pull' bash -c "cd '${off}' && echo nf > nf.txt && '${gitsby}' -q -NoFetch update 'no-fetch work'"

	## The fetch at the start of the command already brought origin's branches in, so the pull
	## step merges what it left rather than asking origin a second time. Origin answers through
	## an upload-pack that logs each time it is asked.
	local onceO="${work}/$1-onceo.git" onceA="${work}/$1-oncea" onceB="${work}/$1-onceb" onceLog="${work}/$1-once.log"
	git init --quiet --bare -b main "${onceO}"
	git clone --quiet "${onceO}" "${onceA}" 2>/dev/null
	( cd "${onceA}" && echo one > f.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main )
	git clone --quiet "${onceO}" "${onceB}"
	( cd "${onceB}" && echo two > g.txt && git add --all && git commit --quiet -m "from B" && git push --quiet )
	( cd "${onceA}" && git config remote.origin.uploadpack "echo asked >> '${onceLog}'; git upload-pack" )
	fAssertPlan "[Erg9NT0] pullcom plans a merge of the upstream"  '^ +git merge --ff-only --autostash @\{u\} \*$'  bash -c "cd '${onceA}' && '${gitsby}' -q -NoFetch pullcom"
	( cd "${onceA}" && echo dirty >> f.txt )
	: > "${onceLog}"
	fAssert "[Erg9NTE] pullcom brings in what origin has"  bash -c "cd '${onceA}' && '${gitsby}' -q pullcom 'once' && [[ -f g.txt ]] && git merge-base --is-ancestor origin/main HEAD && grep -q dirty f.txt"
	fAssert "[Erg9NTS] and asks origin once"               bash -c "[[ \"\$(grep -c asked '${onceLog}')\" == 1 ]]"
	( cd "${onceA}" && git push --quiet )
	( cd "${onceB}" && git pull --quiet --ff-only && echo three > h.txt && git add --all && git commit --quiet -m "B again" && git push --quiet )
	( cd "${onceA}" && echo dirty2 >> f.txt )
	: > "${onceLog}"
	fAssert "[Erg9NTg] sync brings it in and publishes"   bash -c "cd '${onceA}' && '${gitsby}' -q sync 'once more' && [[ -f h.txt ]] && [[ \"\$(git rev-parse HEAD)\" == \"\$(git -C '${onceO}' rev-parse main)\" ]]"
	fAssert "[Erg9NTw] and asks origin once too"          bash -c "[[ \"\$(grep -c asked '${onceLog}')\" == 1 ]]"
	## --no-fetch keeps its meaning: skip the pull, not merge whatever an earlier fetch left,
	## which would call the branch up to date against refs nobody checked.
	( cd "${onceB}" && git pull --quiet --ff-only && echo four > i.txt && git add --all && git commit --quiet -m "B thrice" && git push --quiet )
	( cd "${onceA}" && git fetch --quiet && echo nf >> f.txt )
	: > "${onceLog}"
	fAssertOut "[Erg9NUA] --no-fetch still skips the pull"          'Skipping the pull' bash -c "cd '${onceA}' && '${gitsby}' -q -NoFetch pullcom 'nf'"
	fAssert    "[Erg9NUN] and leaves the fetched commit unmerged"  bash -c "cd '${onceA}' && [[ ! -f i.txt ]] && [[ ! -s '${onceLog}' ]]"
	## An upstream on another remote was not part of that fetch, so it still pulls from there.
	( cd "${onceA}" && git remote add up "${onceO}" && git fetch --quiet up && git branch --quiet -u up/main && git reset --quiet --hard up/main )
	( cd "${onceB}" && echo five > j.txt && git add --all && git commit --quiet -m "B four" && git push --quiet )
	fAssertPlan "[Erg9NUd] an upstream on another remote plans a pull"  '^ +git pull --ff-only --autostash \*$'  bash -c "cd '${onceA}' && '${gitsby}' -q -NoFetch pullcom"
	fAssert     "[Erg9NUr] and pulls from it"                           bash -c "cd '${onceA}' && '${gitsby}' -q pullcom && [[ -f j.txt ]]"
	## The plan reads the same thing for a branch it has not checked out yet.
	( cd "${onceA}" && git checkout --quiet -b side )
	fAssertPlan "[Erg9y2K] so does the plan for a branch checked out later"  '^ +git pull --ff-only \*$'  bash -c "cd '${onceA}' && '${gitsby}' -q -NoFetch br switch main"

	## A command that still means something locally runs offline and says what it skipped; a
	## command that exists to publish refuses up front, before the plan promises a push.
	## Same bogus-path trick, on its own clone so the shared fixture keeps its history.
	## Own throwaway origin: by this point the shared one has a dev branch and release history, so
	## the merge target would not be main and these checks would be reading a different repo shape.
	## 'offland' is made and published while the remote still works, so the land below has a real
	## origin copy to leave alone; everything after the set-url is offline.
	local offOrigin="${work}/$1-offo.git"; local offb="${work}/$1-offlinebr"
	git init --quiet --bare -b main "${offOrigin}"
	git clone --quiet "${offOrigin}" "${offb}" 2>/dev/null
	(
		cd "${offb}"
		echo one > f.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main
		git checkout --quiet -b offland && echo ol > ol.txt && git add --all && git commit --quiet -m "off work" && git push --quiet -u origin offland
		git checkout --quiet main && git remote set-url origin "${work}/nosuch-remote.git"
	)
	fAssert    "[ElKUW2S] br create succeeds with an unreachable remote"  bash -c "cd '${offb}' && '${gitsby}' -q br create offfeat && [[ \"\$(git branch --show-current)\" == offfeat ]]"
	fAssertOut "[ElKUW2T] and says the branch is local only"  "'offfeat2' is local only"  bash -c "cd '${offb}' && '${gitsby}' -q br create offfeat2 2>&1"
	fAssertOut "[ElKUW2U] and warns once, above the prompt"   'nothing will be pushed'   bash -c "cd '${offb}' && '${gitsby}' -q br switch offfeat 2>&1"
	fAssert    "[ElKUW2V] br switch succeeds with an unreachable remote"  bash -c "cd '${offb}' && '${gitsby}' -q br switch main && [[ \"\$(git branch --show-current)\" == main ]]"
	## The publishing commands refuse instead, and name what to do about it. Checked before the
	## land below, since that one leaves the tree clean and 'sync' needs something to refuse over.
	fAssertFail "[ElKUW2W] sync refuses with an unreachable remote"   bash -c "cd '${offb}' && echo s > s.txt && '${gitsby}' -q sync 'nope'"
	## Named per implementation: the scripts say 'update', the compiled build says 'pullcom' and
	## adds what offline changes about it - the pull is skipped, so only the commit half runs.
	fAssertOut  "[EnLB2hc] and points at the command that commits"  "'[^']*(update|pullcom)'"   bash -c "cd '${offb}' && '${gitsby}' -q sync 'nope' 2>&1"
	fAssert     "[ElKUW2X] and it refused before committing anything"  bash -c "cd '${offb}' && git status --porcelain | grep -q 's.txt' && rm -f '${offb}/s.txt'"
	fAssertFail "[ElKUW2Y] release refuses with an unreachable remote"  bash -c "cd '${offb}' && '${gitsby}' -q release v9.9.9"
	fAssertOut  "[ElKUW2Z] and says so before cutting a tag"  "'release' has nothing left to do"  bash -c "cd '${offb}' && '${gitsby}' -q release v9.9.9 2>&1"
	fAssert     "[ElKUW2a] and no tag was cut"  bash -c "cd '${offb}' && ! git rev-parse -q --verify refs/tags/v9.9.9 >/dev/null"
	## A stub gh, because these two are about the offline refusal and nothing else. Without one they
	## depend on the box having gh installed: where it is missing, 'Not found in path: gh' comes
	## first, so the exit-code check passed for a reason that had nothing to do with being offline
	## and the message check failed. The stub never runs - the refusal is reached before it.
	local offBin="${work}/$1-offbin"; mkdir -p "${offBin}"
	fStub "${offBin}/gh" <<-'EOF'
		#!/usr/bin/env bash
		exit 0
	EOF
	fAssertFail "[ElKUW2b] pr create refuses with an unreachable remote"  bash -c "cd '${offb}' && PATH='${offBin}:${PATH}' '${gitsby}' -q br switch offfeat >/dev/null 2>&1; PATH='${offBin}:${PATH}' '${gitsby}' -q pr create 'T'"
	fAssertOut  "[ElKUW2c] and says which command needs origin"  "'pr create' has nothing left to do"  bash -c "cd '${offb}' && PATH='${offBin}:${PATH}' '${gitsby}' -q pr create 'T' 2>&1"
	## land offline: the merge lands locally, and origin's copy of the branch has to survive -
	## with the merge unpushed it is the only ref origin holds to that work.
	fAssertOut "[ElKUW2d] br land leaves origin's copy of the branch alone"  "Leaving origin's 'offland' alone"  bash -c "cd '${offb}' && '${gitsby}' -q br switch offland >/dev/null 2>&1; '${gitsby}' -q br land 'Off land' 2>&1"
	fAssert    "[ElKUW2e] and the merge landed locally"     bash -c "cd '${offb}' && git log -1 --format=%s main | grep -q 'Off land'"
	fAssert    "[ElKUW2f] and the remote-tracking ref survived"  bash -c "cd '${offb}' && git show-ref --verify --quiet refs/remotes/origin/offland"

	## Offline messages have to be true. A park with nothing to push says so instead of claiming
	## committed work awaits; the warning names the branch it means, since the command may move
	## off it next and a 'sync' from wherever you land would publish that branch instead; and a
	## hotfix land names the recovery that publishes the default branch - a bare 'sync' runs
	## from dev after the back-merge and would leave origin's default branch stale.
	local om="${work}/$1-offmsg.git"; local omw="${work}/$1-offmsgw"
	git init --quiet --bare -b main "${om}"
	git clone --quiet "${om}" "${omw}" 2>/dev/null
	(
		cd "${omw}"
		echo one > f.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b b1 && git push --quiet -u origin b1
		git remote set-url origin "${work}/nosuch-remote.git"
	)
	fAssertOut    "[ElYKwz2] an in-sync branch parks offline with nothing to push"  'Nothing to push'    bash -c "cd '${omw}' && '${gitsby}' -q br switch dev 2>&1"
	fAssertNotOut "[ElYKwz3] and no warning claims work awaits publishing"         'skipping the push'  bash -c "cd '${omw}' && git checkout --quiet b1 && '${gitsby}' -q br switch dev 2>&1"
	fAssertOut    "[ElYKwz4] an ahead branch's park warning names the branch"      "stays local on 'b1'"  bash -c "cd '${omw}' && git checkout --quiet b1 && echo w >> f.txt && '${gitsby}' -q br switch dev 2>&1"
	fAssert    "[ElYKwz5] br hotfix works offline"  bash -c "cd '${omw}' && git checkout --quiet main && '${gitsby}' -q br hotfix hx1 && [[ \"\$(git branch --show-current)\" == hotfix/hx1 ]]"
	fAssertOut "[ElYKwz6] an offline hotfix land names the branch its merge is stuck on"  "the merge to 'main' is local only - once online"  bash -c "cd '${omw}' && echo h >> f.txt && '${gitsby}' -q br land 'Hot fix' 2>&1"
	fAssert    "[ElYKwz7] and the back-merge still carried it to dev"  bash -c "cd '${omw}' && [[ \"\$(git branch --show-current)\" == dev ]] && git merge-base --is-ancestor main dev"

	## ... and offline has to mean the same thing inside a compound command, or the flag saves
	## nothing there. Own throwaway origin, so the shared one keeps its history for later checks.
	local nfOrigin="${work}/$1-nfo.git"; local nfPeer="${work}/$1-nfa"; local nfWork="${work}/$1-nfb"
	git init --quiet --bare -b main "${nfOrigin}"
	git clone --quiet "${nfOrigin}" "${nfPeer}" 2>/dev/null
	( cd "${nfPeer}" && echo one > f.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main )
	git clone --quiet "${nfOrigin}" "${nfWork}" 2>/dev/null
	( cd "${nfPeer}" && echo two >> f.txt && git commit --quiet -a -m "peer work" && git push --quiet )
	( cd "${nfWork}" && git rev-parse main > "${work}/$1-nfsha" )
	fAssert "[El9bc7t] br switch -NoFetch skips its pull"    bash -c "cd '${nfWork}' && '${gitsby}' -q -NoFetch br switch main && [[ \"\$(git rev-parse main)\" == \"\$(cat '${work}/$1-nfsha')\" ]]"
	fAssert "[El9bc7u] the same switch pulls when online"    bash -c "cd '${nfWork}' && '${gitsby}' -q br switch main && [[ \"\$(git rev-parse main)\" != \"\$(cat '${work}/$1-nfsha')\" ]]"

	## br prune: drops what's already landed, keeps everything else. Own throwaway origin, since
	## it deletes branches wholesale and the shared fixture still needs its history.
	local prOrigin="${work}/$1-pro.git"; local prWork="${work}/$1-prw"
	git init --quiet --bare -b main "${prOrigin}"
	git clone --quiet "${prOrigin}" "${prWork}" 2>/dev/null
	(
		cd "${prWork}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev; git push --quiet -u origin dev
		for b in landed abandoned; do
			git checkout --quiet -b "${b}" dev; echo "${b}" > "${b}.txt"; git add --all
			git commit --quiet -m "${b}"; git push --quiet -u origin "${b}"
		done
		git checkout --quiet -b wip dev; echo wip > wip.txt; git add --all
		git commit --quiet -m wip; git push --quiet -u origin wip
		git checkout --quiet dev
		git merge --quiet --no-ff landed    -m "merge landed"
		git merge --quiet --no-ff abandoned -m "merge abandoned"
		git push --quiet
	)
	## One call, not one per branch: eight branches were two thirds of everything this command
	## spawned. The plan has to say what the command runs, so both are one line - which is what
	## this asserts, since a per-branch plan would put 'landed' on a line of its own.
	fAssertPlan "[El9kLkZ] br prune plans the merged branches, batched"  'git branch -D abandoned landed'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssert     "[El9kLka] merged branch gone locally"       bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/landed"
	fAssert     "[El9kLkb] the other merged one too"         bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/abandoned"
	fAssert     "[El9kLkc] merged branch gone on origin"     bash -c "cd '${prOrigin}' && ! git show-ref --verify --quiet refs/heads/landed"
	fAssert     "[El9kLkd] unmerged branch kept locally"     bash -c "cd '${prWork}' && git show-ref --verify --quiet refs/heads/wip"
	fAssert     "[El9kLke] unmerged branch kept on origin"   bash -c "cd '${prOrigin}' && git show-ref --verify --quiet refs/heads/wip"
	fAssert     "[El9kLkf] protected branches kept"          bash -c "cd '${prWork}' && git show-ref --verify --quiet refs/heads/dev && git show-ref --verify --quiet refs/heads/main"
	fAssertOut  "[El9kLkg] and it says what it kept"  'Keeping \(not merged yet\): wip'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssertOut  "[El9kLkh] nothing left to prune is a no-op"  'Nothing to prune'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	## The remote delete is batched too, and its own fixture: the run above pruned the one
	## before it, and a plan check has to actually run the command to see a plan.
	local prOrigin2="${work}/$1-pro2.git"; local prWork2="${work}/$1-prw2"
	git init --quiet --bare -b main "${prOrigin2}"
	git clone --quiet "${prOrigin2}" "${prWork2}" 2>/dev/null
	(
		cd "${prWork2}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev; git push --quiet -u origin dev
		for b in alpha beta; do
			git checkout --quiet -b "${b}" dev; echo "${b}" > "${b}.txt"; git add --all
			git commit --quiet -m "${b}"; git push --quiet -u origin "${b}"
		done
		git checkout --quiet dev
		git merge --quiet --no-ff alpha -m "merge alpha"
		git merge --quiet --no-ff beta  -m "merge beta"
		git push --quiet
	)
	fAssertPlan "[EnQWPRo] and the remote delete is one call too"  'git push --force-with-lease origin --delete alpha beta'  bash -c "cd '${prWork2}' && '${gitsby}' -q br prune"
	fAssert     "[EnQWPRp] both went from origin"  bash -c "cd '${prOrigin2}' && ! git show-ref --verify --quiet refs/heads/alpha && ! git show-ref --verify --quiet refs/heads/beta"
	## Batched all the way through, the survey and the delete-time re-check included: the same
	## prune over two merged branches and over six starts git the same number of times.
	local pcBin="${work}/$1-pcbin" pcDir="" pcN=0 pcI=0
	mkdir -p "${pcBin}"
	## git starts git for its own helpers, with this directory still first on PATH; count only
	## what gitsby starts.
	fStub "${pcBin}/git" <<-EOF
		#!/usr/bin/env bash
		[[ -n "\${PC_INNER:-}" ]] || echo "\$*" >> "\${PC_LOG}"
		PC_INNER=1 exec "$(command -v git)" "\$@"
	EOF
	for pcN in 2 6; do
		pcDir="${work}/$1-pc${pcN}"
		git init --quiet --bare -b main "${pcDir}/origin.git"
		git clone --quiet "${pcDir}/origin.git" "${pcDir}/c" 2>/dev/null
		(
			cd "${pcDir}/c" || exit 1
			echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
			git checkout --quiet -b dev; git push --quiet -u origin dev
			for ((pcI = 1; pcI <= pcN; pcI++)); do
				git checkout --quiet -b "b${pcI}" dev; echo "${pcI}" > "b${pcI}.txt"; git add --all
				git commit --quiet -m "b${pcI}"; git push --quiet -u origin "b${pcI}"
				git checkout --quiet dev; git merge --quiet --no-ff "b${pcI}" -m "merge b${pcI}"
			done
			git push --quiet
		)
		( cd "${pcDir}/c" && PC_LOG="${pcDir}/git.log" PATH="${pcBin}:${PATH}" "${gitsby}" -q br prune ) > "${pcDir}/out" 2>&1 || true
	done
	fAssert     "[Er1LxRc] br prune starts git as often for six merged branches as for two" \
		bash -c "grep -q 'Pruned 6 local, 6 on origin' '${work}/$1-pc6/out' && [[ \"\$(wc -l < '${work}/$1-pc2/git.log')\" == \"\$(wc -l < '${work}/$1-pc6/git.log')\" ]]"
	fAssert     "[El9kLki] br clean aliases br prune"        bash -c "cd '${prWork}' && '${gitsby}' -q br clean"
	fAssertFail "[El9kLkj] br prune with an argument rejected"  bash -c "cd '${prWork}' && '${gitsby}' -q br prune wip"
	fAssertFail "[El9kLkk] the internal br-prune token rejected"  bash -c "cd '${prWork}' && '${gitsby}' -q br-prune"
	## The branch you're standing on can't be deleted out from under you, merged or not.
	( cd "${prWork}" && git checkout --quiet -b standing dev && git push --quiet -u origin standing )
	fAssert     "[El9kLkl] current branch survives its own prune"  bash -c "cd '${prWork}' && '${gitsby}' -q br prune; git -C '${prWork}' show-ref --verify --quiet refs/heads/standing"
	## And it must say WHY nothing happened - "no branch is merged" would be false here.
	fAssertOut  "[El9uoIC] and the output says why"  "switch off it to prune it"  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	## A merge that hasn't reached origin means origin still holds the only ref to that work:
	## the local branch may go, the remote copy may not.
	(
		cd "${prWork}"
		git checkout --quiet dev
		git checkout --quiet -b unpushed dev; echo u > u.txt; git add --all
		git commit --quiet -m unpushed; git push --quiet -u origin unpushed
		git checkout --quiet dev; git merge --quiet --no-ff unpushed -m "merge unpushed"
	)
	fAssert "[El9kLkm] local branch pruned on an unpushed merge"  bash -c "cd '${prWork}' && '${gitsby}' -q -NoFetch br prune && ! git show-ref --verify --quiet refs/heads/unpushed"
	fAssert "[El9kLkn] but origin keeps its copy"                bash -c "cd '${prOrigin}' && git show-ref --verify --quiet refs/heads/unpushed"
	## A branch that was never pushed has no upstream, so 'git branch -d' checks it against HEAD
	## and refuses from anywhere else, however merged it is. Standing off the target on purpose.
	(
		cd "${prWork}"
		git checkout --quiet dev
		git checkout --quiet -b localonly dev; echo lo > lo.txt; git add --all; git commit --quiet -m localonly
		git checkout --quiet dev; git merge --quiet --no-ff localonly -m "merge localonly"; git push --quiet
		git checkout --quiet wip
	)
	fAssertOut "[El9rD5U] merged local-only branch pruned, and counted"  'Pruned 1 local, 0 on origin'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssert    "[El9rD5V] the local-only branch is gone"          bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/localonly"
	fAssert    "[El9rD5W] pruned from a branch that doesn't contain it"  bash -c "cd '${prWork}' && [[ \"\$(git branch --show-current)\" == wip ]]"
	## The deletes go in one call, and git deletes what it can and still exits nonzero for the rest -
	## a branch checked out in another worktree, most often. Returning that ended the run with some
	## branches already deleted, origin untouched, and no count printed at all.
	(
		cd "${prWork}"
		git checkout --quiet dev
		for prHeld in held goes; do
			git checkout --quiet -b "${prHeld}" dev; echo "${prHeld}" > "${prHeld}.txt"
			git add --all; git commit --quiet -m "${prHeld}"; git push --quiet -u origin "${prHeld}"
		done
		git checkout --quiet dev
		git merge --quiet --no-ff held -m "merge held"; git merge --quiet --no-ff goes -m "merge goes"
		git push --quiet
		git checkout --quiet wip
		git worktree add --quiet "${work}/$1-prune-held" held
	)
	fAssertOut "[EnQsbMG] a branch git can't delete doesn't stop the prune"  'Pruned 1 local, 1 on origin' \
		bash -c "cd '${prWork}' && '${gitsby}' -q br prune 2>&1"
	fAssertOut "[EnQsbMH] and it names the one it couldn't"  "couldn't delete held here"  bash -c "cd '${prWork}' && '${gitsby}' -q br prune 2>&1"
	fAssert    "[EnQsbMI] the deletable one still went"      bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/goes"
	fAssert    "[EnQsbMJ] and origin keeps the held branch"  bash -c "cd '${prOrigin}' && git show-ref --verify --quiet refs/heads/held"
	( cd "${prWork}" && git worktree remove --force "${work}/$1-prune-held" >/dev/null 2>&1 || true )
	## The remote half is decided from the local copy of origin, which is only as new as the last
	## fetch. So origin is asked just before the push, and each delete is leased on the value the
	## plan tested. A second clone moves things behind the first one's back. Each run's output is
	## kept in a file, since running prune again would find nothing left to prune.
	local pnOrigin="${work}/$1-pno.git"; local pnA="${work}/$1-pna"; local pnB="${work}/$1-pnb"
	local pnBranch="" pnWait=0
	git init --quiet --bare -b main "${pnOrigin}"
	git clone --quiet "${pnOrigin}" "${pnA}" 2>/dev/null
	(
		cd "${pnA}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev; git push --quiet -u origin dev
	)
	git clone --quiet "${pnOrigin}" "${pnB}" 2>/dev/null
	## Someone pushes to one of two merged branches after this clone's last fetch.
	(
		cd "${pnA}"
		for pnBranch in moved plain; do
			git checkout --quiet -b "${pnBranch}" dev; echo "${pnBranch}" > "${pnBranch}.txt"; git add --all
			git commit --quiet -m "${pnBranch}"; git push --quiet -u origin "${pnBranch}"
		done
		git checkout --quiet dev
		git merge --quiet --no-ff moved -m "merge moved"; git merge --quiet --no-ff plain -m "merge plain"
		git push --quiet
	)
	(
		cd "${pnB}"
		git fetch --quiet; git checkout --quiet moved; echo more >> moved.txt
		git commit --quiet -am "more"; git push --quiet; git rev-parse moved > "${work}/$1-pn1moved"
	)
	git -C "${pnA}" rev-parse refs/remotes/origin/plain > "${work}/$1-pn1plain"
	( cd "${pnA}" && GIT_TRACE="${work}/$1-pn1.trace" "${gitsby}" -q -NoFetch br prune ) > "${work}/$1-pn1.out" 2>&1 || true
	fAssert    "[EptMdyy] br prune --no-fetch keeps a branch origin has moved past" \
		bash -c "[[ \"\$(git -C '${pnOrigin}' rev-parse refs/heads/moved)\" == \"\$(cat '${work}/$1-pn1moved')\" ]]"
	fAssert    "[EptMdyz] and still deletes the one origin hasn't moved"  bash -c "! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/plain"
	fAssertOut "[EptMdz0] and says origin's copy changed"  'have changed since this clone last fetched'  cat "${work}/$1-pn1.out"
	fAssertOut "[EptMdz1] and counts only what it deleted there"  'Pruned 1 local, 1 on origin'  cat "${work}/$1-pn1.out"
	fAssert    "[EptMdz2] the delete is leased on the value that was checked" \
		bash -c "grep -qF -- \"--force-with-lease=refs/heads/plain:\$(cat '${work}/$1-pn1plain')\" '${work}/$1-pn1.trace'"
	fAssert    "[EpxuX5c] and keeps the moved branch here too"  bash -c "git -C '${pnA}' show-ref --verify --quiet refs/heads/moved"
	## The warning says a second run takes a fresh look. Once the new commit is merged on origin,
	## that run has to find the branch and clear both copies.
	(
		cd "${pnB}"
		git checkout --quiet dev; git pull --quiet --ff-only
		git merge --quiet --no-ff moved -m "merge moved again"; git push --quiet
	)
	( cd "${pnA}" && "${gitsby}" -q br prune ) > "${work}/$1-pn1b.out" 2>&1 || true
	fAssert    "[EpxuX5d] and a second run, as the warning says, clears it once merged" \
		bash -c "! git -C '${pnA}' show-ref --verify --quiet refs/heads/moved && ! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/moved"
	git -C "${pnA}" pull --quiet --ff-only
	## Someone already deleted one of them on origin. A batched delete with one missing ref sends
	## none of them.
	(
		cd "${pnA}"
		for pnBranch in gone stays; do
			git checkout --quiet -b "${pnBranch}" dev; echo "${pnBranch}" > "${pnBranch}.txt"; git add --all
			git commit --quiet -m "${pnBranch}"; git push --quiet -u origin "${pnBranch}"
		done
		git checkout --quiet dev
		git merge --quiet --no-ff gone -m "merge gone"; git merge --quiet --no-ff stays -m "merge stays"
		git push --quiet
	)
	git -C "${pnB}" push --quiet origin --delete gone
	( cd "${pnA}" && "${gitsby}" -q -NoFetch br prune ) > "${work}/$1-pn2.out" 2>&1 || true
	fAssert    "[EptMdz3] a branch already gone from origin doesn't stop the other deletes"  bash -c "! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/stays"
	fAssertOut "[EptMdz4] and it says which one was already gone"  'Already gone from origin: gone'  cat "${work}/$1-pn2.out"
	fAssertOut "[EptMdz5] and leaves it out of the count"  'Pruned 2 local, 1 on origin'  cat "${work}/$1-pn2.out"
	## Merged and never pushed, so nothing goes to origin and origin is not asked.
	(
		cd "${pnA}"
		git checkout --quiet -b solo dev; echo solo > solo.txt; git add --all; git commit --quiet -m solo
		git checkout --quiet dev; git merge --quiet --no-ff solo -m "merge solo"; git push --quiet
	)
	( cd "${pnA}" && GIT_TRACE="${work}/$1-pn3.trace" "${gitsby}" -q -NoFetch br prune ) > "${work}/$1-pn3.out" 2>&1 || true
	fAssert    "[EptMdz6] origin isn't asked when nothing goes there" \
		bash -c "! git -C '${pnA}' show-ref --verify --quiet refs/heads/solo && [[ -s '${work}/$1-pn3.trace' ]] && ! grep -qF 'ls-remote' '${work}/$1-pn3.trace'"
	## A tag with a branch's name, here and on origin. Origin matches a short name against its tags
	## too, and git shortens the branch here to 'heads/amb'.
	(
		cd "${pnA}"
		for pnBranch in amb other; do
			git checkout --quiet -b "${pnBranch}" dev; echo "${pnBranch}" > "${pnBranch}.txt"; git add --all
			git commit --quiet -m "${pnBranch}"; git push --quiet -u origin "${pnBranch}"
		done
		git checkout --quiet dev
		git merge --quiet --no-ff amb -m "merge amb"; git merge --quiet --no-ff other -m "merge other"
		git push --quiet; git tag amb dev; git push --quiet origin refs/tags/amb
	)
	( cd "${pnA}" && "${gitsby}" -q -NoFetch br prune ) > "${work}/$1-pn6.out" 2>&1 || true
	fAssert    "[EpxuX5e] a tag with a branch's name doesn't stop br prune's deletes" \
		bash -c "! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/amb && ! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/other"
	fAssert    "[EpxuX5f] and leaves the tag"  bash -c "git -C '${pnOrigin}' show-ref --verify --quiet refs/tags/amb"
	fAssertOut "[EpxuX5g] and deletes both here too"  'Pruned 2 local, 2 on origin'  cat "${work}/$1-pn6.out"
	## git merge reads a tag ahead of a branch with the same name. Merging the tag leaves the
	## branch's commit out, and the delete after it takes origin's only copy.
	(
		cd "${pnA}"
		git checkout --quiet -b tagged dev; echo tagged > tagged.txt; git add --all
		git commit --quiet -m tagged; git push --quiet -u origin tagged; git tag tagged dev
		git rev-parse refs/heads/tagged > "${work}/$1-pn7tip"
	)
	( cd "${pnA}" && GIT_TRACE="${work}/$1-pn7.trace" "${gitsby}" -q -NoFetch br merge "merge tagged" ) > "${work}/$1-pn7.out" 2>&1 || true
	fAssert    "[EpxuX5h] br merge merges the branch, not a tag with its name" \
		bash -c "git -C '${pnOrigin}' merge-base --is-ancestor \"\$(cat '${work}/$1-pn7tip')\" refs/heads/dev"
	fAssert    "[EpxuX5i] and deletes origin's copy, leased on the tip it merged" \
		bash -c "! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/tagged && grep -qF -- \"--force-with-lease=refs/heads/tagged:\$(cat '${work}/$1-pn7tip')\" '${work}/$1-pn7.trace'"
	## Someone else pushes to the branch, and br merge --no-fetch never pulls it in. Origin's copy
	## is then the only ref to that commit.
	(
		cd "${pnA}"
		git checkout --quiet -b shared dev; echo shared > shared.txt; git add --all
		git commit --quiet -m shared; git push --quiet -u origin shared
	)
	(
		cd "${pnB}"
		git fetch --quiet; git checkout --quiet shared; echo more >> shared.txt
		git commit --quiet -am "more"; git push --quiet; git rev-parse shared > "${work}/$1-pn8shared"
	)
	( cd "${pnA}" && "${gitsby}" -q -NoFetch br merge "merge shared" ) > "${work}/$1-pn8.out" 2>&1 || true
	fAssert    "[EpxuX5j] br merge --no-fetch keeps its branch on origin after someone else pushed to it" \
		bash -c "[[ \"\$(git -C '${pnOrigin}' rev-parse refs/heads/shared)\" == \"\$(cat '${work}/$1-pn8shared')\" ]]"
	fAssert    "[EpxuX5k] and still merges and pushes what it had"  bash -c "git -C '${pnOrigin}' log -1 --format=%s refs/heads/dev | grep -q 'merge shared'"
	fAssertOut "[EpxuX5l] and names what brings the commit in"  "has commits this merge doesn't; left it alone - '[^']*br switch shared' without --no-fetch, then '[^']*br merge'"  cat "${work}/$1-pn8.out"
	( cd "${pnA}" && "${gitsby}" -q br switch shared && "${gitsby}" -q br merge "merge shared again" ) > "${work}/$1-pn8b.out" 2>&1 || true
	fAssert    "[EpxuX5m] and that advice, followed, brings it in and clears origin's copy" \
		bash -c "git -C '${pnOrigin}' merge-base --is-ancestor \"\$(cat '${work}/$1-pn8shared')\" refs/heads/dev && ! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/shared"
	## Someone else already deleted the branch on origin, and --no-fetch still has its copy here.
	## There is nothing left to delete, which is not a failure.
	local pnRc=0
	(
		cd "${pnA}"
		git checkout --quiet -b vanish dev; echo vanish > vanish.txt; git add --all
		git commit --quiet -m vanish; git push --quiet -u origin vanish
	)
	git -C "${pnB}" push --quiet origin --delete vanish
	( cd "${pnA}" && "${gitsby}" -q -NoFetch br merge "merge vanish" ) > "${work}/$1-pn10.out" 2>&1 || pnRc=$?
	fAssert    "[Er1LxRd] br merge carries on when its branch is already gone from origin"  test "${pnRc}" = 0
	fAssertOut "[Er1LxRe] and says so"  'Already gone from origin: vanish'  cat "${work}/$1-pn10.out"
	fAssert    "[Er1LxRf] and the merge reached origin"  bash -c "git -C '${pnOrigin}' log -1 --format=%s refs/heads/dev | grep -qx 'merge vanish'"
	## Moved while the prompt waits, off anything in dev: the delete-time re-check keeps it, and
	## keeping it has to hold for origin's copy too.
	if ((hasPty)); then
		(
			cd "${pnA}"
			git checkout --quiet -b stray dev; echo stray > stray.txt; git add --all
			git commit --quiet -m stray; git push --quiet -u origin stray
			git checkout --quiet dev; git merge --quiet --no-ff stray -m "merge stray"; git push --quiet
			git commit-tree -p dev -m "off dev" "dev^{tree}" > "${work}/$1-pn11off"
		)
		: > "${work}/$1-pn11.out"
		# shellcheck disable=SC2094  ## the poll reads the file script is writing, on purpose.
		{
			for ((pnWait = 0; pnWait < 100; pnWait++)); do
				grep -qF 'Continue?' "${work}/$1-pn11.out" && break
				sleep 0.1
			done
			git -C "${pnA}" update-ref refs/heads/stray "$(cat "${work}/$1-pn11off")" >/dev/null 2>&1
			echo y
		} | script -qec "cd '${pnA}' && '${gitsby}' br prune" /dev/null > "${work}/$1-pn11.out" 2>&1 || true
		fAssertOut "[Er1LxRg] a branch moved off dev during the prompt is kept"  "'stray' is no longer contained"  cat "${work}/$1-pn11.out"
		fAssert    "[Er1LxRh] and kept here"  bash -c "[[ \"\$(git -C '${pnA}' rev-parse refs/heads/stray)\" == \"\$(cat '${work}/$1-pn11off')\" ]]"
		fAssert    "[Er1LxRi] and on origin"  bash -c "git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/stray"
	fi
	## With the fetch on, someone pushes while the prompt waits. The second clone's output is kept
	## off the pipe, since everything on it is typed at the prompt.
	if ((hasPty)); then
		(
			cd "${pnA}"
			git checkout --quiet -b late dev; echo late > late.txt; git add --all
			git commit --quiet -m late; git push --quiet -u origin late
			git checkout --quiet dev; git merge --quiet --no-ff late -m "merge late"; git push --quiet
		)
		: > "${work}/$1-pn4.out"
		# shellcheck disable=SC2094  ## the poll reads the file script is writing, on purpose.
		{
			for ((pnWait = 0; pnWait < 100; pnWait++)); do
				grep -qF 'Continue?' "${work}/$1-pn4.out" && break
				sleep 0.1
			done
			(
				cd "${pnB}"
				git fetch --quiet; git checkout --quiet late; echo more >> late.txt
				git commit --quiet -am "more"; git push --quiet; git rev-parse late > "${work}/$1-pn4late"
			) >/dev/null 2>&1
			echo y
		} | script -qec "cd '${pnA}' && '${gitsby}' br prune" /dev/null > "${work}/$1-pn4.out" 2>&1 || true
		fAssert "[EptMdz7] a branch moved on origin during the prompt is kept" \
			bash -c "[[ \"\$(git -C '${pnOrigin}' rev-parse refs/heads/late)\" == \"\$(cat '${work}/$1-pn4late')\" ]]"
	fi
	## Last, since origin goes away for it: renamed rather than removed, and put back after.
	(
		cd "${pnA}"
		git checkout --quiet -b far dev; echo far > far.txt; git add --all
		git commit --quiet -m far; git push --quiet -u origin far
		git checkout --quiet dev; git merge --quiet --no-ff far -m "merge far"; git push --quiet
	)
	mv "${pnOrigin}" "${pnOrigin}.away"
	( cd "${pnA}" && "${gitsby}" -q -NoFetch br prune ) > "${work}/$1-pn5.out" 2>&1 || true
	mv "${pnOrigin}.away" "${pnOrigin}"
	## 'late' is still here when there is a pty, since a copy moved on origin keeps its local branch.
	fAssertOut    "[EptMdz8] br prune --no-fetch holds origin's deletes when it can't reach origin"  "left origin's copies of ([^ ]+, )*far(, [^ ]+)* alone"  cat "${work}/$1-pn5.out"
	fAssertNotOut "[EptMdz9] and doesn't blame the branch"  'already gone'  cat "${work}/$1-pn5.out"
	fAssert       "[EptMdzA] and still deletes the local branch without origin"  bash -c "! git -C '${pnA}' show-ref --verify --quiet refs/heads/far"
	fAssert       "[EpxuX5n] and the delete it names, typed as shown once origin is back, clears origin's copy" \
		bash -c "cd '${pnA}' && line=\"\$(grep -E '^ +git push .*refs/heads/far\$' '${work}/$1-pn5.out')\" && [[ -n \"\${line}\" ]] && bash -c \"\${line}\" >/dev/null 2>&1 && ! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/far"
	## br merge with origin unreachable says br prune clears origin's copy later. Prune looks for
	## what to clear among local branches, so the branch has to stay here too.
	(
		cd "${pnA}"
		git checkout --quiet -b later dev; echo later > later.txt; git add --all
		git commit --quiet -m later; git push --quiet -u origin later
	)
	mv "${pnOrigin}" "${pnOrigin}.away"
	( cd "${pnA}" && "${gitsby}" -q br merge "merge later" ) > "${work}/$1-pn9.out" 2>&1 || true
	mv "${pnOrigin}.away" "${pnOrigin}"
	fAssertOut "[EpxuX5o] br merge offline names br prune for origin's copy"  "Leaving origin's 'later' alone.*br prune' deletes both"  cat "${work}/$1-pn9.out"
	( cd "${pnA}" && "${gitsby}" -q sync "publish later" && "${gitsby}" -q br prune ) > "${work}/$1-pn9b.out" 2>&1 || true
	fAssert    "[EpxuX5p] and once online, sync then br prune clears both" \
		bash -c "! git -C '${pnA}' show-ref --verify --quiet refs/heads/later && ! git -C '${pnOrigin}' show-ref --verify --quiet refs/heads/later"

	## clone: derives the dir, checks out dev when the repo has one, no-op re-run, collision guards
	local cl="${work}/$1-clone"
	mkdir -p "${cl}"
	fAssert "[EkyfYaG] repo clone runs"                bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${origin}' cl1"
	fAssert "[EkyfYaH] repo clone checked out dev"     bash -c "cd '${cl}/cl1' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert "[EkyfYaI] repo clone again (already cloned) ok"  bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${origin}' cl1"
	fAssert "[EkyfYaJ] repo clone derives dir from url"       bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${origin}' && [[ -d origin/.git ]]"
	fAssertFail "[EkyfYaK] repo clone into non-empty dir rejected"  bash -c "cd '${cl}' && mkdir -p other && touch other/x && '${gitsby}' -q repo clone '${origin}' other"
	fAssertFail "[EkyfYaL] repo clone with no url rejected"         bash -c "cd '${cl}' && '${gitsby}' -q repo clone"
	## a repo without dev stays on the default branch; a pre-existing empty dir is fine; a clone of a different url is refused
	local o3="${cl}/nodev.git"
	git init --quiet --bare -b main "${o3}"
	git clone --quiet "${o3}" "${cl}/nodev-seed" 2>/dev/null
	( cd "${cl}/nodev-seed" && echo n > n.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main )
	fAssert "[EkykHFQ] repo clone of a no-dev repo stays on default"  bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${o3}' nd && [[ \"\$(cd nd && git branch --show-current)\" == main ]]"
	fAssert "[EkykHFR] repo clone into a pre-existing empty dir"      bash -c "cd '${cl}' && mkdir -p pre && '${gitsby}' -q repo clone '${origin}' pre && [[ -d pre/.git ]]"
	## A folder given relative was shown the way it was typed, which leaves the reader to work out
	## where it lands. The git command keeps the typed form.
	## Windows prints its own spelling of the path, which this fixture does not build.
	if ! ((isWindows)); then
		fAssertOut "[ErCS7c0] repo clone names the folder in full"  "^Clone into \.+: ${cl//./\\.}/sub/named$" \
			bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${origin}' sub/named"
		fAssertOut "[ErCS7cF] and says where it cloned in full as well"  "Cloned into '${cl//./\\.}/sub/named2'" \
			bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${origin}' sub/named2"
	fi
	fAssertFail "[EkykHFS] repo clone over a different-url clone refused"  bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${o3}' cl1"

	## connect: publish a local-only repo to a fresh empty remote; idempotent; guards
	local cn="${work}/$1-connect"
	mkdir -p "${cn}"
	git init --quiet --bare -b main "${cn}/remote.git"
	git init --quiet -b main "${cn}/proj"
	( cd "${cn}/proj" && echo hi > hi.txt && git add --all && git commit --quiet -m "init" )
	fAssert "[EkyfYaM] repo connect pushes to an empty remote"  bash -c "cd '${cn}/proj' && '${gitsby}' -q repo connect '${cn}/remote.git'"
	fAssert "[EkyfYaN] remote got the commit"              bash -c "cd '${cn}/remote.git' && git ls-tree --name-only main | grep -qx hi.txt"
	fAssert "[EkyfYaO] repo connect set the upstream"           bash -c "cd '${cn}/proj' && git rev-parse --abbrev-ref '@{u}' >/dev/null"
	fAssert "[EkyfYaP] repo connect again (nothing to do) ok"   bash -c "cd '${cn}/proj' && '${gitsby}' -q repo connect"
	fAssert "[EkyfYaQ] repo connect commits then pushes new work"  bash -c "cd '${cn}/proj' && echo more > more.txt && '${gitsby}' -q repo connect && cd '${cn}/remote.git' && git ls-tree --name-only main | grep -qx more.txt"
	fAssertFail "[EkyfYaR] repo connect different url rejected"    bash -c "cd '${cn}/proj' && '${gitsby}' -q repo connect '${cn}/other.git'"

	## connect from a plain directory: init + commit + push in one
	git init --quiet --bare -b main "${cn}/remote2.git"
	mkdir -p "${cn}/plain"; echo data > "${cn}/plain/data.txt"
	fAssert "[EkyfYaS] repo connect from a non-repo dir"  bash -c "cd '${cn}/plain' && '${gitsby}' -q repo connect '${cn}/remote2.git'"
	fAssert "[EkyfYaT] plain dir now a pushed repo"  bash -c "cd '${cn}/plain' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"

	## The one command that hands a whole directory over has to say what is in it first, and the
	## list has to be git's answer, not a directory walk - anything else names files 'git add --all'
	## will skip. Own TMPDIR so the throwaway git dir it asks through can be shown to be cleaned up
	## (both builds honor TMPDIR for their temp path).
	git init --quiet --bare -b main "${cn}/remote3.git"
	local pubDir="${cn}/publish"; local pubTmp="${cn}/publish-tmp"
	mkdir -p "${pubDir}/sub" "${pubDir}/skipdir" "${pubTmp}"
	echo keep    > "${pubDir}/keep.txt"
	echo TOKEN=x > "${pubDir}/.env"
	echo nested  > "${pubDir}/sub/nested.txt"
	echo noise   > "${pubDir}/skipme.log"
	echo noise   > "${pubDir}/skipdir/thing.js"
	printf '*.log\nskipdir/\n' > "${pubDir}/.gitignore"
	fAssertOut    "[ElKUW2g] repo connect lists the files it will publish"  'Files to publish:'  bash -c "cd '${pubDir}' && TMPDIR='${pubTmp}' '${gitsby}' -q repo connect '${cn}/remote3.git' 2>&1"
	fAssert       "[ElKUW2h] the listing probe cleaned up after itself"     bash -c "[[ -z \"\$(ls -A '${pubTmp}')\" ]]"
	fAssert       "[ElKUW2i] and the dotfile went up, as the listing said"  bash -c "cd '${cn}/remote3.git' && git ls-tree -r --name-only main | grep -qx '\.env'"
	fAssert       "[ElKUW2j] and the ignored file did not"                  bash -c "cd '${cn}/remote3.git' && ! git ls-tree -r --name-only main | grep -q 'skipme.log'"
	## The list itself, line by line, on a fresh copy of the same tree: the stray dotfile is the
	## point of the feature, and an ignored file appearing would make the whole list untrustworthy.
	local pub2="${cn}/publish2"
	mkdir -p "${pub2}"; cp -r "${pubDir}/." "${pub2}/"; rm -rf -- "${pub2:?}/.git"
	git init --quiet --bare -b main "${cn}/remote4.git"
	fAssertOut    "[ElKUW2k] the listing names a stray dotfile"  '^    \.env$'  bash -c "cd '${pub2}' && '${gitsby}' -q repo connect '${cn}/remote4.git' 2>&1"
	local pub3="${cn}/publish3"
	mkdir -p "${pub3}"; cp -r "${pubDir}/." "${pub3}/"; rm -rf -- "${pub3:?}/.git"
	git init --quiet --bare -b main "${cn}/remote5.git"
	fAssertNotOut "[ElKUW2l] the listing honors .gitignore"  'skipme\.log|skipdir'  bash -c "cd '${pub3}' && '${gitsby}' -q repo connect '${cn}/remote5.git' 2>&1"

	## connect refuses remotes with history, unreachable remotes, and empty dirs
	git init --quiet -b main "${cn}/proj2"
	( cd "${cn}/proj2" && echo x > x.txt && git add --all && git commit --quiet -m "x" )
	fAssertFail "[EkyfYaU] repo connect to nonempty remote rejected"  bash -c "cd '${cn}/proj2' && '${gitsby}' -q repo connect '${cn}/remote2.git'"
	fAssertFail "[EkyfYaV] repo connect to missing remote rejected"   bash -c "cd '${cn}/proj2' && '${gitsby}' -q repo connect '${cn}/nosuch.git'"
	## A remote that can't be reached is not a remote that isn't there. A stub ssh stands in for a
	## network that is down: a GIT_SSH_COMMAND the caller set is left alone, so git runs it. Run
	## from a plain folder of its own, so a build that wrongly connects touches nothing else.
	local cnOff="${cn}/offline"
	mkdir -p "${cnOff}/plain"; echo data > "${cnOff}/plain/data.txt"
	fStub "${cnOff}/ssh" <<-'EOF'
		#!/usr/bin/env bash
		echo "ssh: connect to host offline.example.test port 22: Network is unreachable" >&2
		exit 255
	EOF
	local cnOffRun="cd '${cnOff}/plain' && GIT_SSH_COMMAND='${cnOff}/ssh' '${gitsby}' -q repo connect ssh://git@offline.example.test/me/proj.git"
	fAssertFail   "[EptraIS] repo connect refuses a remote it can't reach"      bash -c "${cnOffRun}"
	fAssertOut    "[EptraIT] and says that, not that the remote is missing"    'no telling whether it exists'  bash -c "${cnOffRun}"
	fAssertOut    "[EptraIU] and repeats what ssh said"                        'Network is unreachable'        bash -c "${cnOffRun}"
	fAssertNotOut "[EptraIV] and does not send you off to repo create"         'repo create'                   bash -c "${cnOffRun}"
	fAssert       "[EptraIW] and nothing was set up"                           bash -c "[[ ! -e '${cnOff}/plain/.git' ]]"
	fAssertOut    "[EptraIX] a remote that isn't there still says so"          "doesn.t exist, or you have no access"  bash -c "cd '${cn}/proj2' && '${gitsby}' -q repo connect '${cn}/nosuch.git'"
	## 127.0.0.1 port 1 is refused on this machine, not sent anywhere; the proxies are unset so it stays that way.
	fAssertNotOut "[EptraIY] a credential in an unreachable url is not printed"  'tok_s3cret' \
		bash -c "cd '${cnOff}/plain' && env -u https_proxy -u HTTPS_PROXY -u ALL_PROXY -u all_proxy '${gitsby}' -q repo connect 'https://me:tok_s3cret@127.0.0.1:1/me/proj.git'"
	## The same url handed to a step: the echo and the failure line name the command, not the token.
	mkdir -p "${cnOff}/clone"
	local cnCred="cd '${cnOff}/clone' && env -u https_proxy -u HTTPS_PROXY -u ALL_PROXY -u all_proxy '${gitsby}' -q repo clone 'https://me:tok_s3cret@127.0.0.1:1/x.git' credc 2>&1"
	fAssertOut    "[Er1LxRj] a credential in a step's url is masked in its echo"  '^\[ git clone .*https://\*\*\*@127\.0\.0\.1:1/x\.git'  bash -c "${cnCred}"
	fAssertNotOut "[Er1LxRk] and is printed nowhere in the run"                   'tok_s3cret'                                         bash -c "${cnCred}"
	fAssertFail "[EkyfYaW] repo connect in an empty dir rejected"     bash -c "mkdir -p '${cn}/empty' && cd '${cn}/empty' && '${gitsby}' -q repo connect '${cn}/remote.git'"
	## an inited repo with no commit and no files is nothing to connect; a matching explicit url re-connects fine (push mode)
	git init --quiet -b main "${cn}/bare-repo"
	fAssertFail "[EkykHFT] repo connect an empty inited repo rejected"  bash -c "cd '${cn}/bare-repo' && '${gitsby}' -q repo connect '${cn}/remote.git'"
	fAssert "[EkykHFU] repo connect accepts a matching explicit url"    bash -c "cd '${cn}/proj' && '${gitsby}' -q repo connect '${cn}/remote.git'"

	## The SSH identity line. Every other check here uses a local-path origin, which has no ssh
	## identity at all - so this whole line went out untested and shipped naming the OS login.
	## A fake ssh gives it an scp-like origin to read without leaving the box: -G defaults 'user'
	## to the OS login when the target carries none (the real behavior, and the whole bug),
	## -T greets as the key's account, and anything else fails so git's own fetch reports offline.
	local sid="${work}/$1-sshid"
	mkdir -p "${sid}/bin"
	fStub "${sid}/bin/ssh" <<-'EOF'
		#!/usr/bin/env bash
		[[ -n "${FAKE_SSH_LOG:-}" ]] && echo "$*" >> "${FAKE_SSH_LOG}"
		target="${*: -1}"
		case "$1" in
			-G) if [[ "${target}" == *@* ]]; then printf 'user %s\n' "${target%%@*}"; else printf 'user %s\n' "osuser"; fi
			    printf 'hostname %s\n' "${FAKE_SSH_HOSTNAME:-github.com}"
			    printf 'identityfile %s\n' "${FAKE_SSH_KEY:-/etc/hostname}"
			    exit 0 ;;
			-T) echo "Hi ${FAKE_SSH_LOGIN:-acmedev}! You've successfully authenticated, but GitHub does not provide shell access." >&2; exit 1 ;;
		esac
		exit 255
	EOF
	local sidp="${sid}/bin:${PATH}"
	## Only a key file that exists gets named, so the stub has to nominate a real one - in a form
	## both builds can stat, which on Windows means a drive path, not a POSIX one.
	: > "${sid}/keyfile"
	local sidKey="${sid}/keyfile"
	((isWindows)) && sidKey="$(cygpath -m "${sid}/keyfile")"
	git init --quiet -b main "${sid}/proj"
	( cd "${sid}/proj" && echo s > s.txt && git add --all && git commit --quiet -m init && git remote add origin git@github.com:acme/api.git )
	local sidRun="cd '${sid}/proj' && PATH='${sidp}' FAKE_SSH_KEY='${sidKey}'"
	## The account the key authenticates as is the question this line exists to answer, so it
	## leads. The old line answered with the OS login, which is neither that nor the connect user.
	fAssertOut    "[ElXjZbc] ssh line names the account the key authenticates as"  "SSH \.+: acmedev \("  bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	## Anchored to the SSH line: a bare 'git@github.com' also matches the Remote line right above
	## it, so the loose form was satisfied by the broken output too.
	fAssertOut    "[ElXjZbd] ssh line names the user git actually connects as"     "SSH \.+: .*\(git@github\.com,"  bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "[ElXjZbe] ssh line never reports the OS login"                  'osuser'               bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	fAssertOut    "[ElXjZbf] the key is still reported"                            "key ${sidKey}"        bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	fAssertOut    "[ElXjZbg] a mutating pre-flight names the account too"          "SSH \.+: acmedev \("  bash -c "${sidRun} '${gitsby}' -q -NoFetch update 'ssh id probe' 2>&1"
	## The target comes from origin, which is anybody's to write: without '--' a host spelled like
	## an option is read as one.
	: > "${sid}/dd.log"
	fAssert "[Er1LxRl] the ssh config lookup ends options before the target" \
		bash -c "${sidRun} FAKE_SSH_LOG='${sid}/dd.log' '${gitsby}' -q -NoFetch status >/dev/null 2>&1; grep -qx -- '-G -- git@github\.com' '${sid}/dd.log'"
	fAssert "[Er1LxRm] and so does the identity probe" \
		bash -c "grep -qE -- '^-T .* -- git@github\.com$' '${sid}/dd.log'"
	## A host alias is the case the line was added for: ~/.ssh/config hides the real host and key.
	git -C "${sid}/proj" remote set-url origin git@gh-acme:acme/api.git
	fAssertOut "[ElXjZbh] an ssh config alias is named alongside the real host"  "via alias 'gh-acme'"  bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	: > "${sid}/dd.log"
	fAssert "[Er1LxRn] and the alias lookup ends options before it too" \
		bash -c "${sidRun} FAKE_SSH_LOG='${sid}/dd.log' '${gitsby}' -q -NoFetch status >/dev/null 2>&1; grep -qx -- '-G -- gh-acme' '${sid}/dd.log'"
	git -C "${sid}/proj" remote set-url origin git@github.com:acme/api.git
	## Offline (the fetch failed): say we don't know rather than guess, and don't spend the
	## round trip finding out. Asserting the log is what proves the probe was actually skipped.
	fAssertOut "[ElXjZbi] an unreachable remote leaves the account unknown"  "SSH \.+: unknown \(git@github\.com"  bash -c "${sidRun} '${gitsby}' -q status"
	fAssert    "[ElXjZbj] and no identity round trip was attempted"  bash -c "${sidRun} FAKE_SSH_LOG='${sid}/log' '${gitsby}' -q status >/dev/null 2>&1; ! grep -q -- '-T' '${sid}/log'"

	## The pre-command fetch must never sit and ask for credentials: it runs before any of our
	## own checks, so an https remote you can't authenticate to would block every command.
	## A git shim records the env the fetch actually got - the only way to see this without a tty.
	local tp="${work}/$1-tprompt"
	mkdir -p "${tp}/bin"
	fStub "${tp}/bin/git" <<-EOF
		#!/usr/bin/env bash
		[[ "\$1" == "fetch" ]] && echo "\${GIT_TERMINAL_PROMPT-UNSET}" >> "\${TPROMPT_LOG}"
		exec "$(command -v git)" "\$@"
	EOF
	git init --quiet -b main "${tp}/proj"
	## Origin is a dead local path, not an https URL: the assert reads the env the fetch got,
	## so it needs no real server, and the suite stays off the network.
	( cd "${tp}/proj" && echo t > t.txt && git add --all && git commit --quiet -m init && git remote add origin "${tp}/nosuch.git" )
	fAssert "[ElAdrDU] the pre-command fetch disables credential prompts"  bash -c "cd '${tp}/proj' && TPROMPT_LOG='${tp}/log' PATH='${tp}/bin:${PATH}' '${gitsby}' -q status >/dev/null 2>&1; grep -qx 0 '${tp}/log'"

	## A clone with no origin/HEAD - older git never wrote one - gets it back from the fetch, so
	## the default branch is origin's. Newer git writes it on fetch by itself, which the config
	## line turns off to stand in for the old one. Two local branches, neither of them a
	## conventional name, leave nothing else to go on.
	local oh="${work}/$1-originhead"
	git init --quiet --bare -b trunk2 "${oh}/origin.git"
	git clone --quiet "${oh}/origin.git" "${oh}/seed" 2>/dev/null
	( cd "${oh}/seed" && echo t > t.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin trunk2 )
	git clone --quiet "${oh}/origin.git" "${oh}/c" 2>/dev/null
	( cd "${oh}/c" && git branch other && git config remote.origin.followRemoteHEAD never && git remote set-head origin -d )
	fAssertOut "[Er1LxRo] the fetch restores a missing origin/HEAD"  '^Default branch: trunk2$'  bash -c "cd '${oh}/c' && '${gitsby}' -q status"
	fAssert    "[Er1LxRp] and leaves the ref in place"  bash -c "git -C '${oh}/c' symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null"
	## Healing asks origin a second time, so a clone that already has the ref is left alone.
	fAssert    "[Er1LxRq] and a clone that has one isn't asked again" \
		bash -c "cd '${oh}/c' && GIT_TRACE='${oh}/trace' '${gitsby}' -q status >/dev/null 2>&1; [[ -s '${oh}/trace' ]] && ! grep -qF 'remote set-head' '${oh}/trace'"

	## owner/name targets: the gh path, driven by a deterministic fake gh (no network). Covers
	## 'repo create' (repo absent), 'repo connect' remote-add (present but empty, https + ssh),
	## the refuse-nonempty guard, and the create/connect division of labour. Add-mode github URLs are rewritten onto a local bare via insteadOf so
	## the push lands offline; create-mode wiring is done inside the stub.
	local gh="${work}/$1-gh"
	mkdir -p "${gh}/bin"
	fStub "${gh}/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
## Test stub: deterministic gh, no network. Behavior driven by FAKE_GH_* env.
## GH_TOKEN is logged too: that is how a check sees which account the run picked for the remote.
[[ -n "${FAKE_GH_LOG:-}" ]] && echo "$* [GH_TOKEN=${GH_TOKEN:-}]" >> "${FAKE_GH_LOG}"
case "$1 $2" in
	"api user")    ## Whose token gh is holding - the exported one when there is one, like the real
	               ## thing. A probe run after the switch can then only ever answer with the account
	               ## it just switched to, which is what the pre-switch probe exists to avoid.
	               if [[ -n "${GH_TOKEN:-}" ]]; then echo "${GH_TOKEN#tok_}"; else echo "${FAKE_GH_LOGIN:-ghuser}"; fi ;;
	"auth token")  ## accounts gh holds, space separated; exit 1 for anyone else, like the real thing
	               case " ${FAKE_GH_ACCOUNTS:-} " in *" $4 "*) echo "tok_$4" ;; *) exit 1 ;; esac ;;
	"repo view")   ## Real gh distinguishes these on stderr, and gitsby now reads it: a name that
	               ## resolves to nothing is not the same answer as an API it couldn't reach.
	               case "${FAKE_GH_VIEW:-}" in
	                 notfound) echo "GraphQL: Could not resolve to a Repository with the name '$3'. (repository)" >&2; exit 1 ;;
	                 offline)  echo "error connecting to api.github.com" >&2; exit 1 ;;
	                 empty)    echo true ;;
	                 nonempty) echo false ;;
	               esac ;;
	"config get")  echo "${FAKE_GH_PROTO:-https}" ;;
	"pr list")     echo "${FAKE_GH_EXISTING:-}" ;;  ## an already-open PR number for this branch, or nothing
	"pr create")   echo "https://github.com/me/proj/pull/${FAKE_GH_NEWPR:-1}" ;;
	"pr review")   : ;;  ## gitsby treats approval as best-effort; nothing to fake
	"pr view")     ## A number gh can't resolve fails, like the real thing - it does not answer with
	               ## nothing and exit 0.
	               [[ "${FAKE_GH_PRVIEW:-}" == fail ]] && { echo "GraphQL: Could not resolve to a PullRequest" >&2; exit 1 ;}
	               echo "${FAKE_GH_HEAD:-$(git branch --show-current)}"     ## the PR's own head branch
	               echo "${FAKE_GH_STATE:-OPEN}" ;;                          ## ... and whether it is still open
	"pr diff")     echo "diff --git a/work.txt b/work.txt" ;;
	"pr merge")    ## Land the branch on the base, then drop it from the remote. Real gh does the delete
	               ## over the API, so the caller's origin/* copy survives it - restore the ref to match.
	               ## FAKE_GH_HEAD lets a check merge a PR whose branch isn't the one we're standing on.
	               ## It merges what ORIGIN holds, not the local branch - the whole point of the
	               ## unpushed-commit guard - and deletes the local copy too, with -D, like gh does.
	               prBranch="${FAKE_GH_HEAD:-$(git branch --show-current)}"
	               prKeep="$(git rev-parse "refs/remotes/origin/${prBranch}")"
	               git push --quiet origin "${prKeep}:refs/heads/${FAKE_GH_BASE:-dev}"
	               git push --quiet origin --delete "${prBranch}"
	               git update-ref "refs/remotes/origin/${prBranch}" "${prKeep}"
	               [[ "${prBranch}" != "$(git branch --show-current)" ]] && git branch -D "${prBranch}" >/dev/null
	               : ;;
	"repo create") git init --quiet --bare -b main "${FAKE_GH_REMOTE}"
	               git remote add origin "${FAKE_GH_REMOTE}"
	               git push --quiet -u origin HEAD ;;
	*) echo "fake gh: unhandled: $*" >&2; exit 2 ;;
esac
GHEOF
	## An ssh-protocol connect now probes the identity of the url it is about to set, so this dir
	## needs an ssh too - otherwise the suite would ask the real github.com who we are. Answers with
	## the same login the fake gh reports, so these checks see a match and carry on.
	fStub "${gh}/bin/ssh" <<-'EOF'
		#!/usr/bin/env bash
		## Scan rather than index $1: the probe now prefixes git's own core.sshCommand arguments,
		## so -T is not necessarily first. A keyed probe answers as that key's owner, which is how
		## a check proves the configured key was the one used.
		mode=""; key=""
		while [[ $# -gt 0 ]]; do
			case "$1" in
				-G) mode=G ;;
				-T) mode=T ;;
				-i) key="$2"; shift ;;
			esac
			shift
		done
		[[ "${mode}" == "G" ]] && { printf 'user git\nhostname github.com\n'; exit 0; }
		if [[ "${mode}" == "T" ]]; then
			login="${FAKE_SSH_LOGIN:-${FAKE_GH_LOGIN:-ghuser}}"
			[[ -n "${key}" ]] && login="$(basename "${key}")"
			echo "Hi ${login}! You've successfully authenticated, but GitHub does not provide shell access."
			exit 1
		fi
		exit 0
	EOF
	local ghp="${gh}/bin:${PATH}"

	## create: repo doesn't exist yet -> gitsby inits + commits, the stub creates and pushes
	mkdir -p "${gh}/create"; echo c > "${gh}/create/c.txt"
	fAssert "[EkykHFV] repo create makes a missing repo"  bash -c "cd '${gh}/create' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/created.git' FAKE_GH_LOG='${gh}/create.log' '${gitsby}' -q repo create me/proj"
	fAssert "[EkykHFW] created repo got the commit"                bash -c "cd '${gh}/created.git' && git ls-tree --name-only main | grep -qx c.txt"
	fAssert "[EkykHFX] create defaulted to a private repo"         bash -c "grep -q -- '--private' '${gh}/create.log'"
	mkdir -p "${gh}/pub"; echo p > "${gh}/pub/p.txt"
	fAssert "[EkykHFY] repo create --public makes a public repo"  bash -c "cd '${gh}/pub' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/pub.git' FAKE_GH_LOG='${gh}/pub.log' '${gitsby}' -q --public repo create me/proj && grep -q -- '--public' '${gh}/pub.log'"

	## add: repo exists but is empty -> gitsby builds the URL from git_protocol and pushes to it
	git init --quiet --bare -b main "${gh}/backing-https.git"
	printf '[url "%s"]\n\tinsteadOf = https://github.com/me/proj.git\n' "${gh}/backing-https.git" > "${gh}/gc-https"
	mkdir -p "${gh}/add-https"; ( cd "${gh}/add-https" && git init --quiet -b main && echo h > h.txt && git add --all && git commit --quiet -m init )
	fAssert "[EkykHFZ] repo connect owner/name adds an https remote to an empty repo"  bash -c "cd '${gh}/add-https' && PATH='${ghp}' FAKE_GH_VIEW=empty FAKE_GH_PROTO=https GIT_CONFIG_GLOBAL='${gh}/gc-https' '${gitsby}' -q repo connect me/proj"
	fAssert "[EkykHFa] https url recorded as origin"  bash -c "cd '${gh}/add-https' && [[ \"\$(git remote get-url origin)\" == 'https://github.com/me/proj.git' ]]"
	fAssert "[EkykHFb] empty repo received the push"  bash -c "cd '${gh}/backing-https.git' && git ls-tree --name-only main | grep -qx h.txt"
	git init --quiet --bare -b main "${gh}/backing-ssh.git"
	printf '[url "%s"]\n\tinsteadOf = git@github.com:me/proj.git\n' "${gh}/backing-ssh.git" > "${gh}/gc-ssh"
	mkdir -p "${gh}/add-ssh"; ( cd "${gh}/add-ssh" && git init --quiet -b main && echo s > s.txt && git add --all && git commit --quiet -m init )
	fAssert "[EkykHFc] ssh protocol builds an scp-style origin url"  bash -c "cd '${gh}/add-ssh' && PATH='${ghp}' FAKE_GH_VIEW=empty FAKE_GH_PROTO=ssh GIT_CONFIG_GLOBAL='${gh}/gc-ssh' '${gitsby}' -q repo connect me/proj && [[ \"\$(git remote get-url origin)\" == 'git@github.com:me/proj.git' ]]"

	## reject: repo already has commits
	mkdir -p "${gh}/reject"; ( cd "${gh}/reject" && git init --quiet -b main && echo r > r.txt && git add --all && git commit --quiet -m init )
	fAssertFail "[EkykHFd] repo connect owner/name refuses a nonempty repo"  bash -c "cd '${gh}/reject' && PATH='${ghp}' FAKE_GH_VIEW=nonempty '${gitsby}' -q repo connect me/proj"
	fAssertFail "[El9QuEo] repo create refuses a nonempty repo"              bash -c "cd '${gh}/reject' && PATH='${ghp}' FAKE_GH_VIEW=nonempty '${gitsby}' -q repo create me/proj"

	## the division of labour: connect never creates, create never adopts something that already exists
	mkdir -p "${gh}/split"; ( cd "${gh}/split" && git init --quiet -b main && echo x > x.txt && git add --all && git commit --quiet -m init )
	fAssertFail "[El9QuEp] repo connect refuses a target that doesn't exist yet"  bash -c "cd '${gh}/split' && PATH='${ghp}' FAKE_GH_VIEW=notfound '${gitsby}' -q repo connect me/proj"
	fAssertOut  "[El9QuEq] and points at repo create"  'repo create me/proj'      bash -c "cd '${gh}/split' && PATH='${ghp}' FAKE_GH_VIEW=notfound '${gitsby}' -q repo connect me/proj 2>&1 || true"
	fAssertFail "[El9QuEr] repo create refuses an existing empty repo"            bash -c "cd '${gh}/split' && PATH='${ghp}' FAKE_GH_VIEW=empty '${gitsby}' -q repo create me/proj"
	fAssertOut  "[El9QuEs] and points at repo connect"  'repo connect me/proj'    bash -c "cd '${gh}/split' && PATH='${ghp}' FAKE_GH_VIEW=empty '${gitsby}' -q repo create me/proj 2>&1 || true"
	## gh exits nonzero for a name that resolves to nothing and for an API it can't reach alike.
	## Taking the second as the first sent you off to create a repo you already have - and these two
	## commands skip the pre-command fetch (no origin yet), so this is where offline surfaces.
	## Its own directory: a build that does NOT refuse here would create a remote and set an origin,
	## and every check after it would then be about a connected repo instead.
	mkdir -p "${gh}/offl"; echo x > "${gh}/offl/x.txt"
	fAssertFail "[EnPP5qC] repo create refuses when it can't reach GitHub"   bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo create me/proj"
	fAssertOut  "[EnPP5qD] and says that, not that the repo is missing"  'no telling whether it exists' \
		bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo create me/proj 2>&1"
	fAssertOut  "[EnPP5qE] and repeats what gh said"  'error connecting to api.github.com' \
		bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo create me/proj 2>&1"
	fAssertFail "[EnPP5qF] repo connect refuses when it can't reach GitHub"  bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo connect me/proj"
	fAssertNotOut "[EnPP5qG] and does not point at repo create"  'repo create me/proj' \
		bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo connect me/proj 2>&1"
	fAssertFail "[El9QuEt] repo create refuses a plain url"                       bash -c "cd '${gh}/split' && PATH='${ghp}' '${gitsby}' -q repo create '${gh}/backing-https.git'"
	## Keep the insteadOf rewrite: this dir's origin is a real github.com URL, and the
	## pre-command fetch runs before the refusal we're testing for.
	## The account is resolved from origin, and these two have none yet - but the repo they are
	## about to publish to is on the command line, and it is that owner's account that should do the
	## publishing. The late re-selection was a no-op behind the already-applied guard, so it went
	## out as gh's own account instead, silently.
	mkdir -p "${gh}/rc-acct"; echo x > "${gh}/rc-acct/x.txt"
	fAssert "[EnPP5qH] repo create publishes as the account that owns the target" \
		bash -c "cd '${gh}/rc-acct' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_PROTO=https FAKE_GH_LOGIN=other FAKE_GH_ACCOUNTS='other acme' FAKE_GH_LOG='${gh}/rc-acct.log' FAKE_GH_REMOTE='${gh}/rc-acct.git' '${gitsby}' -q repo create acme/proj && grep -q 'repo create.*GH_TOKEN=tok_acme' '${gh}/rc-acct.log'"
	git init --quiet --bare -b main "${gh}/backing-acme.git"
	printf '[url "%s"]\n\tinsteadOf = https://github.com/acme/proj.git\n' "${gh}/backing-acme.git" > "${gh}/gc-acme"
	mkdir -p "${gh}/rn-acct"; ( cd "${gh}/rn-acct" && git init --quiet -b main && echo x > x.txt && git add --all && git commit --quiet -m init )
	fAssert "[Er1LxRr] repo connect does the same" \
		bash -c "cd '${gh}/rn-acct' && PATH='${ghp}' FAKE_GH_VIEW=empty FAKE_GH_PROTO=https FAKE_GH_LOGIN=other FAKE_GH_ACCOUNTS='other acme' FAKE_GH_LOG='${gh}/rn-acct.log' GIT_CONFIG_GLOBAL='${gh}/gc-acme' '${gitsby}' -q repo connect acme/proj && grep -q 'repo view.*GH_TOKEN=tok_acme' '${gh}/rn-acct.log'"
	fAssertFail "[El9QuEu] repo create refuses when origin is already set"        bash -c "cd '${gh}/add-https' && PATH='${ghp}' GIT_CONFIG_GLOBAL='${gh}/gc-https' '${gitsby}' -q repo create me/proj"
	fAssertFail "[El9QuEv] repo create with no target rejected"                   bash -c "cd '${gh}/split' && PATH='${ghp}' '${gitsby}' -q repo create"

	## pr ok run from the PR's own branch: gh deletes the branch on the remote but leaves our
	## origin/* copy, so the upstream still looks alive and pulling it can only fail.
	mkdir -p "${gh}/prok"
	git init --quiet --bare -b main "${gh}/prok/origin.git"
	local prc="${gh}/prok/c"
	git clone --quiet "${gh}/prok/origin.git" "${prc}" 2>/dev/null
	(
		cd "${prc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b prfeat && echo work > work.txt && git add --all && git commit --quiet -m work
		git push --quiet -u origin prfeat
	)
	fAssertPlan "[El5iylv] pr ok plans the branch switch"  'git checkout dev'  bash -c "cd '${prc}' && PATH='${ghp}' FAKE_GH_BASE=dev '${gitsby}' -q pr ok 7"
	fAssert    "[El5iylw] pr ok landed on the merge target"  bash -c "cd '${prc}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert    "[El5iylx] pr ok pulled the merged work"      bash -c "cd '${prc}' && git ls-tree --name-only dev | grep -qx work.txt"
	fAssert    "[El5iyly] the merged branch is gone from origin"  bash -c "cd '${prc}' && ! git ls-remote --heads origin prfeat | grep -q prfeat"

	## 'pr ok <n>' from dev is the routine case, and gh deletes the PR's branch with 'branch -D'
	## either way - so unpushed commits on it have to be caught even when we aren't standing there.
	mkdir -p "${gh}/prx"
	git init --quiet --bare -b main "${gh}/prx/origin.git"
	local prx="${gh}/prx/c"
	git clone --quiet "${gh}/prx/origin.git" "${prx}" 2>/dev/null
	(
		cd "${prx}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b xfeat && echo work > work.txt && git add --all && git commit --quiet -m work
		git push --quiet -u origin xfeat
		echo more >> work.txt && git add --all && git commit --quiet -m "never pushed"
		git checkout --quiet dev
		## Local-only branch, no origin copy at all: the PR can hold none of it.
		git checkout --quiet -b xlocal && echo solo > solo.txt && git add --all && git commit --quiet -m solo
		git checkout --quiet dev
	)
	local prxEnv="PATH='${ghp}' FAKE_GH_BASE=dev FAKE_GH_HEAD=xfeat"
	fAssertFail "[ElHGWSG] pr ok refuses unpushed commits on the PR's branch"  bash -c "cd '${prx}' && ${prxEnv} '${gitsby}' -q pr ok 7"
	## Assert the reason: the plan prints the branch name either way, so matching 'xfeat' alone
	## would pass against a build with no guard at all.
	fAssertOut  "[ElHGWSH] and names that branch, not the current one"  "'xfeat' has commits that never reached origin"  bash -c "cd '${prx}' && ${prxEnv} '${gitsby}' -q pr ok 7 2>&1 || true"
	fAssert     "[ElHGWSI] and leaves the branch alone"  bash -c "cd '${prx}' && git show-ref --verify --quiet refs/heads/xfeat"
	fAssert     "[ElHGWSJ] and keeps the unpushed commit reachable"  bash -c "cd '${prx}' && git log -1 --pretty=%s xfeat | grep -qx 'never pushed'"
	fAssertFail "[ElHGWSK] pr ok refuses a branch origin has never seen"  bash -c "cd '${prx}' && PATH='${ghp}' FAKE_GH_BASE=dev FAKE_GH_HEAD=xlocal '${gitsby}' -q pr ok 8"
	## Same fixture, once the work is pushed: the guard must not stand in the way of the real thing.
	fAssert "[ElHGWSL] pr ok accepts a fully pushed branch from dev"  bash -c "cd '${prx}' && git push --quiet origin xfeat && ${prxEnv} '${gitsby}' -q pr ok 7"
	fAssert "[ElHGWSM] and merged what origin held"  bash -c "cd '${prx}' && git ls-tree --name-only dev | grep -qx work.txt"
	## A number gh can't resolve used to fall back to the current branch, so the plan was
	## confidently about the wrong thing and the run died after it had been confirmed - the exact
	## shape preflight exists to prevent.
	fAssertFail "[EnPP5qI] pr ok refuses a PR gh can't read"  bash -c "cd '${prx}' && PATH='${ghp}' FAKE_GH_PRVIEW=fail '${gitsby}' -q pr ok 99"
	fAssertOut  "[EnPP5qJ] and names the number rather than acting on the current branch"  "Can't read PR #99" \
		bash -c "cd '${prx}' && PATH='${ghp}' FAKE_GH_PRVIEW=fail '${gitsby}' -q pr ok 99 2>&1"
	fAssertFail "[EnPP5qK] pr ok refuses a PR that is no longer open"  bash -c "cd '${prx}' && ${prxEnv} FAKE_GH_STATE=MERGED '${gitsby}' -q pr ok 7"
	fAssertOut  "[EnPP5qL] and says which state it is in"  'is merged, not open' \
		bash -c "cd '${prx}' && ${prxEnv} FAKE_GH_STATE=MERGED '${gitsby}' -q pr ok 7 2>&1"
	fAssert     "[Er1LxRs] pr <n> shows the PR and then its diff" \
		bash -c "cd '${prx}' && ${prxEnv} FAKE_GH_LOG='${gh}/prview.log' '${gitsby}' -q -NoFetch pr 7 >/dev/null 2>&1 && awk '/^pr view 7 \[/ { v = NR } /^pr diff 7 \[/ { d = NR } END { exit !(v && d > v) }' '${gh}/prview.log'"

	## Standing on the PR's own branch, pushed once WITHOUT -u: '@{u}' answers nothing at all, so
	## the ahead check passed and gh's '--delete-branch' took the unpushed commits with it. That is
	## the one arrangement where the guard has to ask about origin's copy by name.
	mkdir -p "${gh}/prnou"
	git init --quiet --bare -b main "${gh}/prnou/origin.git"
	local pnu="${gh}/prnou/c"
	git clone --quiet "${gh}/prnou/origin.git" "${pnu}" 2>/dev/null
	(
		cd "${pnu}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b nofeat && echo work > work.txt && git add --all && git commit --quiet -m work
		git push --quiet origin nofeat   ## no -u: on origin, but nothing here tracks it
		echo more >> work.txt && git add --all && git commit --quiet -m "never pushed"
	)
	local pnuEnv="PATH='${ghp}' FAKE_GH_BASE=dev FAKE_GH_HEAD=nofeat"
	fAssert     "[EnPP5qM] the fixture branch really has no upstream"  bash -c "cd '${pnu}' && ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1"
	fAssertFail "[EnPP5qN] pr ok refuses unpushed commits with no upstream to notice them"  bash -c "cd '${pnu}' && ${pnuEnv} '${gitsby}' -q pr ok 7"
	fAssertOut  "[EnPP5qO] and names the branch"  "'nofeat' has commits that never reached origin" \
		bash -c "cd '${pnu}' && ${pnuEnv} '${gitsby}' -q pr ok 7 2>&1"
	fAssert     "[EnPP5qP] and the commit is still reachable"  bash -c "cd '${pnu}' && git log -1 --pretty=%s nofeat | grep -qx 'never pushed'"

	## pr create: parks the work, then opens the PR against the merge target. Same fake gh.
	mkdir -p "${gh}/prnew"
	git init --quiet --bare -b main "${gh}/prnew/origin.git"
	local pnc="${gh}/prnew/c"
	git clone --quiet "${gh}/prnew/origin.git" "${pnc}" 2>/dev/null
	(
		cd "${pnc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b pnfeat && echo work > work.txt && git add --all && git commit --quiet -m "Teach it to retry"
	)
	fAssertFail "[El9Ej23] pr create refuses from the merge target"  bash -c "cd '${pnc}' && git checkout --quiet dev && PATH='${ghp}' '${gitsby}' -q pr create 'nope'"
	fAssertFail "[El9Ej24] pr create refuses an already-open PR"     bash -c "cd '${pnc}' && git checkout --quiet pnfeat && PATH='${ghp}' FAKE_GH_EXISTING=99 '${gitsby}' -q pr create"
	fAssert     "[El9Ej25] pr create opens the PR"                   bash -c "cd '${pnc}' && PATH='${ghp}' FAKE_GH_LOG='${gh}/prnew.log' '${gitsby}' -q pr create"
	fAssert     "[El9Ej26] pr create pushed the branch first"        bash -c "cd '${pnc}' && git ls-remote --heads origin pnfeat | grep -q pnfeat"
	fAssert     "[El9Ej27] pr create based the PR on the merge target"  bash -c "grep -q -- '--base dev' '${gh}/prnew.log'"
	fAssert     "[El9Ej28] pr create titled it from the last commit" bash -c "grep -q -- '--title Teach it to retry' '${gh}/prnew.log'"
	## An explicit title wins over the commit subject.
	(
		cd "${pnc}" || exit 1
		git checkout --quiet -b pnfeat2 && echo more > more.txt && git add --all && git commit --quiet -m "Commit subject"
	)
	fAssert "[El9Ej29] pr create takes an explicit title"  bash -c "cd '${pnc}' && PATH='${ghp}' FAKE_GH_LOG='${gh}/prnew2.log' '${gitsby}' -q pr create 'Explicit title' && grep -q -- '--title Explicit title' '${gh}/prnew2.log'"
	## A hotfix lands on the default branch, so its PR is based there, not on dev.
	( cd "${pnc}" && git checkout --quiet -b hotfix/prfix main && echo fix > fix.txt && git add --all && git commit --quiet -m "Fix it" )
	fAssert "[Er1LxRt] pr create from a hotfix bases the PR on the default branch" \
		bash -c "cd '${pnc}' && PATH='${ghp}' FAKE_GH_LOG='${gh}/prhf.log' '${gitsby}' -q pr create && grep -q -- '--base main ' '${gh}/prhf.log'"

	## A branch whose name starts with a dash can't be typed here - the parser reads a leading dash
	## as an option of ours - but a clone brings whatever the remote has, and then git reads it as
	## options too: 'git checkout -evil' answers "unknown switch". There is no separator that
	## rescues it in that position, so it is refused once, up front.
	local dsh="${work}/$1-dash"
	mkdir -p "${dsh}"
	git init --quiet --bare -b main "${dsh}/origin.git"
	git init --quiet -b main "${dsh}/seed"
	(
		cd "${dsh}/seed" || exit 1
		echo d > d.txt && git add --all && git commit --quiet -m init
		git push --quiet "${dsh}/origin.git" 'HEAD:refs/heads/-evil'
	)
	( cd "${dsh}/origin.git" && git symbolic-ref HEAD refs/heads/-evil )
	git clone --quiet "${dsh}/origin.git" "${dsh}/c" 2>/dev/null
	fAssert     "[EnPP5qQ] the fixture really checked out a dash-led branch"  bash -c "[[ \"\$(git -C '${dsh}/c' branch --show-current)\" == -evil ]]"
	fAssertFail "[EnPP5qR] a dash-led branch name is refused before it reaches git"  bash -c "cd '${dsh}/c' && '${gitsby}' -q pullcom 'x'"
	fAssertOut  "[EnPP5qS] and says why"  'reads it as an option'  bash -c "cd '${dsh}/c' && '${gitsby}' -q pullcom 'x' 2>&1"
	fAssert     "[EnPP5qT] but status still reports the repo it is wrong about"  bash -c "cd '${dsh}/c' && '${gitsby}' -q status >/dev/null"

	## Identity: which account a remote-touching command acts as. gh keeps one active account for the
	## whole host, so against a remote owned by somebody else it acts as the wrong one.
	## The origin really is a github.com url here, because the owner is parsed from what
	## 'git remote get-url' returns and that applies url.*.insteadOf - pointing it at a local bare to
	## stay offline would hand gitsby a local path and test nothing. --no-fetch keeps it off the
	## network instead: gh is stubbed, and a read never probes ssh, so nothing reaches github.com.
	local idn="${gh}/ident"
	mkdir -p "${idn}"
	git init --quiet --bare -b main "${idn}/backing.git"
	git clone --quiet "${idn}/backing.git" "${idn}/c" 2>/dev/null
	(
		cd "${idn}/c" || exit 1
		echo i > i.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git remote set-url origin git@github.com:acme/proj.git
	)
	local idEnv="PATH='${ghp}' FAKE_GH_LOGIN=someoneelse"
	fAssert "[EmCkMZU] gh acts as the remote's owner when it holds that account" \
		bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/held.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=tok_acme' '${idn}/held.log'"
	## A fork or an org we have no account for is ordinary - it must not be touched, and must not refuse.
	fAssert "[EmCkMZV] gh is left alone when it has no account for the owner" \
		bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/unheld.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/unheld.log'"
	## -NoFetch is spelled the same to both ports (bash normalizes it), so these need no branch.
	fAssert "[EmCkMZW] --any-identity leaves gh's active account alone" \
		bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/any.log' '${gitsby}' -q -NoFetch --any-identity pr && grep -q 'GH_TOKEN=\]' '${idn}/any.log'"
	## An account configured for the path wins over the remote's owner, and is the only one of the
	## two that can answer before a remote exists. Set locally here; in practice an includeIf on the
	## repo path supplies it, the same way the ssh key and commit identity already arrive.
	git clone --quiet "${idn}/backing.git" "${idn}/cfg" 2>/dev/null
	(
		cd "${idn}/cfg" || exit 1
		git remote set-url origin git@github.com:acme/proj.git
		git config gitsby.ghAccount configured
	)
	fAssert "[EmHg7uK] a configured account wins over the remote's owner" \
		bash -c "cd '${idn}/cfg' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme configured' FAKE_GH_LOG='${idn}/cfg.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=tok_configured' '${idn}/cfg.log'"
	## No origin at all: nothing to parse an owner from, so only the configured account can answer.
	## Asked through 'raw gh' rather than 'pr': a repo with no remote has nowhere to propose a pull
	## request to, and pr now says so before it selects anything. Which is the right answer, and
	## makes it the wrong vehicle for a question about account selection. 'identity' is no good
	## either - its gh probe deliberately runs BEFORE the token lands, so the log never sees one.
	## 'raw gh' is the documented scripted surface and runs as whatever was selected.
	mkdir -p "${idn}/noremote"
	(
		cd "${idn}/noremote" || exit 1
		git init --quiet -b main . && git commit --quiet --allow-empty -m init
		git config gitsby.ghAccount configured
	)
	fAssert "[EmHg7uL] a configured account applies with no remote at all" \
		bash -c "cd '${idn}/noremote' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse configured' FAKE_GH_LOG='${idn}/nore.log' '${gitsby}' -q -NoFetch raw gh api user && grep -q 'GH_TOKEN=tok_configured' '${idn}/nore.log'"
	## And the refusal itself, which is what makes the line above the right shape.
	fAssertOut "[EnS8ftA] pr refuses outright with no remote to propose to"  'No .origin. remote' \
		bash -c "cd '${idn}/noremote' && ${idEnv} '${gitsby}' -q -NoFetch pr 2>&1"
	## The token file covers a box where that account was never logged in to gh. Absent, unreadable
	## and empty must all fall back to gh's own account rather than fail - a checkout that was never
	## set up this way still has to work.
	## Written into the GLOBAL config, which is where 'account apply' puts it and the only scope
	## gitsby reads it from: the value names any readable file, and its contents go into GH_TOKEN
	## for every child - so a repo you cloned from a stranger does not get to choose it.
	local idnGlobal="${idn}/gcfg"; : > "${idnGlobal}"
	local idTok="GIT_CONFIG_GLOBAL='${idnGlobal}'"
	printf 'tok_fromfile\n' > "${idn}/token.txt"
	fAssert "[EmHg7uM] the token file is used when gh has no such account" \
		bash -c "cd '${idn}/cfg' && ${idTok} git config --global gitsby.ghTokenFile '${idn}/token.txt' && ${idTok} ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/file.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=tok_fromfile' '${idn}/file.log'"
	## The same key set by the repo itself is ignored: it is the one config value that turns into a
	## file read plus an environment variable handed to gh and git.
	fAssert "[EnPP5qU] a repo-local token file is not honored" \
		bash -c "cd '${idn}/cfg' && git config gitsby.ghTokenFile '${idn}/token.txt' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/localtok.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/localtok.log'"
	fAssert "[EmHg7uN] a missing token file falls back instead of failing" \
		bash -c "cd '${idn}/cfg' && ${idTok} git config --global gitsby.ghTokenFile '${idn}/absent.txt' && ${idTok} ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/miss.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/miss.log'"
	: > "${idn}/blank.txt"
	fAssert "[EmHg7uO] an empty token file falls back instead of failing" \
		bash -c "cd '${idn}/cfg' && ${idTok} git config --global gitsby.ghTokenFile '${idn}/blank.txt' && ${idTok} ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/blank.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/blank.log'"
	## gh's own store outranks the file, so a rotated login is not shadowed by a stale token on disk.
	fAssert "[EmHg7uP] gh's own account outranks the token file" \
		bash -c "cd '${idn}/cfg' && ${idTok} git config --global gitsby.ghTokenFile '${idn}/token.txt' && ${idTok} ${idEnv} FAKE_GH_ACCOUNTS='someoneelse configured' FAKE_GH_LOG='${idn}/pref.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=tok_configured' '${idn}/pref.log'"
	( cd "${idn}/cfg" && git config --unset gitsby.ghTokenFile )
	## Naming the account this run replaced has to be asked BEFORE the token lands, or the probe
	## answers as the token just exported and the line can only ever say what it already knows.
	fAssertOut "[EnPP5qV] the identity block names the account gh was on before the switch"  "gh's active account is 'someoneelse'" \
		bash -c "cd '${idn}/cfg' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse configured' '${gitsby}' -q -NoFetch identity 2>&1"

	## The remote's owner is the step that needs no configuration at all, and it is the one step a
	## clone cannot use. The repo being cloned is as likely a stranger's as ours, and the repo we are
	## standing in is not the one being cloned - so asked either way it names an account that has
	## nothing to do with the clone, and quietly authenticates as it.
	: > "${idn}/clone.log"
	fAssert "[EnPebrM] a clone asks for no token on the strength of the surrounding repo's owner" \
		bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/clone.log' '${gitsby}' -q repo clone '${idn}/backing.git' '${idn}/cloned' >/dev/null && ! grep -q -- '--user acme' '${idn}/clone.log'"

	## A remote we can't name an owner for gets no opinion at all.
	git clone --quiet "${idn}/backing.git" "${idn}/local" 2>/dev/null
	fAssert "[EmCkMZX] a non-GitHub remote picks no account" \
		bash -c "cd '${idn}/local' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/plain.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/plain.log'"
	## The probe must ask as the key git would push with, not as ssh's default: a per-repo
	## core.sshCommand is exactly how two accounts are kept apart on one machine, and a probe that
	## ignores it reports the wrong account confidently. The fake ssh answers as the key's basename.
	git clone --quiet "${idn}/backing.git" "${idn}/keyed" 2>/dev/null
	(
		cd "${idn}/keyed" || exit 1
		git remote set-url origin git@github.com:acme/proj.git
		git config core.sshCommand 'ssh -i /keys/keyowner -o IdentitiesOnly=yes'
	)
	fAssertOut "[EmCkMZY] the ssh probe asks as the key git pushes with" 'SSH \.+: keyowner' \
		bash -c "cd '${idn}/keyed' && ${idEnv} '${gitsby}' -NoFetch status"
	fAssertOut "[EmCkMZZ] and the key it names is that one, not ssh's default" 'key /keys/keyowner' \
		bash -c "cd '${idn}/keyed' && ${idEnv} '${gitsby}' -NoFetch status"

	## Hotfix branches target the default branch instead of dev, because they correct what is
	## already published. Landing one must also carry it back to dev, or the next release undoes it.
	local hf="${work}/$1-hotfix"
	git init --quiet --bare -b main "${hf}/origin.git"
	git clone --quiet "${hf}/origin.git" "${hf}/c" 2>/dev/null
	local hfc="${hf}/c"
	(
		cd "${hfc}" || exit 1
		echo "readme v1" > README.md && mkdir -p src-go && echo shipped > src-go/main.go
		git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git tag -a v1.0.0 -m v1.0.0 && git push --quiet origin v1.0.0
		git checkout --quiet -b dev && git push --quiet -u origin dev
	)
	fAssert    "[ElCp8pk] br hotfix creates the branch"  bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix wording"
	fAssert    "[ElCp8pl] and prefixes it"               bash -c "cd '${hfc}' && [[ \"\$(git branch --show-current)\" == 'hotfix/wording' ]]"
	fAssert    "[ElCp8pm] off the default branch, not dev"  bash -c "cd '${hfc}' && git merge-base --is-ancestor origin/main HEAD"
	## -q still prints the plan, it only skips the prompt - so one run proves both.
	## (Non-quiet can't be used here: with no tty gitsby fails closed before printing anything.)
	fAssertPlan "[ElCp8pn] br land plans and lands it on the default branch"  'git checkout main' \
		bash -c "cd '${hfc}' && echo 'readme v2' > README.md && '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; '${gitsby}' -q -NoFetch br land 'Reword' 2>&1"
	fAssert    "[ElCp8po] it reached the default branch" bash -c "cd '${hfc}' && [[ \"\$(git show origin/main:README.md)\" == 'readme v2' ]]"
	fAssert    "[ElCp8pp] and was carried back to dev"   bash -c "cd '${hfc}' && [[ \"\$(git show origin/dev:README.md)\" == 'readme v2' ]]"
	fAssert    "[ElCp8pq] the branch is gone both sides" bash -c "cd '${hfc}' && [[ -z \"\$(git branch --list 'hotfix/*')\" ]] && [[ -z \"\$(git ls-remote --heads origin 'hotfix/*')\" ]]"
	## The back-merge takes origin's copy of the default branch by name, and a tag spelled the
	## same, on an older commit, is what git merge would read first.
	local hft="${work}/$1-hotfix-tag"
	git init --quiet --bare -b main "${hft}/origin.git"
	git clone --quiet "${hft}/origin.git" "${hft}/c" 2>/dev/null
	(
		cd "${hft}/c" || exit 1
		echo "readme v1" > README.md && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git tag origin/main
		git checkout --quiet -b dev && git push --quiet -u origin dev
	)
	fAssert    "[Er1LxRu] the back-merge carries the hotfix, not a tag named like origin's branch" \
		bash -c "cd '${hft}/c' && '${gitsby}' -q -NoFetch br hotfix tagged >/dev/null 2>&1 && echo 'readme v2' > README.md && '${gitsby}' -q -NoFetch br land 'Tagged' >/dev/null 2>&1; [[ \"\$(git -C '${hft}/origin.git' show refs/heads/main:README.md)\" == 'readme v2' ]] && git -C '${hft}/origin.git' merge-base --is-ancestor refs/heads/main refs/heads/dev"
	## A hotfix that changes shipped code leaves main ahead of every tag - say so.
	fAssertOut "[ElCp8pr] a hotfix touching the shipped source warns about the release"  'changes more than documentation' \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix code >/dev/null 2>&1; echo v2 > '${hfc}/src-go/main.go'; '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; '${gitsby}' -q -NoFetch br land 'Fix' 2>&1"
	## The warning reads the branch tip, and 'br land' is what commits the working tree - so an
	## uncommitted edit to it (the ordinary way of making one) has to be checked for after that.
	fAssertOut "[ElCzjRQ] a hotfix warns about shipped code even when the edit is uncommitted"  'changes more than documentation' \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix uncommitted >/dev/null 2>&1; echo v3 > '${hfc}/src-go/main.go'; '${gitsby}' -q -NoFetch br land 'Fix uncommitted' 2>&1"
	## Every other check here runs from the top of the tree. A pathspec is read relative to the
	## current directory, so from anywhere else it matched nothing, git exited 0 with no output,
	## and the warning went missing on exactly the commands you run from wherever you are working.
	mkdir -p "${hfc}/docs"
	fAssertOut "[EnR2Eue] the shipped-code warning survives being run from a subdirectory"  'changes more than documentation' \
		bash -c "cd '${hfc}/docs' && '${gitsby}' -q -NoFetch br hotfix subdir >/dev/null 2>&1; echo v4 > '${hfc}/src-go/main.go'; '${gitsby}' -q -NoFetch br land 'Fix from below' 2>&1"
	fAssert    "[ElCp8ps] a docs-only hotfix says nothing about releases"  \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix docs >/dev/null 2>&1; echo 'readme v3' > README.md; '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; out=\"\$('${gitsby}' -q -NoFetch br land 'Docs' 2>&1)\"; ! grep -q 'changes more than documentation' <<< \"\${out}\""
	## It watched this project's own src-go/, so in any other repo a code hotfix said nothing.
	fAssertOut "[EpyNqT2] a hotfix to code in any other folder warns too"  'changes more than documentation' \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix lib >/dev/null 2>&1; mkdir -p lib && echo x > lib/tool.py; '${gitsby}' -q -NoFetch br land 'Fix lib' 2>&1"
	## A repo that never tagged a release has none to fall out of step with.
	local hn="${work}/$1-hotfix-notag"
	git init --quiet --bare -b main "${hn}/origin.git"
	git clone --quiet "${hn}/origin.git" "${hn}/c" 2>/dev/null
	(
		cd "${hn}/c" || exit 1
		echo a > a.txt && mkdir -p src-go && echo code > src-go/main.go
		git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
	)
	fAssertNotOut "[EpyNqT3] a code hotfix in a repo with no release tags says nothing"  'NOTE: this hotfix' \
		bash -c "cd '${hn}/c' && '${gitsby}' -q -NoFetch br hotfix code >/dev/null 2>&1; echo v2 > src-go/main.go; '${gitsby}' -q -NoFetch br land 'Fix' 2>&1"
	## An empty answer read as nothing changed, when the comparison couldn't run at all.
	( cd "${hn}/c" || exit 1; git checkout --quiet main && git tag -a v1.0.0 -m v1.0.0 && git checkout --quiet --orphan hotfix/stray && git rm -rfq . && echo x > stray.go && git add stray.go && git commit --quiet -m stray )
	fAssertOut "[EpyNqT4] a hotfix that can't be compared says so"  "couldn't tell whether this hotfix" \
		bash -c "cd '${hn}/c' && '${gitsby}' -q -NoFetch br land 'Stray' 2>&1"
	## A back-merge conflict must leave dev untouched and the tree clean, not half-merged.
	fAssert    "[ElCp8pt] a conflicting back-merge leaves dev alone"  \
		bash -c "cd '${hfc}' && git checkout --quiet dev && echo devtext > README.md && git commit --quiet -am devtext && git push --quiet && '${gitsby}' -q -NoFetch br hotfix clash >/dev/null 2>&1 && echo hftext > README.md && '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1 && '${gitsby}' -q -NoFetch br land Clash >/dev/null 2>&1; [[ \"\$(git show origin/main:README.md)\" == hftext && \"\$(git show origin/dev:README.md)\" == devtext ]]"
	fAssert    "[ElCp8pu] and the tree is not left mid-merge"  bash -c "cd '${hfc}' && [[ ! -e .git/MERGE_HEAD ]] && [[ -z \"\$(git status --porcelain)\" ]]"
	## The abort's own result was never read, so a failed one left the tree mid-merge while the run
	## said it had backed out. A git that refuses only the abort stands in for whatever stops it.
	local abortShim="${work}/$1-abortshim"
	mkdir -p "${abortShim}"
	fStub "${abortShim}/git" <<-EOF
		#!/usr/bin/env bash
		if [[ "\${1:-} \${2:-}" == "merge --abort" ]]; then echo "fatal: abort refused for this check" >&2; exit 128; fi
		exec '$(command -v git)' "\$@"
	EOF
	fAssertOut "[ErfwTrE] a back-merge whose abort fails says dev is still mid-merge"  "^  Why:  'git merge --abort' failed, so 'dev' is still mid-merge\.$" \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix clash2 >/dev/null 2>&1 && echo hf2text > README.md && '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1 && env PATH='${abortShim}':\"\${PATH}\" '${gitsby}' -q -NoFetch br land Clash2 > '${abortShim}/back.out' 2>&1; echo \"rc=\$?\" >> '${abortShim}/back.out'; cat '${abortShim}/back.out'"
	fAssertOut "[ErfwTrT] and fails rather than ending in Done"  '^rc=1$'  cat "${abortShim}/back.out"
	( cd "${hfc}" || exit 1; git merge --abort 2>/dev/null || true )
	## The forward merge left the tree in conflict and the merge open, on a bare step failure.
	local fm="${work}/$1-mergeclash"
	git init --quiet --bare -b main "${fm}/origin.git"
	git clone --quiet "${fm}/origin.git" "${fm}/c" 2>/dev/null
	(
		cd "${fm}/c" || exit 1
		echo base > f.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b clash && echo mine > f.txt && git commit --quiet -am mine && git push --quiet -u origin clash
		git checkout --quiet dev && echo theirs > f.txt && git commit --quiet -am theirs && git push --quiet
		git checkout --quiet clash
	)
	fAssertFail "[EpyIe9D] a conflicting br merge refuses"  bash -c "cd '${fm}/c' && '${gitsby}' -q -NoFetch br merge Clash"
	fAssert     "[EpyIe9E] and backs the merge out"         bash -c "cd '${fm}/c' && [[ ! -e .git/MERGE_HEAD ]] && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert     "[EpyIe9F] and leaves dev as it was"        bash -c "cd '${fm}/c' && [[ \"\$(git show dev:f.txt)\" == theirs && \"\$(git show origin/dev:f.txt)\" == theirs ]]"
	fAssert     "[EpyIe9G] and goes back to the branch"     bash -c "cd '${fm}/c' && [[ \"\$(git branch --show-current)\" == clash ]]"
	fAssertOut  "[EpyIe9H] and names the commands to settle it"  "git merge dev, then '.*br merge'"  bash -c "cd '${fm}/c' && '${gitsby}' -q -NoFetch br merge Clash 2>&1"
	fAssertOut    "[ErfwTrh] a br merge whose abort fails says dev is still mid-merge"  "^  Why:  'git merge --abort' failed, so 'dev' is still mid-merge\.$" \
		bash -c "cd '${fm}/c' && env PATH='${abortShim}':\"\${PATH}\" '${gitsby}' -q -NoFetch br merge Clash > '${abortShim}/merge.out' 2>&1; cat '${abortShim}/merge.out'"
	fAssertNotOut "[ErfwTrv] and never says dev is as it was"  'as it was'  cat "${abortShim}/merge.out"
	fAssertOut    "[ErfwTs8] and names the commands to drop it and go back"  "^          git merge --abort\$"  cat "${abortShim}/merge.out"
	fAssertOut    "[ErfwTsM] including the way back to the branch"  "^          git checkout clash\$"  cat "${abortShim}/merge.out"
	## release merges dev into main the same way.
	( cd "${fm}/c" || exit 1; git merge --abort 2>/dev/null || true; git checkout --quiet main && echo mainside > f.txt && git commit --quiet -am mainside && git push --quiet && git checkout --quiet clash )
	fAssertFail "[EpyIe9I] a release whose dev won't merge into main refuses"  bash -c "cd '${fm}/c' && '${gitsby}' -q -NoFetch release v1.0.0"
	fAssert     "[EpyIe9J] and backs it out, cuts no tag, and goes back"  bash -c "cd '${fm}/c' && [[ ! -e .git/MERGE_HEAD ]] && ! git rev-parse -q --verify refs/tags/v1.0.0 >/dev/null && [[ \"\$(git branch --show-current)\" == clash ]]"
	## Feature branches must be untouched by all of this.
	fAssert    "[ElCp8pv] br create still branches off dev"  \
		bash -c "cd '${hfc}' && git checkout --quiet dev && git checkout --quiet -- . 2>/dev/null; '${gitsby}' -q -NoFetch br create feat1 && git merge-base --is-ancestor origin/dev HEAD"
	fAssertOut "[ElCp8pw] and br land still targets dev for them"  'git checkout dev' \
		bash -c "cd '${hfc}' && echo feat > feat.txt && '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; '${gitsby}' -q -NoFetch br land 'Feat' 2>&1"
	fAssertFail "[ElCp8px] br hotfix with no name rejected"  bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix"
	fAssertFail "[ElCp8py] the internal token stays untypeable"  bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br-hotfix x"
	fAssert    "[Er1LxRv] a name typed with the prefix doesn't get it twice" \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix hotfix/typed && [[ \"\$(git branch --show-current)\" == hotfix/typed ]]"

	## The current-branch line says where you ARE, and nothing used to connect that to where the new
	## branch comes off: it read 'dev' while the plan below it checked out main.
	## -q still prints the whole block; it only skips the prompt.
	fAssertOut "[ElcGLVw] br hotfix names the branch it will make, and its base"  '^New branch \.+: main :: hotfix/base1$' \
		bash -c "cd '${hfc}' && git checkout --quiet dev && '${gitsby}' -q -NoFetch br hotfix base1 2>&1"
	fAssertOut "[ElcGLVx] and still reports the branch you're standing on"  '^Current branch: dev' \
		bash -c "cd '${hfc}' && git checkout --quiet dev && '${gitsby}' -q -NoFetch br hotfix base2 2>&1"
	fAssertOut "[ElcGLVy] br create names dev as the base"  '^New branch \.+: dev :: base3$' \
		bash -c "cd '${hfc}' && git checkout --quiet dev && '${gitsby}' -q -NoFetch br create base3 2>&1"
	## Said once, in the pre-flight. The after-shot would be claiming a branch that already exists.
	fAssert "[ElcGLVz] and says it once, not again after the run"  \
		bash -c "cd '${hfc}' && git checkout --quiet dev && [[ \"\$('${gitsby}' -q -NoFetch br create base4 2>&1 | grep -c 'New branch')\" == 1 ]]"
	fAssertNotOut "[ElcGLW0] status claims no new branch at all"  'New branch' \
		bash -c "cd '${hfc}' && '${gitsby}' -q status 2>&1"

	## A work branch is shown against what it lands on; main/master/dev are off nothing, so they
	## stay bare - "dev :: dev" would be noise, and "main :: dev" is only true at release time.
	fAssertOut "[ElcGLW1] a feature branch shows the base it lands on"  '^Current branch: dev :: base3' \
		bash -c "cd '${hfc}' && git checkout --quiet base3 && '${gitsby}' -q status 2>&1"
	fAssertOut "[ElcGLW2] a hotfix branch shows the default branch instead"  '^Current branch: main :: hotfix/base1' \
		bash -c "cd '${hfc}' && git checkout --quiet hotfix/base1 && '${gitsby}' -q status 2>&1"
	fAssertNotOut "[ElcGLW3] dev is shown bare"  '^Current branch: [^ ]+ :: dev' \
		bash -c "cd '${hfc}' && git checkout --quiet dev && '${gitsby}' -q status 2>&1"

	## The default branch is its own line now, not a parenthetical tacked onto the branch line.
	fAssertOut "[ElcGLW4] the default branch gets its own line"  '^Default branch: main$' \
		bash -c "cd '${hfc}' && '${gitsby}' -q status 2>&1"
	fAssertNotOut "[ElcGLW5] and is no longer tacked onto the branch line"  'repo default:' \
		bash -c "cd '${hfc}' && '${gitsby}' -q status 2>&1"
	## br list never said what the default was, which is half of what a listing is for.
	fAssertOut "[ElcGLW6] br list says what the default branch is"  '^Default branch: main$' \
		bash -c "cd '${hfc}' && '${gitsby}' -q br list 2>&1"
	## No origin and no conventional name: a lone branch is the default, and so is the branch
	## an empty repo will be born on.
	local lone="${work}/$1-lonebranch"
	git init --quiet -b mainline "${lone}/one"
	( cd "${lone}/one" && echo l > l.txt && git add --all && git commit --quiet -m init )
	git init --quiet -b trunkish "${lone}/unborn"
	fAssertOut "[Er1LxRw] a lone local branch is the default branch"  '^Default branch: mainline$'  bash -c "cd '${lone}/one' && '${gitsby}' -q status 2>&1"
	fAssert    "[Er1LxRx] and br create works off it"  bash -c "cd '${lone}/one' && '${gitsby}' -q br create lonefeat && [[ \"\$(git branch --show-current)\" == lonefeat ]]"
	fAssertOut "[Er1LxRy] an unborn branch is the default branch"  '^Default branch: trunkish$'  bash -c "cd '${lone}/unborn' && '${gitsby}' -q status 2>&1"

	## gh writes act as gh's own account, not the ssh key git pushes with. A difference BOTH sides
	## know about is refused unattended; unknown (no agent, https remote, deploy key) never blocks,
	## or every CI runner breaks. A fake ssh answers the greeting GitHub really sends.
	local id="${work}/$1-ident"
	mkdir -p "${id}/bin"
	cp "${gh}/bin/gh" "${id}/bin/gh"; fStubShim "${id}/bin/gh"
	## insteadOf is no good here: 'git remote get-url' returns the REWRITTEN url, so there would be
	## no ssh url left to probe. Instead the stub doubles as the transport, so origin stays an
	## scp-style url while every push and fetch lands in a local bare.
	fStub "${id}/bin/ssh" <<-'EOF'
		#!/usr/bin/env bash
		[[ "$1" == "-G" ]] && { printf 'user git\nhostname github.com\n'; exit 0; }
		if [[ "$1" == "-T" ]]; then
			## No FAKE_SSH_LOGIN = no usable key, which is the 'unknown' case.
			[[ -n "${FAKE_SSH_LOGIN:-}" ]] || { echo "git@github.com: Permission denied (publickey)." >&2; exit 255; }
			## Real ssh often writes a line or two of its own before the greeting; we capture stderr too.
			[[ -n "${FAKE_SSH_NOISE:-}" ]] && echo "Warning: Permanently added 'github.com' (ED25519) to the list of known hosts." >&2
			echo "Hi ${FAKE_SSH_LOGIN}! You've successfully authenticated, but GitHub does not provide shell access."
			exit 1   ## GitHub always exits 1 here; the greeting is the answer, not the status
		fi
		## Otherwise git is driving us as its transport: point the pack program at the local bare.
		for arg in "$@"; do
			case "${arg}" in
				git-upload-pack*|git-receive-pack*|git-upload-archive*)
					exec "${arg%% *}" "${FAKE_SSH_REPO}" ;;
			esac
		done
		exit 0
	EOF
	local -r idp="${id}/bin:${PATH}"
	git init --quiet --bare -b main "${id}/origin.git"
	local idc="${id}/c"
	git clone --quiet "${id}/origin.git" "${idc}" 2>/dev/null
	(
		cd "${idc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b idfeat && echo w > w.txt && git add --all && git commit --quiet -m "Work"
		git remote set-url origin git@github_test:x/y.git
	)
	local idEnv="PATH='${idp}' FAKE_SSH_REPO='${id}/origin.git'"
	fAssertFail "[ElAloC0] gh/ssh identity mismatch refused unattended" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "[ElAloC1] and the refusal names both accounts"  "acts as 'alice'.*authenticates as 'bob'" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T' 2>&1 || true"
	fAssertFail "[ElAloC2] the mismatch refusal happens before anything runs" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T'; git -C '${idc}' ls-remote --heads origin idfeat | grep -q idfeat"
	fAssert     "[ElAloC3] unknown ssh identity does not block"  \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "[ElAloC4] and says there was nothing to compare"  'no ssh identity to compare' \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice '${gitsby}' -q -NoFetch pr create 'T' 2>&1"
	fAssert     "[ElAloC5] matching identities proceed"  \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=same FAKE_SSH_LOGIN=same '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "[ElAloC6] the identity block names the gh account"  'GitHub \(gh\) [.]*: same' \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=same FAKE_SSH_LOGIN=same '${gitsby}' -q -NoFetch pr create 'T' 2>&1"
	local anyIdFlag="--any-identity"
	fAssert     "[ElAloC7] the override flag proceeds through a mismatch"  \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch ${anyIdFlag} pr create 'T'"
	fAssertOut  "[ElAloC8] and the mismatch is still on the identity line"  "NOT the ssh key's account" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch ${anyIdFlag} pr create 'T' 2>&1"
	## Read-only pr never pays for the ssh probe, so a mismatch can't block looking.
	fAssert     "[ElAloC9] a mismatch does not block read-only pr"  \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr"
	## ssh writes host-key and missing-identity warnings ahead of the greeting, and we read both
	## streams - so the greeting is not reliably the first line. Anchoring to the whole output
	## answered 'unknown' for exactly the multi-key setups this check exists for.
	fAssertFail "[ElCzjRR] a warning line before the greeting still resolves the ssh identity" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_SSH_NOISE=1 FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "[ElCzjRS] and it still names both accounts"  "acts as 'alice'.*authenticates as 'bob'" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_SSH_NOISE=1 FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T' 2>&1 || true"

	## repo create has no origin yet, but the one gh is about to set IS knowable - gh never uses a
	## host alias, so it is 'git@github.com:owner/name.git'. Check it before creating anything.
	## Note this runs from a plain directory, where the preceding repo probe fails: the gh login
	## must not be read from a stale exit status (the PowerShell port got this wrong once).
	## ssh protocol, or gh would hand git an https url and there would be no ssh identity at all.
	local rcEnv="PATH='${idp}' FAKE_GH_VIEW=notfound FAKE_GH_PROTO=ssh"
	mkdir -p "${id}/rc-bad"; echo x > "${id}/rc-bad/x.txt"
	fAssertFail "[ElBHoqO] repo create refuses a mismatched identity before creating anything" \
		bash -c "cd '${id}/rc-bad' && ${rcEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob FAKE_GH_REMOTE='${id}/rc-bad.git' '${gitsby}' -q repo create me/proj"
	fAssert     "[ElBHoqP] and it neither created the remote nor inited the directory" \
		bash -c "[[ ! -e '${id}/rc-bad.git' && ! -e '${id}/rc-bad/.git' ]]"
	mkdir -p "${id}/rc-ok"; echo x > "${id}/rc-ok/x.txt"
	fAssertOut  "[ElBHoqQ] repo create resolves gh's account from a plain directory"  'GitHub \(gh\) [.]*: same' \
		bash -c "cd '${id}/rc-ok' && ${rcEnv} FAKE_GH_LOGIN=same FAKE_SSH_LOGIN=same FAKE_GH_REMOTE='${id}/rc-ok.git' '${gitsby}' -q repo create me/proj 2>&1"
	mkdir -p "${id}/rc-https"; echo x > "${id}/rc-https/x.txt"
	fAssert     "[ElBHoqR] an https protocol leaves nothing to compare, so it proceeds" \
		bash -c "cd '${id}/rc-https' && ${rcEnv} FAKE_GH_PROTO=https FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob FAKE_GH_REMOTE='${id}/rc-https.git' '${gitsby}' -q repo create me/proj"
	## connect sets the same kind of origin, onto a repo that already exists.
	mkdir -p "${id}/rn-bad"; ( cd "${id}/rn-bad" && git init --quiet -b main && echo x > x.txt && git add --all && git commit --quiet -m init )
	local rnEnv="PATH='${idp}' FAKE_GH_VIEW=empty FAKE_GH_PROTO=ssh FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob"
	fAssertOut  "[Er1LxRz] repo connect owner/name refuses a mismatched identity"  "acts as 'alice'.*authenticates as 'bob'" \
		bash -c "cd '${id}/rn-bad' && ${rnEnv} '${gitsby}' -q repo connect me/proj 2>&1"
	fAssert     "[Er1LxS0] and adds no origin" \
		bash -c "! git -C '${id}/rn-bad' remote get-url origin >/dev/null 2>&1"

	## 'sync' pushes with git rather than writing through gh, so the comparison above never covered
	## it: the command that sends your work to a remote compared nothing at all. This asks the other
	## half of the same question - is the account this folder resolved to the one origin will
	## actually authenticate as? Last in this block because a passing sync really does push.
	local idCanon="${idc}"; ((isWindows)) && idCanon="$( cd "${idc}" && pwd -W )"
	cat > "${id}/mine.shcl" <<-EOF
		account.mine.path      = ${idCanon}
		account.mine.ghAccount = alice
	EOF
	cat > "${id}/theirs.shcl" <<-EOF
		account.mine.path      = ${idCanon}
		account.mine.ghAccount = bob
	EOF
	local idSync="cd '${idc}' && ${idEnv} GITSBY_CONFIG= FAKE_SSH_LOGIN=bob"
	fAssertFail   "[EmlpDMj] sync refuses when the folder's account is not the key's" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' sync 'W'"
	fAssertOut    "[EmlpDMk] and the refusal names both"  "account is 'alice'.*authenticates as 'bob'" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' sync 'W' 2>&1 || true"
	fAssert       "[EmlpDMl] the refusal happens before the push" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' sync 'W'; ! git -C '${idc}' ls-remote --heads origin idfeat 2>/dev/null | grep -q idfeat"
	fAssertNotOut "[EmlpDMm] --any-identity says the difference is intended"  "authenticates as 'bob'" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --any-identity --config '${id}/mine.shcl' sync 'W' 2>&1 || true"
	## A blank ssh command split into nothing, and reading its first word crashed the run.
	fAssertOut    "[Epy8iu0] a blank GIT_SSH_COMMAND is read as plain ssh in the comparison"  "account is 'alice'.*authenticates as 'bob'" \
		bash -c "${idSync} GIT_SSH_COMMAND=' ' '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' sync 'W' 2>&1 || true"
	git -C "${idc}" config core.sshCommand ' '
	fAssertOut    "[Epy8iu1] and so is a blank core.sshCommand"  "account is 'alice'.*authenticates as 'bob'" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' sync 'W' 2>&1 || true"
	git -C "${idc}" config --unset core.sshCommand
	## No configured account at all: the owner of the remote is a guess about a repo, not a claim
	## about who you are, so comparing it would fire for every single-account user.
	fAssertNotOut "[EmlpDMn] an unconfigured account is never compared"  'authenticates as' \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config /dev/null sync 'W' 2>&1 || true"
	fAssertNotOut "[EmlpDMo] and a matching account does not fire"  'authenticates as' \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/theirs.shcl' sync 'W' 2>&1 || true"
	## The interactive warning says gh acts only where gh is the one acting. sync pushes with git
	## alone, so naming gh's account there points at the wrong tool.
	if ((hasPty)); then
		fAssertOut    "[Er1LxS1] an interactive sync warns about the account"  'WRONG ACCOUNT' \
			fAnswerPrompt n "${idSync} '${gitsby}' -NoFetch --config '${id}/mine.shcl' sync 'W'"
		fAssertNotOut "[Er1LxS2] and does not say gh does the GitHub side"  'gh does the GitHub side' \
			fAnswerPrompt n "${idSync} '${gitsby}' -NoFetch --config '${id}/mine.shcl' sync 'W'"
		fAssertOut    "[Er1LxS3] an interactive pr create does say it"  'gh does the GitHub side of this, so it happens as .alice.' \
			fAnswerPrompt n "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -NoFetch pr create 'T'"
	fi
	## Keyed on pushing, not on mutating: 'pullcom' commits locally and sends nothing, so the key
	## origin would push with is nothing to refuse over - and the refusal paid a live ssh probe for
	## a command that never reaches the network.
	fAssert       "[EnPP5qW] pullcom is not refused over the key origin would push with" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' pullcom 'Local only'"

	## pr ok refuses to merge while work is still only local: gh merges what origin has, then
	## deletes the branch, so anything unpushed would be outside both the PR and the merge.
	mkdir -p "${gh}/prguard"
	git init --quiet --bare -b main "${gh}/prguard/origin.git"
	local pgc="${gh}/prguard/c"
	git clone --quiet "${gh}/prguard/origin.git" "${pgc}" 2>/dev/null
	(
		cd "${pgc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b pgfeat && echo w > w.txt && git add --all && git commit --quiet -m work
		git push --quiet -u origin pgfeat
	)
	fAssertFail "[El9Ej2A] pr ok refuses a dirty tree"  bash -c "cd '${pgc}' && echo dirt > dirt.txt && PATH='${ghp}' '${gitsby}' -q pr ok 7"
	fAssert     "[El9Ej2B] pr ok left the dirty work alone"  bash -c "cd '${pgc}' && [[ -f dirt.txt ]] && [[ \"\$(git branch --show-current)\" == pgfeat ]]"
	fAssertFail "[El9Ej2C] pr ok refuses unpushed commits"  bash -c "cd '${pgc}' && rm -f dirt.txt && echo u > u.txt && git add --all && git commit --quiet -m unpushed && PATH='${ghp}' '${gitsby}' -q pr ok 7"
	fAssert     "[El9Ej2D] pr ok kept the unpushed commit"  bash -c "cd '${pgc}' && git log -1 --pretty=%s | grep -qx unpushed"
	fAssert     "[El9Ej2E] pr ok proceeds once synced"  bash -c "cd '${pgc}' && git push --quiet && PATH='${ghp}' FAKE_GH_BASE=dev '${gitsby}' -q pr ok 7"

	## Which branch a PR lands on, and whether it's a hotfix, belong to the PR - not to wherever
	## you happen to be standing. 'pr ok <n>' is routinely run from dev, on someone else's branch.
	local pk="${gh}/prhead"
	git init --quiet --bare -b main "${pk}/origin.git"
	local pkc="${pk}/c"
	git clone --quiet "${pk}/origin.git" "${pkc}" 2>/dev/null
	(
		cd "${pkc}" || exit 1
		echo base > base.txt && echo "readme v1" > README.md
		git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet main && git checkout --quiet -b hotfix/api
		echo "readme v2" > README.md && git commit --quiet -am "Fix wording" && git push --quiet -u origin hotfix/api
		git checkout --quiet dev
	)
	fAssertPlan "[ElCzjRT] pr ok plans the back-merge for a hotfix PR accepted from dev"  'git merge origin/main' \
		bash -c "cd '${pkc}' && PATH='${ghp}' FAKE_GH_HEAD=hotfix/api FAKE_GH_BASE=main '${gitsby}' -q pr ok 7 2>&1"
	fAssert    "[ElCzjRU] and the hotfix reached the default branch"  bash -c "cd '${pkc}' && [[ \"\$(git show origin/main:README.md)\" == 'readme v2' ]]"
	fAssert    "[ElCzjRV] and was carried back to dev"               bash -c "cd '${pkc}' && [[ \"\$(git show origin/dev:README.md)\" == 'readme v2' ]]"
	## The converse: standing on a hotfix branch must not make someone else's feature PR one.
	(
		cd "${pkc}" || exit 1
		git checkout --quiet dev && git checkout --quiet -b pkfeat && echo f > f.txt
		git add --all && git commit --quiet -m feat && git push --quiet -u origin pkfeat
		git checkout --quiet -b hotfix/standing && git push --quiet -u origin hotfix/standing
	)
	fAssertNotPlan "[ElCzjRW] a feature PR accepted from a hotfix branch plans no back-merge"  'git merge origin/main' \
		bash -c "cd '${pkc}' && PATH='${ghp}' FAKE_GH_HEAD=pkfeat FAKE_GH_BASE=dev '${gitsby}' -q pr ok 8 2>&1"

	## The bash version gate. Bash build only - the PowerShell one needs no bash at all.
	local vg="${work}/vgate"
	mkdir -p "${vg}/bin"
	## Raise the floor past any real bash so the gate fires on this one. Everything below the
	## gate is 4.x syntax, so a clean refusal also proves nothing below it was reached.
	sed 's/-lt 4 \]\]/-lt 99 ]]/' "${root}/legacy/bin/gitsby" > "${vg}/gitsby"
	chmod +x "${vg}/gitsby"
	local vgRun="PATH='${vg}/bin:${PATH}' '${vg}/gitsby' status"
	printf '#!/usr/bin/env bash\necho Linux\n' > "${vg}/bin/uname"; chmod +x "${vg}/bin/uname"
	fAssertFail   "[ElCzjRX] too old a bash is refused"                 bash -c "${vgRun}"
	fAssertOut    "[ElCzjRY] and the refusal names the requirement"     'needs bash 4.4 or newer'  bash -c "${vgRun}"
	fAssertNotOut "[ElCzjRZ] and raises no shell error of its own"      'bad substitution|invalid shell option|syntax error'  bash -c "${vgRun}"
	## A fake uname picks the platform arm, so all three can be checked from one box.
	local spec="" plat="" pat=""
	for spec in "Darwin:brew install bash" "FreeBSD:pkg install bash" "Linux:package manager"; do
		plat="${spec%%:*}"; pat="${spec#*:}"
		printf '#!/usr/bin/env bash\necho %s\n' "${plat}" > "${vg}/bin/uname"; chmod +x "${vg}/bin/uname"
		fAssertOut "[ElCzjRa] and tells ${plat} users what to install"  "${pat}"  bash -c "${vgRun}"
	done
	## macOS pins /bin/bash at 3.2 forever, so installing a newer one only helps via PATH.
	fAssert "[ElCzjRb] gitsby resolves bash through PATH, not /bin/bash"  bash -c "head -1 '${root}/legacy/bin/gitsby' | grep -qx '#!/usr/bin/env bash'"

	## Installer options. These run once, not per implementation, and never reach the network:
	## every check either exits during argument parsing, or uses --release (which names the ref
	## outright, so no latest-release lookup) and stops at the confirmation.
	local inst="${root}/legacy/install.bash"
	fAssert     "[ElFABI0] installer --help works"                    bash -c "bash '${inst}' --help"
	fAssertOut  "[ElFABI1] and documents --release"                   '\-\-release dev\|stable'   bash -c "bash '${inst}' --help"
	fAssertOut  "[ElFABI2] and documents --target"                    '\-\-target user\|system'   bash -c "bash '${inst}' --help"
	fAssertOut  "[ElFABI3] and documents --arch"                      '\-\-arch x64\|amd64\|arm64' bash -c "bash '${inst}' --help"
	## Assert the reason, not just the failure: an installer that never heard of --target also
	## exits nonzero here, so a bare exit-code check would pass with the option missing entirely.
	fAssertFail "[ElFABI4] installer exits nonzero on a bad --target"  bash -c "bash '${inst}' --target bogus"
	fAssertOut  "[ElFABI5] installer refuses a bad --target"           "\-\-target takes"          bash -c "bash '${inst}' --target bogus"
	fAssertOut  "[ElFABI6] installer refuses a bad --arch"             "\-\-arch takes"            bash -c "bash '${inst}' --arch sparc"
	fAssertOut  "[ElFABI7] installer refuses a bad --release"          "\-\-release takes"         bash -c "bash '${inst}' --release beta"
	fAssertOut  "[ElFABI8] installer refuses --release with --ref"     'Use --release or --ref'    bash -c "bash '${inst}' --release dev --ref main"
	fAssertOut  "[ElFABI9] installer refuses a valueless --target"     "\-\-target needs a value"  bash -c "bash '${inst}' --target"
	## A ref is interpolated into a download URL, so a path-shaped one installs a script from
	## some other repo while the printed plan still names this one.
	fAssertOut  "[ElHKNn4] installer refuses a path-shaped --ref"      'not a path'                bash -c "bash '${inst}' -y --ref '../../evil/repo/main'"
	fAssertOut  "[ElHKNn5] installer refuses an absolute --ref"        'not a path'                bash -c "bash '${inst}' -y --ref '/etc/passwd'"
	fAssertOut  "[ElHKNn6] installer refuses a shell-shaped --ref"     "aren't valid in a git ref" bash -c "bash '${inst}' -y --ref 'a b;id'"
	## Reading the printed plan needs the confirmation to refuse rather than block. install.bash
	## falls back to /dev/tty when stdin is not one, so this needs setsid - or, failing that, a
	## shell that has no /dev/tty to fall back to. Neither, and there is no safe way to ask.
	if ((shNoTty)); then
		local iHome="${work}/insthome"; mkdir -p "${iHome}"
		local iRun="${noTty[*]} env HOME='${iHome}' bash '${inst}' --release dev"
		fAssertOut "[ElFABIA] --target user installs under HOME"      "insthome/\.local/bin/gitsby"  bash -c "${iRun} --target user </dev/null"
		fAssertOut "[ElFABIB] --target system installs system-wide"   '/usr/local/bin/gitsby'        bash -c "${iRun} --target system </dev/null"
		fAssertOut "[ElFABIC] -s still means --target system"         '/usr/local/bin/gitsby'        bash -c "${iRun} -s </dev/null"
		fAssertOut "[ElFABID] --arch is taken but reported inert"     'Ignore --arch arm64'          bash -c "${iRun} --arch arm64 </dev/null"
		## Whether the download will be checked belongs in the plan, where it can still be
		## declined. It used to be reported only afterwards, and on the dev path not at all -
		## so the one route that installs an unverified file was the quiet one.
		fAssertOut "[EmlXbWy] the dev plan says it will not verify"   'NOT verify the download'      bash -c "${iRun} --target user </dev/null"
	fi
	## The PowerShell installer's ValidateSet does the same job as the case arms above.
	if command -v pwsh >/dev/null 2>&1; then
		local instPs="${root}/legacy/install.ps1"
		fAssertFail "[ElFABIE] ps installer refuses a bad -Target"      pwsh -NoProfile -File "${instPs}" -Target bogus
		fAssertFail "[ElFABIF] ps installer refuses a bad -Arch"        pwsh -NoProfile -File "${instPs}" -Arch sparc
		fAssertFail "[ElFABIG] ps installer refuses a bad -Release"     pwsh -NoProfile -File "${instPs}" -Release beta
		fAssertFail "[ElFABIH] ps installer refuses -Release with -Ref" pwsh -NoProfile -File "${instPs}" -Release dev -Ref main
		fAssertOut  "[ElHKNn7] ps installer refuses a path-shaped -Ref"  'not a path'  pwsh -NoProfile -File "${instPs}" -Yes -Ref '../../evil/repo/main'
		## Same as the Bash plan above: state up front whether the download gets checked, and
		## - on Windows - that PATH is about to be changed, since nothing else there puts the
		## install directory on it and the install would otherwise finish uncallable by name.
		fAssertOut  "[EmlXbWz] ps dev plan says it will not verify"  'NOT verify the download' \
			bash -c "pwsh -NoProfile -File '${instPs}' -Release dev </dev/null 2>&1"
		if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
			fAssertOut "[EmlXbX0] ps plan announces the PATH change"  'to your account PATH' \
				bash -c "pwsh -NoProfile -File '${instPs}' -Release dev </dev/null 2>&1"
		fi
		## Git Bash rewrites a unix-absolute argument into a Windows path before the native
		## pwsh sees it, so '/etc/passwd' would arrive as 'C:/Program Files/Git/etc/passwd'
		## and be refused for the space rather than for being a path. Excluding that one
		## prefix keeps the -File path converting as normal. Ignored off Windows.
		fAssertOut  "[ElHKNn8] ps installer refuses an absolute -Ref"    'not a path' \
			env MSYS2_ARG_CONV_EXCL='/etc' pwsh -NoProfile -File "${instPs}" -Yes -Ref '/etc/passwd'
		## The documented one-liners are 'iex' and a scriptblock, neither of which is a script
		## file - so -File coverage alone says nothing about them. Both must bind their
		## parameters, refuse without a tty, and leave the calling session alive and unaltered.
		## These reach the confirmation prompt, so it has to REFUSE rather than wait: stdin at
		## EOF, and nothing to fall back to - setsid where there is one, and on Windows just the
		## redirect, since Read-Host reads that and never reaches for a terminal.
		if ((canNoTty)); then
			local instDev="${root}/legacy/install-dev.ps1"
			## These paths are read by .NET, not by the shell, so they need native spelling.
			local instPsNative="" instDevNative=""
			instPsNative="$(  fWinPath "${instPs}"  )"
			instDevNative="$( fWinPath "${instDev}" )"
			## The system install location is the platform's own, so the plan line that proves
			## -Target bound differs: /usr/local/bin, or Program Files on Windows. Verified it
			## still discriminates - a user-target plan names AppData\Local\Programs instead.
			local sysBinPat='/usr/local/bin'
			((isWindows)) && sysBinPat='Program Files'
			## Decode the bytes ourselves rather than Get-Content, which quietly drops a BOM.
			## irm doesn't, so a BOM'd file reaches iex with U+FEFF glued to the shebang and
			## the first line stops being a comment - which is how a BOM sat here undetected.
			## With no -Ref the installer looks up the latest release first. The stubs answer the
			## redirect with a tag, the way github.com did before the repo moved to the org. Now
			## it redirects to the org's URL instead, so the real lookup always fell back to the API.
			local readInst="function Invoke-WebRequest { [pscustomobject]@{ Headers = @{ Location = 'https://github.com/jim-collier/gitsby/releases/tag/v2.1.0' } } }; function Invoke-RestMethod { throw 'no network in the suite' }; \$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('${instPsNative}'))"
			fAssertOut "[ElHKNn9] iex form reaches the plan"          'gitsby installer'  fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[ElHKNnA] and refuses without a tty"          'CAUGHT: Aborted'   fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[ElHKNnB] and leaves the session alive"       'HOST ALIVE'        fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[ElHKNnC] scriptblock form binds its options" "${sysBinPat}"      fPwshText "${readInst}; try { & ([scriptblock]::Create(\$t)) -Ref main -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[ElHKNnD] and leaves the session alive too"   'HOST ALIVE'        fPwshText "${readInst}; try { & ([scriptblock]::Create(\$t)) -Ref main -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[ElHKNnE] installer leaks no StrictMode"      'strict stayed off' fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { }; try { \$q = \$neverSet; 'strict stayed off' } catch { 'STRICT LEAKED' }"
			fAssertOut "[ElHKNnF] installer leaks no ErrorAction"     'EAP=Continue'      fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { }; \"EAP=\$ErrorActionPreference\""
			fAssertOut "[ElHKNnG] dev setup's iex form asks first"    'CAUGHT: Aborted'   fPwshText "\$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('${instDevNative}')); try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }"
		fi
		## Byte 0 must be the shebang: a BOM ahead of it means the kernel won't run the
		## file directly either, which the one-liner checks above can't see.
		local psFile=""
		for psFile in "${root}"/legacy/bin/gitsby.ps1 "${root}"/legacy/install.ps1 "${root}"/legacy/install-dev.ps1; do
			fAssert "[ElNAwCG] $(basename "${psFile}") starts with a shebang, no BOM" \
				bash -c "[[ \"\$(head -c2 '${psFile}')\" == '#!' ]]"
		done
		## GitHub serves SHA256SUMS as octet-stream, and Invoke-WebRequest hands back bytes
		## for that, so reading the body as text found no checksum and skipped verification
		## while reporting there was none. Reaching the real asset needs the network, so this
		## pins the decode in the source rather than exercising it.
		fAssert "[Eldf7qa] install.ps1 decodes the SHA256SUMS body from bytes" \
			bash -c "grep -q 'byte\[\]' '${instPs}'"
	fi

	## The shipping installers, at the repo root. What they fetch is a per-platform binary, so
	## everything below the argument parse - the release lookup, SHA256SUMS, the plan - needs the
	## network. These checks stop short of it: parsing, the refusals, and the pins on the parts a
	## live run would have to reach. The download-checksum-run contract itself is proved by
	## release.bash phase 3, against a real published release.
	local goInst="${root}/install.bash"
	fAssert     "[EnPlcIq] go installer --help works"                   bash -c "bash '${goInst}' --help"
	fAssertOut  "[EnPlcIr] and documents --target"                      '\-\-target user\|system'  bash -c "bash '${goInst}' --help"
	fAssertOut  "[EnPlcIs] and documents --arch"                        '\-\-arch amd64\|arm64'    bash -c "bash '${goInst}' --help"
	fAssertOut  "[EnPlcIt] and documents --tag"                         '\-\-tag TAG'               bash -c "bash '${goInst}' --help"
	## The header says --help lists every option the parser takes, and --ref was left out.
	fAssert     "[EpykPWy] and names every option the parser takes"     fBashHelpNamesAll "${goInst}"
	fAssertOut  "[EnPlcIu] go installer refuses a bad --target"         "\-\-target takes"          bash -c "bash '${goInst}' --target bogus"
	fAssertOut  "[EnPlcIv] go installer refuses a valueless --target"   "\-\-target needs a value"  bash -c "bash '${goInst}' --target"
	## --arch names the asset now rather than being accepted and ignored, so the two spellings
	## the release publishes are the two it takes.
	fAssertOut  "[EnPlcIw] go installer refuses a bad --arch"           "\-\-arch takes"            bash -c "bash '${goInst}' --arch sparc"
	## The joined spellings are case arms of their own, so the checks above say nothing about them.
	fAssertOut  "[Er1LxS4] go installer refuses a bad --target=VALUE"   "\-\-target takes 'user' or 'system' \(got 'bogus'\)"  bash -c "bash '${goInst}' --target=bogus"
	fAssertOut  "[Er1LxS5] and names the dropped --release=dev"         'no .--release dev. any more'  bash -c "bash '${goInst}' --release=dev"
	fAssertOut  "[Er1LxS6] and refuses a bad --arch=VALUE"              "\-\-arch takes 'amd64' or 'arm64' \(got 'sparc'\)"  bash -c "bash '${goInst}' --arch=sparc"
	fAssertOut  "[Er1LxS7] and a path-shaped --tag=VALUE"               'not a path'                   bash -c "HOME='${work}/joinhome' bash '${goInst}' -y --tag=../x"
	## '--release dev' installed the tip of a branch while the product was a script. A branch has
	## no build behind it now, so the flag is answered by name rather than left to fail as an
	## unknown option - the same treatment --offline got.
	fAssertOut  "[EnPlcIx] go installer names the dropped --release dev" 'no .--release dev. any more' bash -c "bash '${goInst}' --release dev"
	fAssertOut  "[EnPlcIy] and says so before touching the network"      'build the tip yourself'      bash -c "bash '${goInst}' --release dev"
	## 'stable' named the default and still does, so the text says it takes that one.
	fAssertOut  "[EnPlcIz] go installer refuses any other --release"     "takes only 'stable'"         bash -c "bash '${goInst}' --release beta"
	fAssertNotOut "[EpykPWz] and --help doesn't say it takes neither"    'takes neither'               bash -c "bash '${goInst}' --help"
	## A tag is interpolated into a download URL, so a path-shaped one installs a binary from
	## some other repo while the printed plan still names this one.
	fAssertOut  "[EnPlcJ0] go installer refuses a path-shaped --tag"     'not a path'                  bash -c "bash '${goInst}' -y --tag '../../evil/repo/main'"
	fAssertOut  "[EnPlcJ1] go installer refuses an absolute --tag"       'not a path'                  bash -c "bash '${goInst}' -y --tag '/etc/passwd'"
	fAssertOut  "[EnPlcJ2] go installer refuses a shell-shaped --tag"    "aren't valid in a git tag"   bash -c "bash '${goInst}' -y --tag 'a b;id'"
	## --ref was this option's name for two releases. Every published spelling is permanent.
	fAssertOut  "[EnPlcJ3] --ref still binds as --tag"                   'not a path'                  bash -c "bash '${goInst}' -y --ref '../x'"
	## Under Git Bash the destination is a Windows one and nothing there puts it on PATH, so the
	## Bash installer hands Windows to the one that finishes the job. A fake uname reaches the
	## arm from any box; it fires during detection, so no network either.
	local wg="${work}/wininst"; mkdir -p "${wg}/bin"
	printf '#!/usr/bin/env bash\necho MINGW64_NT-10.0-22631\n' > "${wg}/bin/uname"; chmod +x "${wg}/bin/uname"
	fAssertOut  "[EnPlcJ4] go installer sends Windows to install.ps1"    'use the PowerShell installer' \
		bash -c "PATH='${wg}/bin:${PATH}' bash '${goInst}' -y"
	## The release lookup, with the network stood in for. Under 'set -e' an assignment carries
	## its command's status, so both of these used to end the run silently at the lookup - no
	## message, no fallback, and an exit code straight from curl or wget.
	local lk="${work}/lookup"; mkdir -p "${lk}/bin"
	printf '#!/usr/bin/env bash\nexit 6\n' > "${lk}/bin/curl"; chmod +x "${lk}/bin/curl"
	fAssertOut  "[EnPxi2i] go installer survives a failing curl"        'work out the latest release' \
		bash -c "PATH='${lk}/bin:${PATH}' bash '${goInst}' -y"
	fAssertOut  "[EpykPX0] go installer still takes --release stable"   'work out the latest release' \
		bash -c "PATH='${lk}/bin:${PATH}' bash '${goInst}' --release stable -y"
	## wget-only box: wget answers a declined redirect with exit 8 even though the header it was
	## sent for is right there, so success looked like failure. curl has to be genuinely absent
	## to reach that arm, hence a PATH of just the tools the installer gets that far on.
	local farm="${work}/nocurl"; mkdir -p "${farm}"
	local farmTool="" farmPath=""
	for farmTool in bash uname tr sed head cut cat mktemp rm paste sha256sum shasum openssl; do
		farmPath="$( command -v "${farmTool}" 2>/dev/null || true )"
		if [[ -n "${farmPath}" ]]; then ln -sf "${farmPath}" "${farm}/${farmTool}"; fi
	done
	# shellcheck disable=SC2016  ## the stub's own text; the inner shell does the expanding.
	printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in */releases/latest) echo "  Location: https://github.com/yottacore/gitsby/releases/tag/v9.9.9" >&2; exit 8 ;; esac; done\nexit 1\n' > "${farm}/wget"
	chmod +x "${farm}/wget"
	fAssertOut  "[EnPxi2j] go installer reads a tag out of wget's exit 8" 'v9\.9\.9' \
		bash -c "PATH='${farm}' '${farm}/bash' '${goInst}' -y"
	## Pins on what a live run reaches. Every route is a release asset now, so every route is
	## verified - there is no unverified branch of the plan left to promise around.
	fAssert     "[EnPlcJ5] go installer installs to the documented dirs" \
		bash -c "grep -q 'HOME}/.local/bin' '${goInst}' && grep -q '/usr/local/bin' '${goInst}'"
	fAssert     "[EnPlcJ6] go installer fetches the per-platform asset"  \
		bash -c "grep -q 'asset=\"gitsby-' '${goInst}'"
	fAssert     "[EnPlcJ7] go installer promises no unverified route"   bash -c "! grep -q 'NOT verify' '${goInst}'"

	## 'releases/latest' is the newest release that is NOT a pre-release, so a repo whose newest
	## publication is one has nothing there - and the fallback asked the same endpoint again.
	## A stub curl answers the list endpoint and nothing else, which is exactly that repo.
	local prl="${work}/prerel"; mkdir -p "${prl}/bin"
	fStub "${prl}/bin/curl" <<-'CURLEOF'
		#!/usr/bin/env bash
		url=""
		for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
		case "${url}" in
			*/repos/*/releases) printf '[\n  {\n    "tag_name": "v9.9.9-rc1",\n    "prerelease": true\n  }\n]\n'; exit 0 ;;
		esac
		exit 22
	CURLEOF
	fAssertOut "[EnQQYnw] go installer falls back to a pre-release when that is all there is"  'v9\.9\.9-rc1' \
		bash -c "PATH='${prl}/bin:${PATH}' bash '${goInst}' -y 2>&1"
	fAssertOut "[EnQQYnx] and says that is what it did"  'No full release yet' \
		bash -c "PATH='${prl}/bin:${PATH}' bash '${goInst}' -y 2>&1"
	fAssert    "[EpykPX1] and sets that notice off with blank lines"  fBlankAround 'No full release yet' \
		env PATH="${prl}/bin:${PATH}" bash "${goInst}" -y

	## The list endpoint is ordered by publish date, so a backported fix cut after a newer
	## release lists first: the fallback has to version-sort rather than take the head. The
	## payload here is also packed on one line, which is the other half of the same check -
	## the scrape must not depend on GitHub pretty-printing the JSON.
	local vsort="${work}/vsort"; mkdir -p "${vsort}/bin"
	fStub "${vsort}/bin/curl" <<-'CURLEOF'
		#!/usr/bin/env bash
		url=""
		for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
		case "${url}" in
			*/repos/*/releases) printf '[{"tag_name":"v2.1.1","prerelease":false},{"tag_name":"v3.0.0","prerelease":false}]'; exit 0 ;;
		esac
		exit 22
	CURLEOF
	fAssertOut "[EndU98K] go installer takes the highest version from the fallback, not the newest-listed" 'v3\.0\.0' \
		bash -c "PATH='${vsort}/bin:${PATH}' bash '${goInst}' -y 2>&1"
	## The pre-release pick is a second pass over the same list.
	local vpre="${work}/vsortpre"; mkdir -p "${vpre}/bin"
	fStub "${vpre}/bin/curl" <<-'CURLEOF'
		#!/usr/bin/env bash
		url=""
		for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
		case "${url}" in
			*/repos/*/releases) list='[{"tag_name":"v2.9.0-rc1","prerelease":true},{"tag_name":"v3.0.0-rc1","prerelease":true}]'; printf '%s' "${FAKE_LIST:-${list}}"; exit 0 ;;
		esac
		exit 22
	CURLEOF
	fAssertOut "[Er1LxS8] and from the pre-releases when there is no full release" 'newest pre-release, v3\.0\.0-rc1' \
		bash -c "PATH='${vpre}/bin:${PATH}' bash '${goInst}' -y 2>&1"
	## Two pre-releases of one version tie on the numbers, and the newer-listed one wins.
	fAssertOut "[ErCRFkF] and the newer of two pre-releases of one version" 'newest pre-release, v3\.0\.0-beta\.2' \
		bash -c "PATH='${vpre}/bin:${PATH}' FAKE_LIST='[{\"tag_name\":\"v3.0.0-beta.2\",\"prerelease\":true},{\"tag_name\":\"v3.0.0-beta.1\",\"prerelease\":true}]' bash '${goInst}' -y 2>&1"

	## A whole install, with the network stood in for: resolve, verify, place, run. What this
	## proves is that the staged-and-renamed path works end to end; the pin below it is what
	## discriminates, since writing in place would pass this too.
	local ei="${work}/instend"; mkdir -p "${ei}/bin" "${ei}/home" "${ei}/assets"
	printf '#!/usr/bin/env bash\necho "gitsby v1.2.3 (stand-in)"\n' > "${ei}/asset"
	## SHA256SUMS comes from the generator the release uses, run where a SHA256SUMS already sits,
	## so the names the installers look up are the ones it writes.
	local eiOs="" eiArch=""
	for eiOs in linux darwin freebsd; do
		for eiArch in amd64 arm64; do cp "${ei}/asset" "${ei}/assets/gitsby-${eiOs}-${eiArch}"; done
	done
	cp "${ei}/asset" "${ei}/assets/gitsby-windows-amd64.exe"
	echo stale > "${ei}/assets/SHA256SUMS"
	( cd "${ei}/assets" && bash "${root}/cicd/utility/gen-checksums.bash" SHA256SUMS >/dev/null ) || true
	cp "${ei}/assets/SHA256SUMS" "${ei}/SHA256SUMS"
	fAssert    "[Er1LxS9] gen-checksums writes sums that sha256sum -c accepts"  bash -c "cd '${ei}/assets' && sha256sum -c --quiet SHA256SUMS"
	fAssert    "[Er1LxSA] and leaves SHA256SUMS out of its own listing"  bash -c "grep -q ' gitsby-windows-amd64\.exe\$' '${ei}/SHA256SUMS' && ! grep -q 'SHA256SUMS' '${ei}/SHA256SUMS'"
	fStub "${ei}/bin/curl" <<-'CURLEOF'
		#!/usr/bin/env bash
		url=""
		for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
		[[ -z "${FAKE_CALLS:-}" ]] || echo "${url}" >> "${FAKE_CALLS}"
		case "${url}" in
			*/releases/latest)            printf '%s' "${FAKE_LATEST:-https://github.com/yottacore/gitsby/releases/tag/v1.2.3}"; exit 0 ;;
			*/download/v1.2.3/SHA256SUMS) [[ -e "${FAKE_SUMS}" ]] || exit 22; cat "${FAKE_SUMS}"; exit 0 ;;
			*/download/v1.2.3/gitsby-*)   cat "${FAKE_ASSET}"; exit 0 ;;
		esac
		exit 22
	CURLEOF
	local eiEnv="HOME='${ei}/home' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset'"
	fAssertOut "[EnQQYny] go installer installs, verifies and runs the binary"  'gitsby v1\.2\.3 \(stand-in\)' \
		bash -c "env ${eiEnv} bash '${goInst}' -y 2>&1"
	fAssert    "[EnQQYnz] and a re-install replaces it cleanly" \
		bash -c "env ${eiEnv} bash '${goInst}' -y >/dev/null 2>&1 && '${ei}/home/.local/bin/gitsby' --version | grep -q 'stand-in'"
	fAssert    "[EnQQYo0] and leaves no staging file behind" \
		bash -c "! compgen -G '${ei}/home/.local/bin/.gitsby.install.*' >/dev/null"
	## Written straight to the final path, an interrupt mid-copy leaves a truncated executable
	## where the real one should be, and a write over a copy that is running fails outright.
	## Reproducing either needs a signal or a live process, so the staging is pinned here.
	fAssert    "[EnQQYo1] go installer stages beside the target rather than writing in place" \
		bash -c "grep -q 'staged=\"\${destDir}/' '${goInst}' && grep -qE 'mv -f \"\\\$\{staged\}\"' '${goInst}'"
	## The plan named the install path whether or not a copy was already there.
	fAssertOut "[EpykPX2] go installer's plan says it replaces the one already there"  'replacing the one already there' \
		bash -c "env ${eiEnv} bash '${goInst}' -y 2>&1"
	local eu="${work}/instcase"; mkdir -p "${eu}"
	fAssertNotOut "[EpykPX3] and says nothing of replacing on a first install"  'replacing' \
		bash -c "env HOME='${eu}/fresh' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' bash '${goInst}' -y 2>&1"
	## An upper-case hash read as no binary for this platform, and then named none that was
	## published. sha256sum -c and the PowerShell installer both take one, and CRLF too.
	awk '{ print toupper($1) "  " $2 }' "${ei}/SHA256SUMS" > "${eu}/upper"
	awk '{ printf "%s\r\n", $0 }' "${ei}/SHA256SUMS" > "${eu}/crlf"
	printf '%s  gitsby-plan9-mips\n' "$( head -c 64 "${eu}/upper" )" > "${eu}/other"
	fAssertOut "[EpykPX4] go installer takes an upper-case hash"  'gitsby v1\.2\.3 \(stand-in\)' \
		bash -c "env HOME='${eu}/h1' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${eu}/upper' FAKE_ASSET='${ei}/asset' bash '${goInst}' -y 2>&1"
	fAssertOut "[EpykPX5] and CRLF line ends"                     'gitsby v1\.2\.3 \(stand-in\)' \
		bash -c "env HOME='${eu}/h2' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${eu}/crlf' FAKE_ASSET='${ei}/asset' bash '${goInst}' -y 2>&1"
	fAssertOut "[EpykPX6] and names an upper-case platform it doesn't take"  'It publishes: plan9-mips' \
		bash -c "env HOME='${eu}/h3' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${eu}/other' FAKE_ASSET='${ei}/asset' bash '${goInst}' -y 2>&1"
	## A head reading the hash lookup quit at the first line, and sed died writing the rest once
	## there was more than a pipe holds.
	awk '{ for (i = 0; i < 2000; i++) print }' "${ei}/SHA256SUMS" > "${eu}/repeated"
	fAssertOut "[Erfs792] and reads a long SHA256SUMS to the end"  'gitsby v1\.2\.3 \(stand-in\)' \
		bash -c "env HOME='${eu}/h7' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${eu}/repeated' FAKE_ASSET='${ei}/asset' bash '${goInst}' -y 2>&1"
	## Every exit starts and ends on a blank line, the way fErr's do.
	fAssert    "[EpykPX7] go installer frames the no-binary refusal with blank lines" \
		fFramed env HOME="${eu}/h3" PATH="${ei}/bin:${PATH}" FAKE_SUMS="${eu}/other" FAKE_ASSET="${ei}/asset" bash "${goInst}" -y
	fAssert    "[Er1LxSB] and a successful install" \
		fFramed env HOME="${eu}/h5" PATH="${ei}/bin:${PATH}" FAKE_SUMS="${ei}/SHA256SUMS" FAKE_ASSET="${ei}/asset" bash "${goInst}" -y
	## A piped answer's Enter is never echoed, so the line above is the prompt. Aborted. on a line
	## of its own is then the blank line a terminal shows.
	if ((hasPty)); then
		fAssert    "[EpykPX8] and a declined prompt"  fBlankAfter '^Aborted\.$' \
			fAnswerPrompt n "env HOME='${eu}/h4' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' bash '${goInst}'"
	fi
	## Ctrl-D at the prompt is a no, the same as a closed stdin.
	if ((hasPty)); then
		script -qec "env HOME='${eu}/h6' PATH='${ei}/bin:${PATH}' FAKE_CALLS='${eu}/calls6' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' bash '${goInst}'" /dev/null </dev/null >"${eu}/out6" 2>&1 || true
		fAssert    "[Er1LxSC] go installer takes end of input at the prompt as a no" \
			bash -c "grep -q '/SHA256SUMS\$' '${eu}/calls6' && ! grep -q '/gitsby-' '${eu}/calls6' && [[ ! -e '${eu}/h6/.local/bin/gitsby' ]]"
		## The failed read used to end the script before the answer was looked at, with no word said.
		fAssert    "[ErCLcN9] and says so, with the blank line after"  fBlankAfter '^Aborted\.$' cat "${eu}/out6"
	fi
	## Each of these refusals has to leave nothing behind. Turned into a warning, any one of them
	## puts an unverified binary on PATH and the run still looks like a success.
	local ev="${work}/instverify"; mkdir -p "${ev}"
	printf '#!/usr/bin/env bash\necho "gitsby v6.6.6 (tampered)"\n' > "${ev}/tampered"
	fAssertOut  "[Er1LxSD] go installer refuses a download that fails its checksum"  'Checksum mismatch for gitsby-' \
		bash -c "env HOME='${ev}/h1' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ev}/tampered' bash '${goInst}' -y 2>&1"
	fAssertFail "[Er1LxSE] and exits nonzero" \
		env HOME="${ev}/h1" PATH="${ei}/bin:${PATH}" FAKE_SUMS="${ei}/SHA256SUMS" FAKE_ASSET="${ev}/tampered" bash "${goInst}" -y
	fAssert     "[Er1LxSF] and installs nothing"  bash -c "[[ ! -e '${ev}/h1/.local/bin/gitsby' ]]"
	fAssertOut  "[Er1LxSG] go installer refuses a release with no SHA256SUMS"  'publishes no SHA256SUMS' \
		bash -c "env HOME='${ev}/h2' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${ev}/none' FAKE_ASSET='${ei}/asset' FAKE_CALLS='${ev}/calls2' bash '${goInst}' -y 2>&1"
	fAssert     "[Er1LxSH] and never fetches the binary"  bash -c "grep -q '/SHA256SUMS\$' '${ev}/calls2' && ! grep -q '/gitsby-' '${ev}/calls2'"
	fAssert     "[Er1LxSI] and installs nothing"  bash -c "[[ ! -e '${ev}/h2/.local/bin/gitsby' ]]"
	## Everything the installer needs to finish except a hash tool, so a fallback to installing
	## unverified would get all the way through.
	local nsf="${work}/nosha"; mkdir -p "${nsf}"
	for farmTool in bash uname tr sed head cut cat mktemp rm paste mkdir install mv; do
		farmPath="$( command -v "${farmTool}" 2>/dev/null || true )"
		if [[ -n "${farmPath}" ]]; then ln -sf "${farmPath}" "${nsf}/${farmTool}"; fi
	done
	cp "${ei}/bin/curl" "${nsf}/curl"
	fAssertOut  "[Er1LxSJ] go installer refuses to install with no sha256 tool"  'No sha256 tool here' \
		bash -c "HOME='${ev}/h3' PATH='${nsf}' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' '${nsf}/bash' '${goInst}' -y 2>&1"
	fAssert     "[Er1LxSK] and installs nothing"  bash -c "[[ ! -e '${ev}/h3/.local/bin/gitsby' ]]"
	## A portal page listed in SHA256SUMS, so the first-byte check is the only thing that can refuse it.
	printf '<html>portal</html>\n' > "${ev}/portal"
	local evHash=""; evHash="$( sha256sum "${ev}/portal" | cut -d' ' -f1 )"
	for eiOs in linux darwin freebsd; do
		for eiArch in amd64 arm64; do echo "${evHash}  gitsby-${eiOs}-${eiArch}"; done
	done > "${ev}/portalsums"
	fAssertOut  "[Er1LxSL] go installer refuses a web page served as the binary"  'came back as a web page' \
		bash -c "env HOME='${ev}/h4' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${ev}/portalsums' FAKE_ASSET='${ev}/portal' bash '${goInst}' -y 2>&1"
	fAssert     "[Er1LxSM] and installs nothing"  bash -c "[[ ! -e '${ev}/h4/.local/bin/gitsby' ]]"
	## The redirect's tag reaches the download URLs the same way a typed one does.
	fAssertOut  "[Er1LxSN] go installer refuses a redirect to a tag that isn't one"  "isn't a plain git tag" \
		bash -c "env HOME='${ev}/h5' PATH='${ei}/bin:${PATH}' FAKE_LATEST='https://github.com/yottacore/gitsby/releases/tag/v1;id' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' FAKE_CALLS='${ev}/calls5' bash '${goInst}' -y 2>&1"
	fAssert     "[Er1LxSO] and fetches nothing with it"  bash -c "grep -q '/releases/latest\$' '${ev}/calls5' && ! grep -q 'SHA256SUMS' '${ev}/calls5'"
	## A '..' segment passed the character test, which was the only one the redirect's tag got.
	## The stub never collapses dot segments, so this is the case a curl that didn't would give.
	fAssertOut  "[ErCLuem] and one that climbs out with '..'"  "isn't a plain git tag" \
		bash -c "env HOME='${ev}/h6' PATH='${ei}/bin:${PATH}' FAKE_LATEST='https://github.com/yottacore/gitsby/releases/tag/../x' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' FAKE_CALLS='${ev}/calls6' bash '${goInst}' -y 2>&1"
	fAssert     "[ErCLuf1] and fetches nothing with it"  bash -c "grep -q '/releases/latest\$' '${ev}/calls6' && ! grep -q 'SHA256SUMS' '${ev}/calls6'"
	## 'install' into a directory that isn't there fails, and a fresh macOS has no /usr/local/bin.
	## The sudo stub only logs, so nothing reaches the real directory.
	if [[ ! -w /usr/local/bin ]]; then
		local es="${work}/instsys"; mkdir -p "${es}/bin"
		fStub "${es}/bin/sudo" <<-'SUDOEOF'
			#!/usr/bin/env bash
			echo "$*" >> "${FAKE_SUDO_LOG}"
		SUDOEOF
		fAssert    "[Er1LxSP] go installer creates the system dir before installing into it" \
			bash -c "env HOME='${es}/home' PATH='${es}/bin:${ei}/bin:${PATH}' FAKE_SUDO_LOG='${es}/log' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' bash '${goInst}' --target system -y >/dev/null 2>&1; \
				[[ \"\$(head -n 1 '${es}/log')\" == 'mkdir -p /usr/local/bin' ]] && [[ \"\$(sed -n 2p '${es}/log')\" == 'install -m 755 '* ]]"
	fi
	## Both of these were found at the copy, after the download, or promised in the plan and then
	## failed as a missing command.
	local eno="${work}/instnosudo"; mkdir -p "${eno}/bin"
	for farmTool in bash uname tr sed head cut cat mktemp rm paste sha256sum; do
		farmPath="$( command -v "${farmTool}" 2>/dev/null || true )"
		if [[ -n "${farmPath}" ]]; then ln -sf "${farmPath}" "${eno}/bin/${farmTool}"; fi
	done
	cp "${ei}/bin/curl" "${eno}/bin/"
	if [[ ! -w /usr/local/bin ]]; then
		fAssertOut "[ErCRQbq] go installer refuses a system install with no sudo, before the plan"  'there is no sudo here' \
			bash -c "env HOME='${eno}/home' PATH='${eno}/bin' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' '${eno}/bin/bash' '${goInst}' --target system -y 2>&1"
	fi
	mkdir -p "${eno}/rohome/.local"; chmod 555 "${eno}/rohome/.local"
	fAssertOut "[ErCRQc5] go installer refuses a user folder it can't write, before the plan"  "\.local isn't writable by you" \
		bash -c "env HOME='${eno}/rohome' PATH='${ei}/bin:${PATH}' FAKE_CALLS='${eno}/calls' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset' bash '${goInst}' -y 2>&1"
	fAssert    "[ErCRQcM] and downloads nothing"  bash -c "grep -q '/SHA256SUMS\$' '${eno}/calls' && ! grep -q '/gitsby-' '${eno}/calls'"
	chmod 755 "${eno}/rohome/.local"
	## A binary that ran and failed ended the run on its own exit code, with nothing said.
	local eb="${work}/instbad"; mkdir -p "${eb}"
	printf '#!/usr/bin/env bash\nexit 3\n' > "${eb}/asset"
	local ebHash=""; ebHash="$( sha256sum "${eb}/asset" | cut -d' ' -f1 )"
	for eiOs in linux darwin freebsd; do
		for eiArch in amd64 arm64; do echo "${ebHash}  gitsby-${eiOs}-${eiArch}"; done
	done > "${eb}/SHA256SUMS"
	fAssertOut "[EpykPX9] go installer says when the installed binary won't run"  'but it would not run \(exit 3\)' \
		bash -c "env HOME='${eb}/home' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${eb}/SHA256SUMS' FAKE_ASSET='${eb}/asset' bash '${goInst}' -y 2>&1"
	if command -v pwsh >/dev/null 2>&1; then
		local goInstPs="${root}/install.ps1"
		fAssertFail "[EnPlcJ8] go ps installer refuses a bad -Target"    pwsh -NoProfile -File "${goInstPs}" -Target bogus
		fAssertFail "[EnPlcJ9] go ps installer refuses a bad -Arch"      pwsh -NoProfile -File "${goInstPs}" -Arch sparc
		fAssertOut  "[EnPlcJA] go ps installer names the dropped -Release dev" 'no .-Release dev. any more' \
			bash -c "pwsh -NoProfile -File '${goInstPs}' -Release dev 2>&1"
		fAssertOut  "[EnPlcJB] go ps installer refuses a path-shaped -Tag" 'not a path' \
			pwsh -NoProfile -File "${goInstPs}" -Yes -Tag '../../evil/repo/main'
		## -Ref named this parameter for two releases, so it stays bound as an alias.
		fAssertOut  "[EnPlcJC] -Ref still binds as -Tag"                  'not a path' \
			pwsh -NoProfile -File "${goInstPs}" -Yes -Ref '../../evil/repo/main'
		## Byte 0 must be the shebang: a BOM ahead of it means the kernel won't run the file
		## directly either, and irm carries it into iex where it stops the first line being a comment.
		fAssert "[EnPlcJD] install.ps1 starts with a shebang, no BOM" \
			bash -c "[[ \"\$(head -c2 '${goInstPs}')\" == '#!' ]]"
		## GitHub serves SHA256SUMS as octet-stream and Invoke-WebRequest hands back bytes for
		## that, so reading the body as text finds no checksum. Reaching the real asset needs the
		## network, so this pins the decode in the source rather than exercising it.
		fAssert "[EnPlcJE] go install.ps1 decodes the SHA256SUMS body from bytes" \
			bash -c "grep -q 'byte\[\]' '${goInstPs}'"
		## Assigning to a parameter re-runs its own ValidateSet/ValidatePattern, so detected
		## values that the set doesn't list - x86, a scraped tag - died in the binder instead of
		## reaching the message written for them. Reproducing that needs the hardware or the
		## network, so it is pinned in the source.
		fAssert "[EnPxi2k] go install.ps1 keeps detection out of its validated parameters" \
			bash -c "! grep -qE '^[[:space:]]*\\\$(Arch|Tag)[[:space:]]*=' '${goInstPs}'"
		## [Environment]::GetEnvironmentVariable hands back an EXPANDED PATH; writing that back
		## bakes %USERPROFILE%-style entries in as literals for good.
		fAssert "[EnPxi2l] go install.ps1 reads PATH raw before rewriting it" \
			bash -c "grep -q 'DoNotExpandEnvironmentNames' '${goInstPs}'"
		## The README documents --help for both installers, and this one had no such parameter -
		## PowerShell's binder could only report it as one nobody had heard of.
		fAssertOut "[EnQQYo2] go ps installer answers --help"  'Usage: install\.ps1' \
			bash -c "pwsh -NoProfile -File '${goInstPs}' --help 2>&1"
		fAssertOut "[EnQQYo3] and -Help too"                   'Usage: install\.ps1' \
			bash -c "pwsh -NoProfile -File '${goInstPs}' -Help 2>&1"
		fAssert    "[EpykPXA] and -Help names every option"    fPsHelpNamesAll "${goInstPs}" -Help
		fAssertOut "[EpykPXB] go ps installer refuses any other -Release"  "takes only 'stable'" \
			bash -c "pwsh -NoProfile -File '${goInstPs}' -Release beta 2>&1"
		fAssert    "[EpykPXC] and frames the refusal with blank lines"  fFramed pwsh -NoProfile -File "${goInstPs}" -Release beta
		## A native command's nonzero exit does not trip $ErrorActionPreference, and nothing read
		## $LASTEXITCODE - so a binary that would not run at all was reported as installed.
		## Reaching it needs a real install, so it is pinned in the source.
		fAssert "[EnQQYo4] go install.ps1 reads the verification's exit code" \
			bash -c "grep -q 'LASTEXITCODE' '${goInstPs}'"
		## Move-Item from the system temp is only atomic within one filesystem, and the temp dir
		## and the install dir usually are not the same one.
		fAssert "[EnQQYo5] go install.ps1 stages in the destination directory" \
			bash -c "grep -qF '.gitsby.install.' '${goInstPs}' && grep -q 'ChildPath (.\.gitsby' '${goInstPs}'"
		## 5.1 is what a fresh Windows install has, and the documented one-liner has to work on it.
		fAssert "[EnQQYo6] go install.ps1 does not turn Windows PowerShell 5.1 away" \
			bash -c "! grep -q 'needs PowerShell 7' '${goInstPs}'"
		fAssert "[EnQQYo7] and switches TLS 1.2 on for it"  bash -c "grep -q 'Tls12' '${goInstPs}'"
		fAssert "[EnQQYo8] and asks for basic parsing"      bash -c "grep -q 'UseBasicParsing' '${goInstPs}'"
		## The documented one-liners are 'iex' and a scriptblock, neither of which is a script
		## file - so -File coverage alone says nothing about them. Both must bind their
		## parameters, refuse by throwing rather than exiting, and leave the calling session
		## alive and unaltered. -Release dev is the refusal that lands before any network does.
		if ((canNoTty)); then
			local goInstPsNative=""; goInstPsNative="$( fWinPath "${goInstPs}" )"
			## Decode the bytes ourselves rather than Get-Content, which quietly drops a BOM.
			local goReadInst="\$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('${goInstPsNative}'))"
			fAssertOut "[EnPlcJF] go iex form binds and refuses"     'CAUGHT:'           fPwshText "${goReadInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[EnPlcJG] and leaves the session alive"      'HOST ALIVE'        fPwshText "${goReadInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[EnPlcJH] go scriptblock form binds options" 'no .-Release dev. any more' fPwshText "${goReadInst}; try { & ([scriptblock]::Create(\$t)) -Release dev -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[EnPlcJI] and leaves the session alive too"  'HOST ALIVE'        fPwshText "${goReadInst}; try { & ([scriptblock]::Create(\$t)) -Release dev -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "[EnPlcJJ] go installer leaks no StrictMode"  'strict stayed off' fPwshText "${goReadInst}; try { \$t | Invoke-Expression } catch { }; try { \$q = \$neverSet; 'strict stayed off' } catch { 'STRICT LEAKED' }"
			fAssertOut "[EnPlcJK] go installer leaks no ErrorAction" 'EAP=Continue'      fPwshText "${goReadInst}; try { \$t | Invoke-Expression } catch { }; \"EAP=\$ErrorActionPreference\""
		fi
		## Whole installs through install.ps1, with the network stood in for by fPsInstall's
		## stubs. The asset is the Bash one's stand-in, so these need a box that runs it.
		if ! ((isWindows)); then
			local psi="${work}/psinst"; mkdir -p "${psi}"
			cp "${ei}/asset" "${ei}/SHA256SUMS" "${psi}/"
			cat > "${psi}/stubs.ps1" <<-'PSEOF'
				function Invoke-WebRequest {
					param($Uri, $MaximumRedirection, [switch]$UseBasicParsing, $ErrorAction, $OutFile)
					Add-Content -LiteralPath "$env:FAKE_DIR/calls" -Value $Uri
					if ($Uri -like '*/releases/latest') {
						$to = 'https://github.com/yottacore/gitsby/releases/tag/v1.2.3'
						$carryOn = "$ErrorAction" -eq 'SilentlyContinue'
						if ($env:FAKE_SHAPE -eq '7') {
							$failure = [Exception]::new('Response status code does not indicate success: 302 (Found).')
							$headers = [pscustomobject]@{ Location = [uri]$to }
						} elseif ($env:FAKE_SHAPE -eq '51') {
							if ($carryOn) { $found = [Collections.Generic.Dictionary[string, string]]::new(); $found['Location'] = $to; return [pscustomobject]@{ StatusCode = 302; Headers = $found } }
							throw [InvalidOperationException]::new('Operation is not valid due to the current state of the object.')
						} else {
							if ($carryOn) { return }
							$failure = [Exception]::new('The remote server returned an error: (404) Not Found.')
							$headers = [Net.WebHeaderCollection]::new(); $headers.Add('Server', 'stub')
						}
						$failure | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ Headers = $headers })
						throw $failure
					}
					if ($Uri -like '*/SHA256SUMS') { return [pscustomobject]@{ Content = [IO.File]::ReadAllBytes("$env:FAKE_DIR/SHA256SUMS") } }
					if ($Uri -like '*/gitsby-*') { Copy-Item -LiteralPath "$env:FAKE_DIR/asset" -Destination $OutFile; return }
					throw "no stub for $Uri"
				}
				function Invoke-RestMethod {
					param($Uri, [switch]$UseBasicParsing)
					Add-Content -LiteralPath "$env:FAKE_DIR/calls" -Value $Uri
					# The whole array as one object, the way 5.1 sends it.
					$pre = $env:FAKE_SHAPE -eq 'pre'
					Write-Output -NoEnumerate @([pscustomobject]@{ tag_name = 'v1.2.2'; prerelease = $pre }, [pscustomobject]@{ tag_name = 'v1.2.3'; prerelease = $pre })
				}
			PSEOF
			## On 5.1 the redirect was never read, and the list it fell back to came back as one
			## item, which gave a tag made of every tag name. With no full release, 5.1's 404
			## holds a WebHeaderCollection, where reading Location as a property is an error under
			## strict mode, and that error ended the run inside the catch.
			fAssertOut "[EpyeTQO] go ps installer reads the redirect on 5.1"  'gitsby v1\.2\.3 \(stand-in\)' \
				fPsInstall "${psi}" "${psi}/h51" 51 "${goInstPs}" -Yes
			fAssert    "[EpyeTQP] and needs no list lookup for it"  bash -c "! grep -q '/repos/' '${psi}/calls'"
			fAssertOut "[EpyeTQQ] go ps installer takes the list on 5.1 when there's no full release"  'gitsby v1\.2\.3 \(stand-in\)' \
				fPsInstall "${psi}" "${psi}/hnofull" nofull "${goInstPs}" -Yes
			## The stub lists v1.2.2 ahead of v1.2.3, the order a backported fix publishes in, and
			## serves the stand-in for either tag.
			fAssert    "[Er1LxSQ] and takes the highest version, not the first listed" \
				bash -c "grep -q '/download/v1\.2\.3/' '${psi}/calls' && ! grep -q '/download/v1\.2\.2/' '${psi}/calls'"
			fAssertOut "[EpyeTQR] go ps installer still reads 7's redirect"  'gitsby v1\.2\.3 \(stand-in\)' \
				fPsInstall "${psi}" "${psi}/h7" 7 "${goInstPs}" -Yes
			## A system install promised write access, checked nothing, and failed at the copy
			## after the download with PowerShell's own error.
			if [[ ! -w /usr/local/bin ]]; then
				fAssertOut "[EpyfWSe] go ps installer refuses a system install it can't write, before the plan"  "which this shell doesn't have" \
					fPsInstall "${psi}" "${psi}/hsys" 7 "${goInstPs}" -Target system -Yes
				fAssert    "[EpyfWSf] and downloads nothing first"  bash -c "! grep -q '/gitsby-' '${psi}/calls'"
			fi
			## The options belong to the function inside, so Get-Help on the file listed none.
			fAssert    "[EpyfWSg] go install.ps1's comment help names every option"  fPsHelpNamesAll "${goInstPs}" get-help
			## The Bash installer's long spellings were refused by the binder.
			fAssertOut "[EpyfWSh] go ps installer takes --tag=TAG and --yes"  'gitsby v1\.2\.3 \(stand-in\)' \
				fPsInstall "${psi}" "${psi}/hgnu" 7 "${goInstPs}" --tag=v1.2.3 --yes
			fAssert    "[EpyfWSi] and looks up no latest release"  bash -c "! grep -q 'releases/latest' '${psi}/calls'"
			fAssertOut "[EpyfWSj] go ps installer takes --target and --arch with the value apart"  'gitsby v1\.2\.3 \(stand-in\)' \
				fPsInstall "${psi}" "${psi}/hgnu2" 7 "${goInstPs}" --target user --arch amd64 -Yes
			fAssertOut "[EpyfWSk] go ps installer says a --tag needs a value"  '\-\-tag needs a value' \
				fPsInstall "${psi}" "${psi}/hgnu3" 7 "${goInstPs}" -Yes --tag
			## The compare passed only because -ne ignores case.
			fAssert    "[EpyfWSl] go install.ps1 compares checksums with case spelled out"  bash -c "grep -q 'ToLowerInvariant() -cne' '${goInstPs}'"
			## A binary that can't start throws, so the message for one that won't run was reached
			## only by one that started and failed.
			local psb="${work}/psbad"; mkdir -p "${psb}"
			cp "${psi}/stubs.ps1" "${psb}/"
			printf '\177ELF not a binary' > "${psb}/asset"
			local psbHash=""; psbHash="$( sha256sum "${psb}/asset" | cut -d' ' -f1 )"
			for eiOs in linux darwin freebsd; do
				for eiArch in amd64 arm64; do echo "${psbHash}  gitsby-${eiOs}-${eiArch}"; done
			done > "${psb}/SHA256SUMS"
			fAssertOut "[EpyfWSm] go ps installer says when the installed binary can't start"  'but it would not run' \
				fPsInstall "${psb}" "${psb}/home" 7 "${goInstPs}" -Yes
			fAssertOut "[EpykPXD] go ps installer's plan says it replaces the one already there"  'replacing the one already there' \
				fPsInstall "${psi}" "${psi}/h7" 7 "${goInstPs}" -Yes
			fAssert    "[EpykPXE] go ps installer sets the pre-release notice off with blank lines"  fBlankAround 'No full release yet' \
				fPsInstall "${psi}" "${psi}/hpre" pre "${goInstPs}" -Yes
			fAssertOut "[Er1LxSR] and names the highest version in it"  'newest pre-release, v1\.2\.3' \
				fPsInstall "${psi}" "${psi}/hpre" pre "${goInstPs}" -Yes
			fAssert    "[Er1LxSS] go ps installer frames a successful install with blank lines" \
				fFramed fPsInstall "${psi}" "${psi}/h7" 7 "${goInstPs}" -Yes
			## Each refusal has to leave nothing installed; a warning in its place would not.
			local psv="${work}/psverify" psvDir=""
			for psvDir in sum nosums page exit3 badtag dottag eof; do mkdir -p "${psv}/${psvDir}"; cp "${psi}/stubs.ps1" "${psv}/${psvDir}/"; done
			cp "${ev}/tampered" "${psv}/sum/asset"; cp "${ei}/SHA256SUMS" "${psv}/sum/"
			cp "${ei}/asset" "${psv}/nosums/"
			cp "${ev}/portal" "${psv}/page/asset"; cp "${ev}/portalsums" "${psv}/page/SHA256SUMS"
			cp "${eb}/asset" "${eb}/SHA256SUMS" "${psv}/exit3/"
			cp "${ei}/asset" "${ei}/SHA256SUMS" "${psv}/badtag/"
			sed 's|/releases/tag/v1\.2\.3|/releases/tag/v1;id|' "${psi}/stubs.ps1" > "${psv}/badtag/stubs.ps1"
			cp "${ei}/asset" "${ei}/SHA256SUMS" "${psv}/dottag/"
			sed 's|/releases/tag/v1\.2\.3|/releases/tag/../x|' "${psi}/stubs.ps1" > "${psv}/dottag/stubs.ps1"
			cp "${ei}/asset" "${ei}/SHA256SUMS" "${psv}/eof/"
			fAssertOut "[Er1LxST] go ps installer refuses a download that fails its checksum"  'Checksum mismatch for gitsby-' \
				fPsInstall "${psv}/sum" "${psv}/sum/home" 7 "${goInstPs}" -Yes
			fAssertFail "[Er1LxSU] and exits nonzero"  fPsInstall "${psv}/sum" "${psv}/sum/home" 7 "${goInstPs}" -Yes
			fAssert    "[Er1LxSV] and installs nothing"  bash -c "grep -q '/gitsby-' '${psv}/sum/calls' && [[ ! -e '${psv}/sum/home/.local/bin/gitsby' ]]"
			fAssertOut "[Er1LxSW] go ps installer refuses a release with no SHA256SUMS"  'publishes no SHA256SUMS' \
				fPsInstall "${psv}/nosums" "${psv}/nosums/home" 7 "${goInstPs}" -Yes
			fAssert    "[Er1LxSX] and never fetches the binary"  bash -c "grep -q '/SHA256SUMS\$' '${psv}/nosums/calls' && ! grep -q '/gitsby-' '${psv}/nosums/calls'"
			fAssert    "[Er1LxSY] and installs nothing"  bash -c "[[ ! -e '${psv}/nosums/home/.local/bin/gitsby' ]]"
			## The portal page is listed in SHA256SUMS, so only the first-byte check can refuse it.
			fAssertOut "[Er1LxSZ] go ps installer refuses a web page served as the binary"  'came back as a web page' \
				fPsInstall "${psv}/page" "${psv}/page/home" 7 "${goInstPs}" -Yes
			fAssert    "[Er1LxSa] and installs nothing"  bash -c "[[ ! -e '${psv}/page/home/.local/bin/gitsby' ]]"
			## One byte is all the check needs, and ReadAllBytes loaded the whole binary to get it.
			fAssert    "[Er1LxSb] go install.ps1 reads only the first byte of the download" \
				bash -c "grep -q 'TotalCount 1' '${goInstPs}' && ! grep -qF 'ReadAllBytes(\$tmpFile)' '${goInstPs}'"
			## Started and failed, rather than failed to start: only $LASTEXITCODE says so.
			fAssertOut "[Er1LxSc] go ps installer says when the installed binary exits nonzero"  'but it would not run \(exit 3\)' \
				fPsInstall "${psv}/exit3" "${psv}/exit3/home" 7 "${goInstPs}" -Yes
			fAssertOut "[Er1LxSd] go ps installer refuses a redirect to a tag that isn't one"  "isn't a plain git tag" \
				fPsInstall "${psv}/badtag" "${psv}/badtag/home" 7 "${goInstPs}" -Yes
			fAssert    "[Er1LxSe] and fetches nothing with it"  bash -c "grep -q '/releases/latest\$' '${psv}/badtag/calls' && ! grep -q 'SHA256SUMS' '${psv}/badtag/calls'"
			## 7 hands the header back as a [uri], which collapses the '..' first. 5.1 hands back the text.
			fAssertOut "[ErCLufF] and one that climbs out with '..'"  "isn't a plain git tag" \
				fPsInstall "${psv}/dottag" "${psv}/dottag/home" 51 "${goInstPs}" -Yes
			fAssert    "[ErCLufT] and fetches nothing with it"  bash -c "grep -q '/releases/latest\$' '${psv}/dottag/calls' && ! grep -q 'SHA256SUMS' '${psv}/dottag/calls'"
			## Read-Host at end of input is AutomationNull, and -notmatch on that is falsy.
			fAssertOut "[Er1LxSf] go ps installer takes end of input at the prompt as a no"  'Aborted' \
				fPsInstall "${psv}/eof" "${psv}/eof/home" 7 "${goInstPs}"
			fAssert    "[Er1LxSg] and downloads and installs nothing"  bash -c "grep -q '/SHA256SUMS\$' '${psv}/eof/calls' && ! grep -q '/gitsby-' '${psv}/eof/calls' && [[ ! -e '${psv}/eof/home/.local/bin/gitsby' ]]"
			## The temp dir goes by -LiteralPath, so a bracket in TMPDIR is a character, not a wildcard.
			local pst="${work}/pstmp[1]"; mkdir -p "${pst}"
			TMPDIR="${pst}" fAssertOut "[Er1LxSh] go ps installer installs from a temp dir with brackets in its path"  'gitsby v1\.2\.3 \(stand-in\)' \
				fPsInstall "${psi}" "${psi}/htmp" 7 "${goInstPs}" -Yes
			fAssert    "[Er1LxSi] and removes its temp dir afterwards"  bash -c "[[ -z \"\$(ls -A '${pst}')\" ]]"
			## The plan named the file it would install and not the folder it would create first.
			local psUmask=""; psUmask="$(umask)"; umask 077
			fAssertOut "[ErCRQcb] go ps installer's plan says it creates the folder"  "Create .*/\.local/bin \(it doesn't exist yet\)" \
				fPsInstall "${psi}" "${psi}/hfresh" 7 "${goInstPs}" -Yes
			umask "${psUmask}"
			## chmod +x kept the umask's other bits, so the two installers left different modes.
			fAssert    "[ErCRQcr] and installs the binary 755 whatever the umask" \
				bash -c "[[ \"\$(fMode '${psi}/hfresh/.local/bin/gitsby')\" == 755 ]]"
			mkdir -p "${psi}/hro/.local"; chmod 555 "${psi}/hro/.local"
			fAssertOut "[ErCRQd6] go ps installer refuses a user folder it can't write, before the plan"  "can't write there" \
				fPsInstall "${psi}" "${psi}/hro" 7 "${goInstPs}" -Yes
			fAssert    "[ErCRQdL] and downloads nothing"  bash -c "! grep -q '/gitsby-' '${psi}/calls'"
			chmod 755 "${psi}/hro/.local"
			fAssert    "[Er1LxSj] go install.ps1 names its temp dir at random"  bash -c "grep -q 'tmpDir = Join-Path.*GetRandomFileName' '${goInstPs}'"
		fi
	fi

	## PowerShell only. Set-Location moves PowerShell's own location, not the process cwd, so a
	## script that starts git itself must pass the working directory or reads and writes land in
	## different repos. Every other check cds in bash before starting pwsh, which hides it.

	## A pull whose autostash reapply conflicts still exits 0, so nothing downstream noticed and
	## 'git add --all' marked the conflict resolved - committing the markers and pushing them.
	## The everyday case: local edits to the same lines a teammate already pushed.
	local cf="${work}/$1-conflict"
	mkdir -p "${cf}"
	git init --quiet --bare -b main "${cf}/origin.git"
	git clone --quiet "${cf}/origin.git" "${cf}/mine" 2>/dev/null
	( cd "${cf}/mine" && printf 'line1\nline2\nline3\n' > shared.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main )
	git clone --quiet "${cf}/origin.git" "${cf}/theirs"
	( cd "${cf}/theirs" && printf 'line1\nTHEIRS\nline3\n' > shared.txt && git add --all && git commit --quiet -m "their edit" && git push --quiet origin main )
	( cd "${cf}/mine" && printf 'line1\nMINE\nline3\n' > shared.txt )
	fAssertFail "[ElFFElU] update refuses a conflicted autostash reapply"  bash -c "cd '${cf}/mine' && '${gitsby}' -q update 'mine'"
	fAssertOut  "[ElFFElV] and names the conflicted file"  'shared\.txt'  bash -c "cd '${cf}/mine' && '${gitsby}' -q update 'mine' 2>&1"
	fAssert     "[ElFFElW] and commits no conflict markers"  bash -c "cd '${cf}/mine' && ! git log -p | grep -q '<<<<<<<'"
	fAssert     "[ElFFElX] and leaves the merge unresolved for the user"  bash -c "cd '${cf}/mine' && [[ -n \"\$(git diff --name-only --diff-filter=U)\" ]]"

	## no-remote repo: everything still works locally
	local nr="${work}/$1-noremote"
	git init --quiet -b main "${nr}"
	( cd "${nr}" && echo a > a.txt && git add --all && git commit --quiet -m "initial" )
	fAssert "[EkyQnOb] sync with no remote"   bash -c "cd '${nr}' && '${gitsby}' -q sync 'msg'"
	fAssert "[EkyQnOc] br create with no remote"  bash -c "cd '${nr}' && '${gitsby}' -q br create nb && [[ \"\$(git branch --show-current)\" == nb ]]"
	( cd "${nr}" && echo b > b.txt )
	fAssert "[EkyQnOd] br land with no remote"   bash -c "cd '${nr}' && '${gitsby}' -q br land 'merge nb'"
	fAssert "[EkyQnOe] landed on main"        bash -c "cd '${nr}' && [[ \"\$(git branch --show-current)\" == main ]] && [[ -f b.txt ]]"

	## A default branch that is neither main nor master. Nothing may fall back to the literal
	## 'main' here: that branch doesn't exist, so it would be checked out, protected and merged
	## into as a name - after the WIP commit the wrong protected-branch answer already made.
	local tk="${work}/$1-trunk"
	git init --quiet -b trunk "${tk}"
	( cd "${tk}" && echo a > a.txt && git add --all && git commit --quiet -m init && echo wip >> a.txt )
	fAssertOut "[ElHGWSN] status names the real default branch"  'Default branch: trunk'  bash -c "cd '${tk}' && '${gitsby}' -q status"
	fAssert    "[ElHGWSO] br create works on a trunk-default repo"  bash -c "cd '${tk}' && '${gitsby}' -q br create tfeat && [[ \"\$(git branch --show-current)\" == tfeat ]]"
	fAssert    "[ElHGWSP] and left no WIP commit on trunk"  bash -c "cd '${tk}' && [[ \"\$(git rev-list --count trunk)\" == 1 ]]"
	fAssert    "[ElHGWSQ] and carried the dirty work over"  bash -c "cd '${tk}' && grep -qx wip a.txt"
	fAssert    "[ElHGWSR] update works there too"  bash -c "cd '${tk}' && '${gitsby}' -q update 'tw'"
	fAssert    "[ElHGWSS] br land targets trunk, not a fabricated main"  bash -c "cd '${tk}' && '${gitsby}' -q br land 'landed' && [[ \"\$(git branch --show-current)\" == trunk ]] && ! git show-ref --verify --quiet refs/heads/main"

	## Same shape, but nothing conventional to go on and no origin/HEAD to ask: refuse rather
	## than guess, and refuse before anything is committed.
	local tu="${work}/$1-trunkambig"
	git init --quiet -b mainline "${tu}"
	( cd "${tu}" && echo a > a.txt && git add --all && git commit --quiet -m init && git branch other && echo wip >> a.txt )
	fAssertFail "[ElHGWST] br create refuses when the default branch can't be told"  bash -c "cd '${tu}' && '${gitsby}' -q br create x"
	fAssertOut  "[ElHGWSU] and says so"  "Can't tell this repo's default branch"     bash -c "cd '${tu}' && '${gitsby}' -q br create x 2>&1"
	fAssert     "[ElHGWSV] and committed nothing"  bash -c "cd '${tu}' && [[ \"\$(git rev-list --count mainline)\" == 1 ]]"
	## status is the command you run to find out what is wrong, so it must still work - and must
	## not print a name it couldn't resolve.
	fAssertOut  "[ElHGWSW] status still runs and admits it doesn't know"  'Default branch: unknown'  bash -c "cd '${tu}' && '${gitsby}' -q status"
	fAssert     "[Elct704] br list still runs there too"  bash -c "cd '${tu}' && '${gitsby}' -q br list >/dev/null 2>&1"
	fAssertOut  "[Elct705] and lists the branches with the same admission"  'Default branch: unknown'  bash -c "cd '${tu}' && '${gitsby}' -q br list"
	fAssertOut  "[Elct706] including the ambiguous ones"  '(^|[ /])other'  bash -c "cd '${tu}' && '${gitsby}' -q br list"

	## Folder accounts. Which GitHub account a command acts as is decided by where the repo lives,
	## so the whole block turns on one config file and two directory trees. HOME is faked, and a
	## stub gh holds a token for exactly one of the two accounts - no network, no real credentials.
	## Note on what the checks below can and cannot prove: every "must NOT say X" check passes
	## trivially against a build predating accounts, since that build says nothing at all. Same for
	## a bare exit-code refusal - that build refuses the whole command as unknown. Those are kept as
	## regression guards and each is paired with a check on the message, which is what discriminates.
	local ac="${work}/$1-acct"
	mkdir -p "${ac}/home/${confRel}" "${ac}/bin" "${ac}/trees/work" "${ac}/trees/home"
	fStub "${ac}/bin/gh" <<-'EOF'
		#!/usr/bin/env bash
		[[ -n "${FAKE_GH_LOG:-}" ]] && echo "$*" >> "${FAKE_GH_LOG}"
		case "$1 $2" in
			"auth token") [[ "${3:-}" == "--user" && "${4:-}" == "workacct" ]] && { echo "gho_faketoken"; exit 0; }; exit 1 ;;
			"api user")   [[ -n "${FAKE_GH_PROMPT_LOG:-}" ]] && echo "${GH_PROMPT_DISABLED-UNSET}" >> "${FAKE_GH_PROMPT_LOG}"
			              echo "${FAKE_GH_ACTIVE:-otheracct}"; exit 0 ;;
		esac
		exit 1
	EOF
	## The rules go in written the way a user on this platform would write them. That matters on
	## Windows: '/tmp' is an entry in THIS shell's mount table, so the Bash build resolves it and
	## the PowerShell build - which has no such table - cannot, and never could. A rule spelled
	## that way would match on one leg only, and the block would look like a port bug instead of
	## a fixture that named a path half of it can't see. The drive forms a user would actually
	## type ('C:/x', '/c/x') already resolve the same in both.
	local acCanon="${ac}"
	((isWindows)) && acCanon="$( cd "${ac}" && pwd -W )"
	cat > "${ac}/home/${confRel}/config.shcl" <<-EOF
		# folder accounts
		account.work.path      = ${acCanon}/trees/work
		account.work.ghAccount = workacct
		account.work.name      = Work Person
		account.work.email     = work@example.com
		account.home.path      = ${acCanon}/trees/home
		account.home.ghAccount = homeacct
		account.work.notAKey   = ignored
	EOF
	local acWork="${ac}/trees/work/proj"; local acHome="${ac}/trees/home/proj"
	local acAway="${ac}/trees/away/proj"
	local acRepo=""
	for acRepo in "${acWork}" "${acHome}" "${acAway}"; do
		git init --quiet -b main "${acRepo}"
		( cd "${acRepo}" && echo a > a.txt && git add --all && git commit --quiet -m init )
	done
	## Every check runs with the fake HOME and the stub gh in front. GIT_CONFIG_GLOBAL is pointed at
	## a real file rather than /dev/null, because 'account apply' writes to exactly that.
	## PATH is expanded HERE, not left for the inner shell: single quotes are what stop a path with
	## a space in it from splitting when 'bash -c' re-parses the line, and they would equally stop
	## a '${PATH}' left in place from ever expanding - which silently empties PATH and fails every
	## check in this block for want of git.
	## acNoDiscovery empties every config-file input the file scope pinned: this block is where
	## discovery through HOME is the thing under test.
	local acEnv="${acNoDiscovery} HOME='${ac}/home' GIT_CONFIG_GLOBAL='${ac}/home/.gitconfig' PATH='${ac}/bin:${PATH}'"
	## The two identity checks below need one more thing: this file exports GIT_AUTHOR_NAME/EMAIL
	## for hermeticity, and 'git var GIT_AUTHOR_IDENT' - what the Author line reads - takes those
	## over any config, whether it came from the account or from the repo. Left in place they pin
	## the answer to test <test@test> and neither check can ever see what it is asking about.
	local acEnvIdent="-u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL ${acEnv}"
	: > "${ac}/home/.gitconfig"
	fAssertOut "[EmMuR5c] the account comes from the folder"        "Account \.+: workacct"       bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## "account 'work'" was a bare repeat of the name on the line above it, so the one question a
	## first-time reader asks - what IS that string, and where did gitsby get it - had no answer
	## anywhere on screen. Say what kind of thing it is, and which of the several possible sources
	## produced it.
	fAssertOut "[EnXe9aK] and says what that name is"               "From: An account block named 'work'"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Flattened first: the sentence wraps at a fixed column, so the clause under test straddles two
	## physical lines and no plain grep can see it whole.
	fAssertOut "[EmMuR5d] and which rule chose it"                  'because its folder rule covers this directory' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	## "(from config 'work')" named neither the file nor which config - and there are two in play,
	## since 'gitsby.ghAccount' is a git config key and the account blocks are not. An account that
	## applied cleanly says where to go and look, same as one that didn't.
	## In full, never folded back to '~': the folder rules under it print in full, and one screen
	## spelling home two ways reads as two places.
	fAssertOut "[EnXCRqK] and names the file that rule is written in"  "File: ${ac//./\\.}/home/${confRe}/config\\.shcl" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertOut "[EmMuR5e] a sibling tree resolves to the other one" "Account \.+: homeacct"       bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "[EmMuR5f] and not to the first"                  "workacct"                    bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "[EmMuR5g] a folder no rule covers gets no account line"  "Account \.+:"        bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertOut "[EmMuR5h] the commit identity comes from the account too"  'Work Person <work@example\.com>'  bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch status"
	fAssertOut "[EmMuR5i] a key nothing reads is reported, not ignored"    'account\.work\.notakey'           bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Holding the token is what lets git authenticate over https with no ssh key at all. Only the
	## work account has one in the stub, so only it says so.
	fAssertOut    "[EmMuR5j] the held token is what enables https auth"  'git over https'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "[EmMuR5k] and an account with no token claims nothing" 'git over https' bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Asking gh who is logged in is a live API round trip, and only the identity block reads the
	## answer. The token lookup still has to happen, or the account is not applied at all.
	: > "${ac}/probe-status.log"; : > "${ac}/probe-br.log"; : > "${ac}/probe-raw.log"
	fAssert "[Er1LxSk] status asks gh who is logged in, for the identity block" \
		bash -c "cd '${acWork}' && env ${acEnv} FAKE_GH_LOG='${ac}/probe-status.log' '${gitsby}' -q -NoFetch status >/dev/null && grep -q '^api user' '${ac}/probe-status.log'"
	fAssert "[Er1LxSl] a command that prints no identity block does not" \
		bash -c "cd '${acWork}' && env ${acEnv} FAKE_GH_LOG='${ac}/probe-br.log' '${gitsby}' -q -NoFetch br list >/dev/null && grep -q '^auth token' '${ac}/probe-br.log' && ! grep -q '^api user' '${ac}/probe-br.log'"
	fAssert "[Er1LxSm] and neither does raw" \
		bash -c "cd '${acWork}' && env ${acEnv} FAKE_GH_LOG='${ac}/probe-raw.log' '${gitsby}' -q raw git status >/dev/null && grep -q '^auth token' '${ac}/probe-raw.log' && ! grep -q '^api user' '${ac}/probe-raw.log'"
	## gh can stop and ask to log in, and nobody is there to answer a probe.
	: > "${ac}/prompt.log"
	fAssert "[Er1LxSn] the gh login probe turns gh's prompts off" \
		bash -c "cd '${acWork}' && env -u GH_PROMPT_DISABLED ${acEnv} FAKE_GH_PROMPT_LOG='${ac}/prompt.log' '${gitsby}' -q -NoFetch status >/dev/null && grep -q . '${ac}/prompt.log' && ! grep -qvx 1 '${ac}/prompt.log'"
	## A value typed for one repo specifically outranks a rule about a whole tree. A regression
	## guard, not a discriminating check: code with no accounts at all reads the same repo-local
	## value and passes it too. What it is here to catch is a future account that overrides one.
	( cd "${acWork}" && git config user.email repo@example.com && git config user.name 'Repo Local' )
	fAssertOut "[EmMuR5l] a repo-local identity still wins"  'Repo Local <repo@example\.com>'  bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch status"
	( cd "${acWork}" && git config --unset user.email && git config --unset user.name )
	## Half of one is still a value typed for this repo. These entries reach git the way '-c' does,
	## which outranks the local config, so asking about user.email alone let the account's name
	## replace one the repo had pinned - the exact override the check above exists to forbid.
	( cd "${acWork}" && git config user.name 'Repo Local' )
	fAssertOut "[EnR2Euf] a repo-local name survives an account that names both"  'Repo Local <work@example\.com>' \
		bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch status"
	( cd "${acWork}" && git config --unset user.name && git config user.email repo@example.com )
	fAssertOut "[EnR2Eug] and a repo-local email does the same"  'Work Person <repo@example\.com>' \
		bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch status"
	( cd "${acWork}" && git config --unset user.email )
	## Where the file lives is per-platform now, so which candidate wins is worth pinning. Two more
	## config files, both claiming the same work tree under different account names, so whichever
	## one was read says so on the Account line. The Linux order is all a Linux run can check; the
	## Windows and macOS orders are pinned by TestConfigCandidatesFor in the Go tests.
	mkdir -p "${ac}/xdg/gitsby" "${ac}/appdata/gitsby"
	cat > "${ac}/xdg/gitsby/config.shcl" <<-EOF
		account.xdgacct.path      = ${acCanon}/trees/work
		account.xdgacct.ghAccount = xdgacct
	EOF
	cat > "${ac}/appdata/gitsby/config.shcl" <<-EOF
		account.appdata.path      = ${acCanon}/trees/work
		account.appdata.ghAccount = appdataacct
	EOF
	if ((isMac)); then
		fAssertOut "[ErTFfDS] on macOS, XDG_CONFIG_HOME is not a config location at all"  'Account \.+: workacct' \
			bash -c "cd '${acWork}' && env ${acEnv} XDG_CONFIG_HOME='${ac}/xdg' '${gitsby}' -q -NoFetch status"
	else
		fAssertOut "[Enc9zk0] XDG_CONFIG_HOME is the config location here, ahead of ~/.config"  'Account \.+: xdgacct' \
			bash -c "cd '${acWork}' && env ${acEnv} XDG_CONFIG_HOME='${ac}/xdg' '${gitsby}' -q -NoFetch status"
		fAssertOut "[Enc9zk1] and with none set, ~/.config is still found"  'Account \.+: workacct' \
			bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fi
	## APPDATA is Windows' own answer to this question and means nothing anywhere else, just as
	## XDG_CONFIG_HOME means nothing on Windows. Each used to be tried on every platform, which put
	## a variable a Wine or Samba setup can leave lying around on the list of places a Linux run
	## reads credentials from, and let an MSYS shell answer for a Windows one. Asked with a home
	## that holds no config, so the answer is APPDATA's file or nothing - with the usual one still
	## in place both platforms would read that instead and the check could not tell them apart.
	mkdir -p "${ac}/nohome"
	: > "${ac}/nohome/.gitconfig"
	local acAppdataEnv="${acNoDiscovery} HOME='${ac}/nohome' GIT_CONFIG_GLOBAL='${ac}/nohome/.gitconfig'"
	acAppdataEnv+=" PATH='${ac}/bin:${PATH}' APPDATA='${ac}/appdata'"
	if ((isWindows)); then
		fAssertOut "[Enc9zk2] on Windows, %APPDATA% is where the file lives"  'Account \.+: appdataacct' \
			bash -c "cd '${acWork}' && env ${acAppdataEnv} '${gitsby}' -q -NoFetch status"
	else
		fAssertNotOut "[Enc9zk3] off Windows, APPDATA is not a config location at all"  'appdataacct' \
			bash -c "cd '${acWork}' && env ${acAppdataEnv} '${gitsby}' -q -NoFetch status"
	fi
	## A rule written through a symlink - a synced folder, a stable name pointing at a dated one,
	## a home that is itself a link. git answers with the tree's real path, so a rule spelled the
	## way it was typed was compared against the resolved one and matched nothing. Nor did anything
	## say so: the folder exists, so 'account list' printed it without its "can never match" note.
	if ln -s "${ac}/trees/work" "${ac}/linked" 2>/dev/null; then
		local acLinkCanon="${ac}/linked"
		((isWindows)) && acLinkCanon="$( cd "${ac}/linked" && pwd -W )"
		cat > "${ac}/home/${confRel}/linked.shcl" <<-EOF
			account.linked.path      = ${acLinkCanon}/proj
			account.linked.ghAccount = linkedacct
		EOF
		fAssertOut "[EnR2Euh] a folder rule spelled through a symlink still claims the folder"  'Account \.+: linkedacct' \
			bash -c "cd '${acWork}' && env ${acEnv} GITSBY_CONFIG='${ac}/home/${confRel}/linked.shcl' '${gitsby}' -q -NoFetch status"
		fAssertOut "[EnR2Eui] and 'account list' marks it as the one in force"  '^-> linked' \
			bash -c "cd '${acWork}' && env ${acEnv} GITSBY_CONFIG='${ac}/home/${confRel}/linked.shcl' '${gitsby}' account list"
	fi
	## Overrides, both directions.
	fAssertOut "[EmMuR5m] GITSBY_ACCOUNT overrides the folder"  '^Account .*homeacct'  bash -c "cd '${acWork}' && env ${acEnv} GITSBY_ACCOUNT=home '${gitsby}' -q -NoFetch status"
	## A bare login is a documented spelling of GITSBY_ACCOUNT, and 'raw' already reports one on
	## stderr. The identity line asked instead whether some CONFIGURED value had been used, so a
	## bare login named no account, set no key, and printed nothing at all - silence from the one
	## command whose job is to say who a push will go out as.
	fAssertOut "[EmlOl8y] a bare login still gets an identity line"  '^Account .*barelogin' \
		bash -c "cd '${acAway}' && env ${acEnv} GITSBY_ACCOUNT=barelogin '${gitsby}' -q -NoFetch status"
	## An account the file defines but that names no GitHub login of its own - a commit identity
	## and an ssh key and nothing else, which is a whole way of holding a second one. A folder rule
	## has always applied such an account; naming the same one through GITSBY_ACCOUNT read it as a
	## bare login instead, so none of it applied and the ACCOUNT's own name was reported as the
	## GitHub login the run acts as - asking for it by name got you less than not asking.
	cat > "${ac}/keysonly.shcl" <<-EOF
		account.keysonly.name  = Keys Only
		account.keysonly.email = keys@example.com
	EOF
	fAssertOut "[EnRgpp2] an account with no GitHub login still applies when named"  'Keys Only <keys@example\.com>' \
		bash -c "cd '${acAway}' && env ${acEnvIdent} GITSBY_ACCOUNT=keysonly '${gitsby}' -q -NoFetch --config '${ac}/keysonly.shcl' status"
	fAssertNotOut "[EnRgpp3] and its own name is not reported as a GitHub login"  'Account \.+: keysonly' \
		bash -c "cd '${acAway}' && env ${acEnv} GITSBY_ACCOUNT=keysonly '${gitsby}' -q -NoFetch --config '${ac}/keysonly.shcl' status"
	## The repo's own gitsby.ghAccount says who, not that the rest of the folder's account is off.
	## An account naming no login disagrees with nothing, so its identity still applies.
	cat > "${ac}/nologin.shcl" <<-EOF
		account.nl.path  = ${acCanon}/trees/work
		account.nl.name  = No Login
		account.nl.email = nologin@example.com
	EOF
	( cd "${acWork}" && git config gitsby.ghAccount somelogin )
	fAssertOut "[Er1LxSo] a repo-local login keeps the identity of a folder account that names none"  'No Login <nologin@example\.com>' \
		bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch --config '${ac}/nologin.shcl' status"
	( cd "${acWork}" && git config --unset gitsby.ghAccount )
	## A byte-order mark is what a Windows editor writes by default. It lands on the first key in
	## the file, which then reads as one nothing understands - and the line reporting those printed
	## the mark along with it, so the only diagnostic named a key that looks exactly right.
	printf '\xef\xbb\xbf' > "${ac}/bom.shcl"
	cat >> "${ac}/bom.shcl" <<-EOF
		account.bom.path      = ${acCanon}/trees/work
		account.bom.ghAccount = bomacct
	EOF
	fAssertOut    "[EnRgpp4] a byte-order mark doesn't eat the config's first key"  'bomacct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/bom.shcl' status"
	fAssertNotOut "[EnRgpp5] nor get that key reported as one it couldn't read"  'account\.bom\.path' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/bom.shcl' status"
	## ...but only for an account ASKED for. The owner of the remote is a guess about a repo, and a
	## single-account machine must never learn the feature exists.
	( cd "${acAway}" && git remote add origin https://github.com/someone/repo.git )
	fAssertNotOut "[EmlOl8z] the remote's owner alone prints no identity line"  'Account \.'  \
		bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	( cd "${acAway}" && git remote remove origin )
	## Which folder decides, for the one command whose folder is not the one you are standing in. A
	## clone lands somewhere else, and it is the rules for THERE that pick the account; reading the
	## current directory's answered for whatever repo you happened to be sitting inside.
	git init --quiet --bare -b main "${ac}/src.git"
	( cd "${acWork}" && git push --quiet "${ac}/src.git" HEAD:refs/heads/main )
	fAssertOut    "[EnPebrN] a clone takes the account of the folder it lands in"  "Account \.+: workacct" \
		bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/work/c1'"
	fAssertNotOut "[EnPebrO] and not the one it was launched from"  'homeacct' \
		bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/work/c2'"
	fAssertOut    "[EnPebrP] the other direction the same way"  "Account \.+: homeacct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/home/c3'"
	## Climbing out of one tree into another is the case a rule sees wrong if the '..' survives.
	fAssertOut    "[EnPebrQ] a relative destination is resolved before the rules see it"  "Account \.+: homeacct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' ../../home/c4"
	## 'gitsby.ghAccount' answers for the repo it is set in. A clone's destination has no config of
	## its own yet, and an includeIf keyed on gitdir cannot be asked about a repo that does not exist
	## - so the value belonging to whatever repo we are standing in must not follow the clone out of it.
	( cd "${acAway}" && git config gitsby.ghAccount awayacct )
	fAssertNotOut "[EnPebrR] a repo-local account does not follow a clone out of its folder"  'Account \.' \
		bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/away/c5'"
	fAssertOut    "[EnPebrS] and the destination's rule answers in its place"  "Account \.+: workacct" \
		bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/work/c6'"
	( cd "${acAway}" && git config --unset gitsby.ghAccount )
	cat > "${ac}/alt.shcl" <<-EOF
		account.alt.path      = ${acCanon}/trees/work
		account.alt.ghAccount = altacct
	EOF
	fAssertOut "[EmMuR5n] --config reads somewhere else"  'altacct'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/alt.shcl' status"
	## The name is matched the way the file was stored - the loader lowercases the whole key, so
	## the lookup has to as well. Bash lowercased only half of it, so an account typed in another
	## case simply missed, silently, and the run went out as gh's own identity.
	fAssertOut "[Emlc0gS] an account name matches whatever case you type"  'altacct' \
		bash -c "cd '${acWork}' && env ${acEnv} GITSBY_ACCOUNT=ALT '${gitsby}' -q -NoFetch --config '${ac}/alt.shcl' status"
	## A folder rule has to resolve to the same tree whichever build reads it, and whichever way the
	## path was spelled. On Windows the PowerShell build resolved the drive letter only AFTER asking
	## the filesystem - and .NET reads this shell's '/c/...' against the current drive, so nothing
	## resolved, short names and junctions were left as written, and the same rule matched in one
	## build and not the other. Silently: a rule that does not match reads exactly like no rule.
	## Only spellings BOTH builds can express. The harness works under a temp directory, which this
	## shell reaches through its own mount table as '/tmp/...' - a spelling with no meaning to the
	## native build, and none it could be given without depending on Git Bash existing. That is a
	## documented limit, not a defect, and 'account' marks such a rule rather than letting it look
	## like no rule at all. cicd/parity.bash covers the drive-letter spellings across both builds.
	## 'pathContains' names a run of folder names rather than a tree on this machine, so one config
	## file can be synced between machines whose roots differ. Two fake "machines" here, same
	## trailing structure under different roots, and one decoy: whole folder names only, so
	## 'jim-collier' must never match a directory called 'jim-collier-old'.
	local acRoot=""
	for acRoot in mA mB; do
		mkdir -p "${ac}/${acRoot}/github.com/alice/proj"
		git init --quiet -b main "${ac}/${acRoot}/github.com/alice/proj"
	done
	mkdir -p "${ac}/mA/github.com/alice-old/proj"
	git init --quiet -b main "${ac}/mA/github.com/alice-old/proj"
	cat > "${ac}/seg.shcl" <<-EOF
		account.seg.pathContains = github.com/alice
		account.seg.ghAccount    = segacct
	EOF
	for acRoot in mA mB; do
		fAssertOut "[EmmDRRb] pathContains matches under root ${acRoot}"  'segacct' \
			bash -c "cd '${ac}/${acRoot}/github.com/alice/proj' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/seg.shcl' status"
	done
	fAssertNotOut "[EmmDRRc] and matches whole folder names only"  'segacct' \
		bash -c "cd '${ac}/mA/github.com/alice-old/proj' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/seg.shcl' status"
	## Precedence: naming this machine's own tree is the more specific claim, so an absolute 'path'
	## beats a 'pathContains'; among pathContains rules, more folder names beats fewer.
	cat > "${ac}/segprec.shcl" <<-EOF
		account.broad.pathContains  = alice
		account.broad.ghAccount     = broadacct
		account.narrow.pathContains = github.com/alice
		account.narrow.ghAccount    = narrowacct
	EOF
	fAssertOut "[EmmDRRd] more folder names is the more specific rule"  'narrowacct' \
		bash -c "cd '${ac}/mA/github.com/alice/proj' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/segprec.shcl' status"
	cat >> "${ac}/segprec.shcl" <<-EOF
		account.exact.path      = ${acCanon}/mA/github.com/alice
		account.exact.ghAccount = exactacct
	EOF
	fAssertOut "[EmmDRRe] an absolute path beats a pathContains"  'exactacct' \
		bash -c "cd '${ac}/mA/github.com/alice/proj' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/segprec.shcl' status"
	## 'account apply' hands the same rule to git, which globs gitdir natively - so plain git agrees
	## under either root, which is the whole point of a config file you can sync.
	mkdir -p "${ac}/seghome"
	local acSegEnv="${acNoDiscovery} HOME='${ac}/seghome' GIT_CONFIG_GLOBAL='${ac}/seghome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	cat > "${ac}/segapply.shcl" <<-EOF
		account.seg.pathContains = github.com/alice
		account.seg.ghAccount    = segacct
		account.seg.email        = alice@example.com
	EOF
	fAssert "[EmmDRRf] account apply writes a gitdir glob for pathContains" \
		bash -c "cd '${ac}/mA/github.com/alice/proj' && env ${acSegEnv} '${gitsby}' -q -NoFetch --config '${ac}/segapply.shcl' account apply >/dev/null"
	for acRoot in mA mB; do
		fAssertOut "[EmmDRRg] and plain git agrees under root ${acRoot}"  'alice@example\.com' \
			bash -c "cd '${ac}/${acRoot}/github.com/alice/proj' && env ${acSegEnv} git config user.email"
	done
	cat > "${ac}/spell.shcl" <<-EOF
		account.s.path      = ${acCanon}/trees/work/proj
		account.s.ghAccount = spellacct
	EOF
	fAssertOut "[EmlpDMp] a folder rule resolves in the canonical spelling"  'spellacct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/spell.shcl' status"
	## The identity block used to name the account it RESOLVED, whether or not anything could act as
	## it. With no token found, gh goes on using its own account - so the one command whose job is
	## answering "who does this go out as" gave the wrong name. The stub gh holds no token for this
	## one, so it is the not-applied case.
	cat > "${ac}/notoken.shcl" <<-EOF
		account.nt.path      = ${acCanon}/trees/work
		account.nt.ghAccount = notokenacct
	EOF
	fAssertOut "[EmlpDMq] an account with no token says it was not applied"  'no access token used' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/notoken.shcl' status"
	## These fixtures push to a local bare repo, so there is no host to name - and hostName() stands
	## in the word "origin" for one, which on this line reads as a host actually called origin.
	fAssertNotOut "[EnXe9aL] and does not invent a host to blame"  'used for origin' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/notoken.shcl' status"
	fAssertNotOut "[EmlpDMr] and an account that WAS applied says no such thing"  'Why:' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## A directory is readable, so it got past the check, loaded nothing, and exited 0 - after the
	## shell had printed its own complaint about reading a directory. Silently no accounts is the
	## answer that acts as the wrong identity.
	fAssertFail "[Emlc0gT] --config naming a directory is refused"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}' status"
	fAssertOut  "[Emlc0gU] and says it isn't a file"  "isn't a file"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}' status 2>&1"
	## 'account apply' writes one fragment per account into a directory beside the config file.
	## Blocked, that surfaced as a raw shell or .NET error - a different one in each build - part
	## way through the run, which reads as a crash rather than as something to act on.
	mkdir -p "${ac}/blocked"
	cat > "${ac}/blocked/config.shcl" <<-EOF
		account.b.path      = ${acCanon}/trees/work
		account.b.ghAccount = bacct
	EOF
	: > "${ac}/blocked/accounts"
	## git applies includes in file order and the LAST match wins; gitsby takes the LONGEST matching
	## folder. Written in declaration order, a tree nested inside another account's tree got
	## whichever account was declared later - so plain git and gitsby disagreed about one directory,
	## which is the whole thing 'apply' exists to prevent. 'outer' is declared second on purpose.
	## A real repo, not just a directory: 'includeIf.gitdir' matches on where the .git is, so in a
	## plain folder no include fires at all and 'git config user.email' answers nothing - which
	## would fail this check for a reason that has nothing to do with rule ordering.
	mkdir -p "${ac}/nesthome"
	git init --quiet -b main "${ac}/trees/work/nested"
	cat > "${ac}/nested.shcl" <<-EOF
		account.inner.path      = ${acCanon}/trees/work/nested
		account.inner.ghAccount = inneracct
		account.inner.email     = inner@example.com

		account.outer.path      = ${acCanon}/trees/work
		account.outer.ghAccount = outeracct
		account.outer.email     = outer@example.com
	EOF
	local acNestEnv="${acNoDiscovery} HOME='${ac}/nesthome' GIT_CONFIG_GLOBAL='${ac}/nesthome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssert "[Emlc0gV] apply writes a nested rule after the tree that contains it" \
		bash -c "cd '${ac}/trees/work/nested' && env ${acNestEnv} '${gitsby}' -q -NoFetch --config '${ac}/nested.shcl' account apply >/dev/null"
	fAssertOut "[Emlc0gW] and plain git then agrees with gitsby about the nested folder"  'inner@example\.com' \
		bash -c "cd '${ac}/trees/work/nested' && env ${acNestEnv} git config user.email"
	fAssertFail "[Emlc0gX] account apply refuses a blocked include directory"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/blocked/config.shcl' account apply"
	fAssertOut  "[Emlc0gY] and names it rather than dumping an OS error"  "isn't a directory" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/blocked/config.shcl' account apply 2>&1"
	## A config named with no folder put the fragments under the file itself, 'rel.shcl/accounts', and
	## apply refused. A relative include would be wrong anyway: git reads one from its own config's folder.
	mkdir -p "${ac}/rel" "${ac}/relhome"
	cat > "${ac}/rel/rel.shcl" <<-EOF
		account.rel.path      = ${acCanon}/trees/work
		account.rel.ghAccount = relacct
	EOF
	local acRelEnv="${acNoDiscovery} HOME='${ac}/relhome' GIT_CONFIG_GLOBAL='${ac}/relhome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssert "[EpxzLzs] account apply takes a --config named from the folder it runs in" \
		bash -c "cd '${ac}/rel' && env ${acRelEnv} '${gitsby}' -q -NoFetch --config rel.shcl account apply >/dev/null"
	fAssert "[EpxzLzt] and writes the fragments beside it, included by absolute path" \
		bash -c "[[ -f '${ac}/rel/accounts/github.com_relacct.gitconfig' ]] && env ${acRelEnv} git config --global --get-regexp '^includeif\.' | grep -qE ' /.+/rel/accounts/github\.com_relacct\.gitconfig$'"
	## '~', '${HOME}' and '%USERPROFILE%' are one folder on every platform, so a file synced from a
	## Windows box applies here too. git knows none of them, so apply hands it the folder itself, and
	## the ssh command gets the '~' its shell expands.
	mkdir -p "${ac}/varhome/trees"
	git init --quiet -b main "${ac}/varhome/trees/varproj"
	git init --quiet -b main "${ac}/varhome/trees/pctproj"
	cat > "${ac}/varhome/vars.shcl" <<-'EOF'
		account.dollar.path      = ${HOME}/trees/varproj
		account.dollar.ghAccount = dollaracct
		account.dollar.sshKey    = ${HOME}\.ssh\id_var
		account.pct.path         = %USERPROFILE%\trees\pctproj
		account.pct.ghAccount    = pctacct
	EOF
	local acVarEnv="${acNoDiscovery} HOME='${ac}/varhome' GIT_CONFIG_GLOBAL='${ac}/varhome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	: > "${ac}/varhome/.gitconfig"
	fAssertOut "[Eq4rRn6] a '\${HOME}' folder rule claims its folder"  "Account \.+: dollaracct" \
		bash -c "cd '${ac}/varhome/trees/varproj' && env ${acVarEnv} '${gitsby}' -q -NoFetch --config '${ac}/varhome/vars.shcl' status"
	fAssertOut "[Eq4rRn7] and a '%USERPROFILE%' one with backslashes"  "Account \.+: pctacct" \
		bash -c "cd '${ac}/varhome/trees/pctproj' && env ${acVarEnv} '${gitsby}' -q -NoFetch --config '${ac}/varhome/vars.shcl' status"
	fAssertOut "[Eq4rRn8] and account list prints each rule as the file writes it"  'folder \.\.: %USERPROFILE%\\trees\\pctproj' \
		bash -c "cd '${ac}/varhome' && env ${acVarEnv} '${gitsby}' -q -NoFetch --config '${ac}/varhome/vars.shcl' account list"
	fAssert "[Eq4rRn9] account apply takes both" \
		bash -c "cd '${ac}/varhome/trees/varproj' && env ${acVarEnv} '${gitsby}' -q -NoFetch --config '${ac}/varhome/vars.shcl' account apply >/dev/null"
	fAssertOut "[Eq4rRnA] and gives git the folder, not the variable"  "gitdir/i:${ac//./\\.}/varhome/trees/pctproj/\\.path" \
		bash -c "env ${acVarEnv} git config --global --get-regexp '^includeif\.'"
	fAssertOut "[Eq4rRnB] and gives the ssh command a key its shell expands"  '^ssh -i ~/\.ssh/id_var -o IdentitiesOnly=yes$' \
		bash -c "cd '${ac}/varhome/trees/varproj' && env ${acVarEnv} git config core.sshCommand"
	## A trailing '# ...' is a comment, not part of the value - the documented example config writes
	## them. Folded in, a path became a rule that could never match any directory, and a rule that
	## never matches reads exactly like no rule at all: the command went out as gh's own account.
	## Ahead of 'account apply' on purpose - that writes gitsby.ghAccount into the repo, which
	## outranks any folder rule, so after it this check can no longer see what it is asking about.
	cat > "${ac}/trailing.shcl" <<-EOF
		account.cmt.path      = ${acCanon}/trees/work   # the tree this one owns
		account.cmt.ghAccount = cmtacct                 # who to act as
	EOF
	fAssertOut "[EmlOl90] a trailing comment is not part of the value"  "Account \.+: cmtacct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/trailing.shcl' status"
	## A '#' that was quoted is a literal, and trailing space inside the quotes is kept.
	cat > "${ac}/quoted.shcl" <<-EOF
		account.q.path      = ${acCanon}/trees/work
		account.q.ghAccount = "a#b"                     # quoted, so the hash is part of it
	EOF
	fAssertOut "[EmlOl91] a quoted hash stays in the value"  "Account \.+: a#b" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/quoted.shcl' status"
	## The current layout: one block per account. Read in every shape a hand-written file takes - a
	## block, the dotted spelling of the old lines, a folder list, a key in camel case - and what it
	## can't read is named by the path that reaches it, so the reader can find the line.
	## Spaces for the nesting: '<<-' strips every leading tab, structure included.
	cat > "${ac}/hier.shcl" <<-EOF
		# blocks
		protocol: https
		account: hw
		    path: ${acCanon}/trees/work, ${acCanon}/trees/away
		    ghAccount: hieracct
		    nonsense: 1
		account.hh.path: ${acCanon}/trees/home
		account.hh.ghaccount: dottedacct
	EOF
	fAssertOut "[Eo61m5w] a block-layout config resolves the folder's account"  "Account \.+: hieracct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier.shcl' status"
	fAssertOut "[Eo61m5x] and the second folder in the same list"  "Account \.+: hieracct" \
		bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier.shcl' status"
	fAssertOut "[Eo61m5y] and the dotted spelling of the old lines"  "Account \.+: dottedacct" \
		bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier.shcl' status"
	fAssertOut "[Eo61m5z] a key nothing reads is named by the path that reaches it"  'Ignored keys \.+:.*account\[hw\]\.nonsense' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier.shcl' account"
	## A bare backslash is itself, so '\trees' is not a tab and 'rees'. A rule reads either slash.
	cat > "${ac}/backslash.shcl" <<-EOF
		account: hb
		    path: ${acCanon}\trees\work
		    ghaccount: slashacct
	EOF
	fAssertOut "[Eqp3jdg] a folder rule typed with backslashes keeps them"  "Account \.+: slashacct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/backslash.shcl' status"
	## A key indented under another key is that key's child, and nothing reads a key from there. It
	## is listed by the path that reaches it, and the key above it still applies. A stacked list
	## holds its items as the key's value, so it lists nothing.
	cat > "${ac}/nested.shcl" <<-EOF
		protocol: https
		    sshkey: ~/.ssh/id_proto
		account: hn
		    path:
		        * ${acCanon}/trees/work
		    name: Nested Person
		    email: nested@example.com
		        sshkey: ~/.ssh/id_nested
		    nonsense: 1
		        tokenfile: /t
	EOF
	fAssertOut "[EptqIx6] a key indented under another key is listed as ignored"  'account\[hn\]\.email\.sshkey \(indented under email\)' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/nested.shcl' account"
	fAssertOut "[EptqIx7] and one under a key nothing reads"  'account\[hn\]\.nonsense\.tokenfile \(indented under nonsense\)' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/nested.shcl' account"
	fAssertOut "[EptqIx8] and one under protocol"  'protocol\.sshkey \(indented under protocol\)' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/nested.shcl' account"
	fAssertOut "[EptqIx9] and the identity block names the nested key"  'ignored: .*account\[hn\]\.email\.sshkey' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/nested.shcl' status"
	fAssertOut "[EptqIxA] the key it sits under still applies"  'commits .*<nested@example\.com>' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/nested.shcl' account"
	fAssertNotOut "[EptqIxB] a stacked folder list is not listed as ignored"  'account\[hn\]\.path\.' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/nested.shcl' account"
	## 'account set' on a block-layout file edits the block and keeps the rest as it was, comments
	## included. A new key takes the indent of the lines around it.
	cp "${ac}/hier.shcl" "${ac}/hier-set.shcl"
	fAssertOut "[Eo61m60] 'account set' names the block and the key it adds"  'add: +account\[hw\]\.host: gitea\.example' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier-set.shcl' account set hw host gitea.example 2>&1"
	fAssertOut "[Eo61m61] and the block now holds it"  '^ +host: gitea\.example$'  cat "${ac}/hier-set.shcl"
	fAssertOut "[Eo61m62] with the comment above it kept"  '^# blocks$'  cat "${ac}/hier-set.shcl"
	fAssertOut "[Eo61m63] and an existing key is shown before and after"  'was: +ghaccount: hieracct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier-set.shcl' account set hw ghaccount other 2>&1"
	## A file created from nothing carries a header naming the keys and a footer naming the format,
	## and is readable by nobody else: it names accounts and points at token files.
	local acNew="${ac}/newhome"; mkdir -p "${acNew}"
	fAssertOut "[Eo61m64] 'account set' creates the file where the next run looks"  "create ${acNew//./\\.}/${confRe}/config\\.shcl" \
		bash -c "cd '${acWork}' && env ${acNoDiscovery} HOME='${acNew}' PATH='${ac}/bin:${PATH}' '${gitsby}' -q -NoFetch account set fresh ghaccount freshacct 2>&1"
	fAssertOut "[Eo61m65] and it names the format it is in"  'This config file format is SHCL'  cat "${acNew}/${confRel}/config.shcl"
	fAssertOut "[Eo61m66] and the keys it takes"  '^#   pathcontains '  cat "${acNew}/${confRel}/config.shcl"
	fAssertOut "[Eo61m67] and the next run reads it"  'github \.+: freshacct' \
		bash -c "cd '${acWork}' && env ${acNoDiscovery} HOME='${acNew}' PATH='${ac}/bin:${PATH}' '${gitsby}' -q -NoFetch account 2>&1"
	if ! ((isWindows)); then
		fAssert "[Eo61m68] and nobody else can read it"  bash -c "[[ \"\$(fMode '${acNew}/${confRel}/config.shcl')\" == 600 ]]"
	fi
	## Two edits at once each read the whole file and save it whole, and the later save dropped the
	## earlier one's key. Now the second waits on a lock beside the file and refuses if the file
	## changed under it, so a run that says it wrote keeps its key.
	local acPair="${ac}/pair"; mkdir -p "${acPair}"
	fTwoSets(){
		local try pidA pidB rcA rcB
		for ((try = 0; try < 10; try++)); do
			printf 'account: pair\n\tghaccount: pairacct\n' > "${acPair}/config.shcl"
			(cd "${acWork}" && env GITSBY_CONFIG= XDG_CONFIG_HOME= APPDATA= HOME="${ac}/home" PATH="${ac}/bin:${PATH}" "${gitsby}" -q -NoFetch -Config "${acPair}/config.shcl" account set pair email p@example.com) & pidA=$!
			(cd "${acWork}" && env GITSBY_CONFIG= XDG_CONFIG_HOME= APPDATA= HOME="${ac}/home" PATH="${ac}/bin:${PATH}" "${gitsby}" -q -NoFetch -Config "${acPair}/config.shcl" account set pair name PairPerson) & pidB=$!
			rcA=0; wait "${pidA}" || rcA=$?
			rcB=0; wait "${pidB}" || rcB=$?
			[[ "${rcA}" == 0 || "${rcB}" == 0 ]] || return 1
			[[ "${rcA}" != 0 ]] || grep -Fq 'email: p@example.com' "${acPair}/config.shcl" || return 1
			[[ "${rcB}" != 0 ]] || grep -Fq 'name: PairPerson' "${acPair}/config.shcl" || return 1
			[[ ! -e "${acPair}/config.shcl.lock" ]] || return 1
		done
	}
	fAssert "[EpxmDk0] two 'account set' runs at once keep every key they say they wrote"  fTwoSets
	: > "${acPair}/config.shcl.lock"
	fAssertOut "[EpxmDk1] 'account set' waits on a lock another run left, then refuses and names it"  'Lock: +[^ ]*pair/config\.shcl\.lock' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${acPair}/config.shcl' account set pair email q@example.com 2>&1"
	fAssert "[EpxmDk2] and leaves the file as it was"  bash -c "! grep -Fq 'q@example.com' '${acPair}/config.shcl'"
	rm -f -- "${acPair:?}/config.shcl.lock"
	## Reads pass over a discovered accounts file they can't read, and 'account set' won't create
	## a file while it is there: the new one would replace it, or go in ahead of it and hide it. A
	## dead link or a folder in its place is refused too. chmod can't take the read bit away under
	## MSYS, and root reads a 0200 file anyway.
	if ! ((isWindows)) && [[ "$(id -u)" != 0 ]]; then
		local acUnr="${ac}/unreadable"
		mkdir -p "${acUnr}/home/${confRel}" "${acUnr}/xdg" "${acUnr}/dot" "${acUnr}/linkhome/${confRel}" "${acUnr}/dirhome/${confRel}/config.shcl"
		printf 'account: kept\n\tghaccount: keptacct\n' > "${acUnr}/body.shcl"
		local acUnrFile="${acUnr}/home/${confRel}/config.shcl"
		cp "${acUnr}/body.shcl" "${acUnrFile}"; chmod 200 "${acUnrFile}"
		ln -s "${acUnr}/dot/config.shcl" "${acUnr}/linkhome/${confRel}/config.shcl"
		local acUnrEnv="${acNoDiscovery} HOME='${acUnr}/home' PATH='${ac}/bin:${PATH}'"
		local acUnrSet="'${gitsby}' -q -NoFetch account set kept email k@example.com"
		fAssertFail "[Epta2t6] 'account set' refuses to create over an accounts file it can't read" \
			bash -c "cd '${acWork}' && env ${acUnrEnv} ${acUnrSet}"
		fAssertOut "[Epta2t7] and names the file"  "File: +${acUnr//./\\.}/home/${confRe}/config\\.shcl" \
			bash -c "cd '${acWork}' && env ${acUnrEnv} ${acUnrSet} 2>&1"
		fAssertOut "[Epta2t8] and says why it can't read it"  'permission denied' \
			bash -c "cd '${acWork}' && env ${acUnrEnv} ${acUnrSet} 2>&1"
		fAssertOut "[Epta2t9] and gives the command that makes it readable"  "chmod u\\+r '${acUnrFile//./\\.}'" \
			bash -c "cd '${acWork}' && env ${acUnrEnv} ${acUnrSet} 2>&1"
		## Put back to 0200 whatever cmp says, so the checks after this one still see it unreadable.
		fAssert "[Epta2tA] and leaves the file as it was" \
			bash -c "chmod 600 '${acUnrFile}'; cmp -s '${acUnrFile}' '${acUnr}/body.shcl'; rc=\$?; chmod 200 '${acUnrFile}'; exit \${rc}"
		fAssertOut "[Epta2tB] reads still pass over a file they can't read"  'Config file \.+: \(none found\)' \
			bash -c "cd '${acWork}' && env ${acUnrEnv} '${gitsby}' -q -NoFetch account 2>&1"
		fAssert "[Epta2tC] and no file is created ahead of it in XDG_CONFIG_HOME" \
			bash -c "cd '${acWork}' && ! env ${acNoDiscovery} XDG_CONFIG_HOME='${acUnr}/xdg' HOME='${acUnr}/home' PATH='${ac}/bin:${PATH}' ${acUnrSet} >/dev/null 2>&1 && [[ ! -e '${acUnr}/xdg/gitsby/config.shcl' ]]"
		fAssertOut "[Epta2tD] a link to a file that isn't there is refused"  "is a link to something that isn't there" \
			bash -c "cd '${acWork}' && env ${acNoDiscovery} HOME='${acUnr}/linkhome' PATH='${ac}/bin:${PATH}' ${acUnrSet} 2>&1"
		fAssert "[Epta2tE] and nothing is created where it points"  bash -c "[[ ! -e '${acUnr}/dot/config.shcl' ]]"
		fAssertOut "[Epta2tF] something that isn't a file is named as that"  "isn't a file is where the accounts file goes" \
			bash -c "cd '${acWork}' && env ${acNoDiscovery} HOME='${acUnr}/dirhome' PATH='${ac}/bin:${PATH}' ${acUnrSet} 2>&1"
		## A folder reads look in that can't be searched may hold an accounts file, and a new one in
		## XDG_CONFIG_HOME would go in ahead of it and hide it.
		local acShutDir="${acUnr}/shuthome/${confRel}"
		mkdir -p "${acShutDir}" "${acUnr}/shutxdg"
		cp "${acUnr}/body.shcl" "${acShutDir}/config.shcl"; chmod 600 "${acShutDir}"
		local acShutEnv="${acNoDiscovery} XDG_CONFIG_HOME='${acUnr}/shutxdg' HOME='${acUnr}/shuthome' PATH='${ac}/bin:${PATH}'"
		fAssertFail "[Epu2PTM] 'account set' refuses to create while a folder it looks in can't be searched" \
			bash -c "cd '${acWork}' && env ${acShutEnv} ${acUnrSet}"
		fAssertOut "[Epu2PTN] and names the file it couldn't look for"  "File: +${acUnr//./\\.}/shuthome/${confRe}/config\\.shcl" \
			bash -c "cd '${acWork}' && env ${acShutEnv} ${acUnrSet} 2>&1"
		fAssertOut "[Epu2PTO] and gives the command that makes the folder searchable"  "chmod u\\+x '${acShutDir//./\\.}'" \
			bash -c "cd '${acWork}' && env ${acShutEnv} ${acUnrSet} 2>&1"
		fAssert "[Epu2PTP] and no file is created ahead of it"  bash -c "[[ ! -e '${acUnr}/shutxdg/gitsby/config.shcl' ]]"
		chmod 700 "${acShutDir}"
		fAssertOut "[Epu2PTQ] once the folder can be searched, reads find that file"  'keptacct' \
			bash -c "cd '${acWork}' && env ${acShutEnv} '${gitsby}' -q -NoFetch account 2>&1"
		## A file that opens and then fails to read, which /proc/self/mem is on Linux.
		if [[ -f /proc/self/mem ]]; then
			fAssertOut "[Epu2PTR] a named accounts file that fails to read is refused"  "GITSBY_CONFIG names '/proc/self/mem', which can't be read" \
				bash -c "cd '${acWork}' && env ${acNoDiscovery} GITSBY_CONFIG=/proc/self/mem HOME='${acUnr}/home' PATH='${ac}/bin:${PATH}' ${acUnrSet} 2>&1"
			mkdir -p "${acUnr}/memhome/${confRel}"; ln -sf /proc/self/mem "${acUnr}/memhome/${confRel}/config.shcl"
			fAssertOut "[Epu2PTS] and a found one is refused by 'account set' as a file it can't read"  "is already there, and it can't be read" \
				bash -c "cd '${acWork}' && env ${acNoDiscovery} HOME='${acUnr}/memhome' PATH='${ac}/bin:${PATH}' ${acUnrSet} 2>&1"
		fi
		chmod 600 "${acUnrFile}"
	fi
	## A named file that isn't there is a typo, not a reason to fall back silently.
	fAssertFail "[EmMuR5o] a named config that isn't there is refused"        bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/nope.shcl' status"
	fAssertOut  "[EmMuR5p] and says which file"  'No readable config file'    bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/nope.shcl' status 2>&1"
	## An empty value is a mistake too - a script expanding a variable that turned out empty. Falling
	## back to the default file would pick an account nobody asked for, so it is refused by name.
	fAssertFail "[EmUM8jo] --config with an empty value is refused"     bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '' status"
	fAssertOut  "[EmUM8jp] and says the name was empty"  'empty file name' bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '' status 2>&1"
	## The joined spelling splits the two builds, so each is pinned to what it actually does.
	fAssertOut "[EmUM8jq] --config=FILE (joined) works here"  'altacct'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config='${ac}/alt.shcl' status"

	## account list / apply.
	fAssertOut "[EmMuR5q] account list names the accounts"      'workacct'                 bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssertOut "[EmMuR5r] and marks the one this folder uses"   '^-> work$'                bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssertOut "[EmMuR5s] and says where a token would come from, not what it is"  "token \.+: gh's own store"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssertNotOut "[EmMuR5t] never printing the token itself"   'gho_faketoken'            bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	## A missing login and a missing token are the same kind of answer, so they print the same way.
	printf 'account.bare.path = %s/trees/work\n' "${acCanon}" > "${ac}/bare.shcl"
	fAssertOut "[Eq4W7zU] an account with no token source says (none), as its github line does"  'token \.+: \(none\)$' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/bare.shcl' account list"
	## gh answers about one account at a time, so the listing spent a process on every account that
	## named a login - and 'account set' prints the listing before its own edit, paying it twice.
	## Two accounts on one login is the case that says whether the answer is remembered at all.
	cat > "${ac}/twin.shcl" <<-EOF
		account.a.path      = ${acCanon}/trees/work
		account.a.ghAccount = workacct
		account.b.path      = ${acCanon}/trees/home
		account.b.ghAccount = workacct
	EOF
	: > "${ac}/twin-gh.log"
	fAssert "[Eq2zZrs] account list asks gh once per login, not once per account" \
		bash -c "cd '${acWork}' && env ${acEnv} FAKE_GH_LOG='${ac}/twin-gh.log' '${gitsby}' -q -NoFetch --config '${ac}/twin.shcl' account list >/dev/null && [[ \"\$(grep -c '^auth token' '${ac}/twin-gh.log')\" == 1 ]]"
	fAssert "[EmMuR5u] account list works outside any repo"     bash -c "cd '${ac}' && env ${acEnv} '${gitsby}' -q account >/dev/null"
	## The header used to say "Here" for the directory status calls "Directory", and "Resolves to"
	## for the answer status labels "Account" - two words each for one thing, on the one screen
	## whose whole job is to line the rules up against where you are standing.
	fAssertOut "[Enc14vo] account list names the current directory"  '^Current dir \.+: '  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssertOut "[Enc14vp] and labels the answer the way status does"  '^Account \.+: workacct'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	## An unconfigured folder said "(nothing configured - gh's own account)", which named gh on
	## hosts gh does not serve and answered a question about git's fallback that nobody asked.
	: > "${ac}/none.shcl"
	fAssertOut "[Enc14vq] an unconfigured folder says only that"  '^Account \.+: \(nothing configured\)$' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/none.shcl' account"
	fAssertNotOut "[Enc14vr] naming no tool it cannot speak for"  "gh's own account" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/none.shcl' account"
	fAssertOut "[Er1LxSp] account list with no accounts names the command that adds one"  "No accounts defined\. 'gitsby account set' adds one" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/none.shcl' account list"
	## A rule pointing at nothing matches nothing, which reads exactly like no rule at all.
	cat > "${ac}/dead.shcl" <<-EOF
		account.live.path = ${acCanon}/trees/work
		account.dead.path = ${acCanon}/trees/nosuch
	EOF
	fAssertOut    "[Er1LxSq] account list marks a folder that isn't there"  'folder \.+: .*/trees/nosuch +\(no such directory - this rule can never match\)$' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/dead.shcl' account list"
	fAssertNotOut "[Er1LxSr] and only that one"  'folder \.+: .*/trees/work .*can never match' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/dead.shcl' account list"
	## Two blocks under one name are one account, each key read from the last line to give it. The
	## lines it overrode were dropped without a word, so a gitea block and a github block under one
	## name committed with one's email and authenticated with the other's host.
	printf 'account: tt\n\thost: gitea.com\n\temail: a@example.com\n\naccount: tt\n\thost: github.com\n\temail: b@example.com\n' > "${ac}/twice.shcl"
	fAssertOut "[ErO6xm2] account list names a key an earlier block gave differently"  'account\[tt\]\.host: gitea\.com \(line 2; line 6 gives it again, and that one is read\)' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/twice.shcl' account list"
	## An entry written by hand has to survive; ours have to refresh rather than accumulate.
	( cd "${acWork}" && env HOME="${ac}/home" GIT_CONFIG_GLOBAL="${ac}/home/.gitconfig" git config --global includeIf.gitdir:/hand/written/.path /keep/me.gitconfig )
	fAssert "[EmMuR5v] account apply runs"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account apply >/dev/null"
	fAssert "[EmMuR5w] and plain git now uses the account's identity"  bash -c "cd '${acWork}' && env ${acEnv} git config user.email | grep -qx work@example.com"
	## Without a username a credential manager answers with any entry it holds for the host.
	fAssert "[Er1LxSs] and asks for the account's login over https"  bash -c "cd '${acWork}' && env ${acEnv} git config credential.https://github.com.username | grep -qx workacct"
	fAssert "[EmMuR5x] and the sibling tree gets the other one"        bash -c "cd '${acHome}' && env ${acEnv} git config gitsby.ghAccount | grep -qx homeacct"
	## The key reaches that repo only through the fragment the global config includes, so that is
	## the config to name, with the key spelled as git takes it.
	fAssertOut "[ErCKnBz] and status says it came from the global git config"  "From: The gitsby\.ghAccount key in your global git config\.$" \
		bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssert "[EmMuR5y] re-applying does not duplicate the rules"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account apply >/dev/null && [[ \"\$(grep -c 'gitsby/accounts' '${ac}/home/.gitconfig')\" == 2 ]]"
	fAssert "[EmMuR5z] and leaves a hand-written includeIf alone"  bash -c "grep -q 'hand/written' '${ac}/home/.gitconfig'"
	## Removing an account from the config has to remove its rule, or it silently keeps applying.
	fAssert "[EmMuR60] dropping an account drops its rule"  bash -c "cd '${acWork}' && sed -i.bak '/^account\.home\./d' '${ac}/home/${confRel}/config.shcl' && rm -f '${ac}/home/${confRel}/config.shcl.bak' && env ${acEnv} '${gitsby}' -q account apply >/dev/null && [[ \"\$(grep -c 'gitsby/accounts' '${ac}/home/.gitconfig')\" == 1 ]]"
	## Fragments are named by host and login, so a renamed account leaves its old file behind. It is
	## named, not deleted, since nothing proves gitsby wrote it.
	fAssertOut "[ErO1tXx] and names the fragment no rule uses any more"  'Not used any more, safe to remove: .*/accounts/github\.com_homeacct\.gitconfig' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account apply 2>&1"
	fAssert "[ErO1tYE] and leaves it there"  bash -c "[[ -f '${ac}/home/${confRel}/accounts/github.com_homeacct.gitconfig' ]]"

	## The helper git is handed has to carry the token even when gh is ALREADY that account. The
	## export used to sit inside the "this replaces a different account" branch while the helper
	## install sat outside it, so git got an empty password - and the reset ahead of the helper had
	## already evicted whatever credential manager would otherwise have answered. Every https push
	## by a single-account user went out that way, which is the case needing no configuration.
	fAssertOut "[EmlOl92] the credential helper carries a token when gh is already that account"  'password=gho_faketoken' \
		bash -c "cd '${acWork}' && printf 'protocol=https\nhost=github.com\n\n' | env FAKE_GH_ACTIVE=workacct ${acEnv} '${gitsby}' -q raw git credential fill"

	## A folder path with a space in it. The managed-includes scan split each config line at the
	## first space, so such a key came back truncated and was never recognized as ours - every
	## re-run appended a duplicate, and a rule dropped from the config file kept applying forever.
	mkdir -p "${ac}/spacehome" "${ac}/my trees/work"
	: > "${ac}/spacehome/.gitconfig"
	local acSpaceCanon="${ac}/my trees/work"; ((isWindows)) && acSpaceCanon="$( cd "${ac}/my trees/work" && pwd -W )"
	cat > "${ac}/spaced.shcl" <<-EOF
		account.sp.path      = ${acSpaceCanon}
		account.sp.ghAccount = spacct
	EOF
	local acSpaceEnv="${acNoDiscovery} HOME='${ac}/spacehome' GIT_CONFIG_GLOBAL='${ac}/spacehome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssert "[EnPP5qX] account apply writes a rule for a folder whose path has a space" \
		bash -c "cd '${ac}/my trees/work' && env ${acSpaceEnv} '${gitsby}' -q -NoFetch --config '${ac}/spaced.shcl' account apply >/dev/null && [[ \"\$(grep -c 'spacct\.gitconfig' '${ac}/spacehome/.gitconfig')\" == 1 ]]"
	fAssert "[EnPP5qY] and re-applying refreshes it instead of duplicating it" \
		bash -c "cd '${ac}/my trees/work' && env ${acSpaceEnv} '${gitsby}' -q -NoFetch --config '${ac}/spaced.shcl' account apply >/dev/null && [[ \"\$(grep -c 'spacct\.gitconfig' '${ac}/spacehome/.gitconfig')\" == 1 ]]"
	fAssert "[EnPP5qZ] and dropping that account drops its rule" \
		bash -c "cd '${ac}/my trees/work' && sed -i.bak '/^account\.sp\./d' '${ac}/spaced.shcl' && rm -f '${ac}/spaced.shcl.bak' && env ${acSpaceEnv} '${gitsby}' -q -NoFetch --config '${ac}/spaced.shcl' account apply >/dev/null && ! grep -q 'spacct\.gitconfig' '${ac}/spacehome/.gitconfig'"
	## The username plain git asks with has to be for the account's own host, and the same login
	## gitsby's own runs give the helper. It was always github.com and always ghAccount, so an
	## account on another host got none, and one with both keys set named the other login.
	mkdir -p "${ac}/hosthome"
	: > "${ac}/hosthome/.gitconfig"
	cat > "${ac}/hosts.shcl" <<-EOF
		account.gt.path        = ${acCanon}/trees/work
		account.gt.host        = gitea.example.com
		account.gt.user        = gtuser
		account.gt.ghAccount   = gtgh
		account.both.path      = ${acCanon}/trees/home
		account.both.ghAccount = bothgh
		account.both.user      = bothuser
	EOF
	local acHostEnv="${acNoDiscovery} HOME='${ac}/hosthome' GIT_CONFIG_GLOBAL='${ac}/hosthome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssert "[ErCL5PB] account apply names the login for an account's own host" \
		bash -c "cd '${acWork}' && env ${acHostEnv} '${gitsby}' -q -NoFetch --config '${ac}/hosts.shcl' account apply >/dev/null && env ${acHostEnv} git config credential.https://gitea.example.com.username | grep -qx gtuser"
	fAssertFail "[ErCL5PR] and none for github.com, which that account doesn't use" \
		bash -c "cd '${acWork}' && env ${acHostEnv} git config credential.https://github.com.username"
	fAssert "[ErCL5Pg] and user wins over ghAccount, as it does for gitsby's own runs" \
		bash -c "cd '${acHome}' && env ${acHostEnv} git config credential.https://github.com.username | grep -qx bothuser"
	## A rule for the root covers every folder. It looked for the rule plus a slash, '//', and
	## covered none, and the includeIf git got had the same extra slash.
	mkdir -p "${ac}/roothome"
	: > "${ac}/roothome/.gitconfig"
	printf 'account.all.path = %s\naccount.all.ghAccount = rootacct\n' "${acCanon%%/*}/" > "${ac}/root.shcl"
	local acRootEnv="${acNoDiscovery} HOME='${ac}/roothome' GIT_CONFIG_GLOBAL='${ac}/roothome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssertOut "[ErCLUFY] a folder rule for the root covers every folder"  "Account \.+: rootacct" \
		bash -c "cd '${acAway}' && env ${acRootEnv} '${gitsby}' -q -NoFetch --config '${ac}/root.shcl' status"
	fAssert "[ErCLUFu] and account apply gives plain git the same rule" \
		bash -c "cd '${acAway}' && env ${acRootEnv} '${gitsby}' -q -NoFetch --config '${ac}/root.shcl' account apply >/dev/null && env ${acRootEnv} git config gitsby.ghAccount | grep -qx rootacct"

	## A folder rule typed relative. 'path: .' went out as 'gitdir/i:./', which git measures from
	## the folder holding the global git config, so every repo under home took the account while
	## gitsby matched it nowhere. That base is GIT_CONFIG_GLOBAL's folder, so the repo that would
	## show the leak sits under it and the bound one outside it. The hand-written files use printf:
	## the block layout needs its tabs, and a <<- heredoc strips them.
	local acRel="${ac}/rel"
	mkdir -p "${acRel}/home/other" "${acRel}/trees/work/proj" "${acRel}/cfg"
	git init --quiet -b main "${acRel}/home/other"
	git init --quiet -b main "${acRel}/trees/work/proj"
	: > "${acRel}/home/.gitconfig"
	: > "${acRel}/cfg/config.shcl"
	local acRelProj="${acRel}/trees/work/proj"; ((isWindows)) && acRelProj="$( cd "${acRel}/trees/work/proj" && pwd -W )"
	local acRelEnv="${acNoDiscovery} HOME='${acRel}/home' GIT_CONFIG_GLOBAL='${acRel}/home/.gitconfig' PATH='${ac}/bin:${PATH}'"
	local acRelRun="cd '${acRel}/trees/work/proj' && env ${acRelEnv} '${gitsby}' -q -NoFetch --config"
	fAssert "[Ept2CIE] account set resolves a relative path against the folder it is run from" \
		bash -c "${acRelRun} '${acRel}/cfg/config.shcl' account set rel path . >/dev/null && grep -qF -e 'path: ${acRelProj}' -e 'path: \"${acRelProj}\"' '${acRel}/cfg/config.shcl'"
	fAssert "[Ept2CIF] and plain git then applies that account inside the folder" \
		bash -c "${acRelRun} '${acRel}/cfg/config.shcl' account set rel email rel@example.com >/dev/null && ${acRelRun} '${acRel}/cfg/config.shcl' account apply >/dev/null && [[ \"\$(env ${acRelEnv} git -C '${acRel}/trees/work/proj' config user.email || true)\" == rel@example.com ]]"
	fAssert "[Ept2CIG] and nowhere else under home" \
		bash -c "[[ -z \"\$(env ${acRelEnv} git -C '${acRel}/home/other' config user.email || true)\" ]]"
	printf 'account: hand\n\tpath: .\n\temail: hand@example.com\n' > "${acRel}/cfg/hand.shcl"
	printf 'account.flat.path = dev/work\n' > "${acRel}/cfg/flat.shcl"
	fAssertOut "[Ept2CIH] a relative path in the file is listed as ignored"  'Ignored keys \.: account\[hand\]\.path \(not an absolute folder: \.\)' \
		bash -c "${acRelRun} '${acRel}/cfg/hand.shcl' account list"
	fAssertNotOut "[Ept2CII] and is not shown as a folder"  'folder \.\.: \.$' \
		bash -c "${acRelRun} '${acRel}/cfg/hand.shcl' account list"
	fAssertOut "[Ept2CIJ] and the identity block names it"  'ignored: account\[hand\]\.path \(not an absolute folder: \.\)' \
		bash -c "${acRelRun} '${acRel}/cfg/hand.shcl' status"
	fAssertOut "[Ept2CIK] a relative path in a 2.x flat file is ignored the same way"  'account\.flat\.path \(not an absolute folder: dev/work\)' \
		bash -c "${acRelRun} '${acRel}/cfg/flat.shcl' account list"
	fAssert "[Ept2CIL] account apply writes no rule for a relative path" \
		bash -c ": > '${acRel}/home/.gitconfig' && ${acRelRun} '${acRel}/cfg/hand.shcl' account apply >/dev/null && ! grep -qi includeif '${acRel}/home/.gitconfig'"
	## What an apply from before this left behind stays in force for plain git until the next one.
	git config --file "${acRel}/home/.gitconfig" --add 'includeIf.gitdir/i:./.path' "${acRel}/cfg/accounts/hand.gitconfig"
	fAssertOut "[Ept2CIM] account list warns about a relative rule an earlier apply left behind"  "WARNING: your global git config still has the rule 'gitdir/i:\./'" \
		bash -c "${acRelRun} '${acRel}/cfg/hand.shcl' account list"
	fAssert "[Ept2CIN] and account apply removes it" \
		bash -c "${acRelRun} '${acRel}/cfg/hand.shcl' account apply >/dev/null && ! grep -qF 'gitdir/i:./' '${acRel}/home/.gitconfig'"
	fAssertNotOut "[Ept2CIO] and the warning is gone after"  'WARNING: your global git config still has' \
		bash -c "${acRelRun} '${acRel}/cfg/hand.shcl' account list"
	fAssertFail "[Ept2CIP] account set refuses another user's '~'" \
		bash -c "${acRelRun} '${acRel}/cfg/config.shcl' account set rel path '~nobody/x'"
	fAssertOut "[Ept2CIQ] and says why"  "another user's home folder" \
		bash -c "${acRelRun} '${acRel}/cfg/config.shcl' account set rel path '~nobody/x'"
	## A rule is plain text to gitsby and a pattern to git, so a '[' in one bound a different
	## folder in plain git. Each unbracketed twin is the folder the pattern would have taken.
	local acGlob
	for acGlob in 'lit[x]' litx 'ac[m]e' acme; do
		mkdir -p "${acRel}/trees/${acGlob}/proj" && git init --quiet -b main "${acRel}/trees/${acGlob}/proj"
	done
	local acGlobTrees="${acRel}/trees"; ((isWindows)) && acGlobTrees="$( cd "${acRel}/trees" && pwd -W )"
	printf 'account: glob\n\tpath: "%s/lit[x]"\n\tpathcontains: "ac[m]e"\n\temail: glob@example.com\n' "${acGlobTrees}" > "${acRel}/cfg/glob.shcl"
	fAssert "[Epy6SgS] plain git applies a folder rule holding '[' to that folder" \
		bash -c ": > '${acRel}/home/.gitconfig' && ${acRelRun} '${acRel}/cfg/glob.shcl' account apply >/dev/null && [[ \"\$(env ${acRelEnv} git -C '${acRel}/trees/lit[x]/proj' config user.email || true)\" == glob@example.com ]]"
	fAssert "[Epy6SgT] and not to the folder it would match as a pattern" \
		bash -c "[[ -z \"\$(env ${acRelEnv} git -C '${acRel}/trees/litx/proj' config user.email || true)\" ]]"
	fAssert "[Epy6SgU] plain git applies a pathcontains rule holding '[' to that folder" \
		bash -c "[[ \"\$(env ${acRelEnv} git -C '${acRel}/trees/ac[m]e/proj' config user.email || true)\" == glob@example.com ]]"
	fAssert "[Epy6SgV] and not to the folder that pathcontains would match as a pattern" \
		bash -c "[[ -z \"\$(env ${acRelEnv} git -C '${acRel}/trees/acme/proj' config user.email || true)\" ]]"
	## A token file or key named relative was read from the folder a command ran in, so a file in a
	## cloned repo could pick the token, and ssh read the key from each repo's own folder.
	printf 'secret\n' > "${acRel}/trees/work/proj/tok.txt"
	printf 'account: rk\n\ttokenfile: tok.txt\n\tsshkey: id_work\n\temail: rk@example.com\n' > "${acRel}/cfg/relkey.shcl"
	fAssertOut "[Epy6SgW] a relative tokenfile in the file is listed as ignored"  'account\[rk\]\.tokenfile \(not an absolute path: tok\.txt\)' \
		bash -c "${acRelRun} '${acRel}/cfg/relkey.shcl' account list"
	fAssertNotOut "[Epy6SgX] and no token is read from the folder a command runs in"  'token \.\.\.: tok\.txt' \
		bash -c "${acRelRun} '${acRel}/cfg/relkey.shcl' account list"
	fAssert "[Epy6SgY] a relative sshkey goes into no git config fragment" \
		bash -c "${acRelRun} '${acRel}/cfg/relkey.shcl' account apply >/dev/null && grep -q rk@example.com '${acRel}/cfg/accounts/github.com_rk.gitconfig' && ! grep -qi sshcommand '${acRel}/cfg/accounts/github.com_rk.gitconfig'"
	: > "${acRel}/cfg/keyset.shcl"
	fAssert "[Epy6SgZ] account set writes a relative tokenfile as the file it names from here" \
		bash -c "${acRelRun} '${acRel}/cfg/keyset.shcl' account set rk tokenfile tok.txt >/dev/null && grep -qF -e 'tokenfile: ${acRelProj}/tok.txt' -e 'tokenfile: \"${acRelProj}/tok.txt\"' '${acRel}/cfg/keyset.shcl'"
	fAssertFail "[Epy6Sga] account set refuses a relative sshkey typed in a folder whose path has a space" \
		bash -c "cd '${ac}/my trees/work' && env ${acRelEnv} '${gitsby}' -q -NoFetch --config '${acRel}/cfg/keyset.shcl' account set rk sshkey id_work"

	## 'apply' is the one command that writes outside the repo you are standing in, and it reported
	## success whatever happened: the truncate error was discarded and every 'git config' exit code
	## ignored. A directory where the fragment file belongs is the cheapest way to fail one write.
	mkdir -p "${ac}/frag/accounts/github.com_bacct.gitconfig" "${ac}/fraghome"
	: > "${ac}/fraghome/.gitconfig"
	cat > "${ac}/frag/config.shcl" <<-EOF
		account.b.path      = ${acCanon}/trees/work
		account.b.ghAccount = bacct
	EOF
	local acFragEnv="${acNoDiscovery} HOME='${ac}/fraghome' GIT_CONFIG_GLOBAL='${ac}/fraghome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssertFail   "[EnPP5qa] account apply fails when a fragment can't be written" \
		bash -c "cd '${acWork}' && env ${acFragEnv} '${gitsby}' -q -NoFetch --config '${ac}/frag/config.shcl' account apply"
	fAssertNotOut "[EnPP5qb] and never says it wrote one"  'Wrote ' \
		bash -c "cd '${acWork}' && env ${acFragEnv} '${gitsby}' -q -NoFetch --config '${ac}/frag/config.shcl' account apply 2>&1"
	## It said to check permissions whatever went wrong, and dropped the reason. Windows refuses a
	## write to a folder as access denied, so there the permissions fix is the right one.
	if ((! isWindows)); then
		fAssertOut    "[Erfv8YB] and gives the reason it couldn't"  'Why:  Writing it failed with: is a directory\.' \
			bash -c "cd '${acWork}' && env ${acFragEnv} '${gitsby}' -q -NoFetch --config '${ac}/frag/config.shcl' account apply 2>&1"
		fAssertNotOut "[Erfv8Yu] and doesn't blame permissions for it"  'ermission|writable' \
			bash -c "cd '${acWork}' && env ${acFragEnv} '${gitsby}' -q -NoFetch --config '${ac}/frag/config.shcl' account apply 2>&1"
	fi
	fAssert       "[EnPP5qc] and wrote no includeIf rule either"  bash -c "! grep -q 'bacct\.gitconfig' '${ac}/fraghome/.gitconfig'"
	## The same for the global config itself: a path under a plain file can't be locked for writing.
	mkdir -p "${ac}/addfail"; : > "${ac}/notadir"
	cat > "${ac}/addfail/config.shcl" <<-EOF
		account.b.path      = ${acCanon}/trees/work
		account.b.ghAccount = bacct
	EOF
	local acAddEnv="${acNoDiscovery} HOME='${ac}/fraghome' GIT_CONFIG_GLOBAL='${ac}/notadir/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssertFail   "[Er1LxSt] account apply fails when the global config can't take a rule" \
		bash -c "cd '${acWork}' && env ${acAddEnv} '${gitsby}' -q -NoFetch --config '${ac}/addfail/config.shcl' account apply"
	fAssertOut    "[Er1LxSu] and says which rule it couldn't add"  "Couldn't add 'includeIf\.gitdir" \
		bash -c "cd '${acWork}' && env ${acAddEnv} '${gitsby}' -q -NoFetch --config '${ac}/addfail/config.shcl' account apply 2>&1"
	fAssertNotOut "[Er1LxSv] and never says it is done"  'Done\.' \
		bash -c "cd '${acWork}' && env ${acAddEnv} '${gitsby}' -q -NoFetch --config '${ac}/addfail/config.shcl' account apply 2>&1"

	## The fragment names the account and points at the token file, so it is written 0600 - but
	## os.WriteFile only applies a mode when it CREATES the file, so one left readable by an
	## earlier run stayed that way through every re-apply.
	if ((! isWindows)); then
		fAssert "[EnQsbMK] account apply tightens a fragment left readable by an earlier run" \
			bash -c "chmod 644 '${ac}/home/${confRel}/accounts/github.com_workacct.gitconfig' && cd '${acWork}' && env ${acEnv} '${gitsby}' -q account apply >/dev/null && [[ \"\$(fMode '${ac}/home/${confRel}/accounts/github.com_workacct.gitconfig')\" == 600 ]]"
	fi

	## The sshKey value is concatenated into GIT_SSH_COMMAND and into core.sshCommand, and git hands
	## both to a shell - while the config file itself is redirectable by flag and by environment
	## variable. Dropped and reported, because quietly falling back to whatever key ssh picks is how
	## a push goes out as the wrong person.
	cat > "${ac}/badkey.shcl" <<-EOF
		account.bk.path      = ${acCanon}/trees/work
		account.bk.ghAccount = bkacct
		account.bk.sshKey    = /keys/k; touch ${ac}/pwned
	EOF
	fAssertOut    "[EnPP5qd] an sshKey carrying shell characters is refused"  'Ignored keys \.+:.*sshkey' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/badkey.shcl' account"
	fAssertNotOut "[EnPP5qe] and never becomes this folder's key"  '/keys/k' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/badkey.shcl' account"
	fAssert       "[EnPP5qf] and nothing it named ever ran"  bash -c "[[ ! -e '${ac}/pwned' ]]"

	## An account name becomes a file name under the include directory, so it must not be able to
	## climb out of it. 'account apply' wrote the fragment wherever the name pointed - a name with
	## a couple of '../' in it reached the real '~/.gitconfig' and truncated it.
	cat > "${ac}/traversal.shcl" <<-EOF
		account.ok.path              = ${acCanon}/trees/work
		account.ok.ghAccount         = okacct
		account.../../evil.path      = ${acCanon}/trees/work
		account.../../evil.ghAccount = evilacct
	EOF
	fAssertOut "[EmlOl93] an account name that climbs out of the include dir is refused"  'Ignored keys \.+:.*evil' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/traversal.shcl' account"
	fAssertNotOut "[EmlOl94] and never becomes an account"  'evilacct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/traversal.shcl' account"

	## repo url. A local-path origin has no other spelling, so this needs a github.com one - which
	## is never contacted: every check reads or rewrites the URL and nothing else.
	local ru="${work}/$1-repourl"
	git init --quiet -b main "${ru}"
	( cd "${ru}" && echo a > a.txt && git add --all && git commit --quiet -m init && git remote add origin git@github.com:someone/thing.git )
	fAssertOut "[EmMuR61] repo url shows the current spelling"  'origin \.+: git@github\.com:someone/thing\.git'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url"
	fAssertOut "[EmMuR62] and both alternatives"  'as https \.+: https://github\.com/someone/thing\.git'          bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url"
	fAssertPlan "[EmMuR63] converting plans the set-url"  'git remote set-url origin https://github\.com/someone/thing\.git'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url https"
	fAssert "[EmMuR64] and does it"  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url https >/dev/null && git -C '${ru}' remote get-url origin | grep -qx 'https://github.com/someone/thing.git'"
	fAssertOut "[EmMuR65] re-running says there is nothing to do"  'already uses https'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url https"
	fAssert "[EmMuR66] and back again"  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url ssh >/dev/null && git -C '${ru}' remote get-url origin | grep -qx 'git@github.com:someone/thing.git'"
	## The bare exit code can't tell a refused transport from a build that never heard of 'repo url'
	## - both exit 1 - so the reason is what pins it.
	fAssertFail "[EmMuR67] a transport that isn't one is refused"  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url ftp"
	## Each build names itself in its own syntax lines, so the pattern has to allow both spellings.
	fAssertOut  "[EmZiVeq] and names the two that are"  'Syntax: gitsby(\.ps1)? repo url'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url ftp 2>&1"
	## Whoever reads a Syntax: line just typed the command wrong, so each placeholder is defined under it.
	fAssertOut  "[Eq4W7zV] and says what leaving it off does"  '^  \[https\|ssh\]  +Switches origin .* Without it'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url ftp 2>&1"
	fAssertOut  "[Eq4W7zW] repo clone with no URL defines both of its placeholders"  '^  \[directory\]  +The folder'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo clone 2>&1"
	fAssertOut  "[Eq4W7zX] br hotfix with no name says what the name becomes"  '^ +created as hotfix/<name>'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch br hotfix 2>&1"
	## A remote with no second spelling must say so rather than invent one, and a repo with no
	## remote at all must say that instead of showing an empty one.
	git init --quiet --bare -b main "${ru}-local.git"
	( cd "${acAway}" && git remote add origin "${ru}-local.git" )
	fAssertOut  "[EmMuR68] a non-github origin has no other spelling"  'no other spelling'  bash -c "cd '${acAway}' && '${gitsby}' -q -NoFetch repo url"
	fAssertFail "[EmMwqPY] and converting it is refused"                                    bash -c "cd '${acAway}' && '${gitsby}' -q -NoFetch repo url https"
	fAssertOut  "[EmZiVer] for that reason and not another"  'no other spelling'            bash -c "cd '${acAway}' && '${gitsby}' -q -NoFetch repo url https 2>&1"

	## The nudge to convert. It exists to be seen exactly once per situation that warrants it, so
	## what matters as much as showing it is the two cases where it must stay quiet. Needs a
	## github.com remote inside a matched folder - and a stub ssh, or the identity probe would go
	## to the real github.com. Nothing here contacts anything: every check reads or previews.
	fStub "${ac}/bin/ssh" <<-'EOF'
		#!/usr/bin/env bash
		[[ "$1" == "-G" ]] && { printf 'user git\nhostname github.com\n'; exit 0; }
		exit 255
	EOF
	local acSsh="${ac}/trees/work/sshproj"
	git init --quiet -b main "${acSsh}"
	( cd "${acSsh}" && echo a > a.txt && git add --all && git commit --quiet -m init \
		&& git remote add origin git@github.com:workacct/thing.git )
	fAssertOut "[EmMwqPZ] an ssh remote whose account holds a token is offered the conversion"  "repo url https' switches it"  bash -c "cd '${acSsh}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Was written as a check, but it only ran git - it could not fail and said nothing about gitsby.
	( cd "${acSsh}" && git remote set-url origin https://github.com/workacct/thing.git )
	fAssertNotOut "[EmMwqPa] converting it silences the offer"  "repo url https' switches it"  bash -c "cd '${acSsh}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Saying you want ssh is an answer, and answered advice must stop.
	( cd "${acSsh}" && git remote set-url origin git@github.com:workacct/thing.git )
	echo "account.work.protocol = ssh" >> "${ac}/home/${confRel}/config.shcl"
	fAssertNotOut "[EmMwqPb] and 'protocol = ssh' silences it too"  "repo url https' switches it"  bash -c "cd '${acSsh}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	sed -i.bak '/^account\.work\.protocol/d' "${ac}/home/${confRel}/config.shcl" && rm -f "${ac:?}/home/${confRel}/config.shcl.bak"

	## raw passthrough. The promise is that everything after the tool name reaches it untouched,
	## that stdout is the tool's alone, and that the exit code is the tool's too.
	fAssertOut "[EmMuR69] raw git returns git's own output"  '^main$'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' raw git rev-parse --abbrev-ref HEAD 2>/dev/null"
	fAssertNotOut "[EmMuR6A] and nothing of ours on stdout"  'Account' bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' raw git rev-parse --abbrev-ref HEAD 2>/dev/null"
	fAssertOut "[EmMuR6B] the identity note goes to stderr"  'acting as workacct'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' raw git rev-parse HEAD 2>&1 >/dev/null"
	fAssertNotOut "[EmMuR6C] -q silences it"  'acting as'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git rev-parse HEAD 2>&1 >/dev/null"
	## The flag most likely to be stolen by our own parser, and the one git uses constantly.
	fAssertOut "[EmMuR6D] an option after the tool belongs to the tool"  'acting as'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' raw git log -q --oneline -1 2>&1"
	## Nonzero alone proves nothing here - a build with no 'raw' at all also exits 1 - so what makes
	## these two mean anything is that the failure is git's own and the refusal is ours.
	fAssertFail "[EmMuR6E] the tool's own failure is our exit code"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git rev-parse --verify nosuchref"
	fAssertOut  "[EmZiVes] and the message is git's, not ours"  'Needed a single revision'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git rev-parse --verify nosuchref 2>&1"
	fAssert     "[EmMuR6F] and its success is too"                   bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git rev-parse --verify HEAD >/dev/null"
	fAssertOut  "[EmMuR6G] raw gh reaches gh"  'gho_faketoken'       bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw gh auth token --user workacct"
	fAssertFail "[EmMuR6H] raw with no tool is refused"              bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw"
	fAssertOut  "[EmZiVet] and says what it wanted"  'Syntax: gitsby(\.ps1)? raw'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw 2>&1"
	fAssertOut  "[Eq4W7zY] and what its arguments are"  '^  <arguments \.\.\.>  +Handed to that tool unchanged'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw 2>&1"
	fAssertFail "[EmMuR6I] raw with a tool we don't front is refused" bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw rm -rf /"
	fAssertOut  "[EmMuR6J] and names the two it does"  'One of: git, gh'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw curl x 2>&1"
	## Only the passthrough's own scan runs before 'raw', so an option it didn't take left the main
	## parser looking at a command called 'raw' - and it reported "Unknown command 'raw'", naming
	## the one token that was not the problem. These are inert here; being taken is the point.
	local rawOpt=""
	for rawOpt in "-NoFetch" "-AnyIdentity" "-Public"; do
		fAssertOut "[Emlc0gZ] ${rawOpt} before raw is taken, not blamed"  '^main$' \
			bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q ${rawOpt} raw git rev-parse --abbrev-ref HEAD 2>/dev/null"
	done
	## An option that really is unknown must still be refused - and by its own name.
	fAssertOut "[Emlc0ga] an unknown option before raw names itself"  'bogus' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q --bogus raw git status 2>&1"
	## '--' is git's pathspec separator, so 'raw git log -- path' has to work. Bash takes it
	## directly; PowerShell's binder reads a bare '--' as an empty parameter name and dies before
	## the script runs at all, so there it is spelled '`--' and unescaped on the way to git.
	## Asserted against a path that does NOT exist: a separator that was dropped would still list
	## the commit, so only the empty result proves git actually received one.
	local sep="--"
	fAssertOut    "[Emlc0gb] raw passes a pathspec separator through"  '^init$' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git log --format=%s '${sep}' a.txt 2>/dev/null"
	fAssertNotOut "[Emlc0gc] and it really separates - an absent path lists nothing"  'init' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git log --format=%s '${sep}' nosuchfile.txt 2>/dev/null"

	## How release.bash reads the changelog, which nothing else here reaches. changelog.md opens
	## with a commented-out template whose headings are shaped exactly like real ones, and a
	## first-match search has landed on that decoy three times now. The last one would have
	## retitled the template, left the real section saying vNEXT, published the empty template as
	## the release body, and warned about none of it. Two independent guards, either enough on its
	## own. Pinned in the source because exercising it for real means cutting a release; bash leg
	## only, since neither file belongs to an implementation.
	local relBash="${root}/cicd/release.bash" clMd="${root}/changelog.md"
	fAssertFail "[EmpllxA] the changelog's template heading can't pass for a real one" \
		grep -qE '^## vNEXT - DATE' "${clMd}"
	fAssert "[EmpllxB] and the real vNEXT section is still findable below the template" \
		awk '/^-->/{p=1; next} p && /^## vNEXT$/{n=1} END{exit !n}' "${clMd}"
	fAssert "[EmpllxC] release.bash reads the changelog from past the template" \
		grep -q 'fpChangelogStart' "${relBash}"
	fAssertFail "[EmpllxD] and retitles by line number, not by first match" \
		grep -qE '0,/\^## vNEXT' "${relBash}"
	## The gate is the one thing a release most depends on. There is one engine now, so what
	## has to hold is simply that the release runs it and stops on a failure.
	fAssert "[EmpllxE] release.bash runs the pipeline before touching anything" \
		grep -q 'cicd.bash --no-publish' "${relBash}"
	fAssert "[EmpllxF] and treats a failing pipeline as fatal" \
		grep -q 'the pipeline did not pass' "${relBash}"
	## -y alone is unattended but not quiet, and would print every check line of the phase 1 run.
	# shellcheck disable=SC2016
	fAssert "[Er1LxSw] and release.bash -q runs it quiet" \
		grep -qF '((quiet)) && pipeline=("${here}/cicd.bash" --no-publish -q ' "${relBash}"
	## The footer check read two harnesses once, and three pipeline files went a month without an
	## entry. A footer date is written either way.
	# shellcheck disable=SC2016
	fAssert "[Er1LxSx] release.bash checks the history footer of every pipeline and installer script" \
		grep -qF 'git diff --name-only "${lastTag}" HEAD -- cicd install.bash install.ps1)' "${relBash}"
	local relFootRe=""
	relFootRe="$(sed -n "s/^[[:space:]]*newest=\"\$(grep -oE '\([^']*\)'.*/\1/p" "${relBash}")"
	# shellcheck disable=SC2016
	fAssert "[Er1LxSy] and reads a footer date written 20260819 or 2026-08-19" \
		bash -c '[[ -n "$1" ]] && grep -qE "$1" <<< "$2" && grep -qE "$1" <<< "$3"' _ "${relFootRe}" $'##\t- 20260819 JC: x' $'##\t- 2026-08-19 JC: x'
	if [[ "$(uname -s)" != Linux ]]; then
		echo "  skip: release.bash --dry-run checks (Linux only)"
	else
		## --dry-run end to end, in a clone whose pipeline, build, gh and go are stubs that log. A dry
		## run that took one real step would push, tag or publish, so each step has to be announced in
		## order and none of them may reach a tool. Dated far ahead, so no real footer is newer.
		local rel="${work}/rel" relRc=0 relState="" relStub=""
		local relRepo="${work}/rel/repo" relCalls="${work}/rel/calls.log" relOut="${work}/rel/out.txt"
		mkdir -p "${rel}/bin"
		git init --quiet --bare -b main "${rel}/origin.git"
		git clone --quiet "${rel}/origin.git" "${relRepo}" 2>/dev/null
		mkdir -p "${relRepo}/cicd/utility" "${relRepo}/src-go"
		cp "${root}/cicd/release.bash" "${root}/cicd/config.bash" "${relRepo}/cicd/"
		fStub "${rel}/stub" <<-EOF
			#!/usr/bin/env bash
			printf '%s\n' "\$(basename "\$0") \$*" >> '${relCalls}'
			if [[ "\$(basename "\$0") \${1:-}" == "go env" ]]; then case "\${2:-}" in GOOS) echo linux ;; GOARCH) echo amd64 ;; esac; fi
			exit 0
		EOF
		for relStub in cicd/cicd.bash cicd/utility/gen-winres.bash cicd/utility/gen-checksums.bash src-go/gitsby; do cp "${rel}/stub" "${relRepo}/${relStub}"; done
		for relStub in gh go curl; do cp "${rel}/stub" "${rel}/bin/${relStub}"; done
		printf '%s\n' '# Changelog' '' '<!--' '## TEMPLATE_vNEXT - DATE' '' '- template' '-->' '' '## vNEXT' '' '- a change' '' '## v1.2.3 - 2090-01-01' '' '- older' > "${relRepo}/changelog.md"
		git -C "${relRepo}" add --all
		GIT_COMMITTER_DATE=2090-01-01T12:00:00Z git -C "${relRepo}" commit --quiet -m init
		git -C "${relRepo}" tag v1.2.3
		git -C "${relRepo}" push --quiet -u origin main v1.2.3 2>/dev/null
		relState="$(fRelState)"
		fRelRun --dry-run
		fAssert "[Er1LxSz] release.bash --dry-run passes on a clean, tagged, pushed clone" \
			bash -c "[[ '${relRc}' == 0 ]] && grep -qF 'Dry run done: v1.2.4 was not released' '${relOut}'"
		## It closed by saying the version was tagged, pushed and released, for steps it only announced.
		fAssert "[ErCMBqv] and doesn't claim to have tagged or released anything" \
			bash -c "! grep -qE 'tagged and pushed|Released v1\.2\.4' '${relOut}'"
		fAssert "[Er1LxT0] and announces the pipeline, the cross-build at the next version, the tag and the release, in that order" \
			awk '/would: run cicd\/cicd\.bash --no-publish$/{a=NR} /would: cross-build [0-9]+ targets at v1\.2\.4$/{b=NR} /would: gitsby release v1\.2\.4$/{c=NR} /would: gh release create v1\.2\.4 with /{d=NR} END{exit !(a && a < b && b < c && c < d)}' "${relOut}"
		fAssert "[Er1LxT1] and none of those steps reached a tool" \
			bash -c "grep -qx 'gen-winres.bash --check -q' '${relCalls}' && ! grep -vxE 'gen-winres\.bash --check -q|go env GO(OS|ARCH)' '${relCalls}'"
		fAssert "[Er1LxT2] and HEAD, the tags and origin are as they were"  test "${relState}" = "$(fRelState)"
		fRelRun --dry-run v1.3.0-beta.1
		fAssert "[Er1LxT3] a suffixed version says it publishes as a pre-release" \
			bash -c "[[ '${relRc}' == 0 ]] && grep -qF 'v1.3.0-beta.1 carries a semver suffix, so it publishes as a pre-release.' '${relOut}' && grep -qF 'would: gh release create v1.3.0-beta.1 as a pre-release with ' '${relOut}'"
		## A pipeline file changed since the tag, first with its footer as it was, then with an entry
		## newer than the tag, written the dashed way.
		echo '## fixture' >> "${relRepo}/cicd/config.bash"
		git -C "${relRepo}" add cicd/config.bash
		git -C "${relRepo}" commit --quiet -m 'config edit'
		git -C "${relRepo}" push --quiet 2>/dev/null
		fRelRun --dry-run
		fAssert "[Er1LxT4] a pipeline file changed since the last release with no footer entry is warned about" \
			bash -c "[[ '${relRc}' == 0 ]] && grep -qF 'WARNING: cicd/config.bash has no history entry since v1.2.3 (20900101)' '${relOut}' && ! grep -qF 'WARNING: cicd/release.bash' '${relOut}'"
		printf '##\t\t- 2090-01-02 JC: Fixture.\n' >> "${relRepo}/cicd/config.bash"
		git -C "${relRepo}" add cicd/config.bash
		git -C "${relRepo}" commit --quiet -m 'config footer'
		git -C "${relRepo}" push --quiet 2>/dev/null
		fRelRun --dry-run
		fAssert "[Er1LxT5] and a dashed footer date newer than the tag answers it" \
			bash -c "[[ '${relRc}' == 0 ]] && grep -qF 'Dry run done: v1.2.4 was not released' '${relOut}' && ! grep -qF 'has no history entry' '${relOut}'"
		## Past the dry run. Phase 2 read the PR number through a grep that exits 1 on no match, and
		## under set -e that ended the run before the message written for it. The stub prints no URL.
		: > "${relRepo}/src-go/resource_windows_amd64.syso"
		fStub "${relRepo}/src-go/gitsby" <<-EOF
			#!/usr/bin/env bash
			case "\${2:-}" in
				pr) [[ "\${3:-}" != create ]] || cat '${rel}/pr-url' 2>/dev/null ;;
				release) git tag "\${3:?}" ;;
			esac
			exit 0
		EOF
		git -C "${relRepo}" add --all
		git -C "${relRepo}" commit --quiet -m 'syso and gitsby'
		git -C "${relRepo}" push --quiet 2>/dev/null
		fRelRun -y
		# shellcheck disable=SC2016  ## the inner shell does the expanding.
		fAssert "[Erfs74j] release.bash says so when 'pr create' prints no pull URL" \
			bash -c '[[ "$1" == 1 ]] && grep -qF -- "$2" "$3"' _ "${relRc}" "couldn't read a PR number out of 'pr create' output." "${relOut}"
		git -C "${relRepo}" checkout -q -- .
		## Phase 3, which no dry run reaches. releases/latest can't be reached, and the build's own
		## --version exits 3, and either one ended the run with nothing said. The published binary
		## prints its version and then more than a pipe holds, which a grep -q reading it would
		## cut off, failing the proof under pipefail.
		echo 'https://github.com/yottacore/gitsby/pull/7' > "${rel}/pr-url"
		mkdir -p "${rel}/served"
		printf '#!/usr/bin/env bash\necho "gitsby v1.2.4 (stand-in)"\nprintf "%%0200000d\\n" 0\n' > "${rel}/served/gitsby-linux-amd64"
		(cd "${rel}/served" && sha256sum gitsby-linux-amd64 > SHA256SUMS)
		fStub "${rel}/bin/go" <<-'EOF'
			#!/usr/bin/env bash
			case "${1:-}" in
				env) case "${2:-}" in GOOS) echo linux ;; GOARCH) echo amd64 ;; esac ;;
				build) while (($#)); do [[ "$1" != -o ]] || { printf '#!/usr/bin/env bash\necho "gitsby v1.2.4"\nexit 3\n' > "$2"; chmod +x "$2"; }; shift; done ;;
			esac
			exit 0
		EOF
		fStub "${rel}/bin/curl" <<-EOF
			#!/usr/bin/env bash
			out=""; url=""
			while ((\$#)); do case "\$1" in -o|-w) [[ "\$1" != -o ]] || out="\$2"; shift 2 ;; https://*) url="\$1"; shift ;; *) shift ;; esac; done
			[[ "\${out}" != /dev/null && -f '${rel}/served/'"\${url##*/}" ]] || exit 22
			cp '${rel}/served/'"\${url##*/}" "\${out}"
		EOF
		printf '#!/usr/bin/env bash\nexit 0\n' > "${rel}/bin/sleep"; chmod +x "${rel}/bin/sleep"
		fRelRun -y
		fAssert "[Erfs75a] release.bash phase 3 runs to the end when releases/latest and the build line can't be read" \
			bash -c "[[ '${relRc}' == 0 ]] && grep -qF \"WARNING: releases/latest resolves to '', not v1.2.4.\" '${relOut}' && grep -qF 'Released v1.2.4' '${relOut}'"
		fAssert "[Erfs76S] and its proof reads the whole --version output before matching it" \
			grep -qF 'gitsby-linux-amd64: downloaded, checksum verified, and reports v1.2.4' "${relOut}"
		git -C "${relRepo}" checkout -q -- .
		git -C "${relRepo}" tag -d v1.2.4 >/dev/null
		## A head reading the tag list quit at the first line, and git died writing the rest once
		## the list outgrew a pipe. The same lookup sits in gen-winres.bash.
		seq 1 3000 | awk '{print "create refs/tags/v0.0.1-padpadpadpadpadpadpadpadpadpadpadpadpad." $1 " HEAD"}' | git -C "${relRepo}" update-ref --stdin
		fRelRun --dry-run
		fAssert "[Erfs77J] release.bash finds the last release among thousands of tags" \
			bash -c "[[ '${relRc}' == 0 ]] && grep -qF 'Phase 1 OK: v1.2.3 -> v1.2.4' '${relOut}'"
		git clone --quiet "${relRepo}" "${rel}/winres" 2>/dev/null
		cp "${root}/cicd/utility/gen-winres.bash" "${rel}/winres/cicd/utility/"
		fAssertOut "[Erfs78A] and so does gen-winres.bash" 'gen-winres: no icon at assets/gitsby\.ico' \
			bash "${rel}/winres/cicd/utility/gen-winres.bash" -q
	fi

	## Phase 3 is the build that gets published, and no dry run reaches it. It compiled the working
	## tree while its comment said the tag, which match only when nothing moved since phase 2.
	# shellcheck disable=SC2016  ## the pins are literal source text.
	local relPinExport='archive "${version}^{commit}" | tar -x -C "${tagTree}"' relPinBuild='"${version}^{commit}")" "${tagTree}"'
	# shellcheck disable=SC2016  ## the inner shell does the expanding.
	fAssert "[ErCQl7V] release.bash builds the published bytes from an export of the tag" \
		bash -c 'grep -qF -- "$1" "$3" && grep -qF -- "$2" "$3"' _ "${relPinExport}" "${relPinBuild}" "${root}/cicd/release.bash"

	## Recursive removal. demo-repo.bash is the only script here that removes a path someone else
	## named, so it gets real checks; the rest only ever remove what mktemp just handed them, and
	## that is pinned in the source. None of these files belong to an implementation, which is why
	## they outlived the leg they used to ride. A Ctrl-C mid-probe can't be staged on every platform
	## (a native child defers the signal), so the probe's own cleanup is asserted where it lives.
	## The single quotes in the searches below are the point - they look for literal source text,
	## so each one turns off the expansion warning for itself.
	local demoRepo="${root}/cicd/utility/demo/demo-repo.bash" rmWork="${work}/rmsafe"
	mkdir -p "${rmWork}/notmine/keep"; echo keepme > "${rmWork}/notmine/keep/file.txt"
	## On the message, not just the exit code: a build that refuses for some unrelated reason
	## later on exits nonzero too, and two of these passed against the unguarded script on
	## that alone.
	fAssertFail "[Emq7Y6q] demo-repo refuses a root it did not build" \
		bash "${demoRepo}" "${rmWork}/notmine"
	fAssertOut  "[Emq7Y6r] and says whose directory it is" 'did not build it' \
		bash "${demoRepo}" "${rmWork}/notmine"
	fAssertOut  "[Emq7Y6s] and leaves that directory untouched" '^keepme$' \
		cat "${rmWork}/notmine/keep/file.txt"
	fAssertOut  "[Emq7Y6t] demo-repo refuses a relative root"      'plain absolute path' \
		bash "${demoRepo}" relative/path
	fAssertOut  "[Emq7Y6u] demo-repo refuses a root containing .." 'plain absolute path' \
		bash "${demoRepo}" "${rmWork}/a/../b"
	## Deliberately NOT run: passing '/' to a build that lacks the guard is 'rm -rf /'. It is
	## one clause of the same test the two checks above exercise for real, so it is pinned.
	# shellcheck disable=SC2016
	fAssert "[Emq7Y6v] and the same test rejects the filesystem root" \
		grep -qF '"${root}" != "/"' "${demoRepo}"
	fAssert "[Emq7Y6w] the publish probe's dir is removed on the way out, not only in the happy path" \
		grep -q '_probeDir' "${root}/legacy/bin/gitsby"
	# shellcheck disable=SC2016
	fAssert "[Emq7Y6x] and its pwsh counterpart tests the path before removing it" \
		grep -q 'if ($probeDir) { Remove-Item' "${root}/legacy/bin/gitsby.ps1"
	## By glob, so a script added later is covered without being listed. A glob that stopped
	## matching is left as written, and fails for not being a file.
	local rmScript
	local -a rmScripts=()
	for rmScript in "${root}"/install.bash "${root}"/cicd/*.bash "${root}"/cicd/utility/*.bash \
	                "${root}"/cicd/utility/include/*.bash "${root}"/cicd/utility/n8git_backup-and-publish "${root}"/cicd/utility/demo/*.bash \
	                "${root}"/legacy/bin/gitsby "${root}"/legacy/install.bash "${root}"/legacy/install-dev.bash; do
		rmScripts+=("${rmScript#"${root}/"}")
	done
	# shellcheck disable=SC2016  ## the inner shell does the expanding.
	for rmScript in "${rmScripts[@]}"; do
		fAssert "[Emq7Y6y] ${rmScript} never removes an unguarded variable path" \
			bash -c '[[ -f "$1" ]] && ! grep -qE "$2" "$1"' _ "${root}/${rmScript}" 'rm -[rf]+ +(-- )?"\$\{[a-zA-Z_][a-zA-Z_0-9]*\}'
	done
	## ------------------------------------------------------------------------------------
	## The pipeline itself, after the directive review. Where a check would need a whole run
	## to exercise, it pins the thing in the source and says so.

	## Version-control stamps go into a Go binary by default, and the release builds its assets
	## before it cuts the tag - so the published binaries carried the previous revision and
	## nobody, us included, could rebuild them to the checksums we publish.
	fAssert "[EnQTPxo] the build flags keep version control out of the binary" \
		bash -c "grep -q 'buildvcs=false' '${root}/cicd/config.bash'"
	## Built here rather than read off the suite's own binary: that one may have come from a
	## hand-run 'go build', which legitimately carries the stamps.
	fAssert "[EnQTPxp] and a build with them carries no revision stamp" \
		bash -c "cd '${root}/src-go' && go build -trimpath -buildvcs=false -o '${work}/vcsprobe' . && ! go version -m '${work}/vcsprobe' | grep -q 'vcs\.revision'"
	## The build number is minutes since 2000, Crockford base32, lower case. Built here with a
	## fixed stamp: the suite's own binary carries whatever the last build gave it.
	fAssertOut "[Eo59IMf] a stamped build reports minutes since 2000 in Crockford base32"  '^gitsby v9\.9\.9 build dbd05$' \
		bash -c "cd '${root}/src-go' && go build -ldflags '-X main.version=9.9.9 -X main.buildEpoch=1787000000' -o '${work}/bnprobe' . && '${work}/bnprobe' --version"
	## A number invented from the clock would say the opposite of what a build number means, so
	## an unstamped build reports none rather than one that moves every minute.
	fAssertOut "[Eo59IMg] an unstamped build reports no build number"  '^gitsby v9\.9\.9$' \
		bash -c "cd '${root}/src-go' && go build -ldflags '-X main.version=9.9.9' -o '${work}/bnprobe0' . && '${work}/bnprobe0' --version"
	fAssertOut "[Epywvo0] and the copyright has a line of its own"  '^Copyright © [0-9-]+ Jim Collier\.$' \
		bash -c "'${work}/bnprobe0' --version"
	## release.bash reads the build line back out of the banner for the release notes, and used
	## to cut it at the comma that came before the copyright.
	fAssertFail "[Epywvo1] and release.bash no longer cuts the build line at a comma" \
		grep -qF "v[^,]*" "${root}/cicd/release.bash"
	## Taken from the commit rather than the clock, or a published asset could never be rebuilt
	## to its published checksum - the same reason -buildvcs=false is above.
	fAssert "[Eo59IMh] every build site stamps a build number" \
		bash -c "[[ \"\$(grep -c 'main.buildEpoch=' '${root}/cicd/cicd.bash' '${root}/cicd/release.bash' | awk -F: '{t+=\$2} END{print t}')\" == 4 ]]"
	fAssert "[Eo59IMi] the build number comes from the commit, not the clock" \
		bash -c "grep -q 'log -1 --format=%ct' '${root}/cicd/cicd.bash' '${root}/cicd/release.bash'"
	## Phase 1 proves every target still compiles; phase 3 rebuilds them once the tag exists, and
	## those are the bytes that get uploaded. Without the second build the published build number
	## would belong to a commit the tag does not point at.
	fAssert "[Eo59IMj] the release rebuilds its assets from the tagged commit" \
		bash -c "[[ \"\$(grep -c 'fpCrossBuild ' '${root}/cicd/release.bash')\" == 2 ]]"
	fAssert "[Eo59IMk] and the release notes carry the build number" \
		bash -c "grep -q 'buildLine' '${root}/cicd/release.bash'"
	fAssert "[EnQTPxq] every build site shares one set of flags" \
		bash -c "[[ \"\$(grep -c 'GO_BUILD_FLAGS\[@\]' '${root}/cicd/cicd.bash' '${root}/cicd/release.bash' | awk -F: '{t+=\$2} END{print t}')\" == 4 ]]"
	## The compiler takes every core by default, in every build and in the eight-target
	## release loop, which makes the machine unusable for the duration.
	fAssert "[EnQTPxr] no build step takes every core"  bash -c "grep -q 'BUILD_JOBS=' '${root}/cicd/config.bash'"
	fAssertFail "[EnQTPxs] no go build call is missing -p" \
		bash -c "grep -hE '^[[:space:]]*(go build|.*&& *go build)' '${root}/cicd/cicd.bash' '${root}/cicd/release.bash' | grep -qv 'BUILD_JOBS'"
	## Same source, same bytes: the last input-derived stamp dropped, cgo off wherever those flags
	## link, and the release built by the compiler it names.
	fAssert "[Er1LxT6] the link flags drop the build id"  grep -qE '^GO_LDFLAGS_COMMON=.*-buildid=' "${root}/cicd/config.bash"
	fAssert "[Er1LxT7] and every build that links with them turns cgo off" \
		bash -c "cgo=\$(cat '${root}/cicd/cicd.bash' '${root}/cicd/release.bash' | grep -v '^[[:space:]]*#' | grep -c 'CGO_ENABLED=0'); ld=\$(cat '${root}/cicd/cicd.bash' '${root}/cicd/release.bash' | grep -v '^[[:space:]]*#' | grep -c 'GO_LDFLAGS_COMMON'); [[ \${ld} -gt 0 && \${cgo} == \${ld} ]]"
	# shellcheck disable=SC2016
	fAssert "[Er1LxT8] and the release assets are built by the pinned toolchain" \
		grep -qF 'GOTOOLCHAIN="${GO_RELEASE_TOOLCHAIN}"' "${root}/cicd/release.bash"
	## Every dogfood dest is a share path or a $HOME expansion. A literal home dir would name
	## an account, and would resolve to nothing on any other box.
	fAssertFail "[Eo67ohk] no dogfood dest hardcodes a home directory" \
		bash -c "grep -qE '\"(/home/|/Users/|C:/Users/)' '${root}/cicd/config.bash'"
	## A .exe would match a Linux ~/.local/bin every run, so the fallback is per-box.
	fAssert "[Eo67ohl] the dogfood fallback only applies to this box's own target" \
		bash -c "grep -q 'DOGFOOD_FALLBACK_DIR' '${root}/cicd/config.bash' && grep -q 'host_goos' '${root}/cicd/cicd.bash'"
	## --quick skips the fuzz and the gif, which are not the slow part; three cross-builds are.
	fAssert "[EnQTPxt] --quick narrows the cross-builds too" \
		bash -c "grep -q 'quick).*DOGFOOD_TARGETS=' '${root}/cicd/cicd.bash'"
	## With no third-party dependencies the standard library is the only library code there is.
	fAssert "[EnQTPxu] the pipeline checks the standard library for known problems" \
		bash -c "grep -q 'govulncheck' '${root}/cicd/cicd.bash'"
	## The profiling step. A sampling profile would be a flat wall here - this program is
	## blocked on git for all of its wall clock - so what gets measured is how often it forks.
	fAssert "[EnQTPxv] a spawn-count step exists and gates" \
		bash -c "[[ -x '${root}/cicd/utility/spawn-count.bash' ]] && grep -q 'SPAWN_COUNT_CMD' '${root}/cicd/cicd.bash'"
	fAssert "[EnQTPxw] and a kept-build script exists for bisecting against an older one" \
		bash -c "[[ -x '${root}/cicd/utility/keep-build.bash' ]]"
	fAssert "[EndUdZQ] and a pooled-copy runner exists for driving the newest build" \
		bash -c "[[ -x '${root}/cicd/utility/run-latest.ps1' ]]"
	fAssert "[EndUdZR] and a spawn report exists for the startup look, marker-gated like lint's" \
		bash -c "[[ -x '${root}/cicd/utility/spawn-report.bash' ]] && grep -q 'spawn-seen' '${root}/cicd/utility/spawn-report.bash'"
	## A head reading the sorted list quit after two lines, and sort died writing the rest once
	## the list outgrew a pipe.
	mkdir -p "${work}/spawnmany"
	(cd "${work}/spawnmany" && touch spawn_20260101-{000001..001000}_padpadpadpadpadpadpadpadpadpadpadpad.tsv)
	fAssertOut "[Erfs79u] and it reads a folder of many recordings"  '^COUNTS spawn_20260101-001000_' \
		bash "${root}/cicd/utility/spawn-report.bash" --dir "${work}/spawnmany"
	## A count is used in arithmetic, which runs a $(...) inside the subscript of any array that is
	## set. One folder has that in its newest recording and one in the recording before, and each
	## has to be refused.
	local srBad="${work}/spawnbad"
	mkdir -p "${srBad}/newest" "${srBad}/previous"
	printf 'status\t5\n' > "${srBad}/newest/spawn_20260101-000001.tsv"
	printf 'status\t5\n' > "${srBad}/previous/spawn_20260101-000002.tsv"
	# shellcheck disable=SC2016  ## The fixture's own substitution, left for the script to refuse.
	printf 'status\tBASH_VERSINFO[$(touch %s/ran)0]\n' "${srBad}/newest" > "${srBad}/newest/spawn_20260101-000002.tsv"
	# shellcheck disable=SC2016
	printf 'status\tBASH_VERSINFO[$(touch %s/ran)0]\n' "${srBad}/previous" > "${srBad}/previous/spawn_20260101-000001.tsv"
	fAssert "[ErfzUGl] and refuses a count that isn't a number, without running it" \
		bash -c "out=\$('${root}/cicd/utility/spawn-report.bash' --dir '${srBad}/newest' 2>&1); [[ \$? == 1 ]] && grep -qF \"spawn_20260101-000002.tsv has 'BASH_VERSINFO[\" <<< \"\$out\" && [[ ! -e '${srBad}/newest/ran' ]]"
	fAssert "[ErfzUH0] and in the recording it compares against" \
		bash -c "out=\$('${root}/cicd/utility/spawn-report.bash' --dir '${srBad}/previous' 2>&1); [[ \$? == 1 ]] && grep -qF \"spawn_20260101-000001.tsv has 'BASH_VERSINFO[\" <<< \"\$out\" && [[ ! -e '${srBad}/previous/ran' ]]"
	## One macOS dogfood folder serves Macs of both CPUs, so the build there is universal. The
	## fixtures are only a Mach-O header and a few bytes, which is all the joiner reads.
	local fatDir="${work}/macho" fatJoin="${root}/cicd/utility/macho-universal.bash"
	mkdir -p "${fatDir}"
	printf '%b' '\xcf\xfa\xed\xfe\x07\x00\x00\x01\x03\x00\x00\x00AMD' > "${fatDir}/amd64"
	printf '%b' '\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00ARM' > "${fatDir}/arm64"
	printf 'ELF' > "${fatDir}/elf"
	fAssert "[ErfYFr8] macho-universal.bash joins two Mac builds, each whole on its own 16 KiB boundary" \
		bash -c "'${fatJoin}' '${fatDir}/fat' '${fatDir}/amd64' '${fatDir}/arm64' \
			&& [[ \"\$(od -An -tx1 -N48 '${fatDir}/fat' | xargs)\" == 'ca fe ba be 00 00 00 02 01 00 00 07 00 00 00 03 00 00 40 00 00 00 00 0f 00 00 00 0e 01 00 00 0c 00 00 00 00 00 00 80 00 00 00 00 0f 00 00 00 0e' ]] \
			&& [[ \$(wc -c < '${fatDir}/fat') -eq 32783 ]] \
			&& tail -c +16385 '${fatDir}/fat' | head -c 15 | cmp -s - '${fatDir}/amd64' \
			&& tail -c +32769 '${fatDir}/fat' | cmp -s - '${fatDir}/arm64'"
	fAssertOut "[ErfYFrL] and refuses a build that is not 64-bit Mach-O" 'not a 64-bit Mach-O build' \
		"${fatJoin}" "${fatDir}/bad" "${fatDir}/amd64" "${fatDir}/elf"
	fAssertOut "[ErfYFrY] and two builds for one CPU" 'two builds for one CPU' \
		"${fatJoin}" "${fatDir}/bad" "${fatDir}/arm64" "${fatDir}/arm64"
	fAssert "[ErfYFrl] dogfood builds macOS universal, and joins it with that script" \
		bash -c "grep -q '^[[:space:]]*\"darwin/universal\"' '${root}/cicd/config.bash' && grep -q 'macho-universal\.bash' '${root}/cicd/cicd.bash' && [[ ! -e '${fatDir}/bad' ]]"
	## The mode a clone gets, not the one this tree happens to have: a local chmod hid release.bash
	## going out without its executable bit. Every script runs by path but the ones only sourced.
	fAssert "[ErCM5cg] every script that runs by path is committed executable" \
		bash -c "cd '${root}' && git ls-files -s -- '*.bash' '*.ps1' ':!legacy/' ':!cicd/config.bash' ':!cicd/utility/include/' | awk '\$1 != \"100755\" { bad = 1; print \$4 } END { exit bad }'"
	## What a contributor's machine drops beside the files, and nothing the repo tracks.
	fAssert "[ErCRneY] .gitignore covers OS and editor leftovers, and no tracked file" \
		bash -c "cd '${root}' && git check-ignore -q --no-index .DS_Store && git check-ignore -q --no-index .vscode/x && git check-ignore -q --no-index src-go/x.swp && git check-ignore -q --no-index src-go/gitsby.test && [[ -z \"\$(git ls-files -ci --exclude-standard)\" ]]"
	## A badge the repo grants itself asserts nothing outside the README. Apart from the license
	## and the sponsor links, each one reads what it shows from the repo, the Go version included.
	fAssert "[ErCP9Yz] the README's badges read what they show from the repo" \
		bash -c "grep -q 'shields\.io/github/go-mod/go-version/yottacore/gitsby?filename=src-go%2Fgo\.mod' '${root}/README.md' && ! grep 'img\.shields\.io/badge/' '${root}/README.md' | grep -vE 'badge/(License|Sponsor|Ko--fi)-'"
	## The step itself, against a build that starts three processes per command and a baseline
	## that says none, so every command reads as a rise. Needs strace, like the step. The stub
	## names its shell by path: env would try each PATH entry in turn, and every try is counted,
	## so its count would follow PATH and could pass the lowest limit.
	if command -v strace >/dev/null 2>&1; then
		local sc="${work}/sc"
		mkdir -p "${sc}/cicd/utility/include" "${sc}/src-go" "${sc}/cicd/artifacts/spawn"
		cp "${root}/cicd/config.bash" "${sc}/cicd/"
		cp "${root}/cicd/utility/spawn-count.bash" "${sc}/cicd/utility/"
		cp "${root}/cicd/utility/include/gfs-rotate.bash" "${sc}/cicd/utility/include/"
		fStub "${sc}/src-go/gitsby" <<-'EOF'
			#!/bin/sh
			/bin/sh -c :; /bin/sh -c :; /bin/sh -c :
		EOF
		sed -n 's/^fMeasure "\[[^]]*\] \([^"]*\)".*/\1\t0/p' "${root}/cicd/utility/spawn-count.bash" > "${sc}/cicd/artifacts/spawn/spawn_20260101-000000.tsv"
		fAssert "[Er1LxT9] spawn-count.bash fails on a command that starts more than its baseline, and records nothing" \
			bash -c "out=\$('${sc}/cicd/utility/spawn-count.bash' -q 2>&1); [[ \$? == 1 ]] && grep -qE 'REGRESSED  \[[0-9A-Za-z]{7}\] status: 0 -> ' <<< \"\$out\" && [[ \$(ls '${sc}/cicd/artifacts/spawn' | grep -c '^spawn_.*\.tsv\$') == 1 ]]"
		fAssert "[Er1LxTA] and --record accepts the rise as the new baseline" \
			bash -c "'${sc}/cicd/utility/spawn-count.bash' -q --record && [[ \$(ls '${sc}/cicd/artifacts/spawn' | grep -c '^spawn_.*\.tsv\$') == 2 ]]"
		fAssert "[Er2gqb3] and without -q prints a verdict and test ID for every command, unchanged ones too" \
			bash -c "out=\$('${sc}/cicd/utility/spawn-count.bash' 2>&1) && [[ \$(grep -cE '^  ok +\[[0-9A-Za-z]{7}\] [a-z ]+: [0-9]+\$' <<< \"\$out\") == \$(grep -c '^fMeasure \"' '${root}/cicd/utility/spawn-count.bash') ]]"
		## A limit is the number in the source, so --record can't lift it. A copy with one limit
		## under the stub's four processes.
		sed 's/^\(fMeasure "\[EnQTUO0\] status" *\)[0-9][0-9]*/\11/' "${root}/cicd/utility/spawn-count.bash" > "${sc}/cicd/utility/spawn-count-low.bash"
		chmod +x "${sc}/cicd/utility/spawn-count-low.bash"
		fAssert "[Erg2KNK] and fails a count over its limit, --record or not, and records nothing" \
			bash -c "was=\$(ls '${sc}/cicd/artifacts/spawn'); out=\$('${sc}/cicd/utility/spawn-count-low.bash' -q --record 2>&1); [[ \$? == 1 ]] && grep -qE '^  OVER LIMIT \[EnQTUO0\] status: [0-9]+, limit 1\$' <<< \"\$out\" && ! grep -q 'OVER LIMIT \[EnberSa\]' <<< \"\$out\" && [[ \$(ls '${sc}/cicd/artifacts/spawn') == \"\$was\" ]]"
		## The baseline's counts go into arithmetic, as the report's do.
		# shellcheck disable=SC2016  ## As above, for the script to refuse.
		printf 'status\tBASH_VERSINFO[$(touch %s/ran)0]\n' "${sc}" > "${sc}/cicd/artifacts/spawn/spawn_20991231-000000.tsv"
		fAssert "[ErfzUHF] and refuses a baseline count that isn't a number, without running it or recording" \
			bash -c "was=\$(ls '${sc}/cicd/artifacts/spawn'); out=\$('${sc}/cicd/utility/spawn-count.bash' -q 2>&1); [[ \$? == 1 ]] && grep -qF \"spawn_20991231-000000.tsv has 'BASH_VERSINFO[\" <<< \"\$out\" && [[ ! -e '${sc}/ran' ]] && [[ \$(ls '${sc}/cicd/artifacts/spawn') == \"\$was\" ]]"
	else
		echo "  skip: spawn-count regression checks (no strace)"
	fi
	## -q reached the publisher and nothing else, so an unattended run still printed every one
	## of 900-odd check lines and buried every stage header.
	local qHarness=""
	for qHarness in test fuzz parity; do
		fAssert "[EnQTPxx] cicd/${qHarness}.bash accepts -q"  bash -c "grep -q -- '-q|--quiet) quiet=1' '${root}/cicd/${qHarness}.bash'"
	done
	fAssert "[EnQTPxy] and the engine hands it on"  bash -c "grep -q 'harness_quiet' '${root}/cicd/cicd.bash'"
	## The lint summary matched the suites' own check labels - several of which contain the
	## words "warning" and "error", because that is what those checks are about.
	local lrLog="${work}/lint-report"; mkdir -p "${lrLog}"
	{
		echo "  ok: and raises no shell error of its own"
		echo "  ok: the offline warning names its branch"
		echo "[ OK: gofmt + go vet clean ]"
		echo "passed: 649, failed: 0"
	} > "${lrLog}/run_20260819-000000.log"
	fAssertOut "[EnQTPxz] the lint summary calls a clean run clean"  'CLEAN' \
		bash -c "'${root}/cicd/utility/lint-report.bash' --file '${lrLog}/run_20260819-000000.log'"
	fAssertOut "[EnQTPy0] and still reports a real finding"  'warning line' \
		bash -c "printf 'file.sh:3:1: SC2086 warning: quote this\n' > '${lrLog}/run_20260819-000001.log'; '${root}/cicd/utility/lint-report.bash' --file '${lrLog}/run_20260819-000001.log'"
	## Then it matched the publish stage's archive listing, which names src-go/errors.go.
	fAssertOut "[Epywvo2] and a file named errors in the archive listing is not a finding"  'CLEAN' \
		bash -c "printf 'Adding    .././github/src-go/errors.go     7%%  OK \nall errors reported\n' > '${lrLog}/run_20260819-000002.log'; '${root}/cicd/utility/lint-report.bash' --file '${lrLog}/run_20260819-000002.log'"
	## One line in each tool's format, so narrowing the match can't quietly drop a tool.
	{
		echo "[ WARNING: staticcheck skipped (not installed) ]"
		echo "  ^-- SC2086 (info): Double quote to prevent globbing and word splitting."
		echo "README.md:12:3 MD009/no-trailing-spaces Trailing spaces"
		echo "./main.go:12:3: printf format %d has arg of wrong type"
		echo "Vulnerability #1: GO-2025-3750"
		echo "PSAvoidUsingWriteHost  Warning   install.ps1  12  File uses Write-Host."
		echo '  File "cicd/utility/demo/gen-demo-gif.py", line 12'
	} > "${lrLog}/run_20260819-000003.log"
	fAssertOut "[Epywvo3] and each tool's own format is reported"  '\(7 warning line' \
		bash -c "'${root}/cicd/utility/lint-report.bash' --file '${lrLog}/run_20260819-000003.log'"
	## The backlog gate, the real script in a repo of its own with no integration branch, so only
	## the Origin rule runs. Its count read 0 whatever the backlog held: '\t' in a quoted -E
	## pattern is not a tab.
	local bl="${work}/bl"
	mkdir -p "${bl}/cicd/utility" "${bl}/project"
	cp "${root}/cicd/utility/backlog-check.bash" "${bl}/cicd/utility/"
	git init --quiet "${bl}"
	printf '# Backlog\n\n## Open\n\n\t- 🔘 Code Review 20260101 item 1: x\n\t\t- Origin: y\n\t- 🔘 Code Review 20260101 item 2: x\n\t\t- Origin: y\n\t- ✅ Code Review 20260101 item 3: x\n\t\t- Origin: y\n' > "${bl}/project/backlog.md"
	printf '# Backlog\n\n\t- 🔘 Code Review 20260101 item 1: x\n\t\t- Origin: y\n\t- 🔘 Code Review 20260101 item 4: x\n\t\t- Why: z\n' > "${bl}/project/no-origin.md"
	fAssertOut "[Er1LxTB] the backlog gate counts the open review items it read" 'Origin: present on every open review item \(2 listed\)' \
		"${bl}/cicd/utility/backlog-check.bash"
	fAssertOut "[Er1LxTC] and skips the removed-check rule with no integration branch" 'no integration branch found; removed-check test skipped' \
		"${bl}/cicd/utility/backlog-check.bash"
	fAssert "[Er1LxTD] and fails an open review item with no Origin line, by name" \
		bash -c "out=\$('${bl}/cicd/utility/backlog-check.bash' -q --backlog '${bl}/project/no-origin.md' 2>&1); [[ \$? == 1 ]] && grep -qxF '  Code Review 20260101 item 4' <<< \"\$out\" && ! grep -qF 'item 1' <<< \"\$out\""
	## The new item format: a top-level title with its rows a tab in, open by its Status row. The
	## gate read only the old one, so a round filed this way was never checked.
	printf '# Backlog\n\n## Issues\n\n- Code Review 20260102 item 1: x\n\t- Status: Waiting on signoff\n\t- Origin: y\n\n- Code Review 20260102 item 2: x\n\t- Status: Queued\n\t- Why: z\n\n- Code Review 20260102 enhancement 3: x\n\t- Status: Done\n\n- Code Review 20260102 item 4: x\n\t- Status: Moot\n\n- Code Review 20260102 item 5: x\n\t- Status: Canceled\n\n- Code Review 20260102 item 6: x\n\t- Status: Deferred\n\n- Another item\n\t- Status: Queued\n\n## Old format\n\n\t- 🔘 Code Review 20260101 item 1: x\n\t\t- Origin: y\n' > "${bl}/project/new-format.md"
	fAssertOut "[Erg0LJv] and counts open review items in the new format too" 'Origin: present on every open review item \(3 listed\)' \
		bash -c "sed '/item 2: x/,/Why: z/ s/Why: z/Origin: y/' '${bl}/project/new-format.md' > '${bl}/project/new-format-ok.md' && '${bl}/cicd/utility/backlog-check.bash' --backlog '${bl}/project/new-format-ok.md'"
	fAssert "[Erg0LK9] and fails an open one with no Origin row, by name, leaving the closed ones be" \
		bash -c "out=\$('${bl}/cicd/utility/backlog-check.bash' -q --backlog '${bl}/project/new-format.md' 2>&1); [[ \$? == 1 ]] && [[ \$(grep -c '^  ' <<< \"\$out\") == 1 ]] && grep -qxF '  Code Review 20260102 item 2' <<< \"\$out\""
	## A test is known by its ID, so a new label on an old ID is an edit. The fixture lines spell
	## the check names through %s, or the ID gate below would read them as checks of this file.
	local bi="${work}/bl-ids" chk=fAssert
	mkdir -p "${bi}/cicd/utility" "${bi}/project"
	cp "${root}/cicd/utility/backlog-check.bash" "${bi}/cicd/utility/"
	git init --quiet -b gover "${bi}"
	printf '%s "[AAAAAAA] one" true\n%s "[AAAAAAB] two" true\n' "${chk}" "${chk}" > "${bi}/cicd/test.bash"
	printf '# Backlog\n' > "${bi}/project/backlog.md"
	( cd "${bi}" && git add --all && git commit --quiet -m base && git checkout --quiet -b feat )
	sed -i.bak 's/\[AAAAAAA\] one/[AAAAAAA] one, reworded/' "${bi}/cicd/test.bash" && rm -f "${bi:?}/cicd/test.bash.bak"
	fAssertOut "[Er2NSAQ] the backlog gate reads a relabeled check as edited, by its ID"  '\(0 removed since gover\)' \
		"${bi}/cicd/utility/backlog-check.bash"
	sed -i.bak '/AAAAAAB/d' "${bi}/cicd/test.bash" && rm -f "${bi:?}/cicd/test.bash.bak"
	fAssertOut "[Er2NSAe] and still fails one that was removed"  '^  "\[AAAAAAB\] two"$' \
		"${bi}/cicd/utility/backlog-check.bash"
	echo 'AAAAAAB went with the command it tested.' >> "${bi}/project/backlog.md"
	fAssertOut "[Er2NdiI] and passes once the backlog names it by ID"  '\(1 removed since gover\)' \
		"${bi}/cicd/utility/backlog-check.bash"
	## Every check and Go test carries an ID, dated from when it was written, and no two share one.
	fAssert "[Er2NS9j] every suite check and Go test carries its own ID"  "${root}/cicd/utility/test-id.bash" --check -q
	local ti="${work}/test-id" ok=fOk no=fFail
	mkdir -p "${ti}/cicd" "${ti}/src-go"
	printf '%s "[AAAAAAA] has one" true\n%s "no id" true\n%s "[AAAAAAA] the same one again" true\n' "${chk}" "${chk}" "${chk}" > "${ti}/cicd/test.bash"
	# shellcheck disable=SC2016  ## The fixture's own variable, left for it.
	printf 'if true; then %s "[AAAAAAC] a pair"; else %s "[AAAAAAC] a pair, failed"; fi\n%s "${desc}"\n' "${ok}" "${no}" "${ok}" >> "${ti}/cicd/test.bash"
	printf 'func TestNoID(t *testing.T) {\n}\nfunc TestHasID(t *testing.T) { // [AAAAAAD]\n}\n' > "${ti}/src-go/x_test.go"
	fAssert "[Er2NS9x] and fails a tree where one is missing or shared, naming each" \
		bash -c "out=\$('${root}/cicd/utility/test-id.bash' --check -q --root '${ti}' 2>&1); [[ \$? == 1 ]] && grep -qxF '  cicd/test.bash:2' <<< \"\$out\" && grep -qxF '  src-go/x_test.go:1' <<< \"\$out\" && grep -qxF '  AAAAAAA: cicd/test.bash:1 cicd/test.bash:3' <<< \"\$out\" && ! grep -qE 'AAAAAAC|test\.bash:5|x_test\.go:3' <<< \"\$out\""
	fAssertOut "[ErTFcXs] an ID minted for now is seven characters of base 62"  '^[0-9A-Za-z]{7}$' \
		"${root}/cicd/utility/test-id.bash"
	## --at reads its date with GNU date, which BSD userlands don't have.
	if date -u -d @0 >/dev/null 2>&1; then
		fAssertOut "[Er2NSAB] a minted ID is milliseconds since 2000 in base 62"  '^10$' \
			"${root}/cicd/utility/test-id.bash" --at '2000-01-01 00:00:00.062 UTC'
		## A date before 1970 is a negative count, which bash arithmetic refused by skipping ahead
		## into --check and passing.
		fAssert "[Er2PEtf] and a date before 2000 is refused, not checked" \
			bash -c "out=\$('${root}/cicd/utility/test-id.bash' --at 1960-01-01 2>&1); [[ \$? == 2 ]] && grep -qx 'test-id: 1960-01-01 is before 2000' <<< \"\$out\""
	fi
	fAssert "[Er2PEtt] the ID check fails a tree where it finds no tests" \
		bash -c "out=\$('${root}/cicd/utility/test-id.bash' --check --root '${work}/no-such-tree' 2>&1); [[ \$? == 1 ]] && grep -q '^test-id: found no tests under ' <<< \"\$out\""
	## A file no glob names is linted by nothing, and a glob that names nothing is a file that moved.
	fAssert "[Er1LxTE] every tracked markdown file is in a markdown lint glob" \
		test -z "$(cd "${root}" && git ls-files '*.md' | fLintUncovered MD_LINT_GLOBS)"
	fAssert "[Er1LxTF] every tracked bash file outside legacy/ is in a shell lint glob" \
		test -z "$(fTrackedBash | fLintUncovered SHELL_LINT_GLOBS)"
	fAssert "[Er1LxTG] the PowerShell lint globs name exactly the first-party .ps1 files" \
		test -z "$(cd "${root}" && git ls-files '*.ps1' ':!legacy' | fLintUncovered PS_LINT_GLOBS both)"
	fAssert "[Er1LxTH] and every lint glob matches a file" \
		test -z "$(fLintGlobs MD_LINT_GLOBS empty; fLintGlobs SHELL_LINT_GLOBS empty; fLintGlobs PS_LINT_GLOBS empty)"
	## Bash 4.4 is the floor the style guide sets. install.bash runs on 3.2 on purpose, a file the
	## others source needs no check of its own, and the publish helper is shared and left as it is.
	local bfScript="" bfFound=0
	while IFS= read -r bfScript; do
		case "${bfScript}" in install.bash|cicd/config.bash|cicd/utility/include/*|cicd/utility/n8git_backup-and-publish) continue ;; esac
		bfFound=$((bfFound + 1))
		fAssert "[ErfyDHs] ${bfScript} refuses a bash older than 4.4, before anything else"  fBashFloorRefuses "${bfScript}"
	done < <(fTrackedBash)
	fAssertFail "[ErfyLds] and that check found scripts to look at"  test "${bfFound}" = 0
	## A commit message the user typed passes through the engine's output helpers.
	fAssertFail "[Er1LxTI] cicd.bash prints with printf, never echo -e"  grep -qE '^[^#]*echo -e' "${root}/cicd/cicd.bash"
	## The linter set is argued for line by line, and 'default: none' means a new golangci-lint
	## adds nothing on its own. The stub the gate runs cannot tell a linter dropped from the file.
	local lintYml="${root}/src-go/.golangci.yml" lintName=""
	fAssert "[Er1LxTJ] golangci-lint runs only the linters it names"  grep -qE '^  default: none( |$)' "${lintYml}"
	for lintName in errcheck errorlint govet ineffassign predeclared revive staticcheck unconvert unused; do
		fAssert "[Er1LxTK] and ${lintName} is one of them"  grep -qE "^    - ${lintName}( |\$)" "${lintYml}"
	done
	for lintName in var-naming redefines-builtin-id indent-error-flow errorf error-return early-return unreachable-code; do
		fAssert "[Er1LxTL] and revive checks ${lintName}"  grep -qE "^        - name: ${lintName}( |\$)" "${lintYml}"
	done
	fAssert "[Er1LxTM] and gofmt is its formatter"  bash -c "grep -A2 '^formatters:' '${lintYml}' | grep -qE '^    - gofmt( |\$)'"
	## The Properties tab said 2026 while --about said 2014-2026.
	fAssert "[Epywvo4] the Windows resource takes its copyright years from the program" \
		bash -c "grep -q 'copyrightYear' '${root}/cicd/utility/gen-winres.bash' && ! grep -qE 'LegalCopyright.*© [0-9]' '${root}/cicd/utility/gen-winres.bash'"
	## Explorer shows it on the Properties tab, so the identity marker stays out of it.
	fAssertFail "[Er1LxTN] and carries no identity marker" \
		grep -qE 'LegalCopyright.*ID:' "${root}/cicd/utility/gen-winres.bash"
	## The demo scenario is what the gif is rendered from, so a command renamed in the product
	## and not there means the next render publishes the old name.
	fAssertFail "[EnQTPy1] the demo scenario names no renamed command" \
		grep -qE '\{(prog|bin)\} (update|br land)' "${root}/cicd/utility/demo/demo-scenario.toml"
	fAssertFail "[EnQTPy2] and the demo notes point at no deleted engine" \
		grep -q 'cicd-win' "${root}/cicd/utility/demo/script.txt"
	## "shows you the exact Git it will run, and asks first" is the README's opening claim, so
	## the demo has to show it being answered. Both halves: a scene that answers a prompt, and
	## the prompt it answers being the one the program actually writes.
	fAssert "[Eq4UJbk] the demo shows a command being confirmed, with the prompt the program writes" \
		bash -c "grep -q 'ask .*= \"Continue? (y|n): \"' '${root}/cicd/utility/demo/demo-scenario.toml' && grep -q 'confirm(\"Continue? (y|n): \")' '${root}/src-go/main.go'"
	## Two things the demo started putting on camera once the binary grew the checks that
	## noticed them: a warning about its own fixture's file permissions, and - by way of the
	## real gh - the name of whoever is logged in on the machine doing the rendering.
	fAssert "[EnQf0UC] the demo's fake tokens are not left world-readable" \
		grep -q 'chmod 600' "${root}/cicd/utility/demo/demo-repo.bash"
	fAssert "[EnQf0UD] and the demo answers gh itself, so no real login reaches the frame" \
		bash -c "grep -q 'bin/gh' '${root}/cicd/utility/demo/demo-repo.bash' && grep -q \"export PATH='\\\${root}/bin'\" '${root}/cicd/utility/demo/demo-repo.bash'"
	## The renderer itself, on a scenario small enough to render in about a second. It needs
	## Pillow and a font lookup, which a box that never renders the demo may not have.
	if python3 -c 'import PIL' >/dev/null 2>&1 && command -v fc-match >/dev/null 2>&1; then
		cat > "${work}/tiny-demo.toml" <<'EOF'
title = "demo"
prog  = "demo"
end_hold  = 0
end_black = 0.1
[[step]]
show  = "echo hi"
pause = 0.2
EOF
		## -q is what the pipeline hands every child when it runs quiet.
		fAssert "[Epsq7qy] gen-demo-gif.py takes -q, and then prints nothing" \
			bash -c "cd '${work}' && out=\$(python3 '${root}/cicd/utility/demo/gen-demo-gif.py' -q --scenario '${work}/tiny-demo.toml' --out '${work}/tiny1.gif') && [[ -z \"\${out}\" && -s '${work}/tiny1.gif' ]]"
		## Regression guard. The pipeline's compare, and design.md's byte-for-byte sentence, rest on it.
		fAssert "[Epsq7qz] and renders one scenario to the same bytes twice" \
			bash -c "cd '${work}' && python3 '${root}/cicd/utility/demo/gen-demo-gif.py' --quiet --scenario '${work}/tiny-demo.toml' --out '${work}/tiny2.gif' && python3 '${root}/cicd/utility/demo/gen-demo-gif.py' --quiet --scenario '${work}/tiny-demo.toml' --out '${work}/tiny3.gif' && cmp -s '${work}/tiny2.gif' '${work}/tiny3.gif'"
		## A step that stops to be answered. The marker is written only if the typed answer
		## really reached the command's stdin, which is the whole point: a renderer that
		## ignored ask=/answer= would still produce a perfectly good gif of nothing happening.
		cat > "${work}/ask-demo.toml" <<'EOF'
title = "demo"
prog  = "demo"
end_hold  = 0
end_black = 0.1
[[step]]
show   = "demo go"
run    = "printf 'Q: '; read a; test x$a = xy && : > answered"
ask    = "Q: "
answer = "y"
pause  = 0.1
EOF
		rm -f -- "${work:?}/answered"
		fAssert "[Eq4UJbl] the renderer answers a step that stops to ask" \
			bash -c "cd '${work}' && python3 '${root}/cicd/utility/demo/gen-demo-gif.py' --quiet --scenario '${work}/ask-demo.toml' --out '${work}/ask1.gif' && [[ -f '${work}/answered' ]]"
		## The opposite, because silence here would be a gif that quietly stopped showing the
		## confirmation. It has to stop rather than render what it could not ask for.
		cat > "${work}/ask-none.toml" <<'EOF'
title = "demo"
prog  = "demo"
end_hold  = 0
end_black = 0.1
[[step]]
show   = "demo quiet"
run    = "echo nothing to ask"
ask    = "Never: "
answer = "y"
pause  = 0.1
EOF
		fAssertFail "[Eq4UJbm] and stops when a step that should ask never does" \
			bash -c "cd '${work}' && python3 '${root}/cicd/utility/demo/gen-demo-gif.py' --quiet --scenario '${work}/ask-none.toml' --out '${work}/ask2.gif'"
		## The directive asks for three seconds of black at the loop boundary, and the committed
		## file is the one a reader sees.
		fAssert "[Epsq7r0] the committed demo gif ends on three seconds of black" \
			python3 -c 'import sys; from PIL import Image; im = Image.open(sys.argv[1]); im.seek(im.n_frames - 1); sys.exit(0 if im.info.get("duration") == 3000 and im.convert("RGB").getextrema() == ((0, 0), (0, 0), (0, 0)) else 1)' "${root}/assets/demo.gif"
	else
		echo "  skip: demo renderer checks (need python3 with Pillow, and fc-match)"
	fi

	## The Windows resource. Built here rather than pinned in the source, because the failure
	## mode is the linker quietly ignoring a .syso whose name does not match the target: the
	## file is present, the build succeeds, and the .exe comes out bare.
	local winExe=""
	for winExe in amd64 arm64; do
		fAssert "[EnQf0UE] windows/${winExe} builds with the resource beside it" \
			bash -c "cd '${root}/src-go' && CGO_ENABLED=0 GOOS=windows GOARCH=${winExe} go build -trimpath -buildvcs=false -o '${work}/winres-${winExe}.exe' ."
		fAssert "[EnQf0UF] and the .exe carries version details" \
			bash -c "tr -d '\\000' < '${work}/winres-${winExe}.exe' | grep -aqF 'VS_VERSION_INFO'"
		fAssert "[EnQf0UG] and an icon" \
			bash -c "LC_ALL=C grep -aq \$'\x89PNG' '${work}/winres-${winExe}.exe'"
	done
	## The terminal test is per-platform, and the fallback that answered for everything but Linux
	## and Windows was a character-device test - which passes for /dev/null, the one case the
	## no-terminal rule exists for. macOS and FreeBSD are published targets, so they get the real
	## query. Built rather than pinned: a build constraint that excludes the wrong set compiles
	## two isTTY into one package, or none.
	local bsdTarget=""
	for bsdTarget in darwin/arm64 darwin/amd64 freebsd/amd64; do
		fAssert "[EnQsbML] ${bsdTarget} builds with its own terminal test" \
			bash -c "cd '${root}/src-go' && CGO_ENABLED=0 GOOS='${bsdTarget%%/*}' GOARCH='${bsdTarget##*/}' go build -trimpath -buildvcs=false -o '${work}/tty-${bsdTarget//\//-}' ."
	done
	fAssert "[EnQsbMM] and the character-device fallback covers neither" \
		bash -c "grep -q '^//go:build !linux && !windows && !darwin' '${root}/src-go/tty_other.go'"

	## '~' in a config value used to expand through HOME alone, which nothing sets on native
	## Windows - so every tilde path there resolved to nothing at all, silently. One helper
	## answers it now; a bare lookup anywhere else is the bug coming back.
	fAssert "[EnQsbMN] only one place resolves the home directory" \
		bash -c "[[ \"\$(cat \"${root}\"/src-go/*.go | grep -c 'os.Getenv(\"HOME\")')\" == 1 ]]"

	## vcsprobe above is this same tree built for the host. A resource named without the
	## GOOS_GOARCH suffix would link into every platform, which is a bigger mistake than
	## shipping none at all.
	fAssertFail "[EnQf0UH] nothing but windows picks the resource up" \
		bash -c "tr -d '\\000' < '${work}/vcsprobe' | grep -aqF 'VS_VERSION_INFO'"
	## Committed rather than generated at build time: it is linked into bytes we publish
	## checksums for, so rebuilding a release from its tag must not need a tool installed.
	local winArch=""
	for winArch in amd64 arm64; do
		fAssert "[EnQf0UI] the ${winArch} resource is a file in the tree" \
			bash -c "[[ -s '${root}/src-go/resource_windows_${winArch}.syso' ]]"
		## The committed resource as well as the script that writes it. The strings are UTF-16, and
		## dropping the NULs reads them without grep -P, which not every grep has.
		fAssert "[Er1LxTO] and carries a copyright string" \
			bash -c "tr -d '\\000' < '${root}/src-go/resource_windows_${winArch}.syso' | grep -aqF 'Copyright '"
		fAssertFail "[Er1LxTP] with no identity marker in it" \
			bash -c "tr -d '\\000' < '${root}/src-go/resource_windows_${winArch}.syso' | grep -aqF '[ID:'"
	done
	fAssertFail "[EnQf0UJ] and the two are not one file copied twice" \
		cmp -s "${root}/src-go/resource_windows_amd64.syso" "${root}/src-go/resource_windows_arm64.syso"
	## Six sizes, 16 through 256. Windows synthesizes the rest, badly.
	fAssert "[EnQf0UK] the icon holds the six sizes it is generated with" \
		bash -c "[[ \"\$(head -c 6 '${root}/assets/gitsby.ico' | od -An -tu1 | xargs)\" == '0 0 1 0 6 0' ]]"
	fAssert "[EnQf0UL] the pipeline checks the resource against the newest tag" \
		bash -c "grep -q 'WINRES_CMD' '${root}/cicd/cicd.bash' && grep -q 'WINRES_CMD' '${root}/cicd/config.bash'"
	## Phase 1 builds the assets, phase 2 commits the bump - so the stamp has to happen twice,
	## and phase 1 has to undo its half or it stops being the phase that changes nothing.
	fAssert "[EnQf0UM] a release stamps the resource with the version it cuts" \
		bash -c "[[ \"\$(grep -c 'winres\[@\]' '${root}/cicd/release.bash')\" == 3 ]]"
	fAssert "[EnQf0UN] and phase 1 puts it back afterwards" \
		bash -c "grep -q 'checkout -q -- \"\${GO_MODULE_DIR}\"/\*.syso' '${root}/cicd/release.bash'"

	## Hermeticity, the half that pinning the config FILES does not cover. Two inputs reach a
	## harness from an ordinary working terminal and outrank everything it does set:
	## GIT_CONFIG_COUNT/KEY_n beat every config file including a repo-local one, and an
	## inherited GH_TOKEN is what the fake gh reports back. A run carrying either still reports
	## a count and a list of names - the checks are simply no longer about what they say.
	## The bracketed last letter keeps the pattern from matching this line when the file being
	## searched is this one, which would pass against a harness that dropped the isolation.
	local hermScript
	for hermScript in cicd/test.bash cicd/fuzz.bash cicd/parity.bash; do
		fAssert "[EmsB2dU] ${hermScript} drops env-injected git config" \
			grep -qE 'unset GIT_CONFIG_COUN[T]' "${root}/${hermScript}"
		fAssert "[EmsB2dV] ${hermScript} drops an inherited gh token" \
			grep -qE 'unset GH_TOKE[N]' "${root}/${hermScript}"
		fAssert "[Er1LxTQ] ${hermScript} pins its own accounts file" \
			grep -qE '^export GITSBY_CONFI[G]=' "${root}/${hermScript}"
	done
	## Runtime companions to the pins above. Regression guards, not discriminating checks: on a
	## clean machine they pass just as well against a harness that isolates nothing.
	# shellcheck disable=SC2016  ## the inner shell has to do the expanding, not this one.
	fAssert "[EmsB2dW] this run carries no env-injected git config"  bash -c '[[ -z "${GIT_CONFIG_COUNT:-}" ]]'
	# shellcheck disable=SC2016
	fAssert "[EmsB2dX] and no inherited gh token"                    bash -c '[[ -z "${GH_TOKEN:-}" ]]'

	## The pre-push gate: cicd.bash --gate against the stubbed engine above, then the hook in a
	## throwaway clone whose cicd.bash is a stub. Linux only, like the pipeline they belong to.
	if [[ "$(uname -s)" != Linux ]]; then
		echo "  skip: pre-push gate checks (Linux only)"
	else
		local gateDir="${work}/gate" gateCalls="${work}/gate-calls.log" gateFail="${work}/gate-fail" gateOut="${work}/gate-out.txt"
		fMakeGateFixture
		fAssert "[EpsVDHs] the gate passes a clean tree without asking anything"  fGateStatus 0 --gate
		## go vet, golangci-lint and go test on the build's core budget.
		fAssert "[EpsVDHt] and runs every lint check and the unit tests" \
			fGateCalled '^shellcheck [^-]' '^markdownlint ' '^python3 -m py_compile' 'Invoke-ScriptAnalyzer -Path' '^gofmt -l' \
				'^go vet -p [0-9]+ ' '^staticcheck ' '^golangci-lint run --concurrency [0-9]+ ' '^gen-winres\.bash --check -q' '^backlog-check\.bash -q' '^go test -race -p [0-9]+ '
		## Each pwsh start costs about a second, and the version check used to start its own.
		fAssert "[Erg6RxS] and starts pwsh once, handing it every PowerShell file" \
			bash -c "[[ \$(grep -c '^pwsh ' '${gateCalls}') == 1 ]] && grep '^pwsh ' '${gateCalls}' | grep -qF \"'install.ps1','cicd/utility/run-latest.ps1'\""
		: > "${gateFail}/pwsh-nomodule"
		fAssert "[Erg6Rxh] a box with no PSScriptAnalyzer module skips that lint with a warning" \
			fGateSays 0 'WARNING: PSScriptAnalyzer skipped' --gate
		rm -f -- "${gateFail:?}/pwsh-nomodule"
		mv "${gateDir}/PSScriptAnalyzerSettings.psd1" "${gateDir}/settings.psd1.away"
		fAssert "[Erg6Rxu] and a missing settings file fails the gate, not the rules"  fGateSays 1 'settings not found' --gate
		mv "${gateDir}/settings.psd1.away" "${gateDir}/PSScriptAnalyzerSettings.psd1"
		## This fixture's go answers 'version -m' with nothing, so every tool reads as unknown.
		fAssert "[Er1LxTR] and warns when a lint tool's version is not the recorded one" \
			fGateSays 0 'WARNING: tool versions differ from the recorded set: .*staticcheck unknown \(recorded v' --gate
		## The tools outside Go are compared too. strace stands in for them: nothing here runs it.
		fGateStub "${gateDir}/bin/strace" strace "echo 'strace -- version 0.1'"
		fAssert "[ErCQOcE] and when a tool outside Go is at another version" \
			fGateSays 0 'WARNING: tool versions differ from the recorded set: .*strace 0\.1 \(recorded ' --gate
		rm -f -- "${gateDir:?}/bin/strace"
		## Tied to the gate having passed: a run that did nothing at all adds nothing either.
		fAssert "[EpsVDHu] and nothing the full run adds" \
			bash -c "grep -q 'gate: passed' '${gateOut}' && ! grep -qE '^go build|^test\.bash|^fuzz\.bash|^parity\.bash|^spawn-count\.bash|^n8git_backup-and-publish|^govulncheck|-fuzz' '${gateCalls}' && ! grep -q 'Remote sync' '${gateOut}' && [[ ! -e '${gateDir}/cicd/artifacts/lint' ]]"
		local gateTool
		for gateTool in shellcheck markdownlint python3 pwsh gofmt go-vet staticcheck golangci-lint backlog-check go-test; do
			: > "${gateFail}/${gateTool}"
			fAssert "[EpsVDHv] the gate fails when ${gateTool} finds something"  fGateStatus 1 --gate
			if [[ "${gateTool}" == gofmt ]]; then
				fAssert "[EpsVDHw] and a lint failure stops it before the unit tests" \
					bash -c "grep -q '^gofmt -l' '${gateCalls}' && ! grep -q '^go test' '${gateCalls}'"
			fi
			rm -f -- "${gateFail:?}/${gateTool}"
		done
		fAssert "[EpsVDHx] --gate refuses a stage option"  fGateSays 2 'takes no stage options \(got: --no-lint\)' --gate --no-lint
		fAssert "[EpsVDHy] --gate and --install-hook together are refused"  fGateSays 2 'separate runs' --gate --install-hook
		## Regression guard: the full run is what the two functions were carved out of.
		fAssert "[EpsVDHz] the full run still lints, builds and runs the suites"  fGateFullRun
		fAssert "[Er2UM3f] a -q run still prints every regression, fuzz, parity and spawn check"  fGateQuietSuites
		fAssert "[EpsVDI0] cicd.bash --help lists --gate and --install-hook" \
			bash -c "out=\$('${gateDir}/cicd/cicd.bash' --help) && grep -qE -- '^ +--gate ' <<< \"\$out\" && grep -qE -- '^ +--install-hook ' <<< \"\$out\""
		fAssert "[EpsVDI1] and contributing.md names --install-hook"  grep -qF -- '--install-hook' "${root}/contributing.md"
		## Last on this fixture, since it makes it a git repo. Every tool is still a stub, so an
		## --install-hook that fell through into a full run would reach nothing outside it.
		git init --quiet "${gateDir}"
		cp "${root}/cicd/utility/pre-push.bash" "${gateDir}/cicd/utility/" 2>/dev/null || true
		fAssert "[Epsd07M] cicd.bash --install-hook installs the hook and runs no stage"  fGateInstallHook

		## The PowerShell lint with the real pwsh and the repo's settings file, on a fixture of its
		## own. The settings carry the 5.1 rule, and a file that won't parse must fail whatever
		## severity they ask for. The fixture's HOME hides a module installed for the user, so the
		## runs are told where it is.
		local gatePsModules=""
		# shellcheck disable=SC2016  ## pwsh's own variables.
		gatePsModules="$(pwsh -NoProfile -NonInteractive -Command '$m = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1; if ($m) { Split-Path (Split-Path $m.ModuleBase) }' </dev/null 2>/dev/null || true)"
		# shellcheck disable=SC2016  ## PowerShell source, written as it is.
		if [[ -n "${gatePsModules}" ]]; then
			gateDir="${work}/gate-pwsh"
			fMakeGateFixture
			rm -f -- "${gateDir:?}/bin/pwsh"
			printf 'Get-ChildItem | Out-Null\n' > "${gateDir}/install.ps1"
			fAssert "[Erg6Ry8] the real PowerShell lint passes a clean file"  fGatePwshSays 0 'OK: PSScriptAnalyzer clean'
			printf '$x = $null ?? 1\nWrite-Output $x\n' > "${gateDir}/cicd/utility/run-latest.ps1"
			fAssert "[Erg6RyM] and fails one that Windows PowerShell 5.1 can't parse"  fGatePwshSays 1 'PSUseCompatibleSyntax'
			printf 'function Get-Broken { param($a\n' > "${gateDir}/cicd/utility/run-latest.ps1"
			fAssert "[Erg6Rya] and fails one that doesn't parse at all"  fGatePwshSays 1 'MissingEndParenthesisInFunctionParameterList'
		else
			echo "  skip: real PowerShell lint checks (pwsh or PSScriptAnalyzer not installed)"
		fi
		## The same rule as the .ps1 files: no BOM, nothing outside ASCII.
		fAssert "[Erg6Ryo] PSScriptAnalyzerSettings.psd1 is plain ASCII" \
			bash -c "[[ -z \$(LC_ALL=C tr -d '\\000-\\177' < '${root}/PSScriptAnalyzerSettings.psd1') ]]"

		## The demo stage, on a fixture of its own that is a git repo with tags. Only stage 6 runs,
		## and its build, generator and optimizer are stubs, so what is checked is the stamp each
		## commit hands the demo build and what the stage does with the result.
		gateDir="${work}/gate-demo"
		fMakeGateFixture
		git init --quiet -b main "${gateDir}"
		local demoEpoch="" demoBuildLine=""
		fGateDemoCommit 2026-01-01T00:00:00Z
		fAssert "[Epsq7r1] with no release tag the demo is built as 0.0.0 with no build number" \
			fGateDemoStamp '-X main.version=0.0.0 -X main.buildEpoch= -o '
		git -C "${gateDir}" tag vnext
		fAssert "[Epsq7r2] a v tag that is not a version stamps nothing into the demo, and says so" \
			fGateDemoStamp '-X main.version=0.0.0 -X main.buildEpoch= -o ' '' "WARNING: .*'vnext' is not a version"
		git -C "${gateDir}" tag -d vnext >/dev/null
		## A release candidate sorts below its release only through versionsort.suffix. Without it
		## the candidate would stamp the demo.
		git -C "${gateDir}" tag v9.8.7-rc.1
		fGateDemoCommit 2026-02-01T00:00:00Z
		git -C "${gateDir}" tag v9.8.7
		fGateDemoCommit 2026-03-01T00:00:00Z
		demoEpoch="$(git -C "${gateDir}" log -1 --format=%ct 'v9.8.7^{commit}')"
		fAssert "[Epsq7r3] the demo renders from its own build, stamped with the newest release" \
			fGateDemoStamp "-X main.version=9.8.7 -X main.buildEpoch=${demoEpoch} -o ${gateDir}/src-go/gitsby-demo" "--bin ${gateDir}/src-go/gitsby-demo"
		demoBuildLine="$(fGateDemoBuild)"
		fAssert "[Epsq7r4] and removes that build afterwards" \
			bash -c "[[ -n '${demoBuildLine}' && ! -e '${gateDir}/src-go/gitsby-demo' ]]"
		fGateDemoCommit 2026-04-01T00:00:00Z
		fAssert "[Epsq7r5] a later commit builds the demo identically, so the gif is left alone"  fGateDemoSame "${demoBuildLine}"
		fAssert "[Epsq7r6] -q reaches the demo generator"  fGateDemoQuiet -q 1
		## Regression guard: -y is unattended, not quiet.
		fAssert "[Epsq7r7] and -y alone does not quiet it"  fGateDemoQuiet -y 0
		: > "${gateFail}/go-build"
		fAssert "[Epsq7r8] a failed demo build warns, renders nothing and the run goes on"  fGateDemoBuildFails
		rm -f -- "${gateFail:?}/go-build"
		gateDir="${work}/gate"

		## The stages the gate leaves out, on a fixture of their own that becomes a git repo with a
		## release tag and then an origin. Its go answers 'version -m' with each tool's recorded
		## version and 'test -list' with one fuzz target, and fails fuzzing on a marker of its own.
		## Its python3 logs where py_compile was told to put the cache, and whether that existed.
		gateDir="${work}/gate-pipe"
		fMakeGateFixture
		local gateRc=0 gatePipeTools="" gatePyCache="" gateDest=""
		local gateOrigin="${work}/gate-pipe-origin.git" gateOther="${work}/gate-pipe-other"
		# shellcheck source=/dev/null
		gatePipeTools="$(cd "${root}" && source cicd/config.bash && echo "${GO_TOOL_VERSIONS[*]}")"
		fStub "${gateDir}/bin/go" <<-EOF
			#!/usr/bin/env bash
			printf '%s\n' "go \$*" >> '${gateCalls}'
			case "\${1:-} \${2:-}" in
				"version -m") for s in ${gatePipeTools}; do [[ "\${s%%=*}" != "\$(basename "\${3:-}")" ]] || printf 'mod\tx\t%s\th1:x\n' "\${s#*=}"; done; exit 0 ;;
				"env GOPATH") echo '${gateDir}/gopath'; exit 0 ;;
				"test -list") echo FuzzA; exit 0 ;;
				"test -race") if [[ -e '${gateFail}/go-test' ]]; then printf -- '--- FAIL: TestA (0.00s)\n    a_test.go:4: boom\n'
					else printf -- '=== RUN   TestA\n--- PASS: TestA (0.00s)\n    --- PASS: TestA/sub (0.00s)\n--- PASS: TestC (0.00s)\n'; fi ;;
			esac
			[[ "\$*" != *" -fuzz "* || ! -e '${gateFail}/go-fuzz' ]] || exit 1
			[[ ! -e "${gateFail}/go-\${1:-}" ]] || exit 1
			o=''; for a in "\$@"; do [[ "\${o}" != 1 ]] || : > "\${a}"; o=''; [[ "\${a}" != -o ]] || o=1; done
		EOF
		fGateStub "${gateDir}/bin/python3" python3 "printf 'pycache %s %s\n' \"\${PYTHONPYCACHEPREFIX:-unset}\" \"\$([[ -d \"\${PYTHONPYCACHEPREFIX:-}\" ]] && echo dir || echo nodir)\" >> '${gateCalls}'"
		## Where 'go install' puts it and not on PATH, which is how it sits on a box that never
		## added GOPATH/bin. The version check looked on PATH only, and skipped it without a word.
		mkdir -p "${gateDir}/gopath/bin"
		fGateStub "${gateDir}/gopath/bin/goversioninfo" goversioninfo
		fAssert "[Er1LxTS] the gate says nothing about lint tool versions that match the recorded set"  fGateNoDrift
		fAssert "[ErCQVGY] and finds a Go tool under GOPATH to ask" \
			bash -c "grep -q '^go version -m .*/goversioninfo\$' '${gateCalls}'"
		gatePyCache="$(sed -n 's/^pycache \(.*\) dir$/\1/p' "${gateCalls}")"
		fAssert "[Er1LxTT] py_compile writes its cache to a folder of its own, removed afterwards" \
			bash -c "[[ -n '${gatePyCache}' && ! -e '${gatePyCache}' ]]"
		git init --quiet -b main "${gateDir}"
		printf '%s\n' 1 2 3 4 5 6 7 8 > "${gateDir}/notes.txt"
		git -C "${gateDir}" add --all
		git -C "${gateDir}" commit --quiet -m init
		git -C "${gateDir}" tag v9.8.7
		echo two >> "${gateDir}/README.md"
		git -C "${gateDir}" commit --quiet -m two -- README.md
		echo edited >> "${gateDir}/README.md"
		printf 'package main\n\nfunc FuzzA(f *testing.F) { // [AAAAAAA]\n}\nfunc TestA(t *testing.T) { // [AAAAAAB]\n}\n' > "${gateDir}/src-go/a_test.go"
		fGateOnly test
		fAssert "[Er7b6m3] the unit tests print a line per test with its ID, and none for a subtest" \
			bash -c "grep -qxF '  ok: [AAAAAAB] TestA' '${gateOut}' && grep -qxF '  ok: TestC' '${gateOut}' && ! grep -qF -- '=== RUN' '${gateOut}' && ! grep -qF 'TestA/sub' '${gateOut}'"
		fAssert "[Er1LxTU] a build names the commit it was built from, and -dirty for uncommitted source" \
			fGateRanCalling 0 '^go build .* -X main\.version=9\.8\.7-1-g[0-9a-f]+-dirty -X main\.buildEpoch='
		fAssert "[Er1LxTV] and reads that after the remote sync, which can move HEAD" \
			awk '/^fSection "0\/7  Remote sync"/{s=NR} /^go_version=/{g=NR} END{exit !(s && g > s)}' "${root}/cicd/cicd.bash"
		: > "${gateFail}/go-test"
		fGateOnly test
		rm -f -- "${gateFail:?}/go-test"
		fAssert "[Er7b6mH] and a failing one stops the run, with its line and its output" \
			bash -c "[[ '${gateRc}' == 1 ]] && grep -qxF '  FAIL: [AAAAAAB] TestA' '${gateOut}' && grep -qF 'a_test.go:4: boom' '${gateOut}' && grep -qF 'go test failures' '${gateOut}'"
		git -C "${gateDir}" checkout --quiet -- README.md
		## Stage 3 without --quick. 'go test -list' failing is swallowed there, so a target list
		## that came back empty would pass having fuzzed nothing.
		fGateOnly fuzz
		fAssert "[Er1LxTW] stage 3 runs the fuzz harness, fuzzes each target the module lists, and counts spawns" \
			fGateRanCalling 0 '^fuzz\.bash' '^go test -run \^\$ -fuzz \^FuzzA\$ -fuzztime 5s -parallel [0-9]+ \.$' '^spawn-count\.bash'
		fAssert "[Er631Hf] and prints each target on a line of its own, with its test ID"  fGateRanSaying 0 '^  ok: \[AAAAAAA\] FuzzA$'
		: > "${gateFail}/go-fuzz"
		fGateOnly fuzz
		rm -f -- "${gateFail:?}/go-fuzz"
		fAssert "[Er1LxTX] and a crasher stops the run, naming the target"  fGateRanSaying 1 'fuzzing found a crasher in FuzzA'
		: > "${gateFail}/fuzz"
		fGateOnly fuzz
		rm -f -- "${gateFail:?}/fuzz"
		fAssert "[Er1LxTY] and so does a failing fuzz harness"  fGateRanCalling 1 '^fuzz\.bash'
		: > "${gateFail}/spawn-count"
		fGateOnly fuzz
		rm -f -- "${gateFail:?}/spawn-count"
		fAssert "[Er1LxTZ] and a spawn count that rose"  fGateRanSaying 1 'spawn counts regressed'
		fAssert "[Er1LxTa] the module has at least five fuzz targets for stage 3 to find" \
			bash -c "[[ \"\$(cd '${root}/src-go' && env -u XDG_CONFIG_HOME -u APPDATA go test -list 'Fuzz.*' . | grep -c '^Fuzz')\" -ge 5 ]]"
		## Stage 5 on a box with none of the shared dirs, then with the first one this box's target names.
		mkdir -p "${gateDir}/home/.local/bin"
		fGateOnly dogfood
		fAssert "[Er1LxTb] dogfood falls back to ~/.local/bin for the target this box runs, and only that one" \
			bash -c "[[ '${gateRc}' == 0 && -f '${gateDir}/home/.local/bin/gitsby' && ! -e '${gateDir}/home/.local/bin/gitsby.exe' ]]"
		fAssert "[Er1LxTc] and says the other targets have nowhere to go" \
			bash -c "grep -qF 'WARNING: no windows/amd64 dogfood dest exists/writable' '${gateOut}' && grep -qF 'WARNING: no darwin/universal dogfood dest exists/writable' '${gateOut}'"
		# shellcheck disable=SC2016
		gateDest="$(cd "${gateDir}" && HOME="${gateDir}/home" bash -c 'source cicd/config.bash && echo "${DOGFOOD_DESTS_LINUX_AMD64[0]}"')"
		mkdir -p "${gateDest}"
		rm -f -- "${gateDir:?}/home/.local/bin/gitsby"
		fGateOnly dogfood
		fAssert "[Er1LxTd] a configured dest that exists wins over the fallback" \
			bash -c "[[ '${gateRc}' == 0 && -f '${gateDest}/gitsby' && ! -e '${gateDir}/home/.local/bin/gitsby' ]]"
		fGateOnly publish -m 'hands off'
		fAssert "[Er1LxTe] -m hands its message to the publisher"  fGateRanCalling 0 '^n8git_backup-and-publish --quiet -m hands off$'
		fGateOnly publish --message='hands off'
		fAssert "[Er1LxTf] and so does --message="  fGateRanCalling 0 '^n8git_backup-and-publish --quiet -m hands off$'
		## Stage 0 against a real origin: behind, behind with an edit in the tree, diverged, and gone.
		git init --quiet --bare -b main "${gateOrigin}"
		git -C "${gateDir}" remote add origin "${gateOrigin}"
		git -C "${gateDir}" push --quiet -u origin main 2>/dev/null
		git clone --quiet "${gateOrigin}" "${gateOther}" 2>/dev/null
		fGateUpstream one
		fGateOnly sync
		fAssert "[Er1LxTg] stage 0 fast-forwards a tree that is only behind" \
			bash -c "[[ '${gateRc}' == 0 && \"\$(git -C '${gateDir}' rev-parse HEAD)\" == \"\$(git -C '${gateOther}' rev-parse HEAD)\" ]] && grep -qF 'fast-forwarding 1 commit(s) from origin' '${gateOut}'"
		fAssert "[Er1LxTh] under the 0/7 header"  grep -qxF '[ 0/7  Remote sync ]' "${gateOut}"
		## The same file on both sides, far enough apart to merge. Without --autostash git refuses.
		fGateUpstream two notes.txt
		sed -i.bak 's/^1$/edited/' "${gateDir}/notes.txt" && rm -f "${gateDir:?}/notes.txt.bak"
		fGateOnly sync
		fAssert "[Er1LxTi] and carries an uncommitted edit across the fast-forward" \
			bash -c "[[ '${gateRc}' == 0 && \"\$(git -C '${gateDir}' rev-parse HEAD)\" == \"\$(git -C '${gateOther}' rev-parse HEAD)\" && \"\$(head -n 1 '${gateDir}/notes.txt')\" == edited && \"\$(tail -n 1 '${gateDir}/notes.txt')\" == two ]]"
		git -C "${gateDir}" commit --quiet -m local -- notes.txt
		fGateUpstream three
		fGateOnly sync
		fAssert "[Er1LxTj] a tree that diverged from origin stops the run"  fGateRanSaying 1 'diverged from origin: 1 local, 1 remote'
		git -C "${gateDir}" remote set-url origin "${work}/gate-pipe-nowhere.git"
		fGateOnly sync
		fAssert "[Er1LxTk] an origin it can't reach is a warning, not a stop"  fGateRanSaying 0 "WARNING: can't reach origin"
		fGateOnly ''
		fAssert "[Er1LxTl] --no-sync skips it, and says so"  fGateRanSaying 0 '^remote sync skipped$'
		gateDir="${work}/gate"

		## The hook. Its stub cicd.bash logs where it ran, what it was given, the marker file it saw
		## and two variables git sets for hooks, and fails when the marker reads "fail". Physical
		## paths, since git reports them that way.
		local hookDir; hookDir="$(cd "${work}" && pwd -P)/hook"
		local hookOrigin="${hookDir}/origin.git" hookRepo="${hookDir}/repo" hookLog="${hookDir}/gate.log" hookOut="${hookDir}/push.txt"
		local hookFile="${hookDir}/repo/.git/hooks/pre-push" hookSnap="${hookDir}/repo/.git/gitsby-gate" hookRc=0 hookSum="" hookShort="" hookRemote=""
		mkdir -p "${hookDir}"
		git init --quiet --bare -b main "${hookOrigin}"
		git clone --quiet "${hookOrigin}" "${hookRepo}" 2>/dev/null
		mkdir -p "${hookRepo}/cicd/utility" "${hookRepo}/sub"
		## Absent from a tree that predates the gate. Every check below then fails, not the suite.
		cp "${root}/cicd/utility/pre-push.bash" "${hookRepo}/cicd/utility/" 2>/dev/null || true
		echo keep > "${hookRepo}/sub/keep.txt"
		echo good > "${hookRepo}/marker.txt"
		fStub "${hookRepo}/cicd/cicd.bash" <<-EOF
			#!/usr/bin/env bash
			case "\${1:-}" in --gate) ;; esac
			printf '%s|%s|%s|GIT_PREFIX=%s|GIT_DIR=%s|status=%s\n' "\$(pwd -P)" "\$*" "\$(cat marker.txt)" "\${GIT_PREFIX-unset}" "\${GIT_DIR-unset}" "\$(git status --porcelain --untracked-files=all | wc -l)" >> '${hookLog}'
			[[ "\$(cat marker.txt)" != fail ]]
		EOF
		git -C "${hookRepo}" add --all
		git -C "${hookRepo}" commit --quiet -m init
		git -C "${hookRepo}" push --quiet -u origin main 2>/dev/null

		fAssert "[EpsVDI2] install writes an executable pre-push hook" \
			bash -c "'${hookRepo}/cicd/utility/pre-push.bash' --install && grep -qxF '## gitsby pre-push gate - installed by cicd/cicd.bash --install-hook' '${hookFile}' && [[ \"\$(fMode '${hookFile}')\" == 755 ]]"
		hookSum="$(sha256sum "${hookFile}" 2>/dev/null || true) $(fInode "${hookFile}" 2>/dev/null || true)"
		fAssert "[EpsVDI3] and a second install changes nothing" \
			bash -c "'${hookRepo}/cicd/utility/pre-push.bash' --install && [[ \"\$(sha256sum '${hookFile}') \$(fInode '${hookFile}')\" == '${hookSum}' ]]"
		## A hook from an earlier version of this script: the marker line, other text beneath it.
		# shellcheck disable=SC2016  ## written as text, for the hook to expand.
		printf '%s\n' '#!/usr/bin/env bash' '## gitsby pre-push gate - installed by cicd/cicd.bash --install-hook' \
			'exec "$(git rev-parse --show-toplevel)/cicd/utility/pre-push.bash" "$@"' > "${hookFile}"
		fAssert "[Epsd07N] and an older hook of ours is replaced" \
			bash -c "out=\$('${hookRepo}/cicd/utility/pre-push.bash' --install) && grep -qxF 'pre-push: updated ${hookFile}' <<< \"\$out\" && out=\$('${hookRepo}/cicd/utility/pre-push.bash' --install) && grep -qF 'already installed' <<< \"\$out\""
		## Fresh clones for the refusals, so none of them depends on the install above.
		local hookRepo3="${hookDir}/repo3" hookRepo4="${hookDir}/repo4" hookRepo5="${hookDir}/repo5"
		local hookElsewhere="${hookDir}/hooks-elsewhere" hookUname="${hookDir}/uname-bin" hookForeign=""
		git clone --quiet "${hookOrigin}" "${hookRepo3}"
		mkdir -p "${hookRepo3}/.git/hooks"
		printf '#!/bin/sh\necho mine\n' > "${hookRepo3}/.git/hooks/pre-push"
		hookForeign="$(sha256sum < "${hookRepo3}/.git/hooks/pre-push")"
		fAssert "[EpsVDI4] install leaves a hook it did not write alone" \
			bash -c "out=\$('${hookRepo3}/cicd/utility/pre-push.bash' --install 2>&1); [[ \$? == 1 ]] && grep -qF '${hookRepo3}/.git/hooks/pre-push' <<< \"\$out\" && [[ \"\$(sha256sum < '${hookRepo3}/.git/hooks/pre-push')\" == '${hookForeign}' ]]"
		git clone --quiet "${hookOrigin}" "${hookRepo4}"
		mkdir -p "${hookElsewhere}"
		git -C "${hookRepo4}" config core.hooksPath "${hookElsewhere}"
		fAssert "[EpsVDI5] install refuses while core.hooksPath is set" \
			bash -c "out=\$('${hookRepo4}/cicd/utility/pre-push.bash' --install 2>&1); [[ \$? == 1 ]] && grep -qF core.hooksPath <<< \"\$out\" && [[ ! -e '${hookRepo4}/.git/hooks/pre-push' && ! -e '${hookElsewhere}/pre-push' ]]"
		git clone --quiet "${hookOrigin}" "${hookRepo5}"
		mkdir -p "${hookUname}"
		fStub "${hookUname}/uname" <<-'EOF'
			#!/usr/bin/env bash
			echo Darwin
		EOF
		fAssert "[EpsVDI6] install refuses off Linux" \
			bash -c "out=\$(PATH='${hookUname}':\"\$PATH\" '${hookRepo5}/cicd/utility/pre-push.bash' --install 2>&1); [[ \$? == 1 ]] && grep -qF 'Linux only' <<< \"\$out\" && [[ ! -e '${hookRepo5}/.git/hooks/pre-push' ]]"

		## Committed "good2", with "fail" sitting uncommitted in the working tree.
		echo good2 > "${hookRepo}/marker.txt"
		git -C "${hookRepo}" commit --quiet -m good2 -- marker.txt
		echo fail > "${hookRepo}/marker.txt"
		hookRc=0; fHookPush "${hookRepo}" origin main || hookRc=$?
		fAssert "[EpsVDI7] a push runs the gate on the commit being pushed" \
			bash -c "[[ '${hookRc}' == 0 ]] && grep -qF '${hookSnap}|--gate|good2|' '${hookLog}' && [[ \"\$(git -C '${hookRepo}' ls-remote origin refs/heads/main | cut -f1)\" == \"\$(git -C '${hookRepo}' rev-parse main)\" ]]"
		fAssert "[EpsVDI8] and leaves the working tree as it was" \
			bash -c "[[ -s '${hookLog}' && \"\$(cat '${hookRepo}/marker.txt')\" == fail && \"\$(git -C '${hookRepo}' status --porcelain)\" == ' M marker.txt' ]]"
		git -C "${hookRepo}" commit --quiet -m fail -- marker.txt
		hookShort="$(git -C "${hookRepo}" rev-parse --short HEAD)"
		hookRemote="$(git -C "${hookRepo}" ls-remote origin refs/heads/main)"
		hookRc=0; fHookPush "${hookRepo}" origin main || hookRc=$?
		fAssert "[EpsVDI9] a failing gate refuses the push" \
			bash -c "[[ '${hookRc}' != 0 ]] && grep -qF '${hookShort}' '${hookOut}' && grep -qF 'cicd/cicd.bash --gate' '${hookOut}' && grep -qF -- '--no-verify' '${hookOut}' && [[ \"\$(git -C '${hookRepo}' ls-remote origin refs/heads/main)\" == '${hookRemote}' ]]"
		## main stays on the failing commit from here on.
		git -C "${hookRepo}" checkout --quiet -b side main~1
		echo side > "${hookRepo}/marker.txt"
		git -C "${hookRepo}" commit --quiet -m side -- marker.txt
		git -C "${hookRepo}" checkout --quiet main
		hookRc=0; fHookPush "${hookRepo}" origin side || hookRc=$?
		fAssert "[EpsVDIA] a branch other than main is not gated" \
			bash -c "[[ '${hookRc}' == 0 && ! -s '${hookLog}' ]] && grep -qF 'not gated: refs/heads/side' '${hookOut}' && [[ -n \"\$(git -C '${hookRepo}' ls-remote origin refs/heads/side)\" ]]"
		hookRc=0; fHookPush "${hookRepo}" origin +side:refs/heads/main || hookRc=$?
		fAssert "[Eqo6ntQ] main pushed from another branch is gated at that commit" \
			bash -c "[[ '${hookRc}' == 0 ]] && grep -qF '|--gate|side|' '${hookLog}'"
		## A delete on its own leaves nothing to see, so one goes out beside a branch that is gated.
		hookRc=0; fHookPush "${hookRepo}" origin :side +main~1:refs/heads/main || hookRc=$?
		fAssert "[EpsVDIB] a branch delete runs no gate" \
			bash -c "[[ '${hookRc}' == 0 && \"\$(wc -l < '${hookLog}')\" == 1 ]] && grep -qF '|--gate|good2|' '${hookLog}'"
		git -C "${hookRepo}" tag t1 main
		hookRc=0; fHookPush "${hookRepo}" origin t1 || hookRc=$?
		fAssert "[EpsVDIC] a tag push runs no gate" \
			bash -c "[[ '${hookRc}' == 0 && ! -s '${hookLog}' ]] && grep -qF 'not gated: refs/tags/t1' '${hookOut}'"
		git -C "${hookRepo}" branch b1 side
		git -C "${hookRepo}" branch b2 side
		hookRc=0; fHookPush "${hookRepo}" origin +b1:refs/heads/main b2 || hookRc=$?
		fAssert "[EpsVDID] main pushed beside another branch is gated once" \
			bash -c "[[ '${hookRc}' == 0 && \"\$(grep -c -- '|--gate|' '${hookLog}')\" == 1 ]]"
		## Its cicd.bash has no --gate) arm, and would fail if it were run.
		git -C "${hookRepo}" checkout --quiet -b old main~1
		printf '#!/usr/bin/env bash\nexit 1\n' > "${hookRepo}/cicd/cicd.bash"
		git -C "${hookRepo}" commit --quiet -m old -- cicd/cicd.bash
		git -C "${hookRepo}" checkout --quiet main
		hookRc=0; fHookPush "${hookRepo}" origin +old:refs/heads/main || hookRc=$?
		fAssert "[EpsVDIE] a commit from before the gate is pushed with a note" \
			bash -c "[[ '${hookRc}' == 0 && ! -s '${hookLog}' ]] && grep -qF 'predates the gate' '${hookOut}'"
		git -C "${hookRepo}" checkout --quiet -b noscript main~1
		git -C "${hookRepo}" rm --quiet --ignore-unmatch cicd/utility/pre-push.bash
		git -C "${hookRepo}" commit --quiet --allow-empty -m noscript
		hookRc=0; fHookPush "${hookRepo}" origin noscript || hookRc=$?
		git -C "${hookRepo}" checkout --quiet main
		fAssert "[EpsVDIF] a checkout without the hook script pushes with a note" \
			bash -c "[[ '${hookRc}' == 0 ]] && grep -qF 'not gated' '${hookOut}'"
		hookRc=0; fHookPush "${hookRepo}/sub" origin +side:refs/heads/main || hookRc=$?
		fAssert "[EpsVDIG] the gate does not inherit GIT_PREFIX from a push run in a subdirectory" \
			bash -c "[[ '${hookRc}' == 0 ]] && grep -qF '|side|GIT_PREFIX=unset|' '${hookLog}'"
		## From a subdirectory git starts the hook at the top, but passes a relative --work-tree on as
		## typed. Read from the top, ".." is the directory above the checkout.
		hookRc=0; : > "${hookLog}"
		hookRemote="$(git -C "${hookRepo}" ls-remote origin refs/heads/main)"
		(cd "${hookRepo}/sub" && git --git-dir=../.git --work-tree=.. push origin +main:refs/heads/main) >"${hookOut}" 2>&1 || hookRc=$?
		fAssert "[Epscy2K] a push from a subdirectory with a relative --work-tree is gated all the same" \
			bash -c "[[ '${hookRc}' != 0 ]] && grep -qF '${hookSnap}|--gate|fail|' '${hookLog}' && [[ \"\$(git -C '${hookRepo}' ls-remote origin refs/heads/main)\" == '${hookRemote}' ]]"
		## git hands a hook GIT_DIR from a linked worktree. Passed on, the gate worktree's checkout
		## would land on this worktree instead, and detach it.
		local hookLinked="${hookDir}/linked"
		git -C "${hookRepo}" worktree add --quiet -b linkedb "${hookLinked}" main~1
		hookRc=0; fHookPush "${hookLinked}" origin +linkedb:refs/heads/main || hookRc=$?
		fAssert "[EpsVDIH] a push from a linked worktree hands the gate no GIT_DIR and leaves that worktree on its branch" \
			bash -c "[[ '${hookRc}' == 0 ]] && grep -qF '|good2|GIT_PREFIX=unset|GIT_DIR=unset' '${hookLog}' && [[ \"\$(git -C '${hookLinked}' symbolic-ref --short HEAD)\" == linkedb && -z \"\$(git -C '${hookLinked}' status --porcelain)\" ]]"
		## Moved aside rather than removed. Either way it is a registered worktree whose directory is gone.
		if [[ -d "${hookSnap}" ]]; then mv "${hookSnap}" "${hookDir}/gate-moved-aside"; fi
		git -C "${hookRepo}" checkout --quiet -b b16 main~1
		echo b16 > "${hookRepo}/marker.txt"
		git -C "${hookRepo}" commit --quiet -m b16 -- marker.txt
		git -C "${hookRepo}" checkout --quiet main
		hookRc=0; fHookPush "${hookRepo}" origin +b16:refs/heads/main || hookRc=$?
		fAssert "[EpsVDII] a gate worktree that went missing is recreated" \
			bash -c "[[ '${hookRc}' == 0 ]] && grep -qF '${hookSnap}|--gate|b16|' '${hookLog}'"
		local hookLock="${hookDir}/repo/.git/gitsby-gate.lock" hookLockPid="" hookT0=0 hookT1=0 hookWait=0
		git -C "${hookRepo}" branch b17 main~1
		hookT0="$(date +%s%N)"
		flock "${hookLock}" sleep 2 &
		hookLockPid=$!
		## Until the background flock holds the lock, the push could take it first.
		while flock -n "${hookLock}" true && ((hookWait < 100)); do sleep 0.02; hookWait=$((hookWait + 1)); done
		hookRc=0; fHookPush "${hookRepo}" origin +b17:refs/heads/main || hookRc=$?
		hookT1="$(date +%s%N)"
		kill "${hookLockPid}" 2>/dev/null || true
		wait "${hookLockPid}" 2>/dev/null || true
		fAssert "[EpsVDIJ] a second gate waits for the one running" \
			bash -c "[[ '${hookRc}' == 0 ]] && grep -qF 'waiting for it' '${hookOut}' && (( ${hookT1} - ${hookT0} >= 2000000000 ))"
		## Leftovers from an earlier gate, one tracked and one untracked. checkout --force alone
		## would keep the untracked one.
		if [[ -d "${hookSnap}" ]]; then echo fail > "${hookSnap}/marker.txt"; echo left > "${hookSnap}/leftover.txt"; fi
		hookRc=0; fHookPush "${hookRepo}" origin +b16:refs/heads/main || hookRc=$?
		fAssert "[Epsd07O] a gate worktree left dirty is rebuilt before the gate runs" \
			bash -c "[[ '${hookRc}' == 0 ]] && grep -qF '${hookSnap}|--gate|b16|GIT_PREFIX=unset|GIT_DIR=unset|status=0' '${hookLog}'"
		hookRc=0; PATH="${hookUname}:${PATH}" fHookPush "${hookRepo}" origin +main~1:refs/heads/main || hookRc=$?
		fAssert "[Epsd07P] a push off Linux goes out ungated with a note" \
			bash -c "[[ '${hookRc}' == 0 && ! -s '${hookLog}' ]] && grep -qF 'Linux only' '${hookOut}' && [[ \"\$(git -C '${hookRepo}' ls-remote origin refs/heads/main | cut -f1)\" == \"\$(git -C '${hookRepo}' rev-parse main~1)\" ]]"
		## Without its .git file the directory is still registered, but git inside it answers for the
		## main repo. Nothing there may be forced or removed.
		local hookSnapSum="" hookSnapAfter=""
		if [[ -f "${hookSnap}/.git" ]]; then mv "${hookSnap}/.git" "${hookDir}/gate-dotgit-aside"; fi
		hookSnapSum="$(fTreeDigest "${hookSnap}" || true)"
		hookRc=0; fHookPush "${hookRepo}" origin +b16:refs/heads/main || hookRc=$?
		hookSnapAfter="$(fTreeDigest "${hookSnap}" || true)"
		fAssert "[Epsd07Q] a gate worktree without its .git file is refused and left as it was" \
			bash -c "[[ '${hookRc}' != 0 && -n '${hookSnapSum}' && '${hookSnapSum}' == '${hookSnapAfter}' && ! -s '${hookLog}' ]] && grep -qE 'is not this repo.s gate worktree' '${hookOut}'"
		if [[ -f "${hookDir}/gate-dotgit-aside" && ! -e "${hookSnap}/.git" ]]; then mv "${hookDir}/gate-dotgit-aside" "${hookSnap}/.git"; fi
	fi

	## Go-only: the renamed commands, the aliases that keep every 2.1.0 spelling working, and
	## 'whoami'. The scripts are frozen at the old surface, so asserting the new names on their
	## legs would only prove that a frozen file is frozen.
	local renDir="${work}/rename"
	git clone --quiet "${origin}" "${renDir}"
	fAssertOut "[EnLB2hd] help leads with the new name" 'pullcom \[msg\] \.+: Pull updates'        "${gitsby}" --help
	fAssertOut "[EnLB2he] and offers br merge"          'br merge \[msg\] \.+: Merge current'      "${gitsby}" --help
	fAssertOut "[EnLB2hf] and lists whoami"             'whoami \.+: Show account, ssh key'        "${gitsby}" --help
	## Every accepted spelling, because a ladder is only worth having if the whole ladder is
	## there - a missing rung reads as a typo the tool refused for no reason.
	local spelling
	for spelling in pullcom update pull pullc pullco pullcomm pullcommit; do
		fAssert "[EnLB2hg] '${spelling}' commits" bash -c "cd '${renDir}' && echo x >> '${spelling}.txt' && '${gitsby}' -q ${spelling} 'via ${spelling}' && git -C '${renDir}' log -1 --pretty=%s | grep -qx 'via ${spelling}'"
	done
	fAssertPlan "[EnLB2hh] 'br merge' merges the current branch" 'git merge --no-ff renmerge' \
		bash -c "cd '${renDir}' && '${gitsby}' -q br create renmerge >/dev/null && '${gitsby}' -q br merge 'merged' 2>&1"
	fAssertPlan "[EnLB2hi] 'br land' still does the same"        'git merge --no-ff renland' \
		bash -c "cd '${renDir}' && '${gitsby}' -q br create renland >/dev/null && '${gitsby}' -q br land 'landed' 2>&1"
	fAssertOut  "[EnLB2hj] an unknown br subcommand names merge, not land" 'switch, merge, prune' \
		bash -c "cd '${renDir}' && '${gitsby}' -q br frobnicate 2>&1"
	## whoami is the status block's identity half on its own, and the one read-only command
	## that answers outside a repo - which is where you ask it, before cloning anything.
	fAssert     "[EnLB2hk] whoami exits 0"              bash -c "cd '${renDir}' && '${gitsby}' whoami"
	fAssertOut  "[EnLB2hl] and names the commit author" '^Author \.+: test <test@test>' \
		bash -c "cd '${renDir}' && '${gitsby}' whoami 2>&1"
	fAssertNotOut "[EnLB2hm] and leaves out the working-tree state" 'Local changes:' \
		bash -c "cd '${renDir}' && '${gitsby}' whoami 2>&1"
	fAssert     "[EnLB2hn] whoami answers outside a repo" bash -c "cd '${work}' && '${gitsby}' whoami"
	fAssertFail "[EnLB2ho] whoami with a trailing argument rejected" \
		bash -c "cd '${renDir}' && '${gitsby}' whoami extra"
	## Both older spellings are permanent aliases, so neither may quietly become a typo.
	for spelling in who identity; do
		fAssertOut "[EnbeoL2] '${spelling}' answers as whoami" '^Author \.+: test <test@test>' \
			bash -c "cd '${renDir}' && '${gitsby}' ${spelling} 2>&1"
	done

	## --offline was a silent spelling of --no-fetch that never stopped a push. It is refused by
	## name now, so the one thing it promised can't be believed on the strength of the word.
	fAssertOut  "[EnPXgsa] --offline is refused by name"              'no --offline option' \
		bash -c "cd '${renDir}' && '${gitsby}' --offline status 2>&1"
	fAssertOut  "[EnPXgsb] and points at the option that does exist"  'use --no-fetch' \
		bash -c "cd '${renDir}' && '${gitsby}' --offline status 2>&1"
	fAssertFail "[EnPXgsc] --offline ahead of raw is refused, not handed to the tool" \
		bash -c "cd '${renDir}' && '${gitsby}' --offline raw git status"
	fAssert     "[EnPXgsd] --no-fetch still parses"  bash -c "cd '${renDir}' && '${gitsby}' --no-fetch status"
	fAssert     "[EnPXgse] and so does --nofetch"    bash -c "cd '${renDir}' && '${gitsby}' --nofetch status"

	## Options and no command ask what no arguments ask. -q means no prompts, never no output.
	fAssertOut  "[EnPXgsf] '-q' alone prints the command list"  'Common commands:' \
		bash -c "cd '${renDir}' && '${gitsby}' -q 2>&1"
	fAssertFail "[EnPXgsg] and still exits nonzero"            bash -c "cd '${renDir}' && '${gitsby}' -q"
	fAssertOut  "[EnPXgsh] '-q --help' prints it too"          'Common commands:' \
		bash -c "cd '${renDir}' && '${gitsby}' -q --help 2>&1"

	## pr was the one command that dropped a trailing argument in silence.
	fAssertOut  "[EnPXgsi] 'pr <n> extra' names the extra argument"  "Unexpected extra argument 'extra'" \
		bash -c "cd '${renDir}' && '${gitsby}' -q pr 5 extra 2>&1"
	fAssertOut  "[EnPXgsj] 'pr create' with an unquoted title says to quote it"  'quote your title' \
		bash -c "cd '${renDir}' && '${gitsby}' -q pr create My title 2>&1"
	fAssertOut  "[EnPXgsk] and a longer unquoted one says so too"  'quote it' \
		bash -c "cd '${renDir}' && '${gitsby}' -q pr create My much longer title 2>&1"

	## Ours come before 'raw', the tool's after it - which is not the same as never having heard
	## of what was typed.
	fAssertOut  "[EnPXgsl] an option between raw and the tool says where ours go"  "options come before 'raw'" \
		bash -c "cd '${renDir}' && '${gitsby}' raw -q git status 2>&1"

	## ------------------------------------------------------------------------------------
	## Directive review 20260819. Every check below fails against the build that preceded it,
	## bar the two marked as follow-up state checks on the run above them.
	local dr="${work}/$1-dirrev"
	mkdir -p "${dr}/bin" "${dr}/home/${confRel}" "${dr}/tree"
	local drCanon="${dr}"
	((isWindows)) && drCanon="$( cd "${dr}" && pwd -W )"

	## rev-parse --is-inside-work-tree answers in text and exits zero either way, so the exit
	## code says only that we are somewhere git understands. A bare repo and the .git directory
	## are both that, and neither is a place any of this means anything.
	git init --quiet --bare -b main "${dr}/bare.git"
	git init --quiet -b main "${dr}/wt"
	( cd "${dr}/wt" && echo a > a.txt && git add --all && git commit --quiet -m init )
	fAssertOut "[EnQNsZU] a bare repo is refused by name"       'bare repository' \
		bash -c "cd '${dr}/bare.git' && '${gitsby}' -q -NoFetch status 2>&1"
	fAssertOut "[EnQNsZV] and the .git directory itself too"    "'\.git' directory" \
		bash -c "cd '${dr}/wt/.git' && '${gitsby}' -q -NoFetch status 2>&1"

	## With no remote at all the offline check never trips - there is nothing to find
	## unreachable - so the tag was cut, pushed nowhere, and the run ended on "Done."
	fAssertOut "[EnQNsZW] release with no origin refuses"       "No 'origin' remote, and a release" \
		bash -c "cd '${dr}/wt' && '${gitsby}' -q -NoFetch release 2>&1"
	fAssert    "[EnQNsZX] and cut no tag"                       bash -c "cd '${dr}/wt' && [[ -z \"\$(git tag --list)\" ]]"

	## A bare 'git fetch' follows the current branch's own tracking remote, and every existence
	## check afterwards reads origin. Only a fetch that names origin sees a branch pushed there.
	git init --quiet --bare -b main "${dr}/f-origin.git"
	git init --quiet --bare -b main "${dr}/f-other.git"
	git clone --quiet "${dr}/f-origin.git" "${dr}/fetchr" 2>/dev/null
	(
		cd "${dr}/fetchr" && echo a > a.txt && git add --all && git commit --quiet -m init
		git push --quiet -u origin main
		git remote add other "${dr}/f-other.git" && git push --quiet other main
		git branch --quiet --set-upstream-to=other/main main
	)
	git clone --quiet "${dr}/f-origin.git" "${dr}/pusher" 2>/dev/null
	( cd "${dr}/pusher" && git checkout --quiet -b brandnew && git push --quiet -u origin brandnew )
	fAssert "[EnQNsZY] the pre-command fetch names origin, not the branch's own remote" \
		bash -c "cd '${dr}/fetchr' && '${gitsby}' -q status >/dev/null 2>&1; git -C '${dr}/fetchr' show-ref --verify --quiet refs/remotes/origin/brandnew"

	## br merge holds its remote delete back while origin is unreachable; prune had no such
	## check, so each push failed and was reported as "already gone" - blaming the branch for a
	## network problem, with a summary that read as if it had finished.
	git init --quiet --bare -b main "${dr}/p-origin.git"
	git clone --quiet "${dr}/p-origin.git" "${dr}/prune" 2>/dev/null
	(
		cd "${dr}/prune" && echo a > a.txt && git add --all && git commit --quiet -m init
		git push --quiet -u origin main
		git checkout --quiet -b landed && git push --quiet -u origin landed
		git checkout --quiet main && git merge --quiet --no-ff landed -m merge && git push --quiet
	)
	rm -rf -- "${dr:?}/p-origin.git"
	fAssertOut "[EnQNsZZ] br prune offline leaves origin's copies alone"  "left origin's copies" \
		bash -c "cd '${dr}/prune' && '${gitsby}' -q br prune 2>&1"
	fAssert    "[EnQNsZa] but still deletes the local branch"    bash -c "cd '${dr}/prune' && [[ -z \"\$(git branch --list landed)\" ]]"

	## git's DWIM creates a tracking branch from a remote copy only when exactly one remote has
	## it; with two it refuses to guess, and the up-front check never noticed because it only
	## ever looks at origin.
	git init --quiet --bare -b main "${dr}/t-origin.git"
	git init --quiet --bare -b main "${dr}/t-other.git"
	git clone --quiet "${dr}/t-origin.git" "${dr}/two" 2>/dev/null
	(
		cd "${dr}/two" && echo a > a.txt && git add --all && git commit --quiet -m init
		git push --quiet -u origin main
		git checkout --quiet -b feature && git push --quiet -u origin feature
		git checkout --quiet main
		git remote add other "${dr}/t-other.git"
		git push --quiet other main && git push --quiet other feature
		git branch --quiet -D feature && git fetch --quiet --all
	)
	fAssert "[EnQNsZb] br switch works with two remotes carrying the branch" \
		bash -c "cd '${dr}/two' && '${gitsby}' -q -NoFetch br switch feature && [[ \"\$(git branch --show-current)\" == feature ]]"

	## Two accounts claiming one folder produce the same includeIf key twice. --unset-all takes
	## every entry at once, so the second pass found nothing and git's exit 5 was read as a
	## failure: the config was left with no rules at all, and the command reported an error.
	fStub "${dr}/bin/gh" <<-'GHEOF'
		#!/usr/bin/env bash
		case "$1 $2" in
			"auth token") exit 1 ;;
			"api user")   echo "${FAKE_GH_ACTIVE:-someoneelse}"; exit 0 ;;
		esac
		exit 1
	GHEOF
	cat > "${dr}/home/${confRel}/config.shcl" <<-CFGEOF
		account.abe.path      = ${drCanon}/tree
		account.abe.ghAccount = abe
		account.abe.name      = Abe Person
		account.abe.email     = abe@example.com
		account.zed.path      = ${drCanon}/tree
		account.zed.ghAccount = zed
	CFGEOF
	: > "${dr}/home/.gitconfig"
	git init --quiet -b main "${dr}/tree/proj"
	( cd "${dr}/tree/proj" && echo a > a.txt && git add --all && git commit --quiet -m init )
	local drEnv="${acNoDiscovery} HOME='${dr}/home' GIT_CONFIG_GLOBAL='${dr}/home/.gitconfig' PATH='${dr}/bin:${PATH}'"
	fAssert "[EnQNsZc] account apply runs with two accounts on one folder" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q account apply >/dev/null"
	fAssert "[EnQNsZd] and a second run leaves the rules in place" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q account apply >/dev/null && grep -q 'gitsby/accounts' '${dr}/home/.gitconfig'"
	fAssertOut "[EnQNsZe] and the contested folder is called out" 'more than one account claims' \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q account 2>&1"
	## The two tie-breaks used to disagree: gitsby keeps the first rule declared, git keeps the
	## last written, and sorting the plan by text put them in opposite orders.
	fAssertOut "[EnQNsZf] gitsby keeps the first rule declared"  'Account \.+: abe' \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q account 2>&1"
	fAssert "[EnQNsZg] and plain git now resolves it the same way" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} git config gitsby.ghAccount | grep -qx abe"

	## Account selection is skipped entirely under --any-identity - the token, the key and the
	## commit author all stay as they were - and the block used to name the account anyway.
	fAssertOut "[EnQNsZh] --any-identity says the account was not applied"  'nothing applied - gitsby was run with --any-identity' \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q -NoFetch --any-identity status 2>&1"

	## Treating a malformed count as zero numbers our entries over the caller's first few and
	## leaves the rest applying - half a config each, and nobody's intent.
	fAssertOut "[EnQNsZi] a GIT_CONFIG_COUNT that isn't a count stops the run"  "isn't a count" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} GIT_CONFIG_COUNT=notanumber '${gitsby}' -q -NoFetch identity 2>&1"

	## A token read from a file says nothing about whose it is: the name came from a config key
	## beside it, so a stale file reports the right name and pushes as the wrong person.
	printf 'gho_stale\n' > "${dr}/token"
	cat > "${dr}/token.shcl" <<-TOKEOF
		account.abe.path      = ${drCanon}/tree
		account.abe.ghAccount = abe
		account.abe.tokenFile = ${drCanon}/token
	TOKEOF
	fAssertOut "[EnQNsZj] a file-sourced token is checked against the account it claims"  "authenticates as 'someoneelse'" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q -NoFetch --config '${dr}/token.shcl' identity 2>&1"

	## Naming an account for a repo you only cloned tells a single-account user about a feature
	## they never configured, and claims something was applied when nothing was.
	git init --quiet -b main "${dr}/stranger"
	(
		cd "${dr}/stranger" && echo a > a.txt && git add --all && git commit --quiet -m init
		git remote add origin https://github.com/stranger/repo.git
	)
	fAssertNotOut "[EnQNsZk] raw names no account for a repo you only cloned"  'acting as' \
		bash -c "cd '${dr}/stranger' && env ${drEnv} '${gitsby}' raw git status 2>&1"

	## Mode bits, where the platform has any worth reading. A token file everyone can read loads
	## without a word, and the fragment directory was created 0777 and left to umask.
	if ((! isWindows)); then
		chmod 644 "${dr}/token"
		fAssertOut "[EnQNsZl] a token file other users can read is called out"  'readable by other users' \
			bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q -NoFetch --config '${dr}/token.shcl' identity 2>&1"
		fAssert "[EnQNsZm] the account fragments are yours alone" \
			bash -c "[[ \"\$(fMode '${dr}/home/${confRel}/accounts')\" == 700 ]] && [[ \"\$(fMode '${dr}/home/${confRel}/accounts/github.com_abe.gitconfig')\" == 600 ]]"
	fi

	##••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
	## Other git hosts. gitsby was a GitHub program that reached for gh whenever it wanted anything from
	## a remote; most of what it does is git, and git does not care whose server it is. What is
	## covered here is the seam: the host decides the tool, the tool is only reached for once the
	## host is known to be one it serves, and everything that never needed a git host CLI keeps working
	## without one. A '.test' host is reserved and resolves nowhere, so -NoFetch keeps it all local.
	##••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
	local fg="${work}/$1-githost"
	mkdir -p "${fg}/bin" "${fg}/debbin"
	## A deterministic tea. Logs every call the way the gh stub does, so a check can see not just
	## that a pull request was asked for but which vocabulary it was asked in.
	fStub "${fg}/bin/tea" <<'TEAEOF'
#!/usr/bin/env bash
[[ -n "${FAKE_TEA_LOG:-}" ]] && echo "$*" >> "${FAKE_TEA_LOG}"
case "$1 $2" in
"logins list") [[ -n "${FAKE_TEA_FAIL:-}" ]] && { echo "${FAKE_TEA_FAIL}" >&2; exit 1; }
               printf '"Name"\t"URL"\t"SSHHost"\t"User"\t"Default"\n' ;
               printf '"work"\t"%s"\t""\t"%s"\t"true"\n' "${FAKE_TEA_URL:-https://git.example.test}" "${FAKE_TEA_USER:-giteauser}" ;;
"pulls list")  printf '"index"\t"head"\n' ; [[ -n "${FAKE_TEA_EXISTING:-}" ]] && printf '"%s"\t"%s"\n' "${FAKE_TEA_EXISTING}" "${FAKE_TEA_HEAD:-feat}" ;;
*)             : ;;
esac
exit 0
TEAEOF
	## The same program under the name Debian ships it as. Looking for one spelling finds it only on
	## the machines that happen to use that one.
	fStub "${fg}/debbin/tea-cli" <<'TEAEOF'
#!/usr/bin/env bash
[[ -n "${FAKE_TEA_LOG:-}" ]] && echo "$*" >> "${FAKE_TEA_LOG}"
exit 0
TEAEOF
	## gh is on the path throughout this block, and must never be the one that answers.
	fStub "${fg}/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
[[ -n "${FAKE_GH_LOG:-}" ]] && echo "$*" >> "${FAKE_GH_LOG}"
exit 0
GHEOF
	cp "${fg}/bin/gh" "${fg}/debbin/gh" 2>/dev/null; fStubShim "${fg}/debbin/gh"
	local fgRepo="${fg}/proj"
	git init --quiet -b main "${fgRepo}"
	(
		cd "${fgRepo}" || exit 1
		echo a > a.txt && git add --all && git commit --quiet -m init
		git remote add origin https://git.example.test/acme/proj.git
	)
	local fgPath="${fg}/bin:${PATH}"
	local fgDeb="${fg}/debbin:${PATH}"
	## A path with git on it and no git host CLI at all. Not an empty directory: that takes git away
	## too, and then 'Not found in path: git' comes first and the refusal under test never runs -
	## the exit-code check passes for a reason that has nothing to do with what it is checking.
	## Linked, not wrapped: a '#!/usr/bin/env bash' wrapper needs bash found on the very PATH we are
	## emptying, so it fails to start and the run reads as "not a git repository" instead.
	mkdir -p "${fg}/gitonly"
	local fgBare="${fg}/gitonly"
	## bash as well as git: ${gitsby} is itself a '#!/usr/bin/env bash' shim, so emptying the PATH of
	## bash stops the binary launching at all - which reads as "not a git repository", not as the
	## refusal under test.
	if ! ln -s "$(command -v bash)" "${fg}/gitonly/bash" 2>/dev/null || ! ln -s "$(command -v git)" "${fg}/gitonly/git" 2>/dev/null; then
		## No symlinks (Windows without developer mode): keep the real path on, minus the stubs.
		fgBare="${PATH}"
	fi

	## The whole point: a Gitea remote is served by tea, and gh - installed, on the path, perfectly
	## willing - is not asked anything at all.
	: > "${fg}/tea.log"; : > "${fg}/gh.log"
	fAssert "[EnS8ftB] a Gitea remote lists pull requests through tea" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' FAKE_TEA_LOG='${fg}/tea.log' FAKE_GH_LOG='${fg}/gh.log' '${gitsby}' -q -NoFetch pr && grep -q '^pulls list' '${fg}/tea.log'"
	fAssert "[EnS8ftC] and gh is never run for it, though it is installed" \
		bash -c "! grep -q . '${fg}/gh.log'"
	## Debian renames the binary because the name was taken. One spelling found is not both found.
	: > "${fg}/deb.log"
	fAssert "[EnS8ftD] tea is found under the 'tea-cli' name too" \
		bash -c "cd '${fgRepo}' && PATH='${fgDeb}' FAKE_TEA_LOG='${fg}/deb.log' '${gitsby}' -q -NoFetch pr && grep -q . '${fg}/deb.log'"

	## No CLI for the host: the refusal has to name the host that decided it and the tool that would
	## serve it. Telling a Gitea user to install a GitHub client is the failure this replaced.
	fAssertFail "[EnS8ftE] a Gitea remote with no host CLI refuses"  bash -c "cd '${fgRepo}' && PATH='${fgBare}' '${gitsby}' -q -NoFetch pr"
	fAssertOut  "[EnS8ftF] and names the host that decided it"  'git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgBare}' '${gitsby}' -q -NoFetch pr 2>&1"
	fAssertOut  "[EnS8ftG] and points at tea rather than gh"  'tea' \
		bash -c "cd '${fgRepo}' && PATH='${fgBare}' '${gitsby}' -q -NoFetch pr 2>&1"

	## 'repo url' only ever rewrites text - it asks the host nothing - so refusing it anywhere but
	## github.com was the parser's limit showing through as a rule.
	fAssertOut "[EnS8ftH] repo url shows a Gitea remote's ssh spelling"    'git@git\.example\.test:acme/proj\.git' \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url 2>&1"
	fAssertOut "[EnS8ftI] repo url shows its https spelling too"           'https://git\.example\.test/acme/proj\.git' \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url 2>&1"
	fAssert    "[EnS8ftJ] repo url converts a Gitea remote to ssh" \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url ssh >/dev/null && git -C '${fgRepo}' remote get-url origin | grep -qx 'git@git.example.test:acme/proj.git'"
	fAssert    "[EnS8ftK] and back to https" \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url https >/dev/null && git -C '${fgRepo}' remote get-url origin | grep -qx 'https://git.example.test/acme/proj.git'"
	## The plan named a github.com address, and the command then set the Gitea one.
	fAssertPlan "[EpyIe9K] repo url plans the Gitea address it sets"  'git remote set-url origin git@git\.example\.test:acme/proj\.git' \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url ssh 2>&1; git -C '${fgRepo}' remote set-url origin https://git.example.test/acme/proj.git"

	## The identity block exists to say who the next command acts as. On a host gh does not serve it
	## had no answer at all - it printed nothing rather than saying it could not tell.
	fAssertOut "[EnS8ftL] the identity block names the git host"  'Git host .*git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch identity 2>&1"
	fAssertOut "[EnS8ftM] and who tea holds a login for there"      'giteauser' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch identity 2>&1"
	fAssertNotOut "[EnS8ftN] and prints no GitHub line for it"      'GitHub .gh.' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch identity 2>&1"
	## A tea that fails has said nothing about logins. "No login" would send someone off to add one
	## they may already have.
	fAssertOut    "[Epu08TQ] a tea that fails is not read as holding no login"  "unknown - couldn't ask tea: tea config is unreadable" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' FAKE_TEA_FAIL='tea config is unreadable' '${gitsby}' -q -NoFetch identity 2>&1"
	fAssertNotOut "[Epu08TR] and does not say tea has no login"  'has no login for this host' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' FAKE_TEA_FAIL='tea config is unreadable' '${gitsby}' -q -NoFetch identity 2>&1"
	fAssertOut    "[Epu08TS] a tea with no login for the host still says so"  "unknown - 'tea login add' has no login for this host" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' FAKE_TEA_URL='https://other.example.test' '${gitsby}' -q -NoFetch identity 2>&1"

	## A token is a credential for the git host that issued it. An account that banks at github.com must
	## not have its token handed to a Gitea push - and the block has to say why, not report a missing
	## token that would have been the wrong one anyway.
	cat > "${fg}/gh-acct.shcl" <<-EOF
		account.work.path      = $(fWinPath "${fgRepo}")
		account.work.ghAccount = ghonly
		account.work.tokenFile = $(fWinPath "${fg}/token")
	EOF
	echo tok_ghonly > "${fg}/token"
	fAssertOut "[EnS8ftO] a github.com account is not applied to a Gitea remote"  'no access token used for git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/gh-acct.shcl' identity 2>&1"
	fAssertOut "[EnS8ftP] and says it is the host that decided that"  'git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/gh-acct.shcl' identity 2>&1"
	## Declaring the host is what makes the same account apply - and the credential helper is then
	## written for THAT host, never for github.com.
	cat > "${fg}/tea-acct.shcl" <<-EOF
		account.work.path      = $(fWinPath "${fgRepo}")
		account.work.host      = git.example.test
		account.work.user      = giteauser
		account.work.tokenFile = $(fWinPath "${fg}/token")
	EOF
	fAssertNotOut "[EnS8ftQ] an account that declares the host IS applied"  'Why:' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/tea-acct.shcl' identity 2>&1"

	## An account that never named a host is TAKEN to be a github.com one, which is right for every
	## config written before the key existed - but it is an assumption, not something the file said.
	## Reported in the same words as a host somebody actually typed, it sends them through the config
	## looking for a line that was never there. This account also names no GitHub login, which is the
	## ordinary shape of a Gitea one: reading 'ghAccount' alone reported it as "(no GitHub account
	## named)" - true, and no answer at all to the question the line asks.
	cat > "${fg}/nohost.shcl" <<-EOF
		account.work.path = $(fWinPath "${fgRepo}")
		account.work.user = giteauser
	EOF
	fAssertOut "[EnWSLMW] an unstated host is reported as unstated, not as one the account set"  "doesn't say which git host it is for" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	## Knowing the fix and printing it as homework is a worse answer than doing it. The advice used
	## to spell out a config line to add by hand - and before that, one the parser doesn't even take,
	## so following it exactly left the account no more applied than before. It names the command
	## that makes the edit now, which cannot be mistyped and cannot name a key nothing reads.
	fAssertOut "[EnXe9aM] and names the command that fixes it"  "gitsby account set work host git\.example\.test" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1"
	## Advice to edit a file that never says WHICH file is not advice. The path is on its own line
	## because it is the one thing here long enough to wreck the wrapping.
	fAssertOut "[EnX7v96] and names the file to make that edit in"  '^File: .*nohost\.shcl$' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1 | sed 's/^ *: *//'"
	## Anchored on the Account line: 'giteauser' is also what the tea stub answers, so an unanchored
	## match is satisfied by the Git host line and passes whether the Account line names anybody or not.
	fAssertOut "[EnWSLMX] and names the account's own login, not the GitHub field it hasn't got"  '^Account .*giteauser' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1"

	## The ssh key and the commit identity are applied outside the credential decision, so a flat
	## "not applied" contradicted the SSH and Author lines printed directly under it - the reader is
	## looking at a key and an author this very account put there. Say which half went in.
	cat > "${fg}/nohost-id.shcl" <<-EOF
		account.work.path  = $(fWinPath "${fgRepo}")
		account.work.user  = giteauser
		account.work.name  = Gitea User
		account.work.email = giteauser@example.test
	EOF
	fAssertOut "[EnX7v97] an account whose token did not apply still says what did"  'commit identity still applied' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost-id.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	## Which half, though - it named "the SSH and Author lines" whichever half applied, so an account
	## that only set a commit identity sent the reader looking for an SSH line that is not printed
	## anywhere on screen. That reads as a second thing gone wrong.
	fAssertOut "[EnXe9aN] and names only the lines that are actually printed"  'that is where the Author line below comes from' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost-id.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	fAssertNotOut "[EnXe9aO] not an SSH line it never printed"  'SSH and Author lines' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost-id.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	## GIT_AUTHOR_NAME/EMAIL are exported at the top of this file for hermeticity and outrank every
	## config, so the Author line cannot show an account's identity while they are set.
	fAssertOut "[EnX7v98] and the Author line under it is that account's"  '^Author .*giteauser@example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL '${gitsby}' -q -NoFetch --config '${fg}/nohost-id.shcl' identity 2>&1"

	## A declared Gitea account with no token applies nothing, and said NOTHING about it. The "no
	## token" case was keyed on 'ghAccount' - a field a Gitea account has no reason to set - so
	## exactly the accounts the host key was added for fell through it in silence, which reads as
	## applied. Nor is gh what acts instead on a host gh does not serve.
	cat > "${fg}/notoken.shcl" <<-EOF
		account.work.path = $(fWinPath "${fgRepo}")
		account.work.host = git.example.test
		account.work.user = giteauser
	EOF
	fAssertOut "[EnWSLMY] a Gitea account with no token says it was not applied"  'no access token used for git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/notoken.shcl' identity 2>&1"
	fAssertOut "[EnWSLMZ] and names what authenticates instead"  'Git authenticates however it already would' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/notoken.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	fAssertNotOut "[EnWSLMa] rather than gh, which does not serve this host"  'gh goes on acting as' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/notoken.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"

	## 'account set': knowing the fix and printing it as homework is the worse half of an answer.
	## The whole round trip, because either half alone proves nothing - the command has to write a
	## line the loader then reads back, and the diagnostic has to stop once it has.
	cp "${fg}/nohost.shcl" "${fg}/fixme.shcl"
	## This fixture is in the old flat layout, so the first edit rewrites it whole in the current one
	## - and says so, since the file comes back a different shape from the one that was typed.
	fAssertOut "[EnXe9aP] 'account set' says which file it will edit, and how"  'add: +account\[work\]\.host: git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set work host git.example.test 2>&1"
	fAssertOut "[EnXe9aQ] and the file now holds that key, in the block"  '^	host: git\.example\.test$' \
		cat "${fg}/fixme.shcl"
	fAssertOut "[Eo61m69] and the rest came through the change of layout"  '^	user: giteauser$' \
		cat "${fg}/fixme.shcl"
	fAssertOut "[Eo61m6A] and the footer names the format"  'This config file format is SHCL' \
		cat "${fg}/fixme.shcl"
	## The point of the whole exercise: run what the Fix line said and that complaint is gone. Only
	## that one - this account still has no token, which is a different sentence about a different
	## thing, and asserting no complaint at all would be asserting the wrong fix worked.
	fAssertNotOut "[EnXe9aR] and the account stops being read as a github.com one"  "which git host it is for" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' identity 2>&1"
	## Now in the current layout, an edit names the line it changes and both versions of the key.
	fAssertOut "[Eo61m6B] a second edit names the line and what was there"  'was: +host: git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set work host git.example.org 2>&1"
	## A file written under SHCL 2.x is kept under a dated name, and replaced by one converted for 3.x.
	mkdir -p "${fg}/old2x"
	printf 'account: work\n\tname: C:\\\\new\n\n#\n# This config file format is SHCL.\n# "Simple Hierarchical Config Language"\n#\n' > "${fg}/old2x/config.shcl"
	fAssertOut "[ErfOMAH] a SHCL 2.x accounts file is converted, and the old one kept"  'Converted .* from the SHCL 2\.x format' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/old2x/config.shcl' identity 2>&1"
	fAssertOut "[ErfOMAV] and the old one sits beside it under a dated name"  '^config_backup_[0-9]{8}-[0-9]{6}_format-v2\.shcl$' \
		ls "${fg}/old2x"
	fAssertOut "[ErfOMAj] and the new one names the format"  '^##    Format   3' \
		cat "${fg}/old2x/config.shcl"
	## A key the loader ignores, written past this command, lands in the file and is dropped on every
	## read - so the file says one thing and every command does another. Refuse it at the door, and
	## name the keys that ARE read while refusing.
	fAssertOut "[EnXe9aS] a key nothing reads is refused, not written"  "isn't an account key gitsby reads" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set work hostname git.example.test 2>&1"
	## 'host' and 'user' are interpolated into the credential helper, which git hands to a shell. The
	## loader drops one carrying a shell character; refusing to WRITE it is what keeps the file and
	## the behavior from disagreeing.
	fAssertOut "[EnXe9aT] and so is a shell character in a host name"  "isn't a plain host name" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set work host 'git.example.test; id' 2>&1"
	fAssertNotOut "[EnXe9aU] which never reaches the file"  '; id' \
		cat "${fg}/fixme.shcl"
	## 'path' is repeatable by design, and any key at all can be in there twice by accident.
	## Replacing the first and leaving the rest looks like it worked and changes nothing that is read.
	printf 'account.dup.path = /a\naccount.dup.path = /b\n' > "${fg}/dup.shcl"
	fAssertOut "[EnXe9aV] a key present twice is not guessed at"  'Edit it by hand' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/dup.shcl' account set dup path /c 2>&1"
	## A refusal decided inside the plan printed as the plan, asked to continue, then refused with
	## the same sentence.
	printf 'account: work\n    host: github.com\n' > "${fg}/spaced.shcl"
	fAssertNotOut "[EpySM7k] a refused account set shows no plan"  'Going to do' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/spaced.shcl' account set work host 'a b' 2>&1"
	if ((hasPty)); then
		fAssertNotOut "[EpySM7l] and asks nothing"  'Continue\?' \
			fAnswerPrompt y "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -NoFetch --config '${fg}/spaced.shcl' account set work host 'a b'"
	fi
	## Only https and ssh are acted on. Anything else was written, shown as set, and ignored.
	fAssertOut "[EpySM7m] a protocol gitsby doesn't use is refused"  "isn't a protocol gitsby uses" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/spaced.shcl' account set work protocol git 2>&1"
	fAssertNotOut "[EpySM7n] and never reaches the file"  'protocol' \
		cat "${fg}/spaced.shcl"
	## Lines an edit doesn't touch come back as they were. The plan speaks up only when the module
	## can't manage that and writes the whole file in its own layout.
	fAssertNotOut "[EqwGjDc] an edit to a file spaced by hand says nothing about the rest of it"  'also: ' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/spaced.shcl' account set work host gitea.com 2>&1"
	fAssertOut "[EqwGjDd] and the file keeps its spacing"  '^    host: gitea\.com$'  cat "${fg}/spaced.shcl"
	printf 'account.work.email: a@b.c\n' > "${fg}/dotted.shcl"
	fAssertOut "[EqwGjDe] a key added under a dotted line rewrites the file, and the plan says so"  'also: +the rest of the file' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/dotted.shcl' account set work host gitea.com 2>&1"
	fAssertNotOut "[EpySM7o] and once in that layout it hears nothing of it"  'also: ' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/dotted.shcl' account set work host git.example.org 2>&1"
	printf 'protocol: git\naccount: work\n\tprotocol: xyz\n' > "${fg}/badproto.shcl"
	fAssertOut "[EpySM7p] account list names a protocol nothing acts on as ignored"  'account\[work\]\.protocol \(not https or ssh\)' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/badproto.shcl' account list 2>&1"
	fAssertOut "[EpySM7q] and the one for every account too"  'Ignored keys \.*: protocol \(not https or ssh\)' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/badproto.shcl' account list 2>&1"
	## Three placeholders are the whole interface. Naming them without saying what they are answers
	## nothing for the one reader who ever sees this - the one who just typed the command wrong.
	fAssertOut "[EncI7No] the syntax block says what '<account>' is"  '<account>  A string you define for one login' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set 2>&1"
	## '<key>' is a closed list, and the command that lists it is this one - a reader sent looking
	## for the keys elsewhere guesses instead, and a guess is refused a command later.
	fAssertOut "[EncI7Np] and lists the keys it takes"  'One of: path, pathcontains, ghaccount, tokenfile' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set 2>&1 | tr '\\n' ' ' | tr -s ' '"
	## The example is two lines on one account name, because that repetition is what '<account>' is.
	fAssertOut "[EncI7Nq] and its example runs as printed"  'gitsby account set github.com_my-work-login path ~/dev/work' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set 2>&1"
	## 'pathContains' matches a run of folder names, not a glob. An example with a '*' in it reads
	## as a pattern language that isn't there, and the rule it teaches never matches anything.
	fAssertNotOut "[EncX1Q8] and the pathcontains example is not a glob"  '[*]' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set 2>&1 | grep pathcontains"
	## 'account unset' is the way back from a set, short of a hand edit. It names each line it takes
	## out, and leaves every other line as typed.
	printf 'account: work\n    host: gitea.com\n    email: w@example.com\n' > "${fg}/unset.shcl"
	fAssertPlan "[ErCjvos] 'account unset' names the line it removes"  'remove: +host: gitea\.com' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/unset.shcl' account unset work host 2>&1"
	fAssertNotOut "[ErCjvp5] and the file no longer holds it"  'host' \
		cat "${fg}/unset.shcl"
	fAssertOut "[ErCjvpK] and the rest of the file is as typed"  '^    email: w@example\.com$' \
		cat "${fg}/unset.shcl"
	## A second run is a success with nothing to do, so a script can run it without checking first.
	fAssert "[ErCjvpY] a key already gone is nothing to do, not a failure" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/unset.shcl' account unset work host 2>&1 | grep -q 'nothing to do'"
	## It removes every line of the key, so a value after it would read as a narrower request than
	## the one carried out.
	fAssertOut "[ErCkAkK] a value after the key is refused"  "\\(got '/a' too\\)" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/unset.shcl' account unset work path /a 2>&1"
	fAssertOut "[ErCkAkZ] and with no key it prints the syntax"  'Syntax: gitsby account unset <account> <key>' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/unset.shcl' account unset work 2>&1"
	## The identity block's own vocabulary. "Forge" is a word for people who already knew the answer.
	fAssertOut "[EnXe9aW] the identity block says 'Git host', not 'Forge'"  '^Git host \.+: git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/tea-acct.shcl' identity 2>&1"
	## Narrowed to the labeled notes, which are the lines the word used to turn up in. The check
	## above proves they print at all.
	fAssertNotOut "[EnXe9aX] and the word is gone from the block above it"  'forge' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1 | sed 's/^ *: *//' | grep -E '^(From|Why|Kept|Fix):'"

	## 'account list' is the command that always says, so the field that decides whether anything
	## applies has to be in it - stated or assumed.
	fAssertOut "[EnWSLMb] account list names the host an account is on"  'host \.+: git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/tea-acct.shcl' account list 2>&1"
	## Shown for every account once one of them names a git host, including the ones that never said -
	## that comparison is what answers "why did this one apply and that one not". A config with a
	## single git host in it has nothing to compare and reads exactly as it did before the key existed.
	cat > "${fg}/mixed.shcl" <<-EOF
		account.tea.path = $(fWinPath "${fgRepo}")
		account.tea.host = git.example.test
		account.hub.pathContains = somewhere-else
		account.hub.ghAccount = ghonly
	EOF
	fAssertOut "[EnWSLMc] and marks an unstated one as the assumption it is"  'host \.+: github\.com  .default.' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/mixed.shcl' account list 2>&1"
	fAssertNotOut "[EnWSLMd] but a config with one git host in it is never shown the key"  'host \.+:' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/gh-acct.shcl' account list 2>&1"
	fAssertOut "[EnWSLMe] and prints the host-neutral login beside the GitHub one"  'login \.+: giteauser' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/tea-acct.shcl' account list 2>&1"

	## The identity gate, on a host that is not GitHub. Two accounts disagreeing about who you are is
	## the same outward-facing mistake wherever it happens, and keying the check on 'ghAccount' - a
	## GitHub login, which says nothing about who you are anywhere else - left it silently uncovered.
	## The ssh stub answers with GITEA's greeting, not GitHub's: close enough to look handled by the
	## existing pattern and different enough not to be.
	fStub "${fg}/bin/ssh" <<'SSHEOF'
#!/usr/bin/env bash
mode=""
for a in "$@"; do case "$a" in -G) mode=G ;; -T) mode=T ;; esac; done
if [[ "${mode}" == "G" ]]; then
	printf 'user git
hostname %s
identityfile /etc/hostname
' "${FAKE_SSH_HOSTNAME:-git.example.test}"
	exit 0
fi
if [[ "${mode}" == "T" ]]; then
	echo "Hi there, ${FAKE_SSH_LOGIN:-keyowner}! You've successfully authenticated with the key named k, but Gitea does not provide shell access."
	exit 1
fi
exit 0
SSHEOF
	local fgSsh="${fg}/sshproj"
	git init --quiet -b main "${fgSsh}"
	(
		cd "${fgSsh}" || exit 1
		echo a > a.txt && git add --all && git commit --quiet -m init
		git remote add origin git@git.example.test:acme/proj.git
	)
	## Parsing Gitea's greeting is what makes every check below able to say anything at all.
	fAssertOut "[EnSC7jE] the ssh line names the account a Gitea key authenticates as"  'SSH \.+: keyowner' \
		bash -c "cd '${fgSsh}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch status 2>&1"

	local fgCanon="${fgSsh}"; ((isWindows)) && fgCanon="$( cd "${fgSsh}" && pwd -W )"
	cat > "${fg}/mine.shcl" <<-EOF
		account.mine.path = ${fgCanon}
		account.mine.host = git.example.test
		account.mine.user = gitfriend
	EOF
	cat > "${fg}/theirs.shcl" <<-EOF
		account.mine.path = ${fgCanon}
		account.mine.host = git.example.test
		account.mine.user = keyowner
	EOF
	local fgSync="cd '${fgSsh}' && PATH='${fgPath}' GITSBY_CONFIG="
	fAssertFail   "[EnSC7jF] sync refuses when a Gitea folder's account is not the key's" \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --config '${fg}/mine.shcl' sync 'W'"
	fAssertOut    "[EnSC7jG] and the refusal names both"  "account is 'gitfriend'.*authenticates as 'keyowner'" \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --config '${fg}/mine.shcl' sync 'W' 2>&1 || true"
	fAssertNotOut "[EnSC7jH] --any-identity says the difference is intended"  'authenticates as' \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --any-identity --config '${fg}/mine.shcl' sync 'W' 2>&1 || true"
	fAssertNotOut "[EmlpDMs] and a matching account does not fire"  'authenticates as' \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --config '${fg}/theirs.shcl' sync 'W' 2>&1 || true"
	## An account whose only login is a GitHub one has made no claim about this host, so there is
	## nothing to compare - it must not be read as a match either.
	cat > "${fg}/ghonly.shcl" <<-EOF
		account.mine.path      = ${fgCanon}
		account.mine.ghAccount = alice
	EOF
	fAssertNotOut "[EnSC7jI] a GitHub-only account makes no claim about a Gitea remote"  'authenticates as' \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --config '${fg}/ghonly.shcl' sync 'W' 2>&1 || true"

	## The other half: a write THROUGH tea, acting as tea's login while git pushes as the key. Same
	## mistake as the gh version of this, and it was reachable only because a tea write now counts
	## as a write at all.
	( cd "${fgSsh}" && git checkout --quiet -b fgfeat && echo w > w.txt && git add --all && git commit --quiet -m "work" )
	fAssertFail "[EnSC7jJ] pr create refuses when tea's login is not the key's" \
		bash -c "cd '${fgSsh}' && PATH='${fgPath}' FAKE_TEA_USER=gitfriend FAKE_SSH_LOGIN=keyowner '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "[EnSC7jK] and the refusal names tea rather than gh"  "tea acts as 'gitfriend'" \
		bash -c "cd '${fgSsh}' && PATH='${fgPath}' FAKE_TEA_USER=gitfriend FAKE_SSH_LOGIN=keyowner '${gitsby}' -q -NoFetch pr create 'T' 2>&1"
	fAssertNotOut "[EnSC7jL] and agreeing logins do not fire"  'acts as' \
		bash -c "cd '${fgSsh}' && PATH='${fgPath}' FAKE_TEA_USER=keyowner FAKE_SSH_LOGIN=keyowner '${gitsby}' -q -NoFetch pr create 'T' 2>&1 || true"
	( cd "${fgSsh}" && git checkout --quiet main )

	## An unparseable remote is not a git host we ruled out - it is one we could not name. The standing
	## rule is that such a remote never triggers a refusal, so gh keeps the last word exactly as before.
	git init --quiet -b main "${fg}/localorigin"
	( cd "${fg}/localorigin" && echo a > a.txt && git add --all && git commit --quiet -m init && git remote add origin "${fg}/bare.git" )
	git init --quiet --bare -b main "${fg}/bare.git"
	: > "${fg}/local-gh.log"
	fAssert "[EnS8ftR] a local-path remote still falls through to gh, as it always did" \
		bash -c "cd '${fg}/localorigin' && PATH='${fgPath}' FAKE_GH_LOG='${fg}/local-gh.log' '${gitsby}' -q -NoFetch pr && grep -q '^pr list' '${fg}/local-gh.log'"

	if ((hasPty)); then
		## Only 'y' was a yes, so the word people actually type aborted.
		( cd "${renDir}" && echo yes >> yesword.txt )
		fAnswerPrompt yes "cd '${renDir}' && '${gitsby}' pullcom 'typed yes'" >/dev/null
		fAssert    "[EnPXgsm] 'yes' at the prompt is taken as a yes" \
			bash -c "cd '${renDir}' && git log -1 --pretty=%s | grep -qx 'typed yes'"
		## clone took only a full URL, and said so after the plan was confirmed rather than before.
		fAssertOut "[EnPXgsn] 'repo clone owner/name' plans a github URL"  'git clone .*github\.com[:/]octo/demo' \
			fAnswerPrompt n "cd '${work}' && '${gitsby}' repo clone octo/demo"
	fi
}

echo "gitsby regression tests (fixture: ${work})"

## One implementation, and it gates. The shim keeps ${gitsby} a plain single path so the
## 'bash -c' interpolation throughout the suite stays as it is.
goBin="${root}/src-go/gitsby"; [[ -x "${goBin}" ]] || goBin="${goBin}.exe"
[[ -x "${goBin}" ]] || { echo "no build at src-go/gitsby - run 'go build' there, or cicd.bash stage 2" >&2; exit 1; }
gitsby="${work}/gitsby-go"
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "${goBin}" > "${gitsby}"
chmod +x "${gitsby}"
fMakeFixture "${work}/go"
fRunSuite "go"

echo "passed: ${pass}, failed: ${fail}"
((fail == 0)) || exit 1


##	History:
##		- 20260722 JC: Created, alongside the bin/gitsby refactor.
##		- 20260722 JC: Run the suite per implementation; added the pwsh leg.
##		- 20260723 JC: Checks for the update command (and its old name), and for dev fast-forwarding after a release.
##		- 20260724 JC: clone and connect checks (dev checkout, no-op re-runs, plain-dir connect, nonempty/missing-remote and collision guards).
##		- 20260724 JC: exhaustive clone/connect coverage - no-dev/empty-dir/different-url clone edges, empty-repo + matching-url connect, and the gh owner/name paths (create, add https/ssh, nonempty-refuse) via a hermetic fake gh.
##		- 20260725 JC: Release-candidate version checks, and pr ok from the merged branch - the fake gh grew a pr merge that restores the stale origin ref, since that is what makes the real failure reproduce.
##		- 20260726 JC: Offline coverage inside a compound command, and the protected-branch refusal now has to name a command that still exists. The old offline check spelled the flag --no-fetch, which pwsh rejects, and matched the rejection - green for the wrong reason.
##		- 20260727 JC: Installer option coverage (--release/--target/--arch, both implementations). The refusal checks assert the reason rather than the exit code, since an installer that never heard of --target also exits nonzero. Plan checks need the confirmation to refuse instead of block, so they run under setsid and skip where it is absent.
##		- 20260728 JC: Offline push coverage (branch commands degrade and say so, publishing commands refuse, br land keeps origin's copy of the branch until the merge is pushed), and the file list 'repo connect' shows before a first publication. The offline block gets its own origin: by that point in the suite the shared one has a dev branch, so the merge target was not what the checks assumed.
##		- 20260730 JC: SSH identity coverage. Every other check uses a local-path origin, which has no ssh identity, so the whole line had shipped untested; a fake ssh reproduces the -G user defaulting that caused the bug.
##		- 20260730 JC: Offline message coverage: an in-sync park says "Nothing to push.", the skip warning names its branch, and an offline hotfix land names the recovery that publishes the default branch. Four of the six checks fail against the prior code; the hotfix-runs and back-merge checks are regression guards.
##		- 20260808 JC: Folder-account coverage: a faked HOME, a stub gh holding a token for one of two accounts, and two directory trees. The rules are written in the spelling a user of the running platform would type - '/tmp' is an entry in the Bash build's own mount table and means nothing to the PowerShell one, so a rule spelled that way matches on one leg only and reads as a port bug.
##		- 20260808 JC: The two identity checks run with GIT_AUTHOR_NAME/EMAIL unset. This file exports them for hermeticity, and they outrank every config, so with them in place neither check could see the thing it asks about.
##		- 20260808 JC: Coverage for 'repo url', 'account list|apply', the 'raw' passthrough, and the config-file argument in both builds. The joined '--config=FILE' spelling splits the two, so each leg is pinned to what it actually does.
##		- 20260810 JC: Refusals that only checked the exit code now check the reason too: a build predating these commands also exits 1, so nonzero alone proved nothing. One "check" turned out to run only git and could not fail; it asserts something now.
##		- 20260813 JC: How release.bash reads changelog.md, pinned in the source - proving it for real would mean cutting a release. Three of the four discriminate against the prior code; "the real vNEXT section is still findable" is a regression guard, since that section was always there. Bash leg only: neither file belongs to an implementation.
##		- 20260812 JC: Paths handed to PowerShell go in the platform's spelling, via fWinPath. An MSYS path means nothing to .NET, which reads it against the current drive root, so Set-Location, the script lookup and ReadAllBytes all failed and twelve checks on Windows reported on a fixture nothing had touched - seven red, five green because the thing they forbid also never happened. Also: a unix-absolute argument is rewritten by Git Bash before the native pwsh sees it, and the system install location is the platform's own.
##		- 20260813 JC: Recursive removal. demo-repo.bash is the only script here that removes a path someone else named, so it gets real checks; the rest are pinned to removing only what mktemp handed them. Sixteen of the seventeen discriminate against the prior code; the last is a regression guard on a file that never removed anything. The filesystem-root case is pinned rather than run, because running it against a build without the guard is 'rm -rf /'.
##		- 20260813 JC: Drop the two settings a working terminal carries that outrank everything pinned here - GIT_CONFIG_COUNT with its numbered keys, which beats every config file including a repo-local one, and an inherited GH_TOKEN, which is what the fake gh reports back. Twenty checks had been reporting on the terminal rather than the code. Pinned in all three harnesses; the runtime pair is a regression guard, since a clean machine passes either way.
##		- 20260814 JC: release.bash gates on the pipeline engine belonging to the platform. It always ran the Bash one, which knows nothing about Windows, so the check a release most depends on would have been the wrong pipeline there. Source pins, same reason as the changelog ones above; both discriminate against the prior file.
##		- 20260817 JC: Go leg. Same shim treatment, non-gating: the port is written against this suite, so its failures are the distance left, printed as counts and kept out of the totals. The leg runs without -e - prep commands legitimately die where a command is not ported yet, and the assertions do the judging.
##		- 20260818 JC: The renamed commands, their aliases, and identity - checked on the compiled leg only, since the scripts are frozen at the spelling they shipped with. The offline-sync check now takes either name; it is the one message that had pinned the old one.
##		- 20260818 JC: One leg. The scripted builds moved to legacy/ and their legs went with them, so the compiled build is the subject and it gates. The checks that were never about an implementation - installers, the frozen platform gates, the source pins - stayed, repointed at legacy/; dropping them with the leg they happened to ride would have lost 58 of them silently. The PowerShell-only block went with pwsh, and the per-implementation option spellings collapsed to one.
##		- 20260819 JC: The paper-cut sweep, and a pty for the two checks that have to answer the prompt rather than have it refuse - the plan is only printed to someone who could say yes, and one of them is about the word accepted there. Fourteen checks, all of which discriminate against the prior build; skipped where there is no 'script'.
##		- 20260819 JC: Which folder a clone resolves its account from. The account block grew a bare origin to clone between its two trees, and the identity block one check that the surrounding repo's owner is never asked about - the step that leaves no trace in the output, only in which token the fetch went out with.
##		- 20260819 JC: The shipping installers, at the repo root. Their whole plan is behind the network now - the release lookup and SHA256SUMS both land before it prints - so these checks stop at the argument parse, the refusals, the Windows hand-off, and pins on what a live run reaches. The legacy block stays beside them, still aimed at frozen files. 582 -> 613.
##		- 20260819 JC: A block for the directive-review defects: the bare-repo and .git-directory gates, the fetch naming origin, prune's offline hold-back, br switch with two remotes carrying the branch, the contested-folder tie-break both ways, --any-identity's own line, a file-sourced token checked against the account it claims, and the mode bits. Eighteen of them fail against the build that preceded the fixes; the two mode-bit ones are Linux/macOS only.
##		- 20260826 JC: The accounts file in its block layout: read in every shape, edited in place with the comments kept, created with its header and footer, and a flat file rewritten by its first edit. The old flat fixtures stay as regression guards on the reader that still takes them. 793 -> 808.
##		- 20260819 JC: Installer coverage for the directive-review fixes: the pre-release fallback (a stub curl answering only the list endpoint), a whole install end to end with the network stood in for, and pins on the staging, the verification exit code and the Windows PowerShell 5.1 support. Ten of them fail against the installers that preceded the fixes.
##		- 20260819 JC: Pipeline coverage for the directive review: the reproducible-build flags and a binary built with them, the core cap, --quick's cross-builds, govulncheck, the spawn-count and kept-build scripts, -q reaching the harnesses, the lint summary on a clean log, and the demo scenario's command names. Eleven fail against the pipeline that preceded them.
##		- 20260819 JC: br prune's plan checks follow the batched deletes - one line for the locals and one for the remotes, which is what the command runs. The remote half needed a fixture of its own: a plan check has to run the command to see a plan, and the check before it had already pruned the world it shared.
##		- 20260819 JC: The second adversarial pass. A folder rule spelled through a symlink, checked both by the account line and by which entry 'account list' marks; the shipped-code warning run from a subdirectory, where the pathspec had been reading from the wrong place; and a repo-local commit name or email on its own, each of which the account had been overriding. Five checks, all five failing against the build before them.
##		- 20260819 JC: A config file's discovery inputs are now neutralized in one place. Faking HOME never covered XDG_CONFIG_HOME (tried first) or APPDATA (tried last), so every block that tests discovery read the accounts of whoever was running the suite - thirty checks went red the day this machine had a config of its own. Plus four checks for the two defects found with it: an account named through GITSBY_ACCOUNT that carries no GitHub login, and a config file with a byte-order mark on it.
##		- 20260914 JC: The pre-push gate. cicd.bash --gate against a copy of the engine whose every tool is a stub: what it runs, what it leaves out, a failure per tool, and its refusals. Then the hook in a throwaway clone: the install and its three refusals, the pushed commit gated as committed, a failing push refused, deletes and tags left alone, one gate per commit, commits and checkouts from before the gate, git's own variables kept from the gate, a missing worktree, and the lock. Linux only. 35 of the 36 fail against the tree before them; the full-run check is a regression guard. 810 -> 846.
##		- 20260914 JC: More on the pre-push gate: a push from a subdirectory with a relative --work-tree, --install-hook run through cicd.bash, an older hook of ours replaced, a gate worktree left dirty or missing its .git file, and a push off Linux. 846 -> 852.
##		- 20260914 JC: The demo stage renders from its own build, stamped with the newest release rather than the commit: no tag, a tag that is not a version, a release candidate beside its release, the build removed, a later commit left alone, and a failed build. -q reaches the generator, which renders one scenario to the same bytes twice, and the committed gif ends on three seconds of black. The two build-site pins count four sites. The fixture checks are Linux only, and the renderer checks need Pillow. Nine of the eleven fail against the tree before them; two are regression guards. 852 -> 863.
##		- 20260914 JC: A relative folder rule. account set resolves one from the folder it runs in, and plain git then applies the account there and nowhere else under home. A relative path already in a file, block or flat, is listed as ignored, shown as no folder, and named by the identity block; account apply writes no rule for one, and account list warns about one an earlier apply left behind until apply removes it. Another user's '~' is refused. Twelve of the thirteen fail against the tree before them; the warning going away is a regression guard. 863 -> 876.
##		- 20260914 JC: br prune asks origin before deleting there, and leases the delete: a branch moved or already deleted on origin since the last fetch, one moved during the prompt, and origin unreachable under --no-fetch.
##		- 20260914 JC: account set and an accounts file it can't read: refused, named, kept, still passed over by reads, not shadowed from XDG_CONFIG_HOME, and a dead link or a folder in its place. Linux only. Nine of the ten fail against the tree before them; the read check is a regression guard. 889 -> 899.
##		- 20260914 JC: A key indented under another key in the accounts file is listed by the path that reaches it: under an account's key, under a key nothing reads, and under protocol, and in the identity block too. The key it sits under still applies, and a stacked folder list lists nothing. Four of the six fail against the tree before them; two are regression guards. 899 -> 905.
##		- 20260914 JC: repo connect and a remote it can't reach: refused as unknown, with ssh's reason, no pointer at repo create, and nothing set up. A local path that isn't a repo still reads as missing, and a credential in an unreachable url is not printed. Four of the seven fail against the tree before them; three are regression guards. 905 -> 912.
##		- 20260914 JC: A tea that fails to list its logins: the Git host line says tea couldn't be asked and repeats why, not that tea holds no login, and a host tea has no login for still says so. Two of the three fail against the tree before them; the no-login check is a regression guard. 912 -> 915.
##		- 20260914 JC: account set and a place it can't look: a folder that can't be searched is refused by name, with the chmod that fixes it, and nothing goes in ahead of it in XDG_CONFIG_HOME. A file that opens and then fails to read is refused when named and when found, where it crashed. Linux only. 915 -> 922.
##		- 20260915 JC: Two account set runs at once keep both keys, and a lock another run left is waited on, then refused by name. 922 -> 925.
##		- 20260915 JC: account apply takes a --config named with no folder, and includes the fragments beside it by absolute path. Both fail against the tree before them. 939 -> 941.
##		- 20260915 JC: A folder rule holding '[' binds that folder in plain git and not the one it would match as a pattern, for path and pathcontains. A relative tokenfile or sshkey is listed as ignored, reads no token and writes no key; account set writes a relative tokenfile absolute, and refuses a relative key typed in a folder with a space. All nine fail against the tree before them. 941 -> 950.
##		- 20260915 JC: A blank GIT_SSH_COMMAND or core.sshCommand is read as plain ssh when a push is compared against the account, and the gate fails when py_compile does. All three fail against the tree before them. 950 -> 953.
##		- 20260915 JC: release counts on from a tag with no v and refuses a typed version tagged that way. A br merge or release that conflicts is backed out, leaves the target alone, and goes back to the branch it ran from. repo url plans a Gitea remote's own address. Eight fail against the tree before them; the two refusals and the untouched dev are regression guards. 953 -> 964.
##		- 20260915 JC: A new release tag is spelled like the tag it counts from, and a typed version is tagged as typed. Typed versions in the older checks now carry the v they expect. Both new checks fail against the tree before them, and so does the count from a tag with no v, which now expects 1.4.3. 964 -> 966.
##		- 20260915 JC: The hotfix note is about more than documentation, not one folder. It fires for code in any folder, stays quiet in a repo with no release tags, and says so when the comparison can't run. The three older warning checks match the new wording. All six fail against the tree before them. 966 -> 969.
##		- 20260915 JC: Origin's copies of merged branches. A prune warning's advice, followed, clears the branch. A tag with a branch's name stops nothing, and br merge merges the branch rather than the tag. br merge --no-fetch keeps a copy someone else pushed to, and an offline br merge keeps the branch here so prune can clear both. Twelve of the fourteen fail against the tree before them; the kept tag and the merge's push are regression guards. The first prune's count drops by one, since the moved branch now stays here. 925 -> 939.
##		- 20260915 JC: account set refuses before its plan, so a refused one shows no plan and asks nothing. A protocol other than https or ssh is refused and never written, and account list names one in a file as ignored, in an account and at the top. An edit that respaces the file says so in the plan. Seven of the eight fail against the tree before them; a plan for a file already spaced that way is a regression guard. The prompt check needs script. 969 -> 977.
##		- 20260915 JC: Installer checks for Code Review 20260909 items 12-14. install.ps1 runs whole installs against stubbed web cmdlets that answer the way Windows PowerShell 5.1 and PowerShell 7 each do. Both help texts are checked against the options their parsers take, and the refusals, the prompt and the notices against the blank lines around them. 977 -> 1007.
##		- 20260915 JC: Pipeline housekeeping. The banner's copyright has a line of its own, and release.bash no longer cuts the build line at a comma. The lint report passes an archive listing that names errors.go and still reports one line in each tool's format. The Windows resource takes its copyright years from the program. All five fail against the tree before them; the two build-number checks match the two-line banner. 1007 -> 1012.
##		- 20260916 JC: A Syntax: refusal defines each placeholder under it, checked on repo url, repo clone, br hotfix and raw. account list prints a missing token source as (none). 1016 -> 1021.
##		- 20260924 JC: The pre-push gate runs on pushes to main only. Its checks push to main, and a push of another branch is checked to go out ungated. 1027 -> 1028.
##		- 20260924 JC: A folder rule typed with backslashes reads as typed under shcl 3.0, where 2.x read `\t` as a tab. 1028 -> 1029.
##		- 20260926 JC: A check for each closed backlog item that had none. Accounts and identity: the gh probe skipped where nothing reads it, repo connect's account and identity, account apply's global writes and credential username, a dead folder rule, ssh's '--'. Branches: release and the back-merge beside a tag with the branch's name, a merge whose branch is already gone from origin, prune's spawn count, origin/HEAD healed, a lone or unborn default branch, masked credentials in a step, the dropped aliases. Installers: bad checksum, no SHA256SUMS, no hash tool, a portal page, a bad redirect tag, joined options, end of input, the sudo mkdir, sums from the release's own generator. Pipeline: stage 0, stage 3, dogfood, the publish message, the real backlog gate, spawn-count's regression exit, the lint globs, the release dry run. The whole suite runs with XDG_CONFIG_HOME and APPDATA poisoned. The call-stack check looked for bash's text and now looks for a Go panic. Every new check fails against its fault. 1031 -> 1208.
##		- 20260926 JC: Every check carries a test ID at the front of its label. Checks for test-id.bash, and for backlog-check knowing a relabeled check by its ID. 1208 -> 1217.
##		- 20260926 JC: The suite runs behind a proxy on a closed port, so a check that reaches the network fails every run. The frozen install.ps1 one-liner checks stub its web lookups; two of them asked the live API and went red once its anonymous limit ran out. 1217 -> 1217.
##		- 20260926 JC: A pipeline run under -q still prints every regression and fuzz check. 1217 -> 1218.
##		- 20260926 JC: The same for parity and spawn counts, and spawn-count gives each command a verdict line. 1218 -> 1219.
##		- 20260927 JC: Native fuzz targets and spawn counts print their test IDs. 1219 -> 1220.
##		- 20260927 JC: The Go unit tests print a line per test with its ID, and a failure shows its output. 1220 -> 1222.
##		- 20260928 JC: Checks for the account source line, the fragment's credential username, a root folder rule, the installers' redirect tag and end of input, committed script modes, and the release dry run's closing lines. 1222 -> 1235.
##		- 20260928 JC: Checks for the information options after a command, the clone folder in full, the installers' write access, sudo, plan and mode, the pre-release tie, the release build from the tag, tool versions outside Go and under GOPATH, the README badges and .gitignore. 1235 -> 1254.
##		- 20260928 JC: account unset. It names each line it removes, leaves the rest as typed, treats a key already gone as nothing to do, refuses a value after the key, and prints its syntax with no key. Five of the six fail against the tree before them; the rest-as-typed check is a regression guard. 1254 -> 1260.
##		- 20261001 JC: Runs on macOS. The work folder is resolved, the accounts file goes where each platform looks, and 'sed -i', 'stat', 'grep -P', 'od' and 'script' are used in forms BSD also takes or are skipped without them. On macOS XDG_CONFIG_HOME is checked as ignored. A check for minting an ID for now. 1260 -> 1261.
##		- 20261003 JC: The macOS universal joiner: the joined file, its two refusals, and the dogfood target that uses it. The rm check covers the new script. 1268 -> 1273.
##		- 20261003 JC: release.bash past its dry run, with stubs: a 'pr create' with no URL, and a phase 3 where releases/latest can't be reached and the build line can't be read. Both fail against the tree before them. 1273 -> 1275.
##		- 20261003 JC: A long --version from the published binary, thousands of tags for release.bash and gen-winres.bash, a long SHA256SUMS for the installer, and a full spawn folder. All five fail against the tree before them. 1275 -> 1280.
##		- 20261003 JC: The Bash 4.4 floor in every pipeline script, spawn counts that aren't numbers, and the backlog gate on new-format review items. Every new check fails against the tree before it. 1288 -> 1310.
##		- 20261003 JC: spawn-count.bash fails a count over the limit written beside it, --record or not. Its stub build names its shell by path. 1310 -> 1311.
##		- 20261003 JC: The PowerShell lint starts pwsh once for every file, reads its rules from the settings file, and still fails a file that does not parse. The real pwsh runs it on a fixture of its own. 1311 -> 1318.
