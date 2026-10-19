# 3. Host as a TrueNAS Custom App behind Nginx Proxy Manager

- Status: accepted
- Date: 2026-10-19

## Context

Hosting is an existing TrueNAS SCALE appliance, which already runs Nginx Proxy
Manager (NPM) for other apps, with ports 80/443 forwarded to it.

## Decision

Run the stack as a TrueNAS **Custom App** from a compose YAML document, joined
to NPM's Docker network under the alias `mealplan`. NPM terminates TLS
(Let's Encrypt), forwards to `mealplan:4000`, and must have WebSockets enabled.
The app trusts `X-Forwarded-For`/`-Proto` only from `TRUSTED_PROXIES` (NPM's
subnet) and enforces HTTPS and HSTS itself.

## Consequences

- TrueNAS manages the app's lifecycle; we feed it rendered YAML
  (`scripts/render-truenas-compose`), since it stores a literal document.
- Mealplan depends on NPM's network: an NPM update that recreates it requires
  restarting Mealplan.
- `PHX_HOST` must be the hostname browsers use; other names fail the LiveView
  origin check.
