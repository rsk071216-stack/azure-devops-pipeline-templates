# ADR 0005 - Terraform plan and apply in separate stages; infrastructure rolls forward

- Status: Accepted
- Date: 2026-10-23

## Context

Environment checks (approvals, business hours) are evaluated when a **stage**
starts. If plan and apply live in the same stage, approvers must approve before
the plan exists - they approve blind.

## Decision

- `Plan_<env>` and `Apply_<env>` are separate stages. The plan stage publishes
  the binary plan, the provider lock file, the Terraform Plan tab entry and a
  Markdown summary that highlights destroy and replace actions.
- `Apply_<env>` runs only when `changesPresent == 'true'`, on the deploy branch,
  never for pull requests, and applies exactly the reviewed plan file.
- A stale plan (state changed after review) fails instead of applying.
- Promotion continues to the next environment when the previous apply
  succeeded **or was skipped because there were no changes**, but never after a
  failed plan.
- Infrastructure is not rolled back automatically: Terraform has no safe,
  general undo. Recovery is roll-forward - revert the commit and let the
  pipeline produce a new reviewed plan.

## Consequences

- Approvers see the exact change before approving; no-op runs do not request
  approval at all.
- Plans for all environments run on pull requests (with Reader identities),
  giving reviewers production impact before merge.
- Plan artifacts may contain sensitive values; pipeline artifact access must be
  restricted to the project's contributors.
