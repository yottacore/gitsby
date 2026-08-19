#!/usr/bin/env bash
## Point gh at the account that belongs to wherever the pipeline is running, for this process only.
##
## gh keeps one active account per host. A pipeline that assumes it is the right one acts as
## whoever was last switched to, which against another account's repo either 404s or - worse -
## succeeds somewhere it should not have. 'gh auth switch' is the wrong fix for a script: it is
## global, it outlives the run, and a failure part-way leaves the machine switched.
##
## Configuration is read through git, so an includeIf on the repo path selects it - the same
## mechanism that already picks the ssh key and the commit identity. In ~/.gitconfig-<account>:
##
##     [gitsby]
##         ghAccount   = someaccount
##         ghTokenFile = /path/to/token.txt
##
## Neither key is required, and nothing here fails when they are absent: an unconfigured checkout,
## a missing token file, or no gh at all all leave gh's own account in place. That is deliberate -
## a pipeline must not break on a box that was never set up this way.
##
## Usage:
##     source "${here}/include/gh-account.bash"
##     fGhAccount_Select            ## exports GH_TOKEN when it can, silently no-ops when it can't
##     fEcho "Acting as $(fGhAccount_Active)"

fGhAccount_Configured(){
	## The account configured for this path, or nothing.
	git config --get gitsby.ghAccount 2>/dev/null || true
:;}

fGhAccount_TokenFromFile(){
	## The token for a configured account that gh has never been logged in as. Unset, missing,
	## unreadable and empty are all "no token" - never an error.
	local file=""; file="$(git config --get gitsby.ghTokenFile 2>/dev/null || true)"
	[[ -n "${file}" && -r "${file}" ]] || return 0
	tr -d '[:space:]' < "${file}" 2>/dev/null || true
:;}

fGhAccount_Active(){
	## Who gh is currently acting as, honoring anything fGhAccount_Select already exported.
	## '?' when gh is missing, logged out, or offline.
	command -v gh &>/dev/null || { echo "?"; return 0; }
	local login=""; login="$(GH_PROMPT_DISABLED=1 gh api user --jq .login 2>/dev/null || true)"
	echo "${login:-?}"
:;}

fGhAccount_Select(){
	## Export GH_TOKEN for the configured account, if we can work out who that is and get a token
	## for them. GH_TOKEN outranks gh's stored credentials for this process and its children only,
	## so nothing is left behind and a killed run cannot strand the machine on the wrong account.
	local who=""; who="$(fGhAccount_Configured)"
	[[ -n "${who}" ]] || return 0
	command -v gh &>/dev/null || return 0
	## gh's own store first - it is the one that stays current. The file is the fallback for a box
	## where this account was never logged in.
	local token=""; token="$(gh auth token --user "${who}" 2>/dev/null || true)"
	[[ -n "${token}" ]] || token="$(fGhAccount_TokenFromFile)"
	[[ -n "${token}" ]] || return 0
	export GH_TOKEN="${token}"
:;}
