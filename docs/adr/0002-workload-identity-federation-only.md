# ADR 0002 - All Azure access uses Workload Identity Federation

- Status: Accepted
- Date: 2026-10-23

## Context

Secret-based service principal connections require rotation, are regularly
found in variable groups and logs, and keep working for anyone who copied the
secret. Storage account keys used for Terraform state grant full data-plane
access to every state file in the account.

## Decision

- Every Azure Resource Manager service connection uses Workload Identity
  Federation backed by a user-assigned managed identity (created by
  `platform/azure-devops-governance`).
- Templates never accept a secret, key or password parameter.
- Terraform state is accessed with Entra ID (`use_azuread_auth`, enabled by
  `backendAzureRmUseEntraIdForAuthentication`), so shared key access on the
  state storage account can be disabled.
- AKS access goes through `kubelogin` with the Azure CLI session, so clusters
  can disable local accounts.
- Plan and apply use different identities (Reader vs. Contributor).

## Consequences

- No secret rotation process exists because no secret exists.
- A federated credential trusts one service connection subject; renaming a
  connection requires updating the credential (automated by Terraform).
- Requires `TerraformTask@5` (Microsoft DevLabs Terraform extension) for OIDC
  with token refresh in long-running applies.
