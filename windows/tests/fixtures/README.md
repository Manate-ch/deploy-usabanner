# Test fixtures

Frozen copies of files as this repository shipped them, for the tests that
need that historical text rather than whatever the current files hold:

- `50-manatech.issue` and `issue.net`: the console banner and the SSH banner
  as they were when Ubuntu's banner conffiles were made stock again. The
  conffile and plan tests rebuild the pre-fix `/etc/issue` from the first
  (with its old first line on top) and use the second as an older install's
  `/etc/issue.net`. Both md5s are on the lists in
  `rootfs/usr/local/share/manatech/conffiles.sh`.

- `schema-names.tsv`, `vlans.tsv`, `colors.tsv` and `envs.tsv`: the
  example naming schema, VLAN, colour and environment tables as this
  repository ships them. `ManatechBanner.Tests.ps1` lays them over a copy
  of the shipped data folder, because its decode, VLAN and badge tests
  assert those example rows.

Kept here so that a copy of this repository can change its own banners,
art and tables without touching a test.
