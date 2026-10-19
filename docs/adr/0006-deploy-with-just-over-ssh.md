# 6. Deploy with `just deploy`: verified, digest-pinned, via the TrueNAS API

- Status: accepted
- Date: 2026-10-19

## Context

Deploying by pasting YAML into the TrueNAS UI is error-prone, and a tag can be
moved after review.

## Decision

`just deploy vX.Y.Z` (from the workstation): resolve the tag's digest on GHCR,
verify its build provenance, render the compose YAML with the image pinned as
`vX.Y.Z@sha256:…`, copy it to the NAS over SSH and run `scripts/deploy-remote`
under `sudo` (one password prompt). On the NAS it takes a pre-deploy dump,
replaces the app's compose document through the middleware's Python client
(`truenas_api_client`, `app.update`), starts the app if stopped, and waits until
the new image is healthy. It is a no-op when image and configuration already
match. `just rollback` is the same with a confirmation.

`midclt` was tried first and rejected: given the ~11 KB document as an
argument it was killed before submitting the job, and its default 60 s timeout
is too short for image pulls.

## Consequences

- Only images built by this repo's release workflow can be deployed.
- Deploys need the maintainer's sudo password; nothing is fully automatic.
- Rollbacks restore code, not data: migrations must be undone from a dump.
