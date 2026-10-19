# 11. Supply chain: pin everything, take updates after a cooldown

- Status: accepted
- Date: 2026-10-19

## Context

Compromised releases of actions, images and packages are a recurring attack
route, and they are usually caught within days.

## Decision

- GitHub Actions are pinned by commit SHA, base images by digest, and tools
  downloaded in CI (actionlint, hadolint, Trivy) are checksum-verified. The
  Trivy action itself isn't used: its release tags were hijacked in 2025.
- New versions are adopted only once they are about two weeks old. Dependabot
  (mix, npm, Actions, Docker, compose) has a 14-day cooldown.
- Deploys pin the app image by digest and verify its provenance (ADR 6).

## Consequences

- Updates arrive as reviewable Dependabot PRs with a delay; urgent security
  fixes may need a manual exception.
- Pins must be updated deliberately rather than drifting.
