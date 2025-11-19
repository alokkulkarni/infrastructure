# Azure Infrastructure

This directory contains Terraform configurations and GitHub Actions workflows for deploying infrastructure to Azure using OpenID Connect (OIDC) authentication.

## 🔐 Security First

This setup uses **OIDC (OpenID Connect)** instead of storing long-lived credentials, providing:

- ✅ No service principal secrets to manage or rotate
- ✅ Short-lived tokens (valid for minutes)
- ✅ Branch and environment-specific access control
- ✅ Full audit trail in Azure AD
- ✅ Automatic token refresh

**No SSH access** is configured by default. VMs use managed identities and can be accessed via Azure Bastion or Azure CLI when needed.

## 📁 Directory Structure

```
Azure/
├── .github/
│   └── workflows/
│       ├── deploy-azure-infrastructure.yml    # Main deployment workflow (OIDC)
│       └── destroy-azure-infrastructure.yml   # Infrastructure teardown
├── terraform/
│   ├── main.tf                               # Root configuration
│   ├── variables.tf                          # Input variables
│   ├── outputs.tf                            # Output values
│   ├── backend.tf                            # Terraform state backend
│   ├── terraform.tfvars.example              # Example configuration
│   └── modules/
│       ├── oidc/                             # Azure AD OIDC configuration
│       ├── networking/                       # VNet, subnets
│       ├── security/                         # NSG rules
│       └── vm/                               # Virtual machines
├── scripts/
│   └── setup-terraform-backend.sh            # Backend initialization
├── OIDC_SETUP.md                             # Comprehensive OIDC guide
├── OIDC_QUICKSTART.md                        # Quick reference
└── README.md                                 # This file
```

## 🏗️ Architecture

The Terraform configuration deploys:

- **Resource Group**: Logical container for all resources
- **Virtual Network**: Isolated network (10.0.0.0/16)
- **Subnet**: VM subnet (10.0.1.0/24)
- **Network Security Group**: HTTP/HTTPS only (no SSH)
- **Linux VM**: Ubuntu 22.04 with Docker and Nginx
- **Key Vault**: Secure storage for SSH keys (backup only)
- **Managed Identity**: System-assigned for Azure resource access
- **Azure AD App**: OIDC federated credentials for GitHub Actions
- **GitHub Runner**: Self-hosted runner on the VM

### Network Flow

```
Internet → NSG (Allow HTTP/HTTPS) → VM → Docker Network → Nginx Container
                                       ↓
                                  GitHub Runner
```

### OIDC Authentication Flow

```
GitHub Actions → OIDC Token Request → GitHub OIDC Provider
                                            ↓
                                       Azure AD validates
                                            ↓
                                    Issues Access Token
                                            ↓
                                    Terraform applies changes
```

## 🚀 Quick Start

### Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI installed (`az --version`)
- Terraform >= 1.0
- GitHub repository with Actions enabled
- Permissions: `Application.ReadWrite.All`, `Contributor`, `User Access Administrator`

### Step 1: Setup Terraform Backend

```bash
cd infrastructure/Azure

# Set environment variables
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="terraform-state-rg"
export STORAGE_ACCOUNT_NAME="tfstate$(openssl rand -hex 4)"

# Run setup script
chmod +x scripts/setup-terraform-backend.sh
./scripts/setup-terraform-backend.sh

# Note the storage account name
echo $STORAGE_ACCOUNT_NAME
```

### Step 2: Configure OIDC

Follow the [OIDC Setup Guide](./OIDC_SETUP.md) to create the Azure AD application with federated credentials.

**Quick option** - Let Terraform create the OIDC app:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform apply
```

### Step 3: Configure GitHub Secrets

Add these secrets to your GitHub repository (Settings > Secrets and variables > Actions):

| Secret | Description | How to Get |
|--------|-------------|-----------|
| `AZURE_CLIENT_ID` | Application (client) ID | `terraform output github_actions_app_id` |
| `AZURE_TENANT_ID` | Directory (tenant) ID | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID | `az account show --query id -o tsv` |
| `TERRAFORM_STATE_RG` | Backend resource group | `terraform-state-rg` |
| `TERRAFORM_STATE_STORAGE` | Backend storage account | From Step 1 output |
| `PAT_TOKEN` | GitHub PAT with `repo` scope | [Generate](https://github.com/settings/tokens) |

### Step 4: Deploy Infrastructure

**Option A: GitHub Actions (Recommended)**

1. Go to **Actions** tab
2. Select **Deploy Azure Infrastructure (OIDC)**
3. Click **Run workflow**
4. Select environment and region
5. Click **Run workflow**

**Option B: Local Deployment**

```bash
cd terraform

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
location     = "eastus"
project_name = "testcontainers"
environment  = "dev"

