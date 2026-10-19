# Mealplan

Meal planning and recipe management for the family, built with Elixir and
Phoenix LiveView. Self-hosted on a TrueNAS appliance; accounts are invite-only.

**Status:** Iteration 0, the foundations. Invite-only magic-link login, admin
error dashboard, hardened production stack with backups, CI, releases and
one-command deploys. Meal planning features come next.

## Stack

- Elixir 1.20 / Erlang/OTP 29 (`.tool-versions`), Phoenix 1.8 with LiveView,
  Tailwind
- PostgreSQL 18
- Email through an SMTP relay (Swoosh), TLS verified
- Errors in the app's own database with ErrorTracker (`/admin/errors`)
- Production: Docker image on GHCR, run as a TrueNAS Custom App behind Nginx
  Proxy Manager

## Development

Requires [devenv](https://devenv.sh) (and optionally direnv, which loads it on
`cd`). devenv provides Erlang, Elixir, Postgres and all the tooling.

```sh
just setup                        # deps, database, assets (first time)
just up                           # start Postgres in the background
just invite you@example.com --admin
just dev                          # http://localhost:4000; emails at /dev/mailbox
```

Without direnv, prefix commands with `devenv shell --`; the `just` recipes do
that themselves.

### Before pushing

```sh
just check
```

It runs everything CI requires: Conventional Commit messages, Dockerfile and
shell script lint, formatting, compile warnings, Credo (strict), Sobelow,
dependency audits, tests with the 80% coverage floor, and Dialyzer. jj doesn't
run git hooks, so this is the local gate. `just` lists all recipes.

### Contributing

The repo uses **Jujutsu**. `main` only changes through squash-merged pull
requests with green checks. Commits and PR titles follow
[Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`,
`build:`, …), which release-please turns into versions and the changelog. See
[CLAUDE.md](CLAUDE.md) for the conventions in one place.

## Releasing and deploying

1. **Merge pull requests.** release-please keeps a **Release PR** open
   (`chore(main): release X.Y.Z`) that bumps `mix.exs` and `CHANGELOG.md`.
2. **Merge the Release PR.** The release workflow tags `vX.Y.Z`, creates the
   GitHub Release, builds the image, **scans it with Trivy before pushing**,
   pushes `ghcr.io/leapingfrogs/mealplan:vX.Y.Z` with an SBOM and provenance
   attestation, and adds the digest to the release notes.
3. **Deploy** from your checkout (settings in `.env.deploy`, see
   `.env.deploy.example`):

   ```sh
   just deploy --dry-run vX.Y.Z      # verify provenance and render, touch nothing
   just deploy vX.Y.Z                # asks for the NAS sudo password once
   ```

   It verifies the image's provenance, pins it by digest, takes a pre-deploy
   database dump, updates the TrueNAS app, waits until it's healthy, and checks
   the public URL. Rerunning for the deployed version does nothing.
4. **Roll back** if needed: `just rollback vX.Y.Z` redeploys an earlier
   version. Code rolls back, the database doesn't: if the newer release ran
   migrations, restore its pre-deploy dump ([docs/backups.md](docs/backups.md)).

## Operations

| Topic | Where |
|---|---|
| NAS setup: datasets, permissions, secrets, Custom App, proxy, deploys | [docs/truenas.md](docs/truenas.md) |
| Backups, on-demand dumps (`just backup-now`), restore | [docs/backups.md](docs/backups.md) |
| Configuration variables | [.env.example](.env.example) |
| Why things are the way they are | [docs/adr/](docs/adr/README.md) |

First admin in production (NAS shell as root):

```sh
docker exec ix-mealplan-app-1 /app/bin/mealplan eval 'Mealplan.Release.invite_user("you@example.com", admin: true)'
```

Health: `https://<PHX_HOST>/health/live` and `/health/ready`.
