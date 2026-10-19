# 8. Quality gates: one command locally and in CI

- Status: accepted
- Date: 2026-10-19

## Context

One maintainer, so automated checks are the main safeguard, and local results
should match CI.

## Decision

`mix ci` (`ci.lint` and `ci.test`) runs Styler formatting, unused-lock and
dependency audits (`hex.audit`, `mix_audit`), compile warnings as errors, Credo
`--strict`, Sobelow (medium confidence, fingerprinted skips with reasons) and
tests with an 80% coverage floor (ExCoveralls). Dialyzer runs with strict
flags and no ignore file. CI runs the same aliases plus Docker image checks
(hadolint, Trivy, compose smoke test), actionlint and shellcheck. `just check`
runs it all locally.

## Consequences

- The same verdict locally and in CI.
- Some generated code was adjusted to satisfy Dialyzer and Credo; Credo's
  `AliasUsage` is disabled because it conflicts with Styler.