vnet_address_space    = ["10.0.0.0/16"]
subnet_address_prefix = ["10.0.1.0/24"]

vm_size        = "Standard_D2s_v3"
admin_username = "azureuser"

github_org  = "YOUR_GITHUB_ORG"
github_repo = "YOUR_REPO_NAME"

github_repo_url      = "https://github.com/YOUR_ORG/YOUR_REPO"
github_runner_name   = "azure-vm-runner-dev"
github_runner_labels = ["self-hosted", "azure", "linux", "docker", "dev"]
EOF

# Update backend configuration
cat > backend.tf <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateXXXXXXXX"
    container_name       = "tfstate"
    key                  = "azure/dev/terraform.tfstate"
  }
}
EOF

# Deploy
terraform init
terraform plan
terraform apply
```

### Step 5: Verify Deployment

```bash
# Check resources
az resource list --resource-group testcontainers-dev-rg --output table

# Check GitHub runner
# Go to: Settings > Actions > Runners
# Look for: azure-vm-runner-dev (should be "Idle")

# Get VM IP
terraform output vm_private_ip

# Get OIDC app ID
terraform output github_actions_app_id
```

## 📚 Documentation

- **[OIDC Setup Guide](./OIDC_SETUP.md)**: Comprehensive setup instructions with troubleshooting
- **[OIDC Quick Reference](./OIDC_QUICKSTART.md)**: Quick commands and common fixes

## 🔧 Configuration

### Terraform Variables

Key variables in `terraform.tfvars`:

```hcl
# Basic Configuration
location     = "eastus"
project_name = "testcontainers"
environment  = "dev"

# Networking
vnet_address_space    = ["10.0.0.0/16"]
subnet_address_prefix = ["10.0.1.0/24"]

# VM Configuration
vm_size        = "Standard_D2s_v3"  # 2 vCPU, 8 GB RAM
admin_username = "azureuser"

# GitHub Configuration
github_org             = "YOUR_GITHUB_ORG"
github_repo            = "YOUR_REPO_NAME"
github_repo_url        = "https://github.com/YOUR_ORG/YOUR_REPO"
github_runner_name     = "azure-vm-runner-dev"
github_runner_labels   = ["self-hosted", "azure", "linux", "docker", "dev"]

# GitHub Runner Token (set via environment variable or workflow)
github_runner_token = "RUNNER_TOKEN_FROM_GITHUB"
```

### Environment-Specific Deployments

Create separate state files for each environment:

**Development:**
```hcl
key = "azure/dev/terraform.tfstate"
```

**Staging:**
```hcl
key = "azure/staging/terraform.tfstate"
```

**Production:**
```hcl
key = "azure/prod/terraform.tfstate"
```

## 🔒 Security Features

### No SSH Access
- SSH password authentication disabled
- No SSH inbound rule in NSG
- Access via Azure Bastion or `az vm run-command`

### Managed Identity
- System-assigned managed identity enabled
- No credentials stored on the VM
- Azure resources accessed via identity

### Network Security
- NSG allows only HTTP (80) and HTTPS (443) inbound
- All outbound traffic allowed (for package installation)
- Private IP only (no public IP by default)

### OIDC Benefits
- No long-lived credentials
- Branch/environment-specific access
- Full audit trail
- Automatic token rotation

### Key Vault
- SSH private key stored securely (backup only)
- Soft-delete enabled
- Access via access policy (not RBAC in this setup)

## 🧪 Testing

### Test OIDC Authentication

```bash
# Test federated credentials
az ad app federated-credential list --id $APP_ID

# Test role assignments
az role assignment list --assignee $SP_ID --output table
```

### Test Terraform Configuration

```bash
cd terraform

# Format check
terraform fmt -check -recursive

# Validate
terraform validate

# Dry run
terraform plan
```

### Test GitHub Runner

Create a test workflow:

```yaml
name: Test Azure Runner

