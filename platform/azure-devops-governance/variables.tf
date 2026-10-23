variable "azure_devops_org_url" {
  description = "Azure DevOps organisation URL, e.g. https://dev.azure.com/contoso."
  type        = string

  validation {
    condition     = can(regex("^https://dev\\.azure\\.com/[A-Za-z0-9-]+/?$", var.azure_devops_org_url))
    error_message = "Use the https://dev.azure.com/<organisation> form."
  }
}

variable "project_name" {
  description = "Azure DevOps project that hosts the application pipelines."
  type        = string
}

variable "application" {
  description = "Short application name; used as prefix for environments, identities and service connections."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,24}$", var.application))
    error_message = "Use 2-24 lowercase letters, digits or hyphens."
  }
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID."
  type        = string
}

variable "identity_subscription_id" {
  description = "Subscription that hosts the user-assigned managed identities used by the service connections."
  type        = string
}

variable "identity_resource_group_name" {
  description = "Existing resource group for the pipeline identities."
  type        = string
}

variable "location" {
  description = "Azure region for the managed identities."
  type        = string
  default     = "westeurope"
}

variable "required_template" {
  description = <<-EOT
    The governance extends template every pipeline must use to reach the protected
    resources. `allowed_refs` lists the supported template releases: the Required
    template check matches the exact ref, so adding a new tag here is part of the
    release process and removing an old tag is how a version is retired.
  EOT
  type = object({
    repository_type = string
    repository_name = string
    template_path   = string
    allowed_refs    = list(string)
  })
  default = {
    repository_type = "github"
    repository_name = "rsk071216-stack/azure-devops-pipeline-templates"
    template_path   = "templates/governance/secure-pipeline.yml"
    allowed_refs    = ["refs/tags/v1.0.0"]
  }

  validation {
    condition     = contains(["azuregit", "github", "githubenterprise", "bitbucket"], var.required_template.repository_type)
    error_message = "repository_type must be azuregit, github, githubenterprise or bitbucket."
  }

  validation {
    condition     = length(var.required_template.allowed_refs) > 0 && alltrue([for r in var.required_template.allowed_refs : can(regex("^refs/(tags|heads)/", r))])
    error_message = "allowed_refs must contain at least one full ref such as refs/tags/v1.0.0."
  }
}

variable "environments" {
  description = <<-EOT
    Deployment environments keyed by short name (dev, test, prod...). For each one this
    configuration creates an Azure DevOps environment with checks, a user-assigned
    managed identity, a Workload Identity Federation service connection and RBAC.
  EOT
  type = map(object({
    subscription_id   = string
    subscription_name = string
    approver_groups   = optional(list(string), [])
    min_approvers     = optional(number, 1)
    approval_timeout  = optional(number, 4320)
    exclusive_lock    = optional(bool, false)
    allowed_branches  = optional(string, "refs/heads/main")
    business_hours = optional(object({
      start_time = string
      end_time   = string
      time_zone  = string
      days       = list(string)
    }), null)
    role_assignments = optional(list(object({
      scope = string
      role  = string
    })), [])
  }))

  validation {
    condition = alltrue([
      for env in values(var.environments) : env.business_hours == null || alltrue([
        for d in env.business_hours.days : contains(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"], d)
      ])
    ])
    error_message = "business_hours.days must contain lowercase English weekday names."
  }
}
