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
# neither wget nor curl. On a host joined to AD (one with /etc/krb5.keytab) it
# installs ldap-utils, krb5-user and libsasl2-modules-gssapi-mit too, where any
# is missing: the periodic job reads the computer object's Description with
# them (D29). krb5-config is told first not to add servers to krb5.conf, which
# on a first install it would for a realm found by DNS alone; it then leaves
# the file as the join wrote it. A failed install there is a warning: the
# banner deploys, and takes the tier and role from AD once the tools are in.
# Packages stay when the banner is removed: they may serve more than the
# banner. PowerShell's own logging stays as Microsoft ships it.
#
# apt waits up to 10 minutes for the package lock: at boot, unattended-upgrades
# may hold it, and a startup script that gave up would deploy only at the next.
#
# USABANNER_ROOT (tests only) prefixes /etc/os-release and /etc/krb5.keytab.

root=${USABANNER_ROOT:-}
here=$(dirname "$0")

fail() {
	printf 'bootstrap.sh: %s\n' "$*" >&2
	exit 1
}

apt_get() {
	apt-get -o DPkg::Lock::Timeout=600 "$@"
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
		{ apt_get update && apt_get install -y wget; } || fail 'apt-get could not install wget, to download with'
	fi
	url="https://packages.microsoft.com/config/ubuntu/$version/packages-microsoft-prod.deb"
	# .deb: apt-get installs a file by its path only when the name says it is a package.
	deb=$(mktemp --suffix=.deb) || fail 'mktemp could not make a file to download into'
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$deb" "$url"
	else
		wget -q -O "$deb" "$url"
	fi || {
		rm -f "$deb"
		fail "could not download $url. Microsoft publishes it for the Ubuntu releases it supports (22.04, 24.04 and 26.04), not for interim ones"
	}
	apt_get install -y "$deb" || {
		rm -f "$deb"
		fail "apt-get could not install Microsoft's repository package"
	}
	rm -f "$deb"
	apt_get update || fail "apt-get update failed, with Microsoft's repository added"
	apt_get install -y powershell || fail 'apt-get could not install powershell'
	command -v pwsh >/dev/null 2>&1 || fail 'powershell is installed, but there is no pwsh on the PATH'
fi

if [ -e "$root/etc/krb5.keytab" ]; then
	missing=
	for package in ldap-utils krb5-user libsasl2-modules-gssapi-mit; do
		# "ii" is installed; a package dpkg never knew prints nothing.
		case $(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null) in
		ii*) ;;
		*) missing="$missing $package" ;;
		esac
	done
	if [ -n "$missing" ]; then
		echo "bootstrap.sh: installing the AD tools the periodic job reads the computer's Description with:$missing"
		DEBIAN_FRONTEND=noninteractive
		export DEBIAN_FRONTEND
		# $missing unquoted: each package a word of its own.
		if ! { printf '%s\n' 'krb5-config krb5-config/add_servers boolean false' | debconf-set-selections &&
			apt_get update && apt_get install -y $missing; }; then
			echo "bootstrap.sh: could not install$missing: the banner deploys, and takes its tier and role from the AD Description once they are installed" >&2
		fi
	fi
fi

exec pwsh -NoProfile -NonInteractive -File "$here/bootstrap.ps1" "$@"
