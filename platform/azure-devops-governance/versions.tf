terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.16"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.9"
    }
  }

  # Partial configuration - supply the values with -backend-config at init time.
  backend "azurerm" {
    use_azuread_auth = true
  }
}

provider "azuredevops" {
  # Authentication is taken from the environment, e.g. AZDO_PERSONAL_ACCESS_TOKEN
  # for a one-off bootstrap, or ARM_USE_OIDC / service principal settings when
  # this configuration runs from a pipeline.
  org_service_url = var.azure_devops_org_url
}

provider "azurerm" {
  features {}
  subscription_id = var.identity_subscription_id
  # Authentication: Azure CLI locally, OIDC (ARM_USE_OIDC=true) in CI.
}
