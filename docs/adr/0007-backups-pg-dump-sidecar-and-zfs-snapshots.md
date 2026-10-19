# 7. Backups: pg_dump sidecar plus ZFS snapshots

- Status: accepted
- Date: 2026-10-19

## Context

Data must survive mistakes (bad migrations, deletions) and hardware failure,
and restores must be practised, not hoped for.

## Decision

- A `backup` service on the same digest-pinned Postgres image runs
  `pg_dump -Fc` daily at 03:00 UTC (plus a catch-up dump on start), verifies
  each archive with `pg_restore --list` before keeping it, and retains 7 daily,
  4 weekly, 6 monthly and 10 manual dumps. Its script is inline in the compose
  file, since TrueNAS stores only the YAML.
- Every deploy takes a dump first; `just backup-now` takes one on demand.
- ZFS periodic snapshots of the app's datasets (hourly for 2 days, daily for 30).
- CI restores a fresh dump into a new database on every pull request.

## Consequences

- Portable logical backups as well as fast whole-dataset rollback.
- Off-machine copies depend on TrueNAS replication, configured separately.
- Restore procedures are documented in docs/backups.md and were rehearsed.
