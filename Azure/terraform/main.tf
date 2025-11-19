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

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-${var.environment}-rg"
  location = var.location

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# OIDC Module for GitHub Actions
module "oidc" {
  source = "./modules/oidc"

  project_name    = var.project_name
  environment     = var.environment
  location        = var.location
  github_org      = var.github_org
  github_repo     = var.github_repo
  subscription_id = data.azurerm_client_config.current.subscription_id
  tenant_id       = data.azurerm_client_config.current.tenant_id
}

# Virtual Network Module
module "networking" {
  source = "./modules/networking"

  project_name                  = var.project_name
  environment                   = var.environment
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
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  private_subnet_id   = module.networking.private_subnet_id
}

# Virtual Machine Module (GitHub Runner)
module "vm" {
  source = "./modules/vm"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  private_subnet_id   = module.networking.private_subnet_id
  nsg_id              = module.security.nsg_id
  vm_size             = var.vm_size
  admin_username      = var.admin_username

  github_runner_token  = var.github_runner_token
  github_repo_url      = var.github_repo_url
  github_runner_name   = var.github_runner_name
  github_runner_labels = var.github_runner_labels
}

# Data source for current Azure configuration
data "azurerm_client_config" "current" {}
