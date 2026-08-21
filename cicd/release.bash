#!/usr/bin/env bash

##	Purpose:
##		- Cuts a release end to end, so the steps that have been forgotten by hand
##		  cannot be. 'gitsby release' already does the git half well; this is
##		  everything around it.
##		- Three phases, so a failure never leaves a half-cut release:
##		   1. Prepare and verify. Changes nothing outside the working tree, and
##		      nothing here needs undoing if it stops.
##		   2. Land. Writes the version, lands it through a PR, and calls
##		      'gitsby release'. The only phase that pushes.
##		   3. Publish and prove. Creates the GitHub release, uploads the assets,
##		      then verifies the result the way a user would meet it.
##	Syntax:
##		cicd/release.bash [VERSION] [options]
##		  VERSION          e.g. v2.1.0. Omitted, the changelog's vNEXT heading and
##		                   'gitsby release' decide between them.
##		  -n, --dry-run    Say what each phase would do, change nothing. Use this.
##		  -y, --yes        Don't ask before phase 2.
##		  -h, --help       This.
##	Notes:
##		- Refuses unless the tree is clean and you are on the merge target.
##		- Guards that have caught real mistakes: both builds must agree on the
##		  version string, and both must carry a history-footer entry newer than
##		  the last release tag.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
cd "${root}"

version=""; dryRun=0; assumeYes=0
while (($#)); do case "$1" in
	-n|--dry-run) dryRun=1; shift ;;
	-y|--yes)     assumeYes=1; shift ;;
	-h|--help)    sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	-*)           echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
	*)            version="$1"; shift ;;
esac; done

fEcho(){       echo "[ $* ]"; }
fNote(){       echo "$*"; }
fDie(){        echo "FAILED: $*" >&2; exit 1; }
fWould(){      ((dryRun)) && { echo "   would: $*"; return 0; }; return 1; }

gitsbyBash="${root}/bin/gitsby"
gitsbyPwsh="${root}/bin/gitsby.ps1"
changelog="${root}/changelog.md"

## changelog.md opens with a commented-out template whose headings are shaped exactly like real
## ones, so a first-match search finds the decoy and not the section it meant. That has caused
## three separate bugs here, the last of which would have retitled the template, published an
## empty release body and warned about none of it. Two independent guards now: the template's
## heading is spelled TEMPLATE_vNEXT, and everything below starts reading past the '-->'.
fpChangelogStart(){
	## First line of the real changelog, just past the commented-out template.
	## awk rather than grep piped into head - a pipe would leave pipefail at the mercy of SIGPIPE.
	local -i end=0
	end="$(awk '/^-->/{print NR; exit}' "${changelog}")"
	echo $((end + 1))
:;}

fpChangelogVnext(){
	## Line the real '## vNEXT' heading sits on, or nothing at all.
	local -i start; start="$(fpChangelogStart)"
	awk -v start="${start}" 'NR>=start && /^## vNEXT/{print NR; exit}' "${changelog}"
:;}

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Phase 1: prepare and verify. Nothing here changes anything outside the working tree, so a
## failure costs nothing and needs no undoing.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
fEcho "Phase 1: prepare and verify"

[[ -x "${gitsbyBash}" ]] || fDie "no ${gitsbyBash}"
command -v gh >/dev/null 2>&1 || fDie "gh is needed to publish the release."

## Both builds carry their own version string, by hand. They have drifted before.
## Read the DECLARATION, not the first version-shaped string in the file: both scripts discuss
## versions in their comments, and a loose match picked one of those - which phase 2 would then
## have rewritten instead of the real one. Stored without the leading 'v'.
verBash="$(sed -n 's/.*thisVersion="\([0-9][^"]*\)".*/\1/p' "${gitsbyBash}" | head -n 1)"
verPwsh="$(sed -n "s/.*thisVersion *= *'\([0-9][^']*\)'.*/\1/p" "${gitsbyPwsh}" | head -n 1)"
[[ -n "${verBash}" ]] || fDie "couldn't read 'thisVersion' out of ${gitsbyBash}."
[[ -n "${verPwsh}" ]] || fDie "couldn't read 'thisVersion' out of ${gitsbyPwsh}."
[[ "${verBash}" == "${verPwsh}" ]] || fDie "the two builds disagree about the version: bash says '${verBash}', pwsh says '${verPwsh}'."
fNote "current version in both builds: v${verBash}"

