# motd.psd1 - per-host settings for the Manatech login banner on Windows.
# Same meaning as /etc/manatech/motd.conf on Linux. Set EnvName and Role on
# every host cloned from the template: an UNSET badge means nobody did.
@{
    # UNSET = take the environment from the prefix of this computer's AD
    # Description ("PROD: Hyper-V host"); any other value wins over AD.
    # Colours per environment: envs.tsv.
    EnvName       = 'UNSET'

    # Where the environment shows: 'strip' (above the panel), 'row' (env row).
    EnvShow       = @('strip', 'row')

    # One line: what this host is for. Empty = the role from the AD Description.
    Role          = ''

    # Service names that must be running; each one that is not is reported in red.
    # Check the Zabbix name on a real host with Get-Service *zabbix*.
    Watch         = @('sshd', 'Zabbix Agent 2')

    # truecolor, 256, 16 or none; unicode or ascii glyphs.
    Color         = 'truecolor'
    Glyphs        = 'unicode'

    # Report at this percentage used (red from 95).
    DiskWarn      = 85
    MemWarn       = 90
    CpuWarn       = 85

    # Naming-schema field whose colour draws the border: site, type, subtype, os or none.
    BorderBy      = 'type'

    # Top-right badge: 'site-vlan' shows "<site> - <VLAN name>" (site from the
    # host name, VLAN from the primary address and vlans.tsv) in the VLAN's
    # colour; 'env' shows EnvName. EnvName still colours a VLAN with no colour code.
    Badge         = 'site-vlan'

    # Interfaces not listed in the ipv4 rows (regex; empty = list all).
    IfaceHide     = '^(vEthernet|Loopback|isatap)'

    # More auto-start services that stop by design, not reported. Trigger-start
    # services are never reported, nor the module's own list (InventorySvc and
    # the like); anything else stopped is reported in red.
    # Measure-ManatechBanner.ps1 lists this host's stopped services.
    ServiceIgnore = @()
}
