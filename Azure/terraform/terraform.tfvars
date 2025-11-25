location     = "uksouth"
project_name = "testcontainers"
environment  = "dev"
environment_tag = "SIT-Alok-TeamA-20251125-0921"

vnet_address_space    = ["10.0.0.0/16"]
public_subnet_address_prefix   = ["10.0.1.0/24"]
private_subnet_address_prefix  = ["10.0.2.0/24"]

vm_size        = "Standard_D2s_v3"
admin_username = "azureuser"

github_repo_url      = "https://github.com/alokkulkarni/infrastructure"
github_runner_name   = "azure-vm-runner-SIT-Alok-TeamA-20251125-0921"
github_runner_labels = ["self-hosted", "azure", "linux", "docker", "dev", "SIT-Alok-TeamA-20251125-0921"]

# OIDC Configuration
github_org  = "alokkulkarni"
github_repo = "infrastructure"
