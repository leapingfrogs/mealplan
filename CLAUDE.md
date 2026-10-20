# Mealplan: notes for AI assistants

Family meal planning and recipe management. Elixir/Phoenix LiveView app, deployed
to a TrueNAS appliance. Phoenix's generated coding guidelines are in AGENTS.md
and apply here:

@AGENTS.md

Decisions and their reasons are in [docs/adr/](docs/adr/README.md). Read the
relevant ADR before changing something it covers.

## Version control: Jujutsu, not git

The repo is colocated jj + git; **use `jj`, never `git commit`/`git push`**. The
working copy is itself a commit.

- Describe the change: `jj describe -m "type: summary"`; start the next one with `jj new`
- Publish: `jj bookmark create <branch> -r @` then `jj git push --bookmark <branch>`
- Update after a merge: `jj git fetch` then `jj new main`
- jj doesn't run git hooks: `just check` is the local gate (below)

`main` is protected by a ruleset: changes reach it **only through squash-merged
pull requests** with the required checks green (`lint`, `test`, `dialyzer`,
`docker`, `actionlint`, `commit messages`, `PR title`) and the branch up to
date. Open the PR with `gh pr create`; **the maintainer merges**.

## Commits: Conventional Commits

release-please derives versions and the changelog from them, and CI rejects
anything else (commitlint over every commit and the PR title, which becomes the
squash commit). Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`,
`build`, `ci`, `chore`, `style`, `revert`; `!` or `BREAKING CHANGE:` for breaking
changes. `feat`/`fix` cut a release; `build` shows in the changelog.

## Environment and commands

Everything runs inside the devenv shell (direnv loads it); tool versions come
from `.tool-versions`, the single source shared with CI and the Dockerfile.
`just` lists the recipes. The ones that matter most:

| Command | Purpose |
|---|---|
| `just setup` / `just up` / `just dev` | first-time setup, start Postgres, run the app |
| `just test [args]` | `mix test` |
| `just check` | **run before every push**: commit lint, Dockerfile and shell lint, `mix ci`, Dialyzer |
| `mix precommit` | quick compile, format and test loop while working |
| `just compose-smoke` | boot the production compose stack locally and probe it |

`mix ci` = `ci.lint` (format, unused locks, hex/deps audit, warnings as errors,
`credo --strict`, `sobelow`) + `ci.test` (tests with the 80% coverage floor).

## The domain

The design is in [docs/design/iteration-1.md](docs/design/iteration-1.md) (and
[iteration-2.md](docs/design/iteration-2.md) for import and export);
[USER_STORIES.md](USER_STORIES.md) is the source of the behaviour.

| Context | Owns |
|---|---|
| `Households` | households, invitations, membership and ownership, meal slots |
| `Recipes` | recipes and their ingredient rows (rebuilt from the source on save) |
| `Cooklang` | the parser (ADR 13): pure, never raises, no database |
| `Meals` | meals and the recipes in them, with history |
| `Planning` | planned meals, leftovers, skips, weeks, servings maths, copying |

- **Scope first.** Every context function takes the caller's
  `%Scope{user, household}` and only touches that household. Owner-only
  operations check `Households.owner?/1`. Tables that reference each other
  carry `household_id` in composite foreign keys, so rows can't cross
  households even through a bug.
- **Dates are household-local.** "Today" is `Planning.today/1` (the
  household's time zone); weeks start on Monday. Never use `Date.utc_today/0`
  for plan dates.
- **Live updates** go through `Households.broadcast/2` on `household:<id>`:
  `{:household_updated, h}`, `{:household_changed, :members | :invitations |
  :meal_slots}`, `{:member_removed, id}`, `:household_deleted`,
  `{:recipe_changed, id}`, `{:meal_changed, id}`, `{:plan_changed, monday}`.
  The `:require_household` on_mount hook subscribes every household page and
  passes messages on only if the LiveView defines `handle_info/2`; always
  keep a catch-all clause.
- **The archive rule.** Deleting a recipe, meal or slot that a plan before
  today used archives it (`archived_at`) instead; lists and pickers show
  active rows only. Taking a recipe out of a meal that past plans used sets
  `meal_recipes.removed_on` rather than deleting the row: `Meal.meal_recipes`
  is the current recipes, `Meals.recipes_on/3` what a meal had on a date.
- **UI.** Phone first; check new screens at 390 px. Sheets and confirmation
  panels follow the week plan's patterns; avoid DaisyUI `alert` for panels
  with controls (it lays them out side by side).

## Code conventions

- **Formatting:** Styler, line length 98. Let `mix format` decide.
- **Credo strict** must pass; `Design.AliasUsage` is off (it fights Styler).
- **Dialyzer** runs with `unmatched_returns`, `extra_return`, `missing_return`
  and `error_handling`, and no ignore file. Discard results deliberately with
  `_ =` and assert expected ones (`{:ok, _} = ...`).
- **Sobelow:** fail on medium confidence. Reviewed false positives are in
  `.sobelow-skips` with reasons in `.sobelow-conf`; don't add skips without
  review.
- **Coverage** at least 80% (`coveralls.json`); test behaviour, not
  implementation.

## Security conventions

- **CSP:** scripts and `<style>` blocks must carry `nonce={@csp_nonce}`, and
  inline `style=` attributes are blocked. Use classes or colocated hooks.
- **Proxy trust:** only `MealplanWeb.TrustedProxy` interprets
  `X-Forwarded-*`, and only from `TRUSTED_PROXIES`. Use `conn.remote_ip` (or
  `TrustedProxy.client_ip_from_socket/1` in LiveViews); never read the headers
  directly.
- **Secrets in logs:** `filter_parameters` covers `password` and `token`;
  `MealplanWeb.Redact` scrubs tokens in URLs from request logs and error
  reports. Keep new secret-bearing params and paths covered.
- **Auth:** registration is invite-only (`Accounts.invite_user/3`, the
  `mealplan.invite` task, `Mealplan.Release.invite_user/2` in production).
  Admin-only routes go behind `:require_admin` and the `:require_admin`
  on_mount hook.
- **Supply chain:** pin GitHub Actions by commit SHA and container images by
  digest, prefer releases at least two weeks old, and verify downloaded
  binaries by checksum.

## Deployment

Production is a TrueNAS Custom App (docs/truenas.md). `just deploy vX.Y.Z` and
`just rollback vX.Y.Z` run from the workstation and **prompt for the NAS sudo
password, so the maintainer runs them**. Never run them, `just backup-now`, or
anything that changes the NAS without being asked. `just deploy --dry-run` is
safe. Compose changes take effect through a deploy (the YAML is rendered from
this checkout); image changes need a release first.
