# Complete Azure OIDC Setup Guide for GitHub Actions

## Table of Contents

1. [Overview](#overview)
2. [Why OIDC?](#why-oidc)
3. [How It Works](#how-it-works)
4. [Prerequisites](#prerequisites)
5. [Setup Terraform Backend](#setup-terraform-backend)
6. [Setup Methods](#setup-methods)
7. [Testing](#testing)
8. [Migration from Service Principal](#migration-from-service-principal)
9. [Security Best Practices](#security-best-practices)
10. [Troubleshooting](#troubleshooting)
11. [Quick Reference](#quick-reference)

---

## Overview

OpenID Connect (OIDC) allows GitHub Actions to authenticate with Azure using federated identity credentials without storing secrets. This guide covers everything you need to set up and use OIDC for secure Azure deployments.

### What You'll Achieve

- ✅ No client secrets stored in GitHub
- ✅ Temporary access tokens per workflow run
- ✅ Fine-grained permissions per branch/environment
- ✅ Complete audit trail via Azure AD sign-in logs
- ✅ Automatic token rotation (tokens valid ~10 minutes)
- ✅ Follows Azure security best practices

---

## Why OIDC?

### Problems with Service Principal Secrets

**Traditional Approach:**
```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    client-secret: ${{ secrets.AZURE_CLIENT_SECRET }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

**Security Risks:**
- ❌ Client secrets expire (manual rotation required)
- ❌ Secrets can be stolen if repository is compromised
- ❌ Limited audit trail
- ❌ Secrets stored in GitHub (exposure risk)
- ❌ Hard to manage across multiple repositories
- ❌ Not aligned with zero-trust principles

### Benefits of OIDC

**Modern Approach:**
```yaml
permissions:
  id-token: write   # Required for OIDC
  contents: read

steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

**Security Benefits:**
- ✅ No secrets stored in GitHub (only identifiers)
- ✅ Tokens valid for ~10 minutes only
- ✅ Automatic token rotation
- ✅ Full Azure AD audit trail
- ✅ Granular control per branch/environment
- ✅ Cannot be reused outside GitHub Actions
- ✅ Zero-trust security model
- ✅ Follows Microsoft security best practices

### Comparison

| Feature | Service Principal + Secret | OIDC |
|---------|---------------------------|------|
| **Setup Time** | 5 minutes | 10 minutes (one-time) |
| **Security Level** | ⚠️ Medium | ✅ High |
| **Token Lifetime** | Secret: 6-24 months | Token: ~10 minutes |
| **Rotation** | Manual (expiry) | Automatic |
| **Secrets in GitHub** | 4 (including secret) | 3 (no secret) |
| **Audit Trail** | Limited | Full Azure AD logs |
| **Risk if Leaked** | High (long validity) | Low (short-lived) |
| **Zero Trust** | ❌ No | ✅ Yes |
| **Azure Best Practice** | ⚠️ Acceptable | ✅ Recommended |

---

## How It Works

### Authentication Flow

```
┌─────────────────────┐
│  GitHub Actions     │
│  Workflow           │
└──────────┬──────────┘
           │ 1. Request OIDC token
           ▼
┌─────────────────────┐
│  GitHub OIDC        │
│  Provider           │
└──────────┬──────────┘
           │ 2. Issue signed JWT token
           ▼
┌─────────────────────┐
│  Azure AD           │
│  (Validate Token)   │
└──────────┬──────────┘
           │ 3. Validate token claims
           │ 4. Issue Azure access token (~10 min)
           ▼
┌─────────────────────┐
│  Azure Resources    │
│  (VM, Storage, etc.)│
└─────────────────────┘
```

### Token Claims

The OIDC token from GitHub includes claims that Azure AD validates:

| Claim | Description | Example |
|-------|-------------|---------|
| **iss** (Issuer) | GitHub OIDC endpoint | `https://token.actions.githubusercontent.com` |
| **aud** (Audience) | Target service | `api://AzureADTokenExchange` |
| **sub** (Subject) | Workflow context | `repo:org/repo:ref:refs/heads/main` |
| **jti** (JWT ID) | Unique token ID | Random UUID |

### Subject Patterns

Azure federated credentials validate the `sub` claim against configured subjects:

| Context | Subject Pattern |
|---------|----------------|
| Main branch | `repo:ORG/REPO:ref:refs/heads/main` |
| Specific branch | `repo:ORG/REPO:ref:refs/heads/BRANCH` |
| Any branch | `repo:ORG/REPO:ref:refs/heads/*` |
| Pull requests | `repo:ORG/REPO:pull_request` |
| Environment | `repo:ORG/REPO:environment:ENV` |
| Tags | `repo:ORG/REPO:ref:refs/tags/*` |

---

## Prerequisites

### Required Tools

- Azure CLI installed (`az` version 2.40+)
- Terraform >= 1.0 (for Method 1)
- GitHub repository with Actions enabled
- Azure subscription with permissions

### Required Azure Permissions

Your Azure account needs:

| Permission | Scope | Purpose |
|-----------|-------|---------|
| **Application.ReadWrite.All** | Azure AD | Create app registrations |
| **Contributor** | Subscription | Deploy resources |
| **User Access Administrator** | Subscription | Assign roles |

**Check your permissions:**
```bash
# Check current account
az account show

# List role assignments
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv)

# Check if you have required permissions
az ad app permission list-grants --id YOUR_APP_ID
```

### Prerequisites Checklist

- [ ] Azure CLI installed and logged in (`az login`)
- [ ] Terraform installed (if using Method 1)
- [ ] GitHub repository created
- [ ] Azure subscription ID obtained
- [ ] GitHub PAT token created (for runner registration)
- [ ] Required Azure permissions verified

---

## Setup Terraform Backend

Before setting up OIDC, create a secure backend for Terraform state.

### Why Backend Setup?

- ✅ Store Terraform state remotely (not in Git)
- ✅ Enable state locking (prevent concurrent changes)
- ✅ Share state across team
- ✅ Secure storage with encryption

### Step 1: Create Backend Script

**Create `scripts/setup-terraform-backend.sh`:**

```bash
#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="terraform-state-rg"
STORAGE_ACCOUNT="tfstate$(openssl rand -hex 4)"
CONTAINER_NAME="tfstate"
LOCATION="eastus"

echo "Creating Terraform backend in Azure..."

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Create storage account
az storage account create \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT \
  --location $LOCATION \
  --sku Standard_LRS \
  --encryption-services blob

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT \
  --query '[0].value' -o tsv)

# Create blob container
az storage container create \
  --name $CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT \
  --account-key $ACCOUNT_KEY

# Output values
echo ""
echo "✅ Terraform backend created successfully!"
echo ""
echo "Add these to GitHub Secrets:"
echo "  TERRAFORM_STATE_RG: $RESOURCE_GROUP"
echo "  TERRAFORM_STATE_STORAGE: $STORAGE_ACCOUNT"
echo ""
echo "Add this to your Terraform configuration:"
echo ""
cat <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP"
    storage_account_name = "$STORAGE_ACCOUNT"
    container_name       = "$CONTAINER_NAME"
    key                  = "terraform.tfstate"
  }
}
EOF
```

### Step 2: Run Backend Setup

```bash
# Make script executable
chmod +x scripts/setup-terraform-backend.sh

# Run setup
./scripts/setup-terraform-backend.sh
```

### Step 3: Update Terraform Configuration

Add backend configuration to your `main.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateXXXXXXXX"  # From script output
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
```

---

## Setup Methods

Choose one of three methods to set up OIDC:

### Method 1: Bootstrap with Terraform (Recommended)

This method creates the Azure AD app, federated credentials, and role assignments using Terraform.

#### Step 1: Create Bootstrap Directory

```bash
mkdir -p /tmp/azure-oidc-bootstrap
cd /tmp/azure-oidc-bootstrap
```

#### Step 2: Create Terraform Configuration

**Create `main.tf`:**

```hcl
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
}

provider "azuread" {}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Azure AD Application
resource "azuread_application" "github_actions" {
  display_name = "${var.project_name}-${var.environment}-github-actions"

  owners = [data.azurerm_client_config.current.object_id]
}

# Service Principal
resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

# Federated Credential - Main Branch
resource "azuread_application_federated_identity_credential" "main" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-main"
  description    = "GitHub Actions - Main Branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
}

# Federated Credential - Pull Requests
resource "azuread_application_federated_identity_credential" "pull_request" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-pr"
  description    = "GitHub Actions - Pull Requests"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:pull_request"
}

# Federated Credential - Environments (optional)
resource "azuread_application_federated_identity_credential" "environments" {
  for_each = toset(var.github_environments)

  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-${each.value}"
  description    = "GitHub Actions - ${each.value} Environment"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:environment:${each.value}"
}

# Role Assignment - Contributor
resource "azurerm_role_assignment" "contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# Role Assignment - User Access Administrator (for runner registration)
resource "azurerm_role_assignment" "user_access_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# Outputs
output "github_actions_app_id" {
  description = "Application (client) ID - add to GitHub secrets as AZURE_CLIENT_ID"
  value       = azuread_application.github_actions.client_id
}

output "tenant_id" {
  description = "Tenant ID - add to GitHub secrets as AZURE_TENANT_ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Subscription ID - add to GitHub secrets as AZURE_SUBSCRIPTION_ID"
  value       = data.azurerm_subscription.current.subscription_id
}
```

**Create `variables.tf`:**

```hcl
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "testcontainers"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "github_environments" {
  description = "GitHub environments to configure (optional)"
  type        = list(string)
  default     = ["production", "staging"]
}
```

**Create `terraform.tfvars`:**

```hcl
project_name = "testcontainers"
environment  = "dev"
github_org   = "YOUR_GITHUB_ORG_OR_USERNAME"
github_repo  = "YOUR_REPO_NAME"
github_environments = ["production", "staging"]
```

#### Step 3: Run Terraform

```bash
# Login to Azure
az login

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply configuration
terraform apply

# ⚠️ IMPORTANT: Copy these outputs to GitHub Secrets
terraform output github_actions_app_id
terraform output tenant_id
terraform output subscription_id
```

#### Step 4: Configure GitHub Secrets

Go to GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these secrets:

| Secret Name | Value | Source |
|------------|-------|--------|
| `AZURE_CLIENT_ID` | `abc123...` | `terraform output github_actions_app_id` |
| `AZURE_TENANT_ID` | `def456...` | `terraform output tenant_id` |
| `AZURE_SUBSCRIPTION_ID` | `ghi789...` | `terraform output subscription_id` |
| `TERRAFORM_STATE_RG` | `terraform-state-rg` | Backend setup script |
| `TERRAFORM_STATE_STORAGE` | `tfstateXXXX` | Backend setup script |
| `PAT_TOKEN` | `ghp_...` | Generate at GitHub settings |

#### Step 5: Clean Up Bootstrap

```bash
cd ..
rm -rf /tmp/azure-oidc-bootstrap
```

The app registration and federated credentials remain in Azure and can be managed through your main Terraform configuration.

#### Step 6: Verify Setup

```bash
# Get app registration
az ad app list --display-name "testcontainers-dev-github-actions"

# List federated credentials
APP_ID=$(az ad app list --display-name "testcontainers-dev-github-actions" --query '[0].appId' -o tsv)
az ad app federated-credential list --id $APP_ID

# Check role assignments
az role assignment list --assignee $APP_ID
```

---

### Method 2: Azure Portal Setup

#### Step 1: Create App Registration

1. Open [Azure Portal](https://portal.azure.com)
2. Go to **Azure Active Directory** → **App registrations**
3. Click **New registration**
4. Configure:
   - **Name**: `testcontainers-dev-github-actions`
   - **Supported account types**: Single tenant
   - **Redirect URI**: Leave blank
5. Click **Register**
6. **Copy the Application (client) ID** - this is `AZURE_CLIENT_ID`

#### Step 2: Create Federated Credentials

1. In the app registration, go to **Certificates & secrets**
2. Click **Federated credentials** tab
3. Click **Add credential**

**Credential 1 - Main Branch:**
- **Federated credential scenario**: GitHub Actions deploying Azure resources
- **Organization**: Your GitHub username or org
- **Repository**: Your repository name
- **Entity type**: Branch
- **GitHub branch name**: `main`
- **Name**: `github-actions-main`
- Click **Add**

**Credential 2 - Pull Requests:**
- **Federated credential scenario**: GitHub Actions deploying Azure resources
- **Organization**: Your GitHub username or org
- **Repository**: Your repository name
- **Entity type**: Pull request
- **Name**: `github-actions-pr`
- Click **Add**

**Credential 3 - Environments (optional):**
- **Federated credential scenario**: GitHub Actions deploying Azure resources
- **Organization**: Your GitHub username or org
- **Repository**: Your repository name
- **Entity type**: Environment
- **GitHub environment name**: `production` (repeat for each environment)
- **Name**: `github-actions-production`
- Click **Add**

#### Step 3: Assign Roles

1. Go to **Subscriptions**
2. Select your subscription
3. Go to **Access control (IAM)**
4. Click **Add role assignment**

**Role 1 - Contributor:**
- **Role**: Contributor
- **Assign access to**: User, group, or service principal
- **Select**: Search for your app name `testcontainers-dev-github-actions`
- Click **Save**

**Role 2 - User Access Administrator:**
- **Role**: User Access Administrator
- **Assign access to**: User, group, or service principal
- **Select**: Search for your app name
- Click **Save**

#### Step 4: Get Azure IDs

```bash
# Get tenant ID
az account show --query tenantId -o tsv

# Get subscription ID
az account show --query id -o tsv

# Verify app registration
az ad app list --display-name "testcontainers-dev-github-actions"
```

Add all three IDs to GitHub Secrets.

---

### Method 3: Azure CLI Setup

#### Step 1: Set Variables

```bash
export AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
export APP_NAME="testcontainers-dev-github-actions"
export GITHUB_ORG="YOUR_GITHUB_ORG"
export GITHUB_REPO="YOUR_REPO_NAME"
```

#### Step 2: Create App Registration

```bash
# Create app registration
az ad app create --display-name $APP_NAME

# Get app ID
export APP_ID=$(az ad app list --display-name $APP_NAME --query '[0].appId' -o tsv)
export OBJECT_ID=$(az ad app list --display-name $APP_NAME --query '[0].id' -o tsv)

echo "Application ID: $APP_ID"
echo "Object ID: $OBJECT_ID"
```

#### Step 3: Create Service Principal

```bash
# Create service principal
az ad sp create --id $APP_ID

# Get service principal object ID
export SP_OBJECT_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)

echo "Service Principal Object ID: $SP_OBJECT_ID"
```

#### Step 4: Create Federated Credentials

**Main Branch:**
```bash
az ad app federated-credential create \
  --id $OBJECT_ID \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Pull Requests:**
```bash
az ad app federated-credential create \
  --id $OBJECT_ID \
  --parameters '{
    "name": "github-actions-pr",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Environment (optional):**
```bash
az ad app federated-credential create \
  --id $OBJECT_ID \
  --parameters '{
    "name": "github-actions-production",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':environment:production",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

#### Step 5: Assign Roles

```bash
# Assign Contributor role
az role assignment create \
  --assignee $APP_ID \
  --role "Contributor" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"

# Assign User Access Administrator role (for runner registration)
az role assignment create \
  --assignee $APP_ID \
  --role "User Access Administrator" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
```

#### Step 6: Verify Setup

```bash
# List federated credentials
az ad app federated-credential list --id $OBJECT_ID

# List role assignments
az role assignment list --assignee $APP_ID

# Output values for GitHub Secrets
echo ""
echo "Add these to GitHub Secrets:"
echo "  AZURE_CLIENT_ID: $APP_ID"
echo "  AZURE_TENANT_ID: $AZURE_TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID: $AZURE_SUBSCRIPTION_ID"
```

---

## Testing

### Test 1: Validate Workflow Syntax

```yaml
# .github/workflows/test-azure-oidc.yml
name: Test Azure OIDC

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Test Azure CLI
        run: |
          az account show
          az group list
```

### Test 2: Manual Workflow Run

1. Go to GitHub repository → **Actions**
2. Select **Test Azure OIDC**
3. Click **Run workflow**
4. Click **Run workflow**

**Expected Results:**
- ✅ Login step succeeds
- ✅ Azure account information displayed
- ✅ Resource groups listed

### Test 3: Verify OIDC Authentication

```bash
# Check Azure AD sign-in logs
az monitor activity-log list \
  --max-events 10 \
  --query "[?contains(caller, '$APP_ID')]"

# Or in Azure Portal:
# Azure AD → Sign-in logs → Filter by application
```

### Test 4: Test Terraform Deployment

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Terraform Init
  run: terraform init
  env:
    ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
    ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
    ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    ARM_USE_OIDC: true

- name: Terraform Apply
  run: terraform apply -auto-approve
```

### Test 5: Verify Runner Registration

```bash
# Check if runner can be registered
az vm list --query "[].{name:name, location:location}" -o table
```

---

## Migration from Service Principal

If you're currently using `AZURE_CLIENT_SECRET`, follow these steps to migrate safely.

### Step 1: Understand Current Setup

**Old workflow (with secret):**
```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    client-secret: ${{ secrets.AZURE_CLIENT_SECRET }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### Step 2: Create Federated Credentials

Follow **Method 1**, **Method 2**, or **Method 3** to create federated credentials for your existing app registration.

**Important:** You can add federated credentials to your existing service principal without breaking current workflows.

### Step 3: Update Workflow

**New workflow (OIDC):**
```yaml
permissions:
  id-token: write   # Add this
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}          # Keep same
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}          # Keep same
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }} # Keep same
          # REMOVE: client-secret line
```

### Step 4: Test OIDC Workflow

1. Run the new OIDC workflow
2. Verify all steps complete successfully
3. Check resources are deployed correctly
4. Confirm no authentication errors

### Step 5: Remove Client Secret

Once OIDC is confirmed working:

1. Go to GitHub repository → **Settings** → **Secrets and variables** → **Actions**
2. Delete: `AZURE_CLIENT_SECRET`
3. Keep: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`

### Step 6: Clean Up Azure AD (Optional)

```bash
# List existing secrets (client credentials)
az ad app credential list --id $APP_ID

# Delete old client secret
az ad app credential delete --id $APP_ID --key-id <KEY_ID>
```

### Migration Comparison

| Aspect | Before (Secret) | After (OIDC) |
|--------|----------------|--------------|
| **GitHub Secrets** | 4 (including secret) | 3 (no secret) |
| **Security** | Medium | High |
| **Maintenance** | Manual rotation | No maintenance |
| **Audit Trail** | Limited | Full Azure AD logs |
| **Token Lifetime** | Secret: months | Token: ~10 min |

---

## Security Best Practices

### 1. Use Environments for Production

Create GitHub environments with protection rules:

```yaml
jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment: production  # Requires approval
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### 2. Limit Permissions with Custom Roles

Instead of Contributor, create custom roles:

**Example custom role:**
```json
{
  "Name": "GitHub Actions Deployer",
  "IsCustom": true,
  "Description": "Limited permissions for GitHub Actions",
  "Actions": [
    "Microsoft.Compute/virtualMachines/*",
    "Microsoft.Network/virtualNetworks/*",
    "Microsoft.Network/networkInterfaces/*",
    "Microsoft.Network/publicIPAddresses/*",
    "Microsoft.Network/networkSecurityGroups/*",
    "Microsoft.Storage/storageAccounts/read",
    "Microsoft.Resources/deployments/*",
    "Microsoft.Resources/subscriptions/resourceGroups/*"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/YOUR_SUBSCRIPTION_ID"]
}
```

Apply custom role:
```bash
# Create custom role
az role definition create --role-definition custom-role.json

# Assign custom role
az role assignment create \
  --assignee $APP_ID \
  --role "GitHub Actions Deployer" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"

# Remove Contributor role
az role assignment delete \
  --assignee $APP_ID \
  --role "Contributor" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
```

### 3. Scope Federated Credentials Tightly

**Bad (too permissive):**
```
subject: repo:ORG/REPO:*
```

**Good (specific contexts):**
```
subject: repo:ORG/REPO:ref:refs/heads/main
subject: repo:ORG/REPO:environment:production
subject: repo:ORG/REPO:ref:refs/tags/v*
```

### 4. Use Separate Apps per Environment

```bash
# Development app
testcontainers-dev-github-actions

# Staging app
testcontainers-staging-github-actions

# Production app (most restricted)
testcontainers-prod-github-actions
```

### 5. Enable Conditional Access Policies

In Azure AD, create conditional access policies:
- Require MFA for production deployments
- Restrict access by IP range
- Require compliant devices

### 6. Rotate PAT Tokens Regularly

```bash
# GitHub PAT tokens should be rotated every 90 days
# Set expiration when creating:
# Settings → Developer settings → Personal access tokens → Generate new token
# Expiration: 90 days
```

### 7. Monitor Sign-In Activity

```bash
# Check recent sign-ins
az monitor activity-log list \
  --max-events 50 \
  --query "[?contains(caller, '$APP_ID')]" \
  --output table

# Set up alerts for suspicious activity
az monitor activity-log alert create \
  --name "OIDC-Failed-Logins" \
  --description "Alert on failed OIDC authentications" \
  --condition category=Administrative and operationName=Microsoft.Authorization/roleAssignments/write
```

### 8. Use Azure Policy for Governance

```bash
# Example: Require tags on all resources
az policy assignment create \
  --name "require-tags" \
  --policy "require-tag-and-its-value" \
  --params '{"tagName":{"value":"Environment"},"tagValue":{"value":"Production"}}'
```

### 9. Regular Security Audits

```bash
# List all app registrations
az ad app list --query "[].{name:displayName, appId:appId}" -o table

# Check federated credentials
az ad app federated-credential list --id $APP_ID

# Review role assignments
az role assignment list --all --query "[?principalName=='$APP_ID']" -o table

# Check for unused credentials
az ad app credential list --id $APP_ID
```

---

## Troubleshooting

### Error: "AADSTS700016: Application with identifier was not found"

**Cause:** App registration doesn't exist or app ID is incorrect.

**Solutions:**

1. **Verify app exists:**
```bash
az ad app list --display-name "testcontainers-dev-github-actions"
```

2. **Check AZURE_CLIENT_ID secret:**
- Go to Settings → Secrets
- Verify `AZURE_CLIENT_ID` matches app ID from Azure Portal

3. **Re-create app if missing:**
```bash
az ad app create --display-name "testcontainers-dev-github-actions"
```

### Error: "AADSTS70021: Audience validation failed"

**Cause:** Federated credential audience is incorrect.

**Solutions:**

1. **Check federated credential:**
```bash
az ad app federated-credential list --id $APP_ID
```

2. **Verify audience is correct:**
```json
{
  "audiences": ["api://AzureADTokenExchange"]
}
```

3. **Re-create credential with correct audience:**
```bash
az ad app federated-credential delete --id $APP_ID --federated-credential-id CRED_ID
az ad app federated-credential create --id $APP_ID --parameters '{"name":"github-actions-main","issuer":"https://token.actions.githubusercontent.com","subject":"repo:ORG/REPO:ref:refs/heads/main","audiences":["api://AzureADTokenExchange"]}'
```

### Error: "Subject does not match any configured federated credentials"

**Cause:** The workflow context doesn't match any configured subject pattern.

**Solutions:**

1. **Check configured subjects:**
```bash
az ad app federated-credential list --id $APP_ID --query "[].{name:name, subject:subject}"
```

2. **Common mismatches:**
   - Branch name incorrect: `main` vs `master`
   - Organization/repo name case mismatch
   - Extra spaces or characters

3. **Test with wildcard (temporary):**
```bash
# Add credential with wildcard for testing
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-test",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:ORG/REPO:*",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

4. **Check workflow context:**
Add debug step to workflow:
```yaml
- name: Debug context
  run: |
    echo "Ref: ${{ github.ref }}"
    echo "Repository: ${{ github.repository }}"
    echo "Event: ${{ github.event_name }}"
```

### Error: "Insufficient privileges to complete the operation"

**Cause:** Service principal lacks required Azure permissions.

**Solutions:**

1. **Check role assignments:**
```bash
az role assignment list --assignee $APP_ID --output table
```

2. **Verify required roles:**
   - Contributor (for resource deployment)
   - User Access Administrator (for runner registration)

3. **Re-assign roles:**
```bash
az role assignment create \
  --assignee $APP_ID \
  --role "Contributor" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"

az role assignment create \
  --assignee $APP_ID \
  --role "User Access Administrator" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
```

### Error: "Backend initialization failed"

**Cause:** Terraform backend not configured or inaccessible.

**Solutions:**

1. **Re-run backend setup:**
```bash
./scripts/setup-terraform-backend.sh
```

2. **Verify storage account exists:**
```bash
az storage account list --resource-group terraform-state-rg
```

3. **Check GitHub secrets:**
- `TERRAFORM_STATE_RG`
- `TERRAFORM_STATE_STORAGE`

4. **Verify backend configuration in Terraform:**
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateXXXX"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
```

### Error: "GitHub runner registration failed"

**Cause:** PAT token invalid or lacks required permissions.

**Solutions:**

1. **Verify PAT token permissions:**
- `repo` (full control)
- `workflow`
- `admin:org` (if using organization runners)

2. **Generate new PAT:**
- Go to GitHub → Settings → Developer settings → Personal access tokens
- Generate new token (classic)
- Select required scopes
- Copy token to `PAT_TOKEN` secret

3. **Check token expiration:**
```bash
# PAT tokens expire - check expiration date in GitHub settings
```

### Error: "TF_VAR environment variables not set"

**Cause:** Terraform variables not passed from GitHub secrets.

**Solutions:**

1. **Check workflow configuration:**
```yaml
- name: Terraform Apply
  run: terraform apply -auto-approve
  env:
    ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
    ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
    ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    ARM_USE_OIDC: true
    TF_VAR_project_name: testcontainers
    TF_VAR_environment: ${{ inputs.environment }}
```

2. **Verify all required secrets exist in GitHub**

### Debugging Tips

**Enable debug logging:**
```yaml
env:
  ACTIONS_RUNNER_DEBUG: true
  ACTIONS_STEP_DEBUG: true
```

**Check Azure AD sign-in logs:**
```bash
az monitor activity-log list \
  --max-events 20 \
  --query "[?contains(resourceId, '$APP_ID')]"
```

**Test authentication manually:**
```bash
# Get OIDC token (only works in GitHub Actions)
curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange"
```

**Verify federated credential subject format:**
```bash
# Main branch
repo:ORG/REPO:ref:refs/heads/main

# Pull request
repo:ORG/REPO:pull_request

# Environment
repo:ORG/REPO:environment:production
```

---

## Quick Reference

### Required GitHub Secrets

| Secret Name | Description | How to Get |
|------------|-------------|------------|
| `AZURE_CLIENT_ID` | Application (client) ID | `terraform output github_actions_app_id` or Azure Portal |
| `AZURE_TENANT_ID` | Azure AD tenant ID | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | `az account show --query id -o tsv` |
| `TERRAFORM_STATE_RG` | Resource group for Terraform state | `terraform-state-rg` (from backend setup) |
| `TERRAFORM_STATE_STORAGE` | Storage account for Terraform state | From backend setup script |
| `PAT_TOKEN` | GitHub Personal Access Token | GitHub Settings → Developer settings |

### Workflow Configuration

**Minimal OIDC workflow:**
```yaml
name: Deploy to Azure

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Deploy resources
        run: |
          az group create --name my-rg --location eastus
          az vm list
```

### Common Commands

**List app registrations:**
```bash
az ad app list --display-name "testcontainers-dev-github-actions"
```

**Get app ID:**
```bash
APP_ID=$(az ad app list --display-name "testcontainers-dev-github-actions" --query '[0].appId' -o tsv)
```

**List federated credentials:**
```bash
az ad app federated-credential list --id $APP_ID
```

**Check role assignments:**
```bash
az role assignment list --assignee $APP_ID --output table
```

**View Azure AD sign-in logs:**
```bash
az monitor activity-log list \
  --max-events 10 \
  --query "[?contains(caller, '$APP_ID')]"
```

**Test Azure login:**
```bash
az account show
az group list
```

### Federated Credential Subject Patterns

| Context | Subject Pattern |
|---------|----------------|
| **Main branch** | `repo:ORG/REPO:ref:refs/heads/main` |
| **Specific branch** | `repo:ORG/REPO:ref:refs/heads/BRANCH_NAME` |
| **All branches** | `repo:ORG/REPO:ref:refs/heads/*` |
| **Pull requests** | `repo:ORG/REPO:pull_request` |
| **Environment** | `repo:ORG/REPO:environment:ENV_NAME` |
| **Tags** | `repo:ORG/REPO:ref:refs/tags/*` |
| **All (wildcard)** | `repo:ORG/REPO:*` |

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                    GitHub Actions Workflow                    │
│                                                                │
│  permissions:                                                  │
│    id-token: write  ← Enable OIDC                             │
│                                                                │
│  steps:                                                        │
│    - azure/login@v2 ← No client-secret needed                 │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             │ 1. Request OIDC token
                             ▼
┌──────────────────────────────────────────────────────────────┐
│              GitHub OIDC Token Provider                       │
│         https://token.actions.githubusercontent.com           │
│                                                                │
│  Issues JWT with claims:                                      │
│    iss: https://token.actions.githubusercontent.com           │
│    aud: api://AzureADTokenExchange                           │
│    sub: repo:org/repo:ref:refs/heads/main                    │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             │ 2. Send JWT token
                             ▼
┌──────────────────────────────────────────────────────────────┐
│                      Azure Active Directory                   │
│                                                                │
│  1. Validate JWT signature                                    │
│  2. Check federated credential:                               │
│     - Issuer matches                                          │
│     - Audience matches                                        │
│     - Subject matches configured pattern                      │
│  3. Issue Azure access token (~10 min validity)               │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             │ 3. Azure access token
                             ▼
┌──────────────────────────────────────────────────────────────┐
│                     Azure Resources                           │
│                                                                │
│  ✓ Virtual Machines        ✓ Storage Accounts                │
│  ✓ Virtual Networks        ✓ Resource Groups                 │
│  ✓ All Azure Services (based on assigned roles)              │
└──────────────────────────────────────────────────────────────┘
```

### Security Highlights

- ✅ **Tokens valid for ~10 minutes only**
- ✅ **No secrets stored in GitHub** (only app/tenant/subscription IDs)
- ✅ **Automatic token rotation** (new token per workflow run)
- ✅ **Complete audit trail** (Azure AD sign-in logs)
- ✅ **Granular control** (per branch/environment)
- ✅ **Cannot be reused** (tokens bound to GitHub Actions context)

### Additional Resources

- [GitHub OIDC for Azure](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure Workload Identity Federation](https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation)
- [Azure AD Federated Credentials](https://learn.microsoft.com/en-us/graph/api/resources/federatedidentitycredentials-overview)
- [Azure Login Action](https://github.com/Azure/login)
- [Azure CLI Reference](https://learn.microsoft.com/en-us/cli/azure/)

---

## Summary

### What You've Achieved

✅ **Zero Secrets**: No client secrets stored in GitHub
✅ **Short-Lived Tokens**: Azure tokens valid ~10 minutes only
✅ **Automatic Rotation**: New token per workflow run
✅ **Granular Control**: Different credentials per branch/environment
✅ **Complete Audit Trail**: Full Azure AD sign-in logs
✅ **Zero Trust Model**: Follows Microsoft security best practices
✅ **Low Maintenance**: No manual secret rotation required

You can now run GitHub Actions workflows that deploy to Azure securely using OIDC federated identity!
