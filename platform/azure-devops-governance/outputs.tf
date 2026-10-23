output "environments" {
  description = "Azure DevOps environment names per logical environment - use them as the `environment` key in the promotion templates."
  value       = { for k, v in azuredevops_environment.this : k => v.name }
}

output "service_connections" {
  description = "Workload Identity Federation service connection names per environment."
  value       = { for k, v in azuredevops_serviceendpoint_azurerm.this : k => v.service_endpoint_name }
}

output "pipeline_identities" {
  description = "Client and principal IDs of the managed identities behind the service connections (for additional RBAC, e.g. AKS namespaces)."
  value = {
    for k, v in azurerm_user_assigned_identity.pipeline : k => {
      client_id    = v.client_id
      principal_id = v.principal_id
    }
  }
}
