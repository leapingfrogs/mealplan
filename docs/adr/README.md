# Architecture decision records

Short records of significant decisions: the context, what was decided, and the
consequences accepted. Add a new numbered file for a new decision; to change a
decision, add a record that supersedes the old one and update the old one's
status. The format follows [MADR](https://adr.github.io/madr/) in spirit.

| # | Decision |
|---|---|
| [1](0001-phoenix-liveview-invite-only-auth.md) | Phoenix LiveView with phx.gen.auth, invite-only |
| [2](0002-postgres-in-the-compose-stack.md) | PostgreSQL runs inside the app's compose stack |
| [3](0003-truenas-custom-app-behind-npm.md) | Host as a TrueNAS Custom App behind Nginx Proxy Manager |
| [4](0004-secrets-on-the-nas.md) | Secrets live only on the NAS |
| [5](0005-release-please-and-attested-ghcr-image.md) | Releases with release-please; attested public image on GHCR |
| [6](0006-deploy-with-just-over-ssh.md) | Deploy with `just deploy`: verified, digest-pinned, via the TrueNAS API |
| [7](0007-backups-pg-dump-sidecar-and-zfs-snapshots.md) | Backups: pg_dump sidecar plus ZFS snapshots |
| [8](0008-quality-gates.md) | Quality gates: one command locally and in CI |
| [9](0009-jujutsu-and-just-check.md) | Jujutsu for version control, `just check` instead of hooks |
| [10](0010-self-hosted-error-tracking.md) | Self-hosted error tracking with ErrorTracker |
| [11](0011-supply-chain-pinning.md) | Supply chain: pin everything, take updates after a cooldown |
| [12](0012-postgres-runs-as-uid-10999.md) | Database and backup containers run as uid 10999 |
| [13](0013-own-cooklang-parser.md) | Write our own Cooklang parser with NimbleParsec |
