# Architecture Decision Records

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-extends-template-as-governance-boundary.md) | An `extends` template plus the Required template check is the governance boundary | Accepted |
| [0002](0002-workload-identity-federation-only.md) | All Azure access uses Workload Identity Federation; no secrets | Accepted |
| [0003](0003-semver-tags-for-template-consumption.md) | Consumers pin immutable SemVer tags; the check allow-list is the support policy | Accepted |
| [0004](0004-static-validation-strategy.md) | Static validation: contract lint for templates, JSON schema only for root pipelines | Accepted |
| [0005](0005-terraform-plan-apply-split.md) | Terraform plan and apply in separate stages; infrastructure rolls forward | Accepted |
| [0006](0006-digest-pinned-deploys-with-guarded-rollback.md) | Deploy by image digest with guarded automatic rollback | Accepted |

Format: context, decision, consequences (Michael Nygard style).
