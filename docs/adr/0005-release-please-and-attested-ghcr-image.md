# 5. Releases with release-please; attested public image on GHCR

- Status: accepted
- Date: 2026-10-19

## Context

Releases should be routine and traceable, and the NAS must be able to trust and
pull what it runs.

## Decision

- **release-please** turns Conventional Commits into a Release PR (version
  bump and changelog). It authenticates as a GitHub App so its PRs trigger the
  required checks. The first release is 0.1.0.
- On release, the workflow builds the image, **scans it with Trivy before
  pushing**, pushes `vX.Y.Z`, `X.Y`, `latest` and `sha-…` tags to
  `ghcr.io/leapingfrogs/mealplan` with an SBOM and SLSA provenance, and attests
  the build.
- The image is **public**, like the repo; it contains no secrets, so the NAS
  pulls without credentials.

## Consequences

- Commit messages matter: CI enforces Conventional Commits on commits and PR
  titles.
- Deploys can verify provenance (`gh attestation verify`) before running an
  image.
- No registry token to rotate on the NAS.
