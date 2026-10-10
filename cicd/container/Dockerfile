# Lint, build, test and demo tools for 'cicd.bash --container', pinned, so stages 1-4
# and the demo gif don't depend on what the host has installed. Sync, dogfood, remote
# tests and publish stay on the host.
#
# The versions come from config.bash as build args, and the tag hashes this file
# plus those args. A version bump without its checksum here fails the build.
#
# Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
# SPDX-License-Identifier: MIT

FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# Apt reads the snapshot the base image was cut from, so a trixie point release can't
# move Pillow, freetype or cairo under the demo gif. The base names it in a comment.
ARG APT_SNAP=20261005T000000Z
RUN sed -i -e "s|^URIs: http://deb.debian.org/debian-security|URIs: http://snapshot.debian.org/archive/debian-security/${APT_SNAP}|" \
		-e "s|^URIs: http://deb.debian.org/debian\$|URIs: http://snapshot.debian.org/archive/debian/${APT_SNAP}|" \
		-e 's|^Signed-By:|Check-Valid-Until: no\nSigned-By:|' /etc/apt/sources.list.d/debian.sources \
	&& ! grep -q deb.debian.org /etc/apt/sources.list.d/debian.sources

# gcc is for go test -race, libicu and libgssapi for pwsh. The python and font
# packages are what the demo renderer draws with.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		bash ca-certificates curl openssl xz-utils unzip gcc libc6-dev \
		python3 python3-pil python3-fonttools python3-gi python3-gi-cairo gir1.2-pango-1.0 \
		fontconfig fonts-dejavu-core fonts-noto-color-emoji gifsicle \
		libicu76 libgssapi-krb5-2 \
	&& rm -rf /var/lib/apt/lists/*

# The demo's face. The emoji font above is Debian's, a different build from the one on
# b23, but the demo draws no emoji today, so the gif's bytes don't see it.
ARG MONASPACE_VER=1.400
ARG MONASPACE_SHA256=ab66d71be751495f679727332a3345597943bd4d7beebca03f5cde04bf994de7
RUN cd /tmp \
	&& curl -fsSLo m.zip "https://github.com/githubnext/monaspace/releases/download/v${MONASPACE_VER}/monaspace-static-v${MONASPACE_VER}.zip" \
	&& echo "${MONASPACE_SHA256}  m.zip" | sha256sum -c - \
	&& mkdir -p /usr/local/share/fonts/monaspace \
	&& unzip -j -q m.zip 'Static Fonts/Monaspace Argon/MonaspaceArgon-SemiBold.otf' -d /usr/local/share/fonts/monaspace \
	&& rm -f m.zip && fc-cache -f >/dev/null

ARG VER_Pillow
ARG VER_gifsicle
RUN python3 -c "import PIL; assert PIL.__version__ == '${VER_Pillow:?}', PIL.__version__" \
	&& gifsicle --version | awk -v want="${VER_gifsicle:?}" 'NR==1 { if ($NF != want) { print "gifsicle " $NF; exit 1 } }'

# git and strace are newer on the host than in trixie, and both change a spawn count.
# Same builds, from the snapshot archive.
ARG VER_git
ARG VER_strace
ARG GIT_SNAP=20250827T031115Z
ARG GIT_SHA256=f2e71e4d52cb2eb9d0b81119cd22d43c1aea4612d9cbd74efa634beebca49fc5
ARG GITMAN_SHA256=f13c223498607e18bc22121e4cbc3829d4a589a2711d6cf25a6848711180ca4b
ARG STRACE_SNAP=20260125T203410Z
ARG STRACE_SHA256=b0050028a886224ad1eba4d5f063443c5762e9503b18e13a13151c6961af9325
WORKDIR /tmp/deb
RUN : "${VER_git:?}${VER_strace:?}" \
	&& snap=https://snapshot.debian.org/archive/debian \
	&& curl -fsSLo git.deb "${snap}/${GIT_SNAP}/pool/main/g/git/git_${VER_git}-1_amd64.deb" \
	&& curl -fsSLo git-man.deb "${snap}/${GIT_SNAP}/pool/main/g/git/git-man_${VER_git}-1_all.deb" \
	&& curl -fsSLo strace.deb "${snap}/${STRACE_SNAP}/pool/main/s/strace/strace_${VER_strace}+ds-2_amd64.deb" \
	&& printf '%s  %s\n' "${GIT_SHA256}" git.deb "${GITMAN_SHA256}" git-man.deb "${STRACE_SHA256}" strace.deb | sha256sum -c - \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends ./git-man.deb ./git.deb ./strace.deb \
	&& rm -rf /var/lib/apt/lists/* \
	&& cd / && rm -rf /tmp/deb

ARG VER_go
ARG VER_shellcheck
ARG VER_markdownlint
ARG VER_PSScriptAnalyzer
ARG VER_staticcheck
ARG VER_golangci_lint
ARG VER_govulncheck
ARG VER_goversioninfo

# For the versions in config.bash on 20261010. Upstream shellcheck and PSGallery
# post no checksums, so those two are from the download.
ARG GO_SHA256=990e6b4bbba816dc3ee129eaeaf4b42f17c2800b88a2166c265ac1a200262282
ARG SC_SHA256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
ARG PSA_SHA256=14e634c828eb98efb9f40b2918ba90f139ed5eccdf663a2a747736d996995d60
# Only here for markdownlint-cli, which wants node 22.
ARG NODE_VER=22.23.2
ARG NODE_SHA256=d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307
ARG PWSH_VER=7.6.6
ARG PWSH_SHA256=ddbc4a2d113bbd46d283cfedcbcd117a70caefd7673f41f2b4e0000badf103bc

WORKDIR /tmp/dl
RUN : "${VER_go:?}${VER_shellcheck:?}${VER_markdownlint:?}${VER_PSScriptAnalyzer:?}" \
	&& curl -fsSLo go.tgz "https://go.dev/dl/go${VER_go}.linux-amd64.tar.gz" \
	&& echo "${GO_SHA256}  go.tgz" | sha256sum -c - \
	&& tar -C /opt -xzf go.tgz \
	&& curl -fsSLo sc.txz "https://github.com/koalaman/shellcheck/releases/download/v${VER_shellcheck}/shellcheck-v${VER_shellcheck}.linux.x86_64.tar.xz" \
	&& echo "${SC_SHA256}  sc.txz" | sha256sum -c - \
	&& tar -C /usr/local/bin --strip-components=1 -xJf sc.txz "shellcheck-v${VER_shellcheck}/shellcheck" \
	&& curl -fsSLo node.txz "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-x64.tar.xz" \
	&& echo "${NODE_SHA256}  node.txz" | sha256sum -c - \
	&& mkdir /opt/node && tar -C /opt/node --strip-components=1 -xJf node.txz \
	&& PATH="/opt/node/bin:${PATH}" npm install -g --prefix /opt/node --no-fund --no-audit "markdownlint-cli@${VER_markdownlint}" \
	&& curl -fsSLo pwsh.tgz "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VER}/powershell-${PWSH_VER}-linux-x64.tar.gz" \
	&& echo "${PWSH_SHA256}  pwsh.tgz" | sha256sum -c - \
	&& mkdir /opt/pwsh && tar -C /opt/pwsh -xzf pwsh.tgz && chmod +x /opt/pwsh/pwsh \
	&& ln -s /opt/pwsh/pwsh /usr/local/bin/pwsh \
	&& curl -fsSLo psa.nupkg "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/${VER_PSScriptAnalyzer}" \
	&& echo "${PSA_SHA256}  psa.nupkg" | sha256sum -c - \
	&& psa="/usr/local/share/powershell/Modules/PSScriptAnalyzer/${VER_PSScriptAnalyzer}" \
	&& mkdir -p "${psa}" && unzip -q psa.nupkg -d "${psa}" \
	&& rm -rf "${psa}/_rels" "${psa}/package" "${psa}/[Content_Types].xml" "${psa}/PSScriptAnalyzer.nuspec" \
	&& cd / && rm -rf /tmp/dl

# Built by the toolchain above, from the module proxy and its checksum db.
RUN : "${VER_staticcheck:?}${VER_golangci_lint:?}${VER_govulncheck:?}${VER_goversioninfo:?}" \
	&& export GOTOOLCHAIN=local GOBIN=/usr/local/bin GOPATH=/tmp/gopath GOCACHE=/tmp/gocache \
	&& /opt/go/bin/go install "honnef.co/go/tools/cmd/staticcheck@${VER_staticcheck}" \
	&& /opt/go/bin/go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${VER_golangci_lint}" \
	&& /opt/go/bin/go install "golang.org/x/vuln/cmd/govulncheck@${VER_govulncheck}" \
	&& /opt/go/bin/go install "github.com/josephspurrier/goversioninfo/cmd/goversioninfo@${VER_goversioninfo}" \
	&& rm -rf /tmp/gopath /tmp/gocache

# Runs as the caller's uid, which has no passwd entry. /cache takes the named volume,
# which copies this dir's mode when new, so anyone can write.
RUN mkdir -m 1777 /cache /cache/home
ENV PATH=/opt/go/bin:/opt/node/bin:${PATH} \
	HOME=/cache/home \
	GOTOOLCHAIN=local \
	GITSBY_CICD_IN_CONTAINER=1 \
	POWERSHELL_TELEMETRY_OPTOUT=1 \
	POWERSHELL_UPDATECHECK=Off \
	DOTNET_CLI_TELEMETRY_OPTOUT=1
WORKDIR /
