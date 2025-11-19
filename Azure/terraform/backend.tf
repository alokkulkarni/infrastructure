# Temporarily using local backend for dry run validation
# Uncomment and configure for production use
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "terraform-state-rg"
#     storage_account_name = "tfstateXXXXX" # Must be globally unique
#     container_name       = "tfstate"
#     key                  = "azure/testcontainers/terraform.tfstate"
#   }
# }

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
