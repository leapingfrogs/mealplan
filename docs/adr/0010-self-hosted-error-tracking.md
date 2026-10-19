# 10. Self-hosted error tracking with ErrorTracker

- Status: accepted
- Date: 2026-10-19

## Context

Production errors need to be visible, but family data shouldn't go to a
third-party service.

## Decision

ErrorTracker stores errors in the app's own Postgres, viewable at
`/admin/errors` by admins only (404 for everyone else). Error context is
scrubbed of passwords, tokens and magic-link URLs (`MealplanWeb.Redact`).
Resolved errors are pruned after 30 days. Production logs are JSON with request
IDs.

## Consequences

- No external service or account; errors are covered by the database backups.
- No alerting: someone has to look at the dashboard.
