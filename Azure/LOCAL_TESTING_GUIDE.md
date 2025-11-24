# Local Testing Guide for Azure Backend Setup

## Overview

This guide explains how to test the Terraform backend setup locally **before** running GitHub Actions. This helps catch configuration issues early and avoids the trial-and-error cycle in CI/CD.

## Why Local Testing?

**Benefits:**
- **Fast feedback**: Test in seconds instead of waiting for GitHub Actions
- **Better debugging**: Full access to error messages and Azure CLI output
- **Cost savings**: No CI/CD minutes wasted on failed attempts
- **Confidence**: Verify scripts work before committing to GitHub

## Prerequisites

### 1. Install Azure CLI

```bash
# macOS
brew install azure-cli

# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Windows
# Download from: https://aka.ms/installazurecliwindows
```

### 2. Authenticate with Azure

```bash
az login

# If you have multiple subscriptions, set the correct one
az account set --subscription "YOUR_SUBSCRIPTION_ID_OR_NAME"

# Verify authentication
az account show
```

### 3. Verify Permissions

You need these roles on the subscription:
- **Contributor** (to create resources)
- **User Access Administrator** (to assign roles)
- **Storage Account Contributor** (to manage storage)
- **Storage Blob Data Contributor** (to manage blobs)

Check your roles:
```bash
az role assignment list \
  --assignee $(az account show --query user.name -o tsv) \
  --output table
```

## Quick Start

### 1. Navigate to Scripts Directory

```bash
cd infrastructure/Azure/scripts
```

### 2. Run Local Test

**Basic usage** (auto-generates environment tag):
```bash
./test-backend-setup-locally.sh
```

**With custom environment tag**:
```bash
./test-backend-setup-locally.sh SIT-myname-teamA-20251124-1500
```

**With custom location**:
```bash
./test-backend-setup-locally.sh SIT-myname-teamA-20251124-1500 eastus
```

**Generate timestamp-based tag**:
```bash
./test-backend-setup-locally.sh SIT-$(whoami)-test-$(date +%Y%m%d-%H%M) eastus
```

### 3. Review Output

The script will:
1. ✅ Check Azure CLI installation
2. ✅ Verify authentication
3. ✅ Display current subscription
4. ✅ Show resources to be created
5. ❓ Ask for confirmation
6. 🚀 Run setup-terraform-backend.sh
7. ✅ Display backend configuration if successful

**Example successful output:**
```
═══════════════════════════════════════════════════════
  Local Testing - Terraform Backend Setup
═══════════════════════════════════════════════════════

✓ Authenticated
{
  "name": "My Subscription",
  "id": "2745ace7-...",
  "tenantId": "abc-123-..."
}

Configuration:
  Environment Tag: SIT-alok-test-20251124-1645
  Location: eastus

Subscription ID: 2745ace7-...

This will create/update the following resources:
  - Resource Group: testcontainers-tfstate-rg
  - Storage Account: testcontainerstfstate2745ace7
  - Container: sit-alok-test-20251124-1645

Continue? (y/n) y

═══════════════════════════════════════════════════════
  Running setup-terraform-backend.sh
═══════════════════════════════════════════════════════

Setting up Terraform Backend for Azure...
✓ Resource group exists
✓ Storage account exists
✓ Blob versioning enabled
✓ RBAC permissions configured
✓ Container created
✓ Terraform backend setup complete!

═══════════════════════════════════════════════════════
✓ Local test completed successfully!

Backend Configuration:
  backend_resource_group=testcontainers-tfstate-rg
  backend_storage_account=testcontainerstfstate2745ace7
  backend_container=sit-alok-test-20251124-1645
  backend_key=terraform.tfstate

You can now use these values in your Terraform backend config:

terraform {
  backend "azurerm" {
    resource_group_name  = "testcontainers-tfstate-rg"
    storage_account_name = "testcontainerstfstate2745ace7"
    container_name       = "sit-alok-test-20251124-1645"
    key                  = "terraform.tfstate"
  }
}

Ready to run GitHub Actions workflow!
═══════════════════════════════════════════════════════
```

