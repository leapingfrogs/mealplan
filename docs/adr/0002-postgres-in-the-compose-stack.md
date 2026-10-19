# 2. PostgreSQL runs inside the app's compose stack

- Status: accepted
- Date: 2026-10-19

## Context

The NAS runs several apps. The database could be shared, external, or private
to this app.

## Decision

A dedicated PostgreSQL 18 container in `compose.yaml`, on an internal network
with no route out and no published ports, with its data in its own ZFS dataset
(`recordsize=16K`).

## Consequences

- The app is self-contained: install, upgrade and back up as one unit.
- Postgres upgrades (e.g. to 19) are our job: dump and restore, or `pg_upgrade`.
- The database is unreachable from the LAN; administration goes through
  `docker exec`.
