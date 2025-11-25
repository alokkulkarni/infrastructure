terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}

  # Skip automatic resource provider registration for dry runs
  skip_provider_registration = true
}

provider "azuread" {
}

locals {
  common_tags = {
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
    Project        = var.project_name
    ManagedBy      = "Terraform"
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-${var.environment}-rg"
  location = var.location

  tags = local.common_tags
}

# OIDC Module for GitHub Actions
# NOTE: OIDC is already configured manually via setup-oidc-manually.sh
# This module requires Azure AD admin privileges and is not needed for runtime infrastructure
# Uncomment only if you want Terraform to manage OIDC configuration
# module "oidc" {
#   source = "./modules/oidc"
#
#   project_name    = var.project_name
#   environment     = var.environment
#   environment_tag = var.environment_tag
#   location        = var.location
#   github_org      = var.github_org
#   github_repo     = var.github_repo
#   subscription_id = data.azurerm_client_config.current.subscription_id
#   tenant_id       = data.azurerm_client_config.current.tenant_id
# }

# Virtual Network Module
module "networking" {
  source = "./modules/networking"

  project_name                  = var.project_name
  environment                   = var.environment
  environment_tag               = var.environment_tag
  location                      = var.location
  resource_group_name           = azurerm_resource_group.main.name
  vnet_address_space            = var.vnet_address_space
  public_subnet_address_prefix  = var.public_subnet_address_prefix
  private_subnet_address_prefix = var.private_subnet_address_prefix
}

# Network Security Group Module
module "security" {
  source = "./modules/security"

  project_name        = var.project_name
  environment         = var.environment
  environment_tag     = var.environment_tag
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  private_subnet_id   = module.networking.private_subnet_id
}

# Load Balancer Module (in public subnet)
module "load_balancer" {
  source = "./modules/load-balancer"

  project_name        = var.project_name
  environment         = var.environment
  environment_tag     = var.environment_tag
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  public_subnet_id    = module.networking.public_subnet_id
}

# Virtual Machine Module (GitHub Runner)
module "vm" {
  source = "./modules/vm"

  project_name        = var.project_name
  environment         = var.environment
  environment_tag     = var.environment_tag
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  private_subnet_id   = module.networking.private_subnet_id
  nsg_id              = module.security.nsg_id
  vm_size             = var.vm_size
  admin_username      = var.admin_username

  github_pat           = var.github_pat
  github_repo_url      = var.github_repo_url
  github_runner_name   = var.github_runner_name
  github_runner_labels = var.github_runner_labels
}

# Associate VM NIC with Load Balancer Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "main" {
  network_interface_id    = module.vm.network_interface_id
  ip_configuration_name   = "internal"
  backend_address_pool_id = module.load_balancer.backend_pool_id
}

# Data source for current Azure configuration
data "azurerm_client_config" "current" {}
