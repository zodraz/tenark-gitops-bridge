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

# resource "local_file" "kubeconfig" {
#   content  = module.aks.kube_config_raw
#   filename = "${path.module}/kubeconfig"
# }

resource "local_file" "kubeconfig" {
  content  = module.aks.kubeconfig_raw
  filename = "kubeconfig"
}

output "kubeconfig_file" {
    value = "${path.cwd}/kubeconfig"
}

data "terraform_remote_state" "kubeconfig_file" {
  backend = "remote"

  config = {
    organization = "Tenark"
    workspaces = {
      name = "control-plane"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = "${data.terraform_remote_state.kubeconfig_file.outputs.kubeconfig_file}"
  }
}

provider "kubernetes" {
  config_path = "${data.terraform_remote_state.kubeconfig_file.outputs.kubeconfig_file}"
}


# provider "kubernetes" {
#    config_path = local_file.kubeconfig.filename
# }

# provider "helm" {
#   kubernetes {
#      config_path = local_file.kubeconfig.filename
#   }

# }
provider "random" {}