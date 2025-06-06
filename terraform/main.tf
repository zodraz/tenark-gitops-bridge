locals {
  name        = local.environment
  environment = "control-plane"
  location    = var.location

  #cluster_version = var.kubernetes_version

  gitops_addons_url      = "${var.gitops_addons_org}/${var.gitops_addons_repo}"
  gitops_addons_basepath = var.gitops_addons_basepath
  gitops_addons_path     = var.gitops_addons_path
  gitops_addons_revision = var.gitops_addons_revision

  argocd_namespace = "argocd"

  azure_addons = {
    enable_azure_crossplane_upbound_provider = var.infrastructure_provider == "crossplane" ? true : false
    enable_cluster_api_operator              = var.infrastructure_provider == "capz" ? true : false
  }

  oss_addons = {
    enable_argocd                          = try(var.addons.enable_argocd, true) # installed by default
    argocd_chart_version                   = var.addons_versions[0].argocd_chart_version
    enable_argo_rollouts                   = try(var.addons.enable_argo_rollouts, true) # installed by default
    argo_rollouts_chart_version            = var.addons_versions[0].argo_rollouts_chart_version
    enable_argo_events                     = try(var.addons.enable_argo_events, true) # installed by default
    enable_argo_workflows                  = try(var.addons.enable_argo_workflows, true) # installed by default
    enable_cluster_proportional_autoscaler = try(var.addons.enable_cluster_proportional_autoscaler, false)
    enable_cert_manager                    = true
    enable_gatekeeper                      = try(var.addons.enable_gatekeeper, false)
    enable_gpu_operator                    = try(var.addons.enable_gpu_operator, false)
    enable_ingress_nginx                   = try(var.addons.enable_ingress_nginx, false)
    enable_kargo                           = try(var.addons.enable_kargo, true) # installed by default
    kargo_chart_version                    = var.addons_versions[0].kargo_chart_version
    enable_kyverno                         = try(var.addons.enable_kyverno, false)
    enable_kube_prometheus_stack           = try(var.addons.enable_kube_prometheus_stack, false)
    enable_metrics_server                  = try(var.addons.enable_metrics_server, false)
    enable_prometheus_adapter              = try(var.addons.enable_prometheus_adapter, false)
    enable_secrets_store_csi_driver        = try(var.addons.enable_secrets_store_csi_driver, false)
    enable_vpa                             = try(var.addons.enable_vpa, false)
    enable_crossplane                      = var.infrastructure_provider == "crossplane" ? true : false
    enable_crossplane_helm_provider        = var.infrastructure_provider == "crossplane" ? true : false
    enable_crossplane_kubernetes_provider  = var.infrastructure_provider == "crossplane" ? true : false
  }
  addons = merge(local.azure_addons, local.oss_addons)

  cluster_metadata = merge(local.environment_metadata, local.addons_metadata)

  environment_metadata = {
    infrastructure_provider = var.infrastructure_provider
    akspe_identity_id       = azurerm_user_assigned_identity.akspe.client_id
    git_public_ssh_key      = var.git_public_ssh_key
  }

  addons_metadata = {
    addons_repo_url      = local.gitops_addons_url
    addons_repo_basepath = local.gitops_addons_basepath
    addons_repo_path     = local.gitops_addons_path
    addons_repo_revision = local.gitops_addons_revision
  }

  argocd_apps = {
    addons    = file("${path.module}/bootstrap/addons.yaml")
  }

  tags = {
    Blueprint  = local.name
    GithubRepo = "https://github.com/zodraz/tenark-gitops-bridge"
    Environment = local.environment
    CreatedWith = "Terraform"
  }
}

data "azurerm_subscription" "current" {}

################################################################################
# Resource Group: Resource
################################################################################
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

################################################################################
# Virtual Network: Module
################################################################################

