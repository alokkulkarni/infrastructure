# Azure OIDC Deployment - Pre-Deployment Checklist

## Issue Resolved
✅ **Fixed subscription ID newline issue** - The setup script and workflow now properly sanitize the subscription ID by removing any whitespace or newline characters.

## Before Running the Workflow

### 1. Verify GitHub Secrets (CRITICAL)

Go to your repository → Settings → Secrets and variables → Actions

Check that these secrets exist and have **NO trailing spaces or newlines**:

| Secret Name | Description | Example Format | Check |
|-------------|-------------|----------------|-------|
| `AZURE_CLIENT_ID` | Service Principal Application (client) ID | `12345678-1234-1234-1234-123456789abc` | ☐ |
| `AZURE_TENANT_ID` | Microsoft Entra Tenant ID | `87654321-4321-4321-4321-cba987654321` | ☐ |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | `abcdef12-3456-7890-abcd-ef1234567890` | ☐ |
| `PAT_TOKEN` | GitHub Personal Access Token (for runner) | `ghp_...` | ☐ |

**How to verify secrets don't have trailing characters**:
1. Click "Update" on each secret
2. Copy the value to a text editor
3. Check there are NO spaces, tabs, or newlines at the end
4. If found, remove them and save

### 2. Verify Azure App Registration

```bash
# Get your subscription ID
az account show --query id -o tsv

# Verify the service principal exists
az ad sp show --id <YOUR_AZURE_CLIENT_ID>

# Check federated credentials are configured
az ad app federated-credential list --id <YOUR_AZURE_CLIENT_ID>
```

Expected output should show:
- Subject: `repo:alokkulkarni/beneficiaries:environment:dev`
- Issuer: `https://token.actions.githubusercontent.com`

### 3. Verify RBAC Role Assignments

```bash
# Check role assignments for your service principal
az role assignment list \
  --assignee <YOUR_AZURE_CLIENT_ID> \
  --subscription <YOUR_AZURE_SUBSCRIPTION_ID> \
  --output table
```

Expected roles at subscription level:
- ✅ Contributor
- ✅ User Access Administrator (if creating role assignments)

### 4. Verify GitHub Environment

Go to repository → Settings → Environments

Ensure `dev` environment exists with:
- ☐ Environment protection rules (optional but recommended)
- ☐ Required reviewers (optional)

### 5. Test Azure CLI Connection Locally (Optional)

```bash
# Login with the service principal
az login --service-principal \
  -u <YOUR_AZURE_CLIENT_ID> \
  -p <YOUR_CLIENT_SECRET> \
  --tenant <YOUR_AZURE_TENANT_ID>

# Test subscription access
az account show
az group list --query "[].name" -o tsv

# If successful, you're good to go!
```

## Running the Workflow

### Workflow Inputs Required

When you trigger the workflow manually, provide:

| Input | Value | Notes |
|-------|-------|-------|
| **environment** | `dev` | Choose: dev, staging, or prod |
| **environment_tag** | `SIT-alok-teamA-20251124-1530` | Format: `SIT-USERID-TEAMID-YYYYMMDD-HHMM` |
| **location** | `uksouth` | Azure region (e.g., eastus, westeurope) |

**Environment Tag Guidelines**:
- Must be unique for each deployment
- Used for resource isolation and state file path
- Example: `SIT-john-teamA-20251124-1430`
- Format: `<ENV>-<USER>-<TEAM>-<DATE>-<TIME>`

## What to Watch For During Deployment

### Stage 1: Setup Backend (Expected: ~2 minutes)

**Success Indicators**:
```
✓ Authenticated
✓ Subscription context set
✓ Resource group already exists, reusing existing resource group
✓ Storage account already exists, reusing existing storage account
✓ RBAC permissions configured
Extracted values:
  Resource Group: testcontainers-tfstate-rg
  Storage Account: testcontainerstfstate<8-chars>
```

**Red Flags**:
```
ERROR: (SubscriptionNotFound) Subscription *** was not found
ERROR: Failed to extract backend configuration
Extracted values:
  Resource Group: 
  Storage Account:
```

### Stage 2: Terraform Plan (Expected: ~3-5 minutes)

**Success Indicators**:
```
Terraform has been successfully initialized!
Terraform used the selected providers to generate the following execution plan
Plan: X to add, 0 to change, 0 to destroy
```

**Red Flags**:
```
Error: Failed to get existing workspaces: containers.Client#ListBlobs
Error: Either an Access Key / SAS Token ... must be specified
Error: accountName cannot be an empty string
```

### Stage 3: Terraform Apply (Expected: ~10-15 minutes)

**Success Indicators**:
```
Apply complete! Resources: X added, 0 changed, 0 destroyed
Outputs:
  resource_group_name = "testcontainers-<env-tag>-rg"
  ...
```

**Red Flags**:
```
Error: creating/updating Resource Group
Error: A resource with the ID "..." already exists
```

## Common Issues and Fixes

