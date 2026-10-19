# 12. Database and backup containers run as uid 10999

- Status: accepted
- Date: 2026-10-19

## Context

The containers run as fixed non-root users, and TrueNAS's Docker is rootful
with no user-namespace remapping, so container IDs are host IDs. The Postgres
image's default 999 is, on this NAS, the host's `netdata` user and `docker`
group, which gave the host's netdata service read/write access to the database
files and backups.

## Decision

Run `db` and `backup` as `10999:10999`, an ID unused on the host (the official
image supports arbitrary IDs), from the start, with no capabilities. The data
and backup directories are owned `10999:10999`; the database password secret
is `10001:10999` (app user, database group), mode 440.

## Consequences

- No host account shares access to the database files.
- New IDs must be checked against the host's users before use.
- Existing installs needed a one-time re-own (docs/truenas.md).
