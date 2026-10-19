# 4. Secrets live only on the NAS

- Status: accepted
- Date: 2026-10-19

## Context

The app needs a database password, `SECRET_KEY_BASE`, the release cookie and
SMTP credentials. TrueNAS stores a Custom App's YAML in its own configuration.

## Decision

Secrets are generated on the NAS and never pass through the repo or the
workstation: settings in `MEALPLAN_ROOT/.env` (root, mode 600), and the
database password in `secrets/db_password`, mounted as a compose secret that
both Postgres (`POSTGRES_PASSWORD_FILE`) and the app (`DATABASE_PASSWORD_FILE`)
read. The compose YAML contains no secrets.

## Consequences

- Nothing secret in git, CI or the TrueNAS app config.
- Rotating the database password means changing it in Postgres as well as the
  file; Postgres only reads the file on first initialisation.
- Configuration typos in `.env` stop the app at boot with a message naming the
  variable.
