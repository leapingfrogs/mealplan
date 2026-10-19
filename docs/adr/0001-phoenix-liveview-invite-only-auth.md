# 1. Phoenix LiveView with phx.gen.auth, invite-only

- Status: accepted
- Date: 2026-10-19

## Context

A small family app: a handful of users, rich interactive pages (planning a
week, editing recipes), maintained by one person. It will be reachable from the
public internet.

## Decision

Phoenix 1.8 with LiveView for the UI, and `phx.gen.auth` (magic links plus
optional passwords, Argon2) for accounts. Public registration is removed: accounts are
created by invitation (`Accounts.invite_user/3`, `mix mealplan.invite`,
`Mealplan.Release.invite_user/2`), and an `admin` flag gates admin pages.

## Consequences

- One language and process for UI and server logic; no separate SPA or API.
- LiveView needs WebSockets end to end, so the proxy must pass them.
- No sign-up flow to abuse; login endpoints are still rate limited.
- Generated auth code is ours to maintain.