## Troubleshooting

### Error: "Not authenticated with Azure CLI"

**Problem:** Azure CLI session expired or not logged in.

**Solution:**
```bash
az login
az account show
```

### Error: "Insufficient permissions"

**Problem:** Your account lacks required roles.

**Solution:** Ask your Azure admin to grant these roles:
```bash
# Example: Admin grants roles to user
az role assignment create \
  --assignee user@example.com \
  --role "Contributor" \
  --scope /subscriptions/YOUR_SUBSCRIPTION_ID

az role assignment create \
  --assignee user@example.com \
  --role "Storage Account Contributor" \
  --scope /subscriptions/YOUR_SUBSCRIPTION_ID

az role assignment create \
  --assignee user@example.com \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/YOUR_SUBSCRIPTION_ID
```

### Error: "SubscriptionNotFound"

**Problem:** Subscription context not set correctly.

**Solution:**
```bash
# List available subscriptions
az account list --output table

# Set correct subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Verify
az account show --query id -o tsv
```

### Error: "Storage account name already taken"

**Problem:** Storage account name is globally unique across all of Azure.

**Solution:** 
- The script uses subscription ID to ensure uniqueness: `testcontainerstfstate{sub-first-8}`
- If this fails, someone else has that exact storage account name
- Modify `PROJECT_NAME` in the script:
  ```bash
  export PROJECT_NAME="myproject"  # Changes to: myprojecttfstate2745ace7
  ./test-backend-setup-locally.sh
  ```

### Error: "Location not supported"

**Problem:** Storage accounts not available in specified region.

**Solution:**
```bash
# List available locations for storage accounts
az provider show --namespace Microsoft.Storage \
  --query "resourceTypes[?resourceType=='storageAccounts'].locations" -o table

# Use supported location
./test-backend-setup-locally.sh SIT-test-tag eastus
```

## Comparing Local vs GitHub Actions

| Aspect | Local Testing | GitHub Actions |
|--------|--------------|----------------|
| **Authentication** | `az login` (user credentials) | OIDC (service principal) |
| **Speed** | ⚡ Fast (30-60 seconds) | 🐢 Slower (2-5 minutes) |
| **Debugging** | ✅ Full terminal access | ⚠️ Limited (logs only) |
| **Cost** | 🆓 Free | 💰 Uses CI/CD minutes |
| **Environment** | Your machine | GitHub-hosted runner |
| **RBAC** | Optional (uses user perms) | Required (service principal) |

## Best Practices

### 1. Test Before Pushing

Always run local test before pushing to GitHub:
```bash
# Make changes to scripts
vim setup-terraform-backend.sh

# Test locally
./test-backend-setup-locally.sh SIT-test-$(date +%Y%m%d-%H%M)

# If successful, commit and push
git add .
git commit -m "Update backend setup script"
git push
```

### 2. Use Descriptive Environment Tags

Good examples:
```bash
SIT-alok-teamA-20251124-1500          # Team-based
SIT-feature-auth-20251124             # Feature-based
SIT-bugfix-storage-20251124           # Bug fix testing
DEV-$(whoami)-$(date +%Y%m%d)         # Personal dev environment
```

Bad examples:
```bash
test                    # Too generic
SIT                     # Not specific enough
my-environment          # No timestamp
```

### 3. Clean Up Test Resources

Delete test containers after validation:
```bash
# List containers
az storage container list \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login \
  --output table

# Delete specific container
az storage container delete \
  --name sit-test-20251124-1500 \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login
```

### 4. Verify OIDC Separately

If you're testing OIDC setup, you need service principal credentials:
```bash
# Get service principal details from GitHub
# Settings → Secrets → AZURE_CLIENT_ID

# Set in environment
export ARM_CLIENT_ID="your-client-id"

# Run test with RBAC configuration
./test-backend-setup-locally.sh SIT-oidc-test-$(date +%Y%m%d-%H%M)
```

## Common Workflows

### Workflow 1: First-Time Setup

