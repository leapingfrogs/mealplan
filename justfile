# Task runner. jj doesn't run git hooks, so `just check` is the local quality
# gate: run it before pushing. It gives the same verdict as CI.
#
# Recipes run directly inside the devenv shell (direnv) or in CI, and through
# `devenv shell --` anywhere else.

set shell := ["bash", "-euo", "pipefail", "-c"]

run := if env("DEVENV_ROOT", env("CI", "")) == "" { "devenv shell --" } else { "" }

# List recipes
default:
    @just --list --unsorted

# Install dependencies, create and migrate the database, build assets
setup:
    {{ run }} npm ci --ignore-scripts --no-audit --no-fund
    {{ run }} mix setup

# Start background services (Postgres) for development
up:
    devenv up --detach

# Run the dev server with an IEx shell
dev:
    {{ run }} iex -S mix phx.server

# Format Elixir code
fmt:
    {{ run }} mix format

# Run tests (extra args go to mix test, e.g. `just test --failed`)
test *args:
    {{ run }} mix test {{ args }}

# Everything CI checks: formatting, warnings, audits, tests, commit messages
check: lint-commits
    {{ run }} mix ci

# Lint descriptions of unpushed commits (trunk()..@) against Conventional Commits
lint-commits:
    #!/usr/bin/env bash
    set -euo pipefail
    revs=$(jj log --no-graph -r 'trunk()..@ ~ description(exact:"")' -T 'commit_id ++ "\n"')
    if [ -z "$revs" ]; then echo "lint-commits: no unpushed commits to check"; exit 0; fi
    status=0
    for rev in $revs; do
      if ! jj log --no-graph -r "$rev" -T description | {{ run }} npx --no-install commitlint; then
        echo "lint-commits: ✖ $(jj log --no-graph -r "$rev" -T 'change_id.short() ++ " " ++ description.first_line()')"
        status=1
      fi
    done
    exit $status

# Show outdated Hex and npm dependencies
outdated:
    {{ run }} mix hex.outdated
    {{ run }} npm outdated || true

# Invite someone by email in dev (`just invite me@example.com --admin`)
invite email *flags:
    {{ run }} mix mealplan.invite {{ flags }} {{ email }}
