#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	Purpose:
##		- Joins macOS builds for different CPUs into one universal binary, which
##		  runs on Intel and Apple silicon Macs alike.
##		- Does the one job of Apple's lipo, which only exists on a Mac. The file is a
##		  short big-endian header naming each build's CPU, offset and size, then the
##		  builds themselves, unchanged, so each keeps its own signature.
##	Syntax:
##		cicd/utility/macho-universal.bash OUT BUILD BUILD...
##	Exit: 0 written, 1 a build is missing, not 64-bit Mach-O, or repeats a CPU.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404 )); then
	printf '%s\n' "${0##*/}: needs bash 4.4 or newer, and this is bash ${BASH_VERSION}. On macOS, install one with 'brew install bash' and put it first on PATH." >&2; exit 1
fi
set -Eeuo pipefail

fDie(){ printf '%s\n' "macho-universal: $*" >&2; exit 1; }

## Each build starts on a 16 KiB boundary, the arm64 page size. lipo uses the same for both
## CPUs today.
alignPow=14

## Decimal bytes, space separated. od rather than xxd, which a stock Linux may not have.
fBytes(){ od -An -tu1 -j"$2" -N"$3" -- "$1" | xargs ;}
fLe32(){ echo $(( $1 | ($2 << 8) | ($3 << 16) | ($4 << 24) )) ;}
## Written as \x escapes for printf '%b'.
fBe32(){ printf '\\x%02x\\x%02x\\x%02x\\x%02x' $(( ($1 >> 24) & 255 )) $(( ($1 >> 16) & 255 )) $(( ($1 >> 8) & 255 )) $(( $1 & 255 )) ;}

(($# >= 3)) || fDie "usage: macho-universal.bash OUT BUILD BUILD..."
out="$1"; shift

cpus=(); subs=(); sizes=(); offsets=()
next=$(( 1 << alignPow ))
for thin in "$@"; do
	[[ -f "${thin}" ]] || fDie "no such file: ${thin}"
	read -r m0 m1 m2 m3 c0 c1 c2 c3 s0 s1 s2 s3 <<< "$(fBytes "${thin}" 0 12)"
	## Every Mac target Go builds is 64-bit and little-endian, so that is the only magic taken.
	[[ "${m0:-} ${m1:-} ${m2:-} ${m3:-}" == "207 250 237 254" ]] || fDie "not a 64-bit Mach-O build: ${thin}"
	cpu="$(fLe32 "${c0}" "${c1}" "${c2}" "${c3}")"
	for seen in "${cpus[@]}"; do [[ "${seen}" != "${cpu}" ]] || fDie "two builds for one CPU: ${thin}"; done
	size=$(( $(wc -c < "${thin}") ))
	cpus+=("${cpu}"); subs+=("$(fLe32 "${s0}" "${s1}" "${s2}" "${s3}")"); sizes+=("${size}"); offsets+=("${next}")
	next=$(( (next + size + (1 << alignPow) - 1) >> alignPow << alignPow ))
done

tmp="${out}.tmp.$$"
trap 'rm -f -- "${tmp:?}"' EXIT
{
	printf '%b' "$(fBe32 0xcafebabe)$(fBe32 "${#cpus[@]}")"
	for i in "${!cpus[@]}"; do
		printf '%b' "$(fBe32 "${cpus[i]}")$(fBe32 "${subs[i]}")$(fBe32 "${offsets[i]}")$(fBe32 "${sizes[i]}")$(fBe32 "${alignPow}")"
	done
	pos=$(( 8 + 20 * ${#cpus[@]} ))
	i=0
	for thin in "$@"; do
		head -c $(( offsets[i] - pos )) /dev/zero
		cat -- "${thin}"
		pos=$(( offsets[i] + sizes[i] ))
		i=$((i + 1))
	done
} > "${tmp}"
mv -f -- "${tmp}" "${out}"


##	History:
##		- 20261003 JC: Created. Dogfood puts one macOS file in one shared folder, and it has to
##		  run on both Intel and Apple silicon.
##		- 20261004 JC: fDie prints with printf. Every expansion braced, and shellcheck enforces it.