```bash
# 1. Clone repository
git clone https://github.com/your-org/TestContainers.git
cd TestContainers/infrastructure/Azure/scripts

# 2. Authenticate
az login
az account set --subscription "Your Subscription"

# 3. Test backend setup
./test-backend-setup-locally.sh SIT-$(whoami)-init-$(date +%Y%m%d)

# 4. Review output and verify resources created
az storage container list \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login
```

### Workflow 2: Testing Script Changes

```bash
# 1. Make changes
vim setup-terraform-backend.sh

# 2. Test locally with new environment tag
./test-backend-setup-locally.sh SIT-test-change-$(date +%Y%m%d-%H%M)

# 3. If successful, clean up test container
az storage container delete \
  --name sit-test-change-20251124-1500 \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login

# 4. Commit and push
git add setup-terraform-backend.sh
git commit -m "Fix: Add --subscription to all az commands"
git push
```

### Workflow 3: Debugging GitHub Actions Failures

```bash
# 1. GitHub Action failed - check logs for error
# Example: "SubscriptionNotFound" error

# 2. Reproduce locally with same environment tag
./test-backend-setup-locally.sh SIT-alok-teama-20251124-1500

# 3. If local test passes, issue is OIDC-specific
# Check service principal permissions

# 4. If local test fails, fix the script
vim setup-terraform-backend.sh

# 5. Retest
./test-backend-setup-locally.sh SIT-fix-test-$(date +%Y%m%d-%H%M)

# 6. Push fix
git add setup-terraform-backend.sh
git commit -m "Fix: Resolve SubscriptionNotFound error"
git push
```

## Script Details

### What the Test Script Does

1. **Validates Environment**
   - Checks Azure CLI installation
   - Verifies authentication
   - Shows current subscription

2. **Gathers Configuration**
   - Environment tag (from argument or auto-generated)
   - Location (default: eastus)
   - Subscription ID (from current context)

3. **Shows Preview**
   - Lists resources to be created/updated
   - Asks for confirmation

4. **Runs Setup Script**
   - Exports required environment variables
   - Executes `setup-terraform-backend.sh`
   - Captures exit code

5. **Reports Results**
   - Shows backend configuration on success
   - Provides troubleshooting tips on failure

### Environment Variables Set

The test script sets these variables before calling setup-terraform-backend.sh:

```bash
AZURE_SUBSCRIPTION_ID    # From az account show
AZURE_LOCATION           # From argument (default: eastus)
ENVIRONMENT_TAG          # From argument or auto-generated
PROJECT_NAME            # Default: testcontainers
ARM_CLIENT_ID           # Optional (for RBAC testing)
```

## Next Steps

After successful local testing:

1. ✅ **Commit your changes**
   ```bash
   git add .
   git commit -m "Update backend setup with improvements"
   git push
   ```

2. ✅ **Run GitHub Actions workflow**
   - Go to Actions tab
   - Select "Deploy Azure Infrastructure"
   - Click "Run workflow"
   - Fill in parameters (use same environment tag if testing)

3. ✅ **Monitor workflow execution**
   - Watch logs for setup-backend job
   - Verify backend configuration is identical to local test
   - Confirm terraform-plan succeeds

4. ✅ **Deploy infrastructure**
   - Approve terraform-apply if plan looks good
   - Monitor deployment

## Additional Resources

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [Azure Storage Account Naming Rules](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#naming-storage-accounts)
- [Terraform azurerm Backend](https://www.terraform.io/language/settings/backends/azurerm)
- [ENVIRONMENT_TAG_QUICK_START.md](./ENVIRONMENT_TAG_QUICK_START.md) - GitHub Actions guide
- [ENVIRONMENT_TAG_ISOLATION_ARCHITECTURE.md](./ENVIRONMENT_TAG_ISOLATION_ARCHITECTURE.md) - Architecture details

## Support

If you encounter issues:

1. Check troubleshooting section above
2. Review error messages carefully
3. Verify Azure CLI version: `az version`
4. Check Azure service health: https://status.azure.com/
5. Ask team members or Azure support
