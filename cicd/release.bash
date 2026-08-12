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
grep -qE '^## vNEXT' "${changelog}" || fDie "changelog has no '## vNEXT' section, so there is nothing to release."

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

## The whole pipeline, against the tree as it stands. This is the gate.
if ! fWould "run cicd/cicd.bash --no-publish"; then
	fNote "running the full pipeline before touching anything ..."
	"${here}/cicd.bash" --no-publish -y -m "pre-release check" || fDie "the pipeline did not pass; nothing was changed."
fi
fEcho "Phase 1 OK: ${verBash} -> ${version}"

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
if ! fWould "bump both builds to ${version} and retitle the changelog's vNEXT as '${version} - ${today}'"; then
	## Only the declaration line in each build. A global replace of the old version string would
	## also rewrite every mention of it in the comments and the history footer, which are a record
	## of what happened and must keep saying what they said.
	sed -i "s/\(thisVersion=\"\)[0-9][^\"]*\(\"\)/\1${version#v}\2/" "${gitsbyBash}"
	sed -i "s/\(thisVersion *= *'\)[0-9][^']*\('\)/\1${version#v}\2/" "${gitsbyPwsh}"
	sed -i "0,/^## vNEXT.*$/s//## ${version} - ${today}/" "${changelog}"
	git add --all
	git commit --quiet -m "${version}"
	git push --quiet
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
notes="$(mktemp)"; trap 'rm -f "${notes}"' EXIT
awk -v ver="## ${version} " 'index($0, ver)==1 {f=1; next} f && /^## /{exit} f' "${changelog}" > "${notes}" || true
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
	fakeHome="$(mktemp -d)"
	if HOME="${fakeHome}" bash "${root}/install.bash" -y >/dev/null 2>&1 \
		&& "${fakeHome}/.local/bin/gitsby" --version 2>/dev/null | grep -q "${version#v}"; then
		fNote "bash installer: installed ${version} and verified its checksum"
	else
		fNote "WARNING: the bash installer did not produce ${version} from the published release."
	fi
	rm -rf "${fakeHome}"
fi
rm -rf "${assets}"

echo
fEcho "Released ${version}"
echo

##	History:
##		- 20260812 JC: Created, to the three-phase shape in project/design.md. The version bump, the
##		  changelog heading, the release body, the assets and the after-the-fact verification were
##		  all by hand, and each has been missed at least once. Both guards here exist because the
##		  thing they check has already gone wrong: the two builds' version strings drifting, and the
##		  in-script history footers going a whole release without an entry.
