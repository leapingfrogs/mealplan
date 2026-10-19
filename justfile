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

# Everything CI checks: commits, format, Credo, Sobelow, audits, coverage, Dialyzer
check: lint-commits docker-lint
    {{ run }} mix ci
    {{ run }} mix dialyzer

# Type-check with Dialyzer (first run builds PLTs into priv/plts)
dialyzer:
    {{ run }} mix dialyzer

# Test coverage report in cover/excoveralls.html
cover:
    {{ run }} mix coveralls.html

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

# Lint the Dockerfile and check its Elixir/Erlang versions match .tool-versions
docker-lint:
    {{ run }} hadolint Dockerfile
    scripts/check-docker-versions

# Build the production image locally as mealplan:local
docker-build:
    docker build $(docker --version | grep -qi podman && echo --format docker) -t mealplan:local \
      --build-arg VERSION=local --build-arg REVISION=$(jj log -r @- --no-graph -T commit_id) .

# Scan mealplan:local for HIGH/CRITICAL vulnerabilities (as CI does)
docker-scan:
    #!/usr/bin/env bash
    set -euo pipefail
    tar=$(mktemp --suffix .tar)
    trap 'rm -f "$tar"' EXIT
    docker save mealplan:local -o "$tar"
    {{ run }} trivy image --input "$tar" --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1

# Show outdated Hex and npm dependencies
outdated:
    {{ run }} mix hex.outdated
    {{ run }} npm outdated || true

# Invite someone by email in dev (`just invite me@example.com --admin`)
invite email *flags:
    {{ run }} mix mealplan.invite {{ flags }} {{ email }}
