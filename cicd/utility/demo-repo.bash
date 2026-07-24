#!/usr/bin/env bash

##	Purpose:
##		- Builds a throwaway, fully anonymized git repo (+ a local bare "origin") for the
##		  demo gif. The scenario in cicd/demo-scenario.toml drives real gitsby commands
##		  against it, so nothing about the demo can go stale.
##		- Everything is generic: a /tmp path with no username, a fake HOME + gitconfig,
##		  a made-up author, and pinned commit dates. Pinned dates keep commit hashes (and
##		  thus gitsby's output, and thus the gif bytes) identical run to run, so cicd only
##		  regenerates the gif when the demo actually changes.
##		- Writes "$root/demo.env" holding the env the scenario steps source before each
##		  gitsby call.
##	Syntax: demo-repo.bash [ROOT]   (ROOT default: /tmp/gitsby-demo)
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -eu; set -o pipefail

root="${1:-/tmp/gitsby-demo}"
work="${root}/acme-api"
bare="${root}/acme-api-origin.git"

##	Generic identity + fixed dates. Same values for every commit -> reproducible hashes.
##	A local-path remote means gitsby never runs ssh -G, so no real ssh/login identity
##	can leak into the rendered output.
export HOME="${root}/home"
export GIT_CONFIG_GLOBAL="${root}/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME="Mika Rivers"
export GIT_AUTHOR_EMAIL="mika@example.com"
export GIT_COMMITTER_NAME="Mika Rivers"
export GIT_COMMITTER_EMAIL="mika@example.com"
export GIT_AUTHOR_DATE="2026-01-15T10:00:00 +0000"
export GIT_COMMITTER_DATE="2026-01-15T10:00:00 +0000"

rm -rf "${root}"
mkdir -p "${HOME}" "${work}"

cat > "${GIT_CONFIG_GLOBAL}" <<-EOF
	[user]
		name = ${GIT_AUTHOR_NAME}
		email = ${GIT_AUTHOR_EMAIL}
	[init]
		defaultBranch = main
	[advice]
		detachedHead = false
EOF

git init -q --bare "${bare}"

cd "${work}"
git init -q
printf 'name: acme-api\nport: 8080\n'          > config.yml
printf '# Acme API\n\nA small service.\n'       > README.md
git add -A
git commit -qm "Initial commit"
git remote add origin "${bare}"
git push -q -u origin main

##	Leave one pending edit so `status` (and the branch/land flow) has something to show.
printf 'retries: 3\n' >> config.yml

##	Env the scenario steps source before each gitsby call.
{
	echo "export HOME='${HOME}'"
	echo "export GIT_CONFIG_GLOBAL='${GIT_CONFIG_GLOBAL}'"
	echo "export GIT_CONFIG_SYSTEM=/dev/null"
	echo "export GIT_TERMINAL_PROMPT=0"
	echo "export GIT_AUTHOR_NAME='${GIT_AUTHOR_NAME}'"
	echo "export GIT_AUTHOR_EMAIL='${GIT_AUTHOR_EMAIL}'"
	echo "export GIT_COMMITTER_NAME='${GIT_COMMITTER_NAME}'"
	echo "export GIT_COMMITTER_EMAIL='${GIT_COMMITTER_EMAIL}'"
	echo "export GIT_AUTHOR_DATE='${GIT_AUTHOR_DATE}'"
	echo "export GIT_COMMITTER_DATE='${GIT_COMMITTER_DATE}'"
} > "${root}/demo.env"


##	History:
##		- 20260724 JC: v1.0. Anonymized offline repo builder for the demo gif.
