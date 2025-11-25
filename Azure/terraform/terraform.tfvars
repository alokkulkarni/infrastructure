location     = "uksouth"
project_name = "testcontainers"
environment  = "dev"
environment_tag = "SIT-Alok-TeamA-20251125-0921"

vnet_address_space    = ["10.0.0.0/16"]
public_subnet_address_prefix   = ["10.0.1.0/24"]
private_subnet_address_prefix  = ["10.0.2.0/24"]

vm_size        = "Standard_D2s_v3"
admin_username = "azureuser"

# GitHub Runner Configuration
# NOTE: When running via GitHub Actions workflow, these values are dynamically generated
# and this file is overwritten. The workflow uses the 'github_runner_repo' input parameter
# to determine the target repository for runner registration (defaults to sit-test-repo).
github_repo_url      = "https://github.com/alokkulkarni/sit-test-repo"
github_runner_name   = "azure-vm-runner-SIT-Alok-TeamA-20251125-0921"
github_runner_labels = ["self-hosted", "azure", "linux", "docker", "dev", "SIT-Alok-TeamA-20251125-0921"]

# OIDC Configuration (for GitHub Actions authentication to Azure)
# These refer to the infrastructure repo where workflows run
github_org  = "alokkulkarni"
github_repo = "infrastructure"