on: workflow_dispatch

jobs:
  test:
    runs-on: [self-hosted, azure, linux, docker, dev]
    steps:
      - run: echo "Running on Azure VM runner"
      - run: docker --version
      - run: az --version
```

## 🗑️ Cleanup

### Destroy Infrastructure

**Option A: GitHub Actions**

1. Go to **Actions** tab
2. Select **Destroy Azure Infrastructure**
3. Click **Run workflow**
4. Type `destroy` to confirm
5. Click **Run workflow**

**Option B: Local Destroy**

```bash
cd terraform
terraform destroy
```

### Remove OIDC Application

```bash
# Get app ID
export APP_ID=$(az ad app list --display-name "github-actions-oidc-testcontainers" --query "[0].appId" -o tsv)

# Delete service principal
az ad sp delete --id $APP_ID

# Delete application
az ad app delete --id $APP_ID
```

### Remove Terraform Backend

```bash
# Delete storage container
az storage container delete \
  --name tfstate \
  --account-name $STORAGE_ACCOUNT_NAME

# Delete storage account
az storage account delete \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group terraform-state-rg

# Delete resource group
az group delete --name terraform-state-rg --yes --no-wait
```

## 🐛 Troubleshooting

### Common Issues

**"Application not found"**
```bash
# Verify app exists
az ad app show --id $APP_ID
```

**"Subject does not match"**
```bash
# Check federated credentials
az ad app federated-credential list --id $APP_ID
```

**"Insufficient privileges"**
```bash
# Re-assign roles
az role assignment create \
  --role "Contributor" \
  --assignee $SP_ID \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

**"Backend initialization failed"**
```bash
# Re-run backend setup
cd infrastructure/Azure
./scripts/setup-terraform-backend.sh
```

For more troubleshooting, see [OIDC Setup Guide - Troubleshooting](./OIDC_SETUP.md#troubleshooting).

## 📊 Outputs

After deployment, Terraform provides:

```hcl
resource_group_name                = "testcontainers-dev-rg"
resource_group_id                  = "/subscriptions/.../resourceGroups/..."
vnet_id                            = "/subscriptions/.../virtualNetworks/..."
subnet_id                          = "/subscriptions/.../subnets/..."
vm_id                              = "/subscriptions/.../virtualMachines/..."
vm_private_ip                      = "10.0.1.4"
nsg_id                             = "/subscriptions/.../networkSecurityGroups/..."
github_actions_app_id              = "12345678-1234-1234-1234-123456789abc"
github_actions_service_principal_id = "87654321-4321-4321-4321-cba987654321"
subscription_id                    = "your-subscription-id"
tenant_id                          = "your-tenant-id"
```

## 🔄 Workflow Features

### Deploy Workflow

- **4-stage pipeline**: backend setup, token generation, plan, apply
- **Environment protection**: Approval required for production
- **Artifact storage**: Plan files retained for 5 days
- **Output artifacts**: Terraform outputs saved for 30 days
- **Summary generation**: Results displayed in GitHub Actions summary

### Destroy Workflow

- **Confirmation required**: Must type "destroy" to proceed
- **Environment protection**: Uses same environment protection rules
- **Clean summary**: Reports destruction status

## 📖 Additional Resources

- [Azure OIDC Documentation](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
- [GitHub Actions OIDC](https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure AD Federated Credentials](https://learn.microsoft.com/azure/active-directory/develop/workload-identity-federation)

## 🤝 Contributing

When making changes:

1. Test locally with `terraform plan`
2. Format code: `terraform fmt -recursive`
3. Validate: `terraform validate`
4. Create PR with clear description
5. Wait for workflow validation
6. Merge after approval

## 📝 License

See main repository LICENSE file.

## 🎯 Summary

This Azure infrastructure setup provides:

- ✅ Secure OIDC authentication (no secrets)
- ✅ Modular Terraform configuration
- ✅ Automated GitHub Actions workflows
- ✅ Self-hosted GitHub runner on Azure VM
- ✅ Docker and Nginx ready to deploy applications
- ✅ No SSH access (security-first approach)
- ✅ Managed identity for Azure resource access
- ✅ Comprehensive documentation and troubleshooting

Get started with the [OIDC Setup Guide](./OIDC_SETUP.md) or the [Quick Reference](./OIDC_QUICKSTART.md).
