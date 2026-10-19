# 9. Jujutsu for version control, `just check` instead of hooks

- Status: accepted
- Date: 2026-10-19

## Context

The maintainer prefers Jujutsu. It is git-compatible (colocated repo, GitHub as
the remote) but doesn't run git hooks.

## Decision

Use `jj` for all version control. Pre-push checks are run explicitly with
`just check` (including commitlint over unpushed descriptions via
`just lint-commits`). `main` is protected by a ruleset: squash-merged PRs only,
required checks, up-to-date branches, no bypass.

## Consequences

- Nothing stops a push with failing checks locally, but nothing reaches `main`
  without passing them in CI.
- Tooling and docs use jj commands (`jj git push --bookmark`, `jj new main`).