module "network" {
  source              = "Azure/subnets/azurerm"
  version             = "1.0.0"
  resource_group_name = azurerm_resource_group.this.name
  subnets = {
    aks = {
      address_prefixes  = ["10.52.0.0/16"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
  virtual_network_address_space = ["10.52.0.0/16"]
  virtual_network_location      = azurerm_resource_group.this.location
  virtual_network_name          = var.vnet_name
  virtual_network_tags          = var.tags
}

################################################################################
# AKS: Module
################################################################################

module "aks" {
  source                            = "Azure/aks/azurerm"
  version                           = "9.1.0"
  resource_group_name               = azurerm_resource_group.this.name
  location                          = var.location
  kubernetes_version                = var.kubernetes_version
  orchestrator_version              = var.kubernetes_version
  role_based_access_control_enabled = var.role_based_access_control_enabled
  rbac_aad                          = var.rbac_aad
  prefix                            = var.prefix
  # cluster_name                      = var.cluster_name
  # cluster_log_analytics_workspace_name = var.cluster_log_analytics_workspace_name 
  network_plugin                    = var.network_plugin
  vnet_subnet_id                    = lookup(module.network.vnet_subnets_name_id, "aks")
  os_disk_size_gb                   = var.os_disk_size_gb
  os_sku                            = var.os_sku
  sku_tier                          = var.sku_tier
  private_cluster_enabled           = var.private_cluster_enabled
  enable_auto_scaling               = var.enable_auto_scaling
  enable_host_encryption            = var.enable_host_encryption
  log_analytics_workspace_enabled   = var.log_analytics_workspace_enabled
  # agents_min_count                  = var.agents_min_count
  # agents_max_count                  = var.agents_max_count
  # agents_count                      = 2 # Please set `agents_count` `null` while `enable_auto_scaling` is `true` to avoid possible `agents_count` changes.
  # agents_max_pods                   = var.agents_max_pods
  # agents_pool_name                  = "system"
  # agents_availability_zones         = ["3"]
  # agents_type                       = "VirtualMachineScaleSets"
  # agents_size                       = var.agents_size
  monitor_metrics                   = {}
  azure_policy_enabled              = var.azure_policy_enabled
  microsoft_defender_enabled        = var.microsoft_defender_enabled
  tags                              = var.tags

  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  node_pools = {
    systempool = {
      name           = "systempool"
      vm_size        = var.agents_size
      node_count     = 2
      mode           = "User"
      os_type        = "Linux"
      enable_auto_scaling = true
      min_count      = var.agents_min_count
      max_count      = var.agents_max_count
      max_pods                     = var.agents_max_pods
      availability_zones           = ["3"]
      type                         = "VirtualMachineScaleSets"

      node_labels = {
        purpose = "apps"
        "nodepool" : "defaultnodepool"
      }
      tags = {
        # environment = "dev"
         Agent : "defaultnodepoolagent"
      }
    }
    userpool = {
      name           = "userpool"
      vm_size        = var.agents_size
      node_count     = 2
      mode           = "User"
      os_type        = "Linux"
      enable_auto_scaling = true
      min_count      = var.agents_min_count
      max_count      = var.agents_max_count
      max_pods                     = var.agents_max_pods
      availability_zones           = ["3"]
      type                         = "VirtualMachineScaleSets"
      node_labels = {
        purpose = "apps"
      }
      tags = var.tags
    }
  }

  # agents_labels = {
  #   "nodepool" : "defaultnodepool"
  # }

  # agents_tags = {
  #   "Agent" : "defaultnodepoolagent"
  # }

  network_policy             = var.network_policy
  net_profile_dns_service_ip = var.net_profile_dns_service_ip
  net_profile_service_cidr   = var.net_profile_service_cidr

  network_contributor_role_assigned_subnet_ids = { "aks" = lookup(module.network.vnet_subnets_name_id, "aks") }

  depends_on = [module.network]
}

################################################################################
# Workload Identity: Module
################################################################################

resource "azurerm_user_assigned_identity" "akspe" {
  name                = var.id_aks_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

resource "azurerm_role_assignment" "akspe_role_assignment" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.akspe.principal_id
}

resource "azurerm_federated_identity_credential" "crossplane" {
  count               = var.infrastructure_provider == "crossplane" ? 1 : 0
  depends_on          = [module.aks]
  name                = "crossplane-provider-azure"
  resource_group_name = azurerm_resource_group.this.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.akspe.id
  subject             = "system:serviceaccount:crossplane-system:azure-provider"
}

resource "azurerm_federated_identity_credential" "capz" {
  count               = var.infrastructure_provider == "capz" ? 1 : 0
  depends_on          = [module.aks]
  name                = "capz-manager-credential"
  resource_group_name = azurerm_resource_group.this.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.akspe.id
  subject             = "system:serviceaccount:azure-infrastructure-system:capz-manager"
}

resource "azurerm_federated_identity_credential" "service_operator" {
  count               = var.infrastructure_provider == "capz" ? 1 : 0
  depends_on          = [module.aks]
  name                = "serviceoperator"
  resource_group_name = azurerm_resource_group.this.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.akspe.id
  subject             = "system:serviceaccount:azure-infrastructure-system:azureserviceoperator-default"
}

################################################################################
# GitOps Bridge: Private ssh keys for git
################################################################################
resource "kubernetes_namespace" "argocd_namespace" {
  depends_on = [module.aks]
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_secret" "git_secrets" {
  depends_on = [kubernetes_namespace.argocd_namespace]
  for_each = {
    git-addons = {
      type          = "git"
      url           = var.gitops_addons_org
      # sshPrivateKey = file(pathexpand(var.git_private_ssh_key))
    }
  }
  metadata {
    name      = each.key
    namespace = kubernetes_namespace.argocd_namespace.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }
  data = each.value
}

################################################################################
# GitOps Bridge: Bootstrap
################################################################################
module "gitops_bridge_bootstrap" {
  depends_on = [module.aks,time_sleep.wait_60_seconds]
  source     = "gitops-bridge-dev/gitops-bridge/helm"

  cluster = {
    cluster_name = module.aks.aks_name
    environment  = local.environment
    metadata = merge(local.cluster_metadata,
    {
        kubelet_identity_client_id = module.aks.kubelet_identity[0].client_id
        subscription_id            = data.azurerm_subscription.current.subscription_id
        tenant_id                  = data.azurerm_subscription.current.tenant_id
    })
    addons = local.addons
  }
  apps = local.argocd_apps
  argocd = {
    namespace     = local.argocd_namespace
    chart_version = var.addons_versions[0].argocd_chart_version
  }
}

resource "time_sleep" "wait_60_seconds" {
  # depends_on = [kubernetes_namespace.openfaas]

  destroy_duration = "60s"
}

################################################################################
# ACR
################################################################################

resource "azurerm_container_registry" "acr" {
  name                = "acrtenark"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"
}

output "container_registry_name" {
  value = azurerm_container_registry.acr.name
}

output "container_registry_login_server" {
  value = azurerm_container_registry.acr.login_server
}

################################################################################
# KeyVault
################################################################################

resource "random_string" "azurerm_key_vault_name" {
  length  = 13
  lower   = true
  numeric = false
  special = false
  upper   = false
}

locals {
  current_user_id = coalesce(var.msi_id, data.azurerm_client_config.current.object_id)
}

resource "azurerm_key_vault" "vault" {
  name                       = coalesce(var.vault_name, "vault-${random_string.azurerm_key_vault_name.result}")
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.sku_name
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = local.current_user_id

    key_permissions    = var.key_permissions
    secret_permissions = var.secret_permissions
    certificate_permissions = var.certificate_permissions
  }
}

resource "azurerm_key_vault_certificate" "imported" {
  name         = "tenark-cert"
  key_vault_id = azurerm_key_vault.vault.id

  certificate {
    contents = filebase64("${path.module}/aks-ingress-tls.pfx")
    # password = var.pfx_password
  }

  certificate_policy {
    issuer_parameters {
      name = "Unknown"  # Required when importing
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=tenark.com"
      validity_in_months = 12
      key_usage = [                               
        "digitalSignature",
        "keyEncipherment"
      ]
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }
  }

  depends_on = [azurerm_key_vault_access_policy.example] # Ensure permissions exist
}


resource "random_string" "azurerm_key_vault_key_name" {
  length  = 13
  lower   = true
  numeric = false
  special = false
  upper   = false
}

resource "azurerm_key_vault_key" "key" {
  name = coalesce(var.key_name, "key-${random_string.azurerm_key_vault_key_name.result}")

  key_vault_id = azurerm_key_vault.vault.id
  key_type     = var.key_type
  key_size     = var.key_size
  key_opts     = var.key_ops

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }
}

output "azurerm_key_vault_name" {
  value = azurerm_key_vault.vault.name
}

output "azurerm_key_vault_id" {
  value = azurerm_key_vault.vault.id
}

resource "random_string" "azurerm_dns_zone_name" {
  length  = 13
  lower   = true
  numeric = false
  special = false
  upper   = false
}

resource "azurerm_dns_zone" "zone" {
  name = (
    var.dns_zone_name != null ?
    var.dns_zone_name :
    "www.${random_string.azurerm_dns_zone_name.result}.tenark.com"
  )
  resource_group_name = azurerm_resource_group.this.name
}