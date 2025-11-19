# Azure OIDC Setup for GitHub Actions

This guide explains how to set up OpenID Connect (OIDC) authentication between GitHub Actions and Azure, eliminating the need for storing long-lived credentials as secrets.

## Table of Contents

- [Why OIDC?](#why-oidc)
- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Bootstrap Terraform State Backend](#bootstrap-terraform-state-backend)
- [Method 1: Bootstrap with Terraform](#method-1-bootstrap-with-terraform)
- [Method 2: Manual Setup via Azure Portal](#method-2-manual-setup-via-azure-portal)
- [Method 3: Setup via Azure CLI](#method-3-setup-via-azure-cli)
- [Configure GitHub Secrets](#configure-github-secrets)
- [Testing the Setup](#testing-the-setup)
- [Troubleshooting](#troubleshooting)
- [Migration from Service Principal Secrets](#migration-from-service-principal-secrets)

## Why OIDC?

### Problems with Traditional Authentication

**Service Principal with Client Secret:**
- ❌ Secrets must be rotated regularly (typically every 90 days)
- ❌ Secrets can be accidentally exposed in logs or code
- ❌ Secrets must be stored in GitHub Secrets
- ❌ Risk of secret sprawl across multiple repositories
- ❌ Manual rotation process is error-prone

### Benefits of OIDC

**Federated Identity Credentials:**
- ✅ No secrets to manage or rotate
- ✅ Credentials are short-lived tokens (valid for minutes)
- ✅ Built-in to GitHub Actions (no external dependencies)
- ✅ Automatic token refresh
- ✅ Scope credentials to specific branches, PRs, or environments
- ✅ Improved security posture and compliance

## How It Works

```
┌─────────────────┐
│  GitHub Actions │
│   Workflow      │
└────────┬────────┘
         │ 1. Request OIDC token
         ▼
┌─────────────────┐
│  GitHub OIDC    │
│   Provider      │
└────────┬────────┘
         │ 2. Issues signed JWT token
         ▼
┌─────────────────┐
│  Azure AD       │
│  (Entra ID)     │
└────────┬────────┘
         │ 3. Validates token
         │ 4. Issues Azure access token
         ▼
┌─────────────────┐
│  Azure          │
│  Resources      │
└─────────────────┘
```

### Token Claims

The OIDC token includes claims that Azure uses to validate:

- **Issuer**: `https://token.actions.githubusercontent.com`
- **Audience**: `api://AzureADTokenExchange`
- **Subject**: Identifies the workflow context
  - Branch: `repo:ORG/REPO:ref:refs/heads/BRANCH`
  - Pull Request: `repo:ORG/REPO:pull_request`
  - Environment: `repo:ORG/REPO:environment:ENV_NAME`

## Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI installed (`az --version`)
- Terraform >= 1.0 (if using Terraform bootstrap method)
- GitHub repository with Actions enabled
- Permissions to create Azure AD applications and service principals

### Required Azure Permissions

Your account needs:
- `Application.ReadWrite.All` in Azure AD
- `Contributor` or higher on the subscription
- `User Access Administrator` (to assign roles to the app)

Check permissions:
```bash
az ad signed-in-user show --query "{Name:displayName, UPN:userPrincipalName, ObjectId:id}"
```

## Bootstrap Terraform State Backend

Before deploying infrastructure, set up the Terraform backend storage:

### Step 1: Set Environment Variables

```bash
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="terraform-state-rg"
export STORAGE_ACCOUNT_NAME="tfstate$(openssl rand -hex 4)"  # Generates unique name
```

### Step 2: Run Backend Setup Script

```bash
cd infrastructure/Azure
chmod +x scripts/setup-terraform-backend.sh
./scripts/setup-terraform-backend.sh
```

This creates:
- Resource group for Terraform state
- Storage account with encryption and versioning
- Blob container for state files

### Step 3: Note the Storage Account Name

Save the storage account name for GitHub Secrets:
```bash
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
```

## Method 1: Bootstrap with Terraform

This is the recommended approach as it creates the OIDC app and federated credentials automatically.

### Step 1: Authenticate to Azure

```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### Step 2: Get Your Azure IDs

```bash
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export ARM_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Subscription ID: $ARM_SUBSCRIPTION_ID"
echo "Tenant ID: $ARM_TENANT_ID"
```

### Step 3: Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
location     = "eastus"
project_name = "testcontainers"
environment  = "dev"

# GitHub Configuration
github_org  = "YOUR_GITHUB_ORG"
github_repo = "YOUR_REPO_NAME"

github_repo_url      = "https://github.com/YOUR_ORG/YOUR_REPO"
github_runner_name   = "azure-vm-runner-dev"
github_runner_labels = ["self-hosted", "azure", "linux", "docker", "dev"]
```

### Step 4: Initialize Terraform

Update `backend.tf` with your backend storage:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateXXXXXXXX"  # Your storage account
    container_name       = "tfstate"
    key                  = "azure/dev/terraform.tfstate"
  }
}
```

Initialize:
```bash
terraform init
```

### Step 5: Deploy with Terraform

```bash
# Review the plan
terraform plan

# Apply (this creates the OIDC app)
terraform apply
```

### Step 6: Get the Application ID

```bash
terraform output github_actions_app_id
```

This Application ID (Client ID) is needed for GitHub Secrets.

### Step 7: Skip to [Configure GitHub Secrets](#configure-github-secrets)

## Method 2: Manual Setup via Azure Portal

### Step 1: Create Azure AD Application

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** > **App registrations**
3. Click **New registration**
4. Enter details:
   - **Name**: `github-actions-oidc-testcontainers`
   - **Supported account types**: Single tenant
5. Click **Register**

### Step 2: Add Federated Credentials

1. In your app registration, go to **Certificates & secrets**
2. Click **Federated credentials** tab
3. Click **Add credential**

#### For Main Branch Deployments:

- **Federated credential scenario**: GitHub Actions deploying Azure resources
- **Organization**: `YOUR_GITHUB_ORG`
- **Repository**: `YOUR_REPO_NAME`
- **Entity type**: Branch
- **GitHub branch name**: `main`
- **Name**: `main-branch-deploy`

Click **Add**.

#### For Pull Request Validation:

Click **Add credential** again:
- **Entity type**: Pull request
- **Name**: `pull-request-validation`

Click **Add**.

#### For Environment-Specific Deployments:

Click **Add credential** again:
- **Entity type**: Environment
- **GitHub environment name**: `dev` (or `staging`, `prod`)
- **Name**: `dev-environment`

Repeat for each environment.

### Step 3: Create Service Principal

1. Go to **Azure Active Directory** > **App registrations**
2. Select your application
3. Copy the **Application (client) ID**
4. Copy the **Directory (tenant) ID**

### Step 4: Assign Subscription Roles

1. Go to **Subscriptions**
2. Select your subscription
3. Go to **Access control (IAM)**
4. Click **Add** > **Add role assignment**
5. Select **Contributor** role
6. In **Members** tab, select **User, group, or service principal**
7. Search for `github-actions-oidc-testcontainers`
8. Select it and click **Review + assign**

Repeat for **User Access Administrator** role (required for Terraform to manage role assignments).

## Method 3: Setup via Azure CLI

### Step 1: Set Variables

```bash
export APP_NAME="github-actions-oidc-testcontainers"
export GITHUB_ORG="YOUR_GITHUB_ORG"
export GITHUB_REPO="YOUR_REPO_NAME"
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

### Step 2: Create Azure AD Application

```bash
az ad app create \
  --display-name "$APP_NAME" \
  --sign-in-audience AzureADMyOrg
```

Get the Application ID:
```bash
export APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
echo "Application ID: $APP_ID"
```

### Step 3: Create Service Principal

```bash
az ad sp create --id $APP_ID
export SP_ID=$(az ad sp list --display-name "$APP_NAME" --query "[0].id" -o tsv)
```

### Step 4: Add Federated Credentials

#### Main Branch:
```bash
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "main-branch-deploy",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

#### Pull Requests:
```bash
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "pull-request-validation",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

#### Environment (dev):
```bash
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "dev-environment",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Step 5: Assign Roles

```bash
# Contributor role
az role assignment create \
  --role "Contributor" \
  --assignee $SP_ID \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# User Access Administrator role
az role assignment create \
  --role "User Access Administrator" \
  --assignee $SP_ID \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Step 6: Verify Setup

```bash
# List federated credentials
az ad app federated-credential list --id $APP_ID

# List role assignments
az role assignment list --assignee $SP_ID --output table
```

## Configure GitHub Secrets

Add these secrets to your GitHub repository:

1. Go to your repository on GitHub
2. Navigate to **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**

### Required Secrets:

| Secret Name | Value | Where to Find |
|------------|-------|---------------|
| `AZURE_CLIENT_ID` | Application (client) ID | App registration overview or `terraform output github_actions_app_id` |
| `AZURE_TENANT_ID` | Directory (tenant) ID | App registration overview or `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID | Subscription overview or `az account show --query id -o tsv` |
| `TERRAFORM_STATE_RG` | Resource group name | `terraform-state-rg` (from backend setup) |
| `TERRAFORM_STATE_STORAGE` | Storage account name | From backend setup script output |
| `PAT_TOKEN` | GitHub Personal Access Token | [Generate token](https://github.com/settings/tokens) with `repo` scope |

### GitHub Environments (Optional but Recommended):

For environment-specific deployments:

1. Go to **Settings** > **Environments**
2. Click **New environment**
3. Create environments: `dev`, `staging`, `prod`
4. Add protection rules (e.g., required reviewers for `prod`)

## Testing the Setup

### Test 1: Validate Workflow Syntax

```bash
# Install act (optional - for local testing)
brew install act

# Validate workflow
cd .github/workflows
act --list
```

### Test 2: Manual Workflow Run

1. Go to **Actions** tab in GitHub
2. Select **Deploy Azure Infrastructure (OIDC)**
3. Click **Run workflow**
4. Select:
   - **Environment**: `dev`
   - **Azure Region**: `eastus`
5. Click **Run workflow**

### Test 3: Verify OIDC Authentication

Check the workflow logs:

```
Azure Login using OIDC
✓ Azure login successful
✓ Using federated identity credential
```

### Test 4: Check Terraform Apply

Verify resources were created:
```bash
az resource list --resource-group testcontainers-dev-rg --output table
```

### Test 5: Verify Self-Hosted Runner

Check if the runner registered:
1. Go to **Settings** > **Actions** > **Runners**
2. Look for `azure-vm-runner-dev`
3. Status should be "Idle" (green)

## Troubleshooting

### Error: "AADSTS700016: Application not found"

**Cause**: Application ID is incorrect or doesn't exist.

**Solution**:
```bash
# List all apps
az ad app list --display-name "github-actions" --output table

# Verify APP_ID
az ad app show --id $APP_ID
```

### Error: "AADSTS70021: Audience validation failed"

**Cause**: Federated credential audience is incorrect.

**Solution**:
```bash
# Check federated credentials
az ad app federated-credential list --id $APP_ID

# Verify audience is "api://AzureADTokenExchange"
```

### Error: "Subject does not match"

**Cause**: The GitHub context doesn't match the federated credential subject.

**Solutions**:

For branch mismatch:
```bash
# Make sure subject matches: repo:ORG/REPO:ref:refs/heads/BRANCH
git branch --show-current  # Should match the subject
```

For repository mismatch:
```bash
# Verify GitHub repo URL
echo "repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main"
```

### Error: "Insufficient privileges to complete the operation"

**Cause**: Service principal lacks required roles.

**Solution**:
```bash
# Re-assign roles
export SP_ID=$(az ad sp list --display-name "$APP_NAME" --query "[0].id" -o tsv)
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az role assignment create \
  --role "Contributor" \
  --assignee $SP_ID \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create \
  --role "User Access Administrator" \
  --assignee $SP_ID \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Error: "Backend initialization failed"

**Cause**: Terraform backend storage doesn't exist or access is denied.

**Solution**:
```bash
# Re-run backend setup
cd infrastructure/Azure
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="terraform-state-rg"
export STORAGE_ACCOUNT_NAME="your-storage-account-name"
./scripts/setup-terraform-backend.sh

# Verify access
az storage container list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --auth-mode login
```

### Error: "GitHub runner registration failed"

**Cause**: PAT token is invalid or lacks permissions.

**Solution**:
1. Generate new PAT: https://github.com/settings/tokens
2. Required scopes: `repo` (full control)
3. Update `PAT_TOKEN` secret in GitHub
4. Re-run workflow

### Debugging Tips

**Enable Terraform Debug Logging:**
```bash
export TF_LOG=DEBUG
terraform plan
```

**Check Azure Login:**
```bash
az account show
az ad signed-in-user show
```

**Verify Federated Credentials:**
```bash
az ad app federated-credential list --id $APP_ID --output json | jq .
```

**Test OIDC Token Locally:**

Note: This only works in GitHub Actions context, but you can view the token in workflow logs:

```yaml
- name: Debug OIDC Token
  run: |
    echo "Token endpoint: $ACTIONS_ID_TOKEN_REQUEST_URL"
    echo "Token request token: ${ACTIONS_ID_TOKEN_REQUEST_TOKEN::20}..."
```

## Migration from Service Principal Secrets

If you're currently using a service principal with client secret:

### Step 1: Note Current Configuration

```bash
# Current secrets (don't delete yet)
# - AZURE_CREDENTIALS (JSON with clientId, clientSecret, subscriptionId, tenantId)
```

### Step 2: Set Up OIDC (Follow Guide Above)

Complete either Method 1, 2, or 3 to create the OIDC application.

### Step 3: Update Workflow

Replace:
```yaml
- name: Azure Login
  uses: azure/login@v1
  with:
    creds: ${{ secrets.AZURE_CREDENTIALS }}
```

With:
```yaml
- name: Azure Login using OIDC
  uses: azure/login@v1
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

permissions:
  id-token: write   # Required for OIDC
  contents: read
```

### Step 4: Test OIDC Workflow

Run the workflow and verify it works with OIDC.

### Step 5: Clean Up Old Secrets

Once OIDC is confirmed working:

```bash
# Rotate the old client secret (invalidate it)
az ad app credential reset --id $OLD_APP_ID

# Delete the old service principal (optional)
az ad sp delete --id $OLD_SP_ID

# Remove AZURE_CREDENTIALS secret from GitHub
# Settings > Secrets and variables > Actions > Delete AZURE_CREDENTIALS
```

## Security Best Practices

1. **Use Environments**: Protect production with required reviewers
2. **Limit Permissions**: Grant minimum required Azure roles
3. **Scope Federated Credentials**: Use branch/environment-specific subjects
4. **Rotate PAT Tokens**: Set expiration on GitHub PAT tokens
5. **Monitor Access**: Enable Azure AD sign-in logs and audit logs
6. **Use Managed Identities**: For Azure resources accessing other Azure resources
7. **Enable MFA**: Require MFA for accounts with Azure access
8. **Review Regularly**: Audit federated credentials and role assignments quarterly

## Additional Resources

- [Azure OIDC Documentation](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure AD Federated Credentials](https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation)

## Summary

You now have a secure, credential-free CI/CD pipeline with:

- ✅ No long-lived secrets to manage
- ✅ Automatic token rotation
- ✅ Branch/environment-specific access control
- ✅ Full audit trail in Azure AD
- ✅ Terraform-managed infrastructure

The OIDC setup eliminates secret management overhead and improves your security posture significantly.
