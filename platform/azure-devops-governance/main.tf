# Governance as code for one application: Azure DevOps environments with their
# checks, plus one secretless (Workload Identity Federation) service connection
# per environment backed by a user-assigned managed identity.

data "azuredevops_project" "this" {
  name = var.project_name
}

locals {
  all_approver_groups = toset(flatten([for env in values(var.environments) : env.approver_groups]))

  role_assignments = merge([
    for env_name, env in var.environments : {
      for idx, ra in env.role_assignments : "${env_name}-${idx}" => {
        env   = env_name
        scope = ra.scope
        role  = ra.role
      }
    }
  ]...)
}

data "azuredevops_group" "approvers" {
  for_each   = local.all_approver_groups
  project_id = data.azuredevops_project.this.id
  name       = each.value
}

# -----------------------------------------------------------------------------
# Environments and their checks
# -----------------------------------------------------------------------------

resource "azuredevops_environment" "this" {
  for_each    = var.environments
  project_id  = data.azuredevops_project.this.id
  name        = "${var.application}-${each.key}"
  description = "Managed by Terraform (platform/azure-devops-governance). Do not edit checks in the portal."
}

resource "azuredevops_check_approval" "this" {
  for_each = { for k, v in var.environments : k => v if length(v.approver_groups) > 0 }

  project_id                 = data.azuredevops_project.this.id
  target_resource_id         = azuredevops_environment.this[each.key].id
  target_resource_type       = "environment"
  approvers                  = [for g in each.value.approver_groups : data.azuredevops_group.approvers[g].origin_id]
  minimum_required_approvers = each.value.min_approvers
  requester_can_approve      = false
  timeout                    = each.value.approval_timeout
  instructions               = "Review the Terraform plan / release summary on the run before approving ${var.application}-${each.key}."
}

resource "azuredevops_check_business_hours" "this" {
  for_each = { for k, v in var.environments : k => v if v.business_hours != null }

  project_id           = data.azuredevops_project.this.id
  display_name         = "Business hours (${each.value.business_hours.time_zone})"
  target_resource_id   = azuredevops_environment.this[each.key].id
  target_resource_type = "environment"
  start_time           = each.value.business_hours.start_time
  end_time             = each.value.business_hours.end_time
  time_zone            = each.value.business_hours.time_zone
  monday               = contains(each.value.business_hours.days, "monday")
  tuesday              = contains(each.value.business_hours.days, "tuesday")
  wednesday            = contains(each.value.business_hours.days, "wednesday")
  thursday             = contains(each.value.business_hours.days, "thursday")
  friday               = contains(each.value.business_hours.days, "friday")
  saturday             = contains(each.value.business_hours.days, "saturday")
  sunday               = contains(each.value.business_hours.days, "sunday")
  timeout              = 1440
}

resource "azuredevops_check_exclusive_lock" "this" {
  for_each = { for k, v in var.environments : k => v if v.exclusive_lock }

  project_id           = data.azuredevops_project.this.id
  target_resource_id   = azuredevops_environment.this[each.key].id
  target_resource_type = "environment"
  timeout              = 43200
}

resource "azuredevops_check_required_template" "environment" {
  for_each = var.environments

  project_id           = data.azuredevops_project.this.id
  target_resource_id   = azuredevops_environment.this[each.key].id
  target_resource_type = "environment"

  dynamic "required_template" {
    for_each = var.required_template.allowed_refs
    content {
      repository_type = var.required_template.repository_type
      repository_name = var.required_template.repository_name
      repository_ref  = required_template.value
      template_path   = var.required_template.template_path
    }
  }
}

# -----------------------------------------------------------------------------
# Secretless service connections (Workload Identity Federation)
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "pipeline" {
  for_each            = var.environments
  name                = "id-ado-${var.application}-${each.key}"
  resource_group_name = var.identity_resource_group_name
  location            = var.location
  tags = {
    purpose     = "azure-devops-service-connection"
    application = var.application
    environment = each.key
  }
}

resource "azuredevops_serviceendpoint_azurerm" "this" {
  for_each = var.environments

  project_id                             = data.azuredevops_project.this.id
  service_endpoint_name                  = "sc-${var.application}-${each.key}"
  description                            = "Workload Identity Federation - managed by Terraform. No secret exists for this connection."
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"

  credentials {
    serviceprincipalid = azurerm_user_assigned_identity.pipeline[each.key].client_id
  }

  azurerm_spn_tenantid      = var.tenant_id
  azurerm_subscription_id   = each.value.subscription_id
  azurerm_subscription_name = each.value.subscription_name
}

resource "azurerm_federated_identity_credential" "pipeline" {
  for_each                  = var.environments
  name                      = "ado-${var.application}-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.pipeline[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azuredevops_serviceendpoint_azurerm.this[each.key].workload_identity_federation_issuer
  subject                   = azuredevops_serviceendpoint_azurerm.this[each.key].workload_identity_federation_subject
}

resource "azurerm_role_assignment" "pipeline" {
  for_each             = local.role_assignments
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.pipeline[each.value.env].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Azure DevOps pipeline identity for ${var.application}-${each.value.env}"
}

# The service connection itself is protected too: only governed pipelines on
# protected branches may use it, even outside a deployment job.
resource "azuredevops_check_required_template" "service_connection" {
  for_each = var.environments

  project_id           = data.azuredevops_project.this.id
  target_resource_id   = azuredevops_serviceendpoint_azurerm.this[each.key].id
  target_resource_type = "endpoint"

  dynamic "required_template" {
    for_each = var.required_template.allowed_refs
    content {
      repository_type = var.required_template.repository_type
      repository_name = var.required_template.repository_name
      repository_ref  = required_template.value
      template_path   = var.required_template.template_path
    }
  }
}

resource "azuredevops_check_branch_control" "service_connection" {
  for_each = var.environments

  project_id                       = data.azuredevops_project.this.id
  display_name                     = "Protected branches only"
  target_resource_id               = azuredevops_serviceendpoint_azurerm.this[each.key].id
  target_resource_type             = "endpoint"
  allowed_branches                 = each.value.allowed_branches
  verify_branch_protection         = true
  ignore_unknown_protection_status = false
}
