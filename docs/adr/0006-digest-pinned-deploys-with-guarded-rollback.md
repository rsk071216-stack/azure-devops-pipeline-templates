# ADR 0006 - Deploy by image digest with guarded automatic rollback

- Status: Accepted
- Date: 2026-10-23

## Context

Tags are mutable: `:1.4.2` in prod may not be what was tested in test.
Automatic rollback is valuable, but a naive `on.failure: helm rollback` can
roll back a healthy release when the job failed before deploying anything, or
roll back twice after Helm already restored the previous revision.

## Decision

- The build job pushes once and exports `repository@sha256:digest`; every
  environment deploys that digest. Deploy steps refuse non-digest references.
- Helm uses `--rollback-on-failure` (Helm 4) for failed rollouts.
- Post-deployment smoke tests run in `postRouteTraffic`; a failure triggers
  `on.failure`.
- The rollback step acts only if the live release runs the digest from the
  current run, and is a no-op when Helm already rolled back.

## Consequences

- "What runs in prod" is answerable from the run summary: one digest per run.
- The chart contract requires `image.repository` and `image.digest` values
  (keys are configurable).
- Database migrations must be backwards compatible (expand/contract), because
  an application rollback does not roll back data.
