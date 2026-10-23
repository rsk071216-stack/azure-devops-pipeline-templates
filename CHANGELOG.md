# Changelog

All notable changes to this template library are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) as
defined for templates in [docs/release-process.md](docs/release-process.md).

## [Unreleased]

## [1.0.0] - 2026-10-23

### Added

- `governance/secure-pipeline.yml` extends template: mandatory `SecurityBaseline`
  stage, dependency/condition rewriting so the baseline cannot be bypassed, and
  compile-time rejection of inline scripts, shell-wrapper tasks, raw deployment
  jobs, foreign templates and `persistCredentials: true`.
- Stage templates: `container-ci`, `aks-promotion` (multi-environment, fan-out via
  `promoteFrom`), `terraform-promotion` (plan/apply split per environment),
  `security-baseline`.
- Job templates: `container-build`, `dotnet-test`, `node-test`, `secret-scan`,
  `supply-chain-scan`, `terraform-plan`, `terraform-apply` (deployment),
  `aks-deploy` (deployment with smoke test and automatic rollback).
- Step templates for checksum-verified tool installation, gitleaks, Trivy, syft,
  Docker build, ACR push by digest, Helm 4 and Kustomize deploys, rollback, smoke
  tests, coverage gate and Terraform plan summaries.
- Workload Identity Federation everywhere (`AzureCLI@2`, `TerraformTask@5` with
  Entra ID backend auth); no client secrets or storage keys.
- `platform/azure-devops-governance`: Terraform for environments, approvals,
  business hours, exclusive lock, Required template and branch control checks,
  WIF service connections, managed identities and RBAC.
- Example consumer pipelines (AKS web app, Terraform infrastructure, policy
  violation) and documentation (catalogue, onboarding, governance model,
  workload identity federation, migration from classic releases, ADRs).
- GitHub Actions CI: yamllint, YAML parsing, parameter typing and documentation
  coverage, task version pinning, version consistency, actionlint, JSON-schema
  validation of example pipelines, `terraform validate`.

[Unreleased]: https://github.com/rsk071216-stack/azure-devops-pipeline-templates/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/rsk071216-stack/azure-devops-pipeline-templates/releases/tag/v1.0.0
