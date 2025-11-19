# Backend configuration for storing Terraform state in Azure Storage
# Note: Storage Account must be created before initializing
# Run the setup script: scripts/setup-terraform-backend.sh

terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateXXXXX" # Must be globally unique
    container_name       = "tfstate"
    key                  = "azure/testcontainers/terraform.tfstate"
  }
}
