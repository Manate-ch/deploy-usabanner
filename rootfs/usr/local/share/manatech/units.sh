# units.sh - the systemd units install.sh writes, kept in one file so the
# tests can generate them into any folder and check them with
# systemd-analyze verify. Sourced by install.sh; it only defines things.
#
# Two layouts, each written into the folder given as the first argument:
#
#   units_clone DIR REPO [RUN]  a git clone, or any copy outside the ADSys
#                               copy of SYSVOL: a 4-hourly timer running
#                               "sh REPO/install.sh RUN".
#   units_adsys DIR             the ADSys copy of SYSVOL (Group Policy
#                               delivery): the same timer running the full
#                               adsys-startup.sh, and a publish watcher.
#
# The publish watcher is why Group Policy updates need no reboot. ADSys
# refreshes its copy of SYSVOL every 90 minutes but runs startup scripts only
# at boot. manatech-motd-publish.path watches the copy's GPT.INI, whose
# Version= Publish-ManatechMotd.ps1 bumps on every publish, and runs
# adsys-startup.sh --if-new-version when it changes. On systemd 255 (Ubuntu
# 24.04) a PathChanged= unit fires when that file is created, replaced by a
# rename or rewritten, and not for other files in its folder (measured
# 2026-09-25; the README has the probe and its results).

ADSYS_ASSETS=/var/cache/adsys/sysvol/assets
ADSYS_MOTD=$ADSYS_ASSETS/scripts/MOTD

# units_timer DIR - the 4-hourly timer both layouts share.
units_timer() {
	cat >"$1/manatech-motd-update.timer" <<'EOF'
[Unit]
Description=Update the Manatech login banner every 4 hours

[Timer]
OnCalendar=*-*-* 00/4:00:00
RandomizedDelaySec=20min
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

units_clone() {
	cat >"$1/manatech-motd-update.service" <<EOF
[Unit]
Description=Pull and install the Manatech login banner
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh $2/install.sh${3:+ $3}
# The same journal tag as adsys-startup.sh's runs: journalctl -t manatech-motd
SyslogIdentifier=manatech-motd
EOF
	units_timer "$1"
}

units_adsys() {
	cat >"$1/manatech-motd-update.service" <<EOF
[Unit]
Description=Install the Manatech login banner from the ADSys copy of SYSVOL
Wants=network-online.target
After=network-online.target
ConditionPathExists=$ADSYS_MOTD/adsys-startup.sh

[Service]
Type=oneshot
ExecStart=/bin/sh $ADSYS_MOTD/adsys-startup.sh
SyslogIdentifier=manatech-motd
EOF
	units_timer "$1"
	cat >"$1/manatech-motd-publish.path" <<EOF
[Unit]
Description=Watch the ADSys copy of SYSVOL for a new Manatech MOTD publish

[Path]
PathChanged=$ADSYS_ASSETS/GPT.INI
Unit=manatech-motd-publish.service

[Install]
WantedBy=paths.target
EOF
	cat >"$1/manatech-motd-publish.service" <<EOF
[Unit]
Description=Install a new Manatech MOTD publish from the ADSys copy of SYSVOL
Wants=network-online.target
After=network-online.target
ConditionPathExists=$ADSYS_MOTD/adsys-startup.sh

[Service]
Type=oneshot
# ADSys writes its copy file by file (each one atomically). GPT.INI changing
# is the signal; the wait lets the rest of the publish land before installing.
ExecStartPre=/bin/sleep 30
ExecStart=/bin/sh $ADSYS_MOTD/adsys-startup.sh --if-new-version
SyslogIdentifier=manatech-motd
EOF
}
