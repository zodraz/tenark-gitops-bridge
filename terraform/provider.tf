terraform {
  cloud {
    organization = "Tenark"
    # hostname = "app.terraform.io" # Optional; defaults to app.terraform.io

    workspaces {
      name = "control-plane"
    }
  }
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53.1"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.111"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13"
    }
  }
  required_version = ">= 1.1.0"
}

data "azurerm_client_config" "current" {}

provider "azuread" {
  tenant_id = data.azurerm_client_config.current.tenant_id
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

output "kube_config_host" {
  value = module.aks.host
  sensitive = true
}

output "kube_config_client_certificate" {
  value     = module.aks.client_certificate
  sensitive = true
}

output "kube_config_client_key" {
  value     = module.aks.client_key
  sensitive = true
}

output "kube_config_cluster_ca_certificate" {
  value     = module.aks.cluster_ca_certificate
  sensitive = true
}

provider "helm" {
  kubernetes = {
    host                   = module.aks.host
    client_certificate     = base64decode(module.aks.client_certificate)
    client_key             = base64decode(module.aks.client_key)
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  }
}
provider "kubernetes" {
    host                   = module.aks.host
    client_certificate     = base64decode(module.aks.client_certificate)
    client_key             = base64decode(module.aks.client_key)
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
}

provider "random" {}