### Issue 1: "Subscription was not found"
**Cause**: Trailing newline in `AZURE_SUBSCRIPTION_ID` secret
**Fix**: ✅ Already handled by workflow - it now sanitizes the subscription ID

### Issue 2: "accountName cannot be an empty string"
**Cause**: Failed to extract backend configuration from setup script output
**Fix**: ✅ Already handled by workflow - proper ANSI code stripping and validation

### Issue 3: "Either an Access Key / SAS Token must be specified"
**Cause**: Missing `ARM_USE_AZUREAD` environment variable
**Fix**: ✅ Already configured in all terraform init steps

### Issue 4: RBAC role assignment failures
**Cause**: Service principal doesn't have permission to create role assignments
**Fix**: Assign "User Access Administrator" role at subscription level

## Post-Deployment Verification

### Check Azure Resources Created

```bash
# Set your environment tag
ENV_TAG="SIT-alok-teamA-20251124-1530"

# List resources in the resource group
az resource list \
  --resource-group "testcontainers-${ENV_TAG}-rg" \
  --output table

# Check state file exists
az storage blob list \
  --account-name testcontainerstfstate<8-chars> \
  --container-name tfstate \
  --prefix "azure/dev/${ENV_TAG}/" \
  --auth-mode login \
  --output table
```

### Verify GitHub Runner Registration

```bash
# Check if the self-hosted runner appears in GitHub
# Go to: Repository → Settings → Actions → Runners

# You should see: azure-vm-runner-<ENV_TAG>
# Status: Idle (green)
```

### Test Runner Connectivity

Create a simple test workflow to verify the runner works:

```yaml
name: Test Runner
on: workflow_dispatch

jobs:
  test:
    runs-on: [self-hosted, azure, linux, docker, dev, <YOUR_ENV_TAG>]
    steps:
      - run: echo "Runner is working!"
      - run: docker --version
```

## Cleanup After Testing

### Destroy Resources

```bash
# Set your environment tag
ENV_TAG="SIT-alok-teamA-20251124-1530"

# Option 1: Through GitHub Actions (recommended)
# The workflow has a rollback job that runs on failure

# Option 2: Manually with Terraform
cd infrastructure/Azure/terraform

# Create backend.tf with your values
cat > backend.tf <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "testcontainers-tfstate-rg"
    storage_account_name = "testcontainerstfstate<8-chars>"
    container_name       = "tfstate"
    key                  = "azure/dev/${ENV_TAG}/terraform.tfstate"
    use_oidc             = true
  }
}
EOF

# Initialize and destroy
terraform init
terraform destroy -auto-approve
```

### Clean Up State File

```bash
# Delete the state file blob
az storage blob delete \
  --account-name testcontainerstfstate<8-chars> \
  --container-name tfstate \
  --name "azure/dev/${ENV_TAG}/terraform.tfstate" \
  --auth-mode login
```

### Purge Soft-Deleted Key Vault

```bash
# List soft-deleted key vaults
az keyvault list-deleted --query "[].name" -o tsv

# Purge specific key vault
az keyvault purge --name <keyvault-name>
```

## Support Resources

### Documentation Files
- `OIDC_BACKEND_FIX.md` - Comprehensive OIDC authentication troubleshooting
- `FINAL_SOLUTION_SUMMARY.md` - Complete solution overview
- `QUICK_REFERENCE.md` - Quick troubleshooting reference
- `EMPTY_STORAGE_ACCOUNT_FIX.md` - Details on the output extraction fix
- `verify-oidc-config.sh` - Automated configuration verification script

### Run Verification Script

```bash
cd infrastructure/Azure
./scripts/verify-oidc-config.sh
```

This will check:
1. Environment variables
2. Azure CLI authentication
3. App registration
4. Federated credentials
5. RBAC roles
6. Backend resources
7. GitHub environment

## Final Checklist

Before clicking "Run workflow":

- ☐ All GitHub secrets verified (no trailing spaces/newlines)
- ☐ Service principal has required RBAC roles
- ☐ Federated credentials configured correctly
- ☐ GitHub `dev` environment exists
- ☐ Unique environment tag prepared
- ☐ Azure region selected
- ☐ `PAT_TOKEN` secret has runner registration permissions

## Expected Timeline

| Stage | Duration | Total Elapsed |
|-------|----------|---------------|
| Setup Backend | 1-2 min | 2 min |
| Terraform Plan | 3-5 min | 7 min |
| Terraform Apply | 10-15 min | 22 min |
| **Total** | **~15-22 min** | |

---

## You're Ready! 🚀

If all checklist items are completed, you should have a **successful deployment**.

The main fix applied:
- ✅ Subscription ID is now sanitized to remove any whitespace/newlines
- ✅ All environment variables are consistent (`ARM_USE_AZUREAD`)
- ✅ Backend configuration extraction properly handles ANSI codes
- ✅ Validation prevents empty values from being used

**Good luck with your deployment!** 🎉
