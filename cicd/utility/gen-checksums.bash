#!/usr/bin/env bash

##	Purpose:
##		- Writes SHA256SUMS for the release assets (bin/gitsby, bin/gitsby.ps1), named as
##		  the assets are named on the release (no bin/ prefix), to stdout or a given file.
##		- Upload it with the assets when cutting a release:
##		      cicd/utility/gen-checksums.bash SHA256SUMS
##		      gh release upload vX.Y.Z bin/gitsby bin/gitsby.ps1 SHA256SUMS
##		  The installers verify against it when present.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -eu; set -o pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
outFile="${1:-}"

fSums(){
	( cd "${root}/bin" && sha256sum gitsby gitsby.ps1 )
}

if [[ -n "${outFile}" ]]; then
	fSums > "${outFile}"
	echo "[ Wrote ${outFile} ]"
else
	fSums
fi


##	History:
##		- 20260724 JC: Created.
