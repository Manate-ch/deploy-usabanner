#!/bin/sh
# bootstrap.sh - deploys the banner on Ubuntu from this copy of the module
# (docs/DECISIONS.md, D18). Where PowerShell 7 is missing, it installs it from
# Microsoft's package repository, packages.microsoft.com, the way Microsoft's
# own instructions do, never as the snap; then it runs Deploy-UsaBanner with
# the flags it was given:
#
#   sudo sh UsaBanner/linux/bootstrap.sh -Company Contoso -Environment PROD
#
# A list takes commas: -Services ssh,cron. Legal text of your own comes from a
# configuration file: -Path. The packages it installs are
# packages-microsoft-prod (Microsoft's repository and its signing key) and
# powershell, with what apt needs for them; wget too, where the host has
# neither wget nor curl. PowerShell stays when the banner is removed: it may
# serve more than the banner. PowerShell's own logging stays as Microsoft
# ships it.
#
# USABANNER_ROOT (tests only) prefixes /etc/os-release.

root=${USABANNER_ROOT:-}
here=$(dirname "$0")

fail() {
	printf 'bootstrap.sh: %s\n' "$*" >&2
	exit 1
}

field() {
	# A field of os-release, read as text and never run, without its quotes.
	sed -n "s/^$1=//p" "$root/etc/os-release" 2>/dev/null | tr -d "\"'"
}

[ "$(id -u)" = 0 ] || fail 'it installs PowerShell and deploys the banner, so it runs as root: sudo sh bootstrap.sh ...'
[ "$(field ID)" = ubuntu ] || fail 'this host is not Ubuntu. Deploy-UsaBanner works on Ubuntu (24.04 and later) and Windows Server (2022 and later)'

if ! command -v pwsh >/dev/null 2>&1; then
	version=$(field VERSION_ID)
	case $version in
	'' | *[!0-9.]*) fail "/etc/os-release gives no Ubuntu version to find Microsoft's repository package by: '$version'" ;;
	esac
	echo "bootstrap.sh: installing PowerShell 7 from Microsoft's package repository (packages-microsoft-prod, powershell)"
	DEBIAN_FRONTEND=noninteractive
	export DEBIAN_FRONTEND
	if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
		{ apt-get update && apt-get install -y wget; } || fail 'apt-get could not install wget, to download with'
	fi
	url="https://packages.microsoft.com/config/ubuntu/$version/packages-microsoft-prod.deb"
	deb=$(mktemp) || fail 'mktemp could not make a file to download into'
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$deb" "$url"
	else
		wget -q -O "$deb" "$url"
	fi || {
		rm -f "$deb"
		fail "could not download $url. Microsoft publishes it for the Ubuntu releases it supports (22.04, 24.04 and 26.04), not for interim ones"
	}
	dpkg -i "$deb" || {
		rm -f "$deb"
		fail "dpkg could not install Microsoft's repository package"
	}
	rm -f "$deb"
	apt-get update || fail "apt-get update failed, with Microsoft's repository added"
	apt-get install -y powershell || fail 'apt-get could not install powershell'
	command -v pwsh >/dev/null 2>&1 || fail 'powershell is installed, but there is no pwsh on the PATH'
fi

exec pwsh -NoProfile -NonInteractive -File "$here/bootstrap.ps1" "$@"
