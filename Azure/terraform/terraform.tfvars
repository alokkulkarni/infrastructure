# Azure Configuration
location     = "eastus"
project_name = "testcontainers"
environment  = "dev"

# Networking Configuration
vnet_address_space             = ["10.0.0.0/16"]
public_subnet_address_prefix   = ["10.0.1.0/24"]  # Public subnet for load balancers, etc.
private_subnet_address_prefix  = ["10.0.2.0/24"]  # Private subnet for VMs

# VM Configuration
vm_size        = "Standard_D2s_v3"
admin_username = "azureuser"

# GitHub Configuration - Update these for actual deployment
github_repo_url      = "https://github.com/alokkulkarni/infrastructure"
github_runner_name   = "azure-vm-runner-dev"
github_runner_labels = ["self-hosted", "azure", "linux", "docker", "dev"]

# GitHub OIDC Configuration - Update these for actual deployment
github_org  = "alokkulkarni"
github_repo = "infrastructure"