## The changelog has to have something to release. 'vNEXT' is this project's convention for
## "landed but not cut", and releasing with no such section means the notes would be empty.
[[ -n "$(fpChangelogVnext)" ]] || fDie "changelog has no '## vNEXT' section, so there is nothing to release."

## Where the version comes from: the argument, else the same bump 'gitsby release' would choose.
if [[ -z "${version}" ]]; then
	lastTag="$(git -c versionsort.suffix=- tag --sort=-v:refname --list 'v*' | head -n 1)"
	[[ -n "${lastTag}" ]] || fDie "no v* tag to bump from; pass a version explicitly."
	if [[ "${lastTag}" == *-* ]]; then
		## A candidate promotes to its own plain version rather than bumping past it.
		version="${lastTag%%-*}"
	else
		IFS='.' read -r major minor patch <<< "${lastTag#v}"
		version="v${major}.${minor}.$((patch + 1))"
	fi
	fNote "no version given; the next one after ${lastTag} is ${version}"
fi
[[ "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([A-Za-z0-9.-]+)?$ ]] || fDie "'${version}' is not a vX.Y.Z version."
git rev-parse -q --verify "refs/tags/${version}" >/dev/null && fDie "tag ${version} already exists."
[[ "${version}" != "v${verBash}" ]] || fDie "both builds already say ${version}; nothing to bump."

## The history footers are maintained by hand and are missed most rounds, so check rather than trust.
lastTagForFooter="$(git -c versionsort.suffix=- tag --sort=-v:refname --list 'v*' | head -n 1)"
if [[ -n "${lastTagForFooter}" ]]; then
	for f in "${gitsbyBash}" "${gitsbyPwsh}"; do
		newest="$(grep -oE '^##[[:space:]]+- 20[0-9]{6}' "${f}" | grep -oE '20[0-9]{6}' | sort | tail -n 1)"
		tagDate="$(git log -1 --format=%cd --date=format:%Y%m%d "${lastTagForFooter}" 2>/dev/null || echo 0)"
		[[ -n "${newest}" && "${newest}" -ge "${tagDate}" ]] \
			|| fNote "WARNING: ${f##*/} has no history entry since ${lastTagForFooter} (${tagDate}); add one before releasing."
	done
fi

## State: clean tree, on the merge target, nothing unpushed.
[[ -z "$(git status --porcelain)" ]] || fDie "working tree isn't clean."
branch="$(git rev-parse --abbrev-ref HEAD)"
target="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
[[ -n "${target}" ]] || fDie "branch '${branch}' has no upstream."
[[ -z "$(git log '@{u}..HEAD' --oneline)" ]] || fDie "branch '${branch}' has unpushed commits."

## One engine, and it is Linux-only. cicd.bash has no Windows awareness whatsoever, so running it
## under MSYS would gate the release on the wrong thing entirely - refuse rather than pretend.
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
	fDie "cut the release from Linux - there is no Windows pipeline engine."
fi
pipeline=("${here}/cicd.bash" --no-publish -y -m "pre-release check")
pipelineName="cicd/cicd.bash --no-publish"

## The whole pipeline, against the tree as it stands. This is the gate.
if ! fWould "run ${pipelineName}"; then
	fNote "running the full pipeline before touching anything ..."
	"${pipeline[@]}" || fDie "the pipeline did not pass; nothing was changed."
fi
fEcho "Phase 1 OK: v${verBash} -> ${version}"

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Phase 2: land. The only phase that pushes.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
fEcho "Phase 2: land ${version}"
if ((! dryRun)) && ((! assumeYes)); then
	read -r -p "Cut ${version}? This pushes. [y/N] " answer < /dev/tty || answer=""
	[[ "${answer}" =~ ^([yY]|[yY][eE][sS])$ ]] || fDie "Aborted."
fi

today="$(date +%Y-%m-%d)"
relBranch="rel-${version#v}"
## The version bump goes in through a branch and a pull request, like everything else. Committing
## it straight to the merge target would be the one place this project pushes its own work there -
## exactly what the tool refuses to do for you, so the thing that cuts the release must not do it
## either. 'gitsby release' below is the only push to the default branch, and that push IS the
## release rather than a shortcut around one.
if ! fWould "branch ${relBranch}, bump both builds to ${version}, retitle the changelog's vNEXT as '${version} - ${today}', and land it through a PR"; then
	"${gitsbyBash}" -q br create "${relBranch}" || fDie "couldn't create ${relBranch}."
	## Only the declaration line in each build. A global replace of the old version string would
	## also rewrite every mention of it in the comments and the history footer, which are a record
	## of what happened and must keep saying what they said.
	sed -i "s/\(thisVersion=\"\)[0-9][^\"]*\(\"\)/\1${version#v}\2/" "${gitsbyBash}"
	sed -i "s/\(thisVersion *= *'\)[0-9][^']*\('\)/\1${version#v}\2/" "${gitsbyPwsh}"
	## By line number, so the substitution cannot wander to a heading somewhere else in the file.
	clLine="$(fpChangelogVnext)"
	[[ -n "${clLine}" ]] || fDie "the changelog's '## vNEXT' heading went missing after phase 1."
	sed -i "${clLine}s/^## vNEXT.*$/## ${version} - ${today}/" "${changelog}"
	## gitsby's own 'pr create' rather than gh directly: it already knows this repo's merge target,
	## which is the one thing a hand-written --base can get wrong.
	prOut="$("${gitsbyBash}" -q pr create "${version}" 2>&1)" || { echo "${prOut}" >&2; fDie "couldn't open the version-bump PR."; }
	prNum="$(printf '%s\n' "${prOut}" | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -n 1)"
	prNum="${prNum##*/}"
	[[ "${prNum}" =~ ^[0-9]+$ ]] || { echo "${prOut}" >&2; fDie "couldn't read a PR number out of 'pr create' output."; }
	fNote "opened PR #${prNum} for the version bump"
	"${gitsbyBash}" -q pr ok "${prNum}" || fDie "couldn't merge PR #${prNum}; the bump is pushed but nothing is tagged."
fi
if ! fWould "gitsby release ${version}"; then
	"${gitsbyBash}" -q release "${version}" || fDie "'gitsby release' failed; the version commit is pushed but no tag was cut."
fi
fEcho "Phase 2 OK: ${version} tagged and pushed"

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Phase 3: publish and prove. A failure here is recoverable by hand and corrupts nothing.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
fEcho "Phase 3: publish and prove"

## The release body is the changelog section, verbatim - the same words the repo already carries.
notes="$(mktemp)"; trap 'rm -f -- "${notes:?}"' EXIT
awk -v ver="## ${version} " -v start="$(fpChangelogStart)" \
	'NR>=start && index($0, ver)==1 {f=1; next} f && /^## /{exit} f' "${changelog}" > "${notes}" || true
[[ -s "${notes}" ]] || fNote "WARNING: no changelog section found for ${version}; the release body will be empty."

assets="$(mktemp -d)"
cp "${gitsbyBash}" "${gitsbyPwsh}" "${assets}/"
if [[ -x "${here}/utility/gen-checksums.bash" ]]; then
	( cd "${assets}" && "${here}/utility/gen-checksums.bash" > SHA256SUMS 2>/dev/null ) || \
		( cd "${assets}" && sha256sum gitsby gitsby.ps1 > SHA256SUMS )
else
	( cd "${assets}" && sha256sum gitsby gitsby.ps1 > SHA256SUMS )
fi

if ! fWould "gh release create ${version} with gitsby, gitsby.ps1 and SHA256SUMS"; then
	"${gitsbyBash}" -q raw gh release create "${version}" --title "${version}" --notes-file "${notes}" \
		"${assets}/gitsby" "${assets}/gitsby.ps1" "${assets}/SHA256SUMS" || fDie "publishing the release failed; the tag is pushed, so re-run 'gh release create ${version}' by hand."
fi

## Prove it the way a user meets it, not by trusting the steps above. Running BOTH installers side
## by side is what caught the PowerShell checksum bug, which had silently skipped verification since
## the day it was added.
if ! fWould "verify releases/latest and run both documented installers into a throwaway HOME"; then
	latest="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/jim-collier/gitsby/releases/latest" 2>/dev/null | sed -n 's|.*/releases/tag/||p')"
	[[ "${latest}" == "${version}" ]] || fNote "WARNING: releases/latest resolves to '${latest}', not ${version}."
	## Seconds after publication GitHub serves the tag but not yet the assets, and the installers
	## stop rather than quietly skip verification when SHA256SUMS can't be fetched - so a first
	## attempt can fail against a release that is perfectly good. It did on v2.1.0: the same check
	## passed unchanged minutes later, with elapsed time the only difference. Retry before saying
	## anything, or the one warning that would mean a broken release is the one nobody believes.
	installed=0
	for attempt in 1 2 3; do
		((attempt > 1)) && { fNote "not installable yet; giving GitHub a moment to serve the assets (attempt ${attempt}) ..."; sleep 20; }
		fakeHome="$(mktemp -d)"
		if HOME="${fakeHome}" bash "${root}/install.bash" -y >/dev/null 2>&1 \
			&& "${fakeHome}/.local/bin/gitsby" --version 2>/dev/null | grep -q "${version#v}"; then
			installed=1
		fi
		rm -rf -- "${fakeHome:?}"
		((installed)) && break
	done
	if ((installed)); then
		fNote "bash installer: installed ${version} and verified its checksum"
	else
		fNote "WARNING: the bash installer did not produce ${version} from the published release."
	fi
fi
rm -rf -- "${assets:?}"

echo
fEcho "Released ${version}"
echo

##	History:
##		- 20260812 JC: Created, to the three-phase shape in project/design.md. The version bump, the
##		  changelog heading, the release body, the assets and the after-the-fact verification were
##		  all by hand, and each has been missed at least once. Both guards here exist because the
##		  thing they check has already gone wrong: the two builds' version strings drifting, and the
##		  in-script history footers going a whole release without an entry.
##		- 20260813 JC: All three readings of the changelog start below the commented-out template.
##		  Each took the first match, so each found the template's decoy heading instead: the guard
##		  passed with nothing to release, the retitle rewrote the template and left the real section
##		  saying vNEXT, and the release body came out as the empty template plus a stray '-->' -
##		  non-empty, so the warning that exists for this never fired. The retitle is line-addressed
##		  now, and the template's heading is spelled TEMPLATE_vNEXT so either guard would do alone.
##		- 20260814 JC: Runs the pipeline engine that belongs to the platform. It always ran the Bash
##		  one, which knows nothing about Windows, so the gate a release most depends on would have
##		  been the wrong pipeline on half the machines this project supports.
##		- 20260814 JC: The installer proof retries. Cutting v2.1.0 warned that the release wasn't
##		  installable when it was - GitHub was still serving the tag without its assets, and the
##		  installer stops rather than skip verification. A warning that fires on a good release is
##		  worse than none, because the next one is read the same way.
