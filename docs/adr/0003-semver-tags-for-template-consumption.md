# ADR 0003 - Consumers pin immutable SemVer tags

- Status: Accepted
- Date: 2026-10-23

## Context

Repository resources default to the default branch. Consuming templates from
`main` means every merge to the library changes every pipeline at once, without
the consumer's knowledge and without a way to roll back one team.

## Decision

- Consumers reference `ref: refs/tags/vMAJOR.MINOR.PATCH`.
- The library follows Semantic Versioning where the contract is parameters,
  defaults, outputs, stage/job names and enforced policies
  ([release-process.md](../release-process.md)).
- Tags are annotated, never moved and never deleted.
- The Required template check lists the supported tags explicitly; removing a
  tag retires that version for protected resources.
- CI keeps the CHANGELOG version, the run tag emitted by the baseline stage, the
  example pipelines and the check allow-list in sync.

## Consequences

- Upgrades are explicit, reviewable one-line PRs per consumer; the PR run
  validates the new version end to end without deploying.
- Security fixes still reach everyone quickly: release a PATCH and remove the
  vulnerable tag from the allow-list.
- Azure Pipelines cannot express version ranges (`~1.2`), so automated bump PRs
  (for example a Renovate custom manager) are recommended for large estates.
