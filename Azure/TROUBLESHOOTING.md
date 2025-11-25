# Azure Infrastructure Troubleshooting Guide

## Common Terraform Errors and Solutions

### 1. MissingSubscriptionRegistration Error

**Error:**
```
Error: MissingSubscriptionRegistration: The subscription is not registered to use namespace 'Microsoft.Network'
```

**Cause:** Azure resource providers are not registered in your subscription.

**Solution:**

Run the provider registration script:
```bash
cd infrastructure/Azure/scripts
./register-azure-providers.sh
```

Or manually register providers:
```bash
# Register all common providers
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.KeyVault

# Check registration status
az provider list --query "[?registrationState=='Registering' || registrationState=='NotRegistered']" -o table
```

**Prevention:** Run the registration script before first Terraform deployment.

---

### 2. Resource Already Exists (Import Required)

**Error:**
```
Error: A resource with the ID "/subscriptions/***/resourceGroups/testcontainers-dev-rg" already exists - 
to be managed via Terraform this resource needs to be imported into the State.

  with azurerm_resource_group.main,
  on main.tf line 35, in resource "azurerm_resource_group" "main":
  35: resource "azurerm_resource_group" "main" {
```

**Cause:** 
- Resource exists in Azure but not in Terraform state
- Previous `terraform destroy` or rollback failed mid-execution
- Resources were created manually outside Terraform
- State file was deleted or corrupted

**Solution 1: Import Existing Resources (Recommended)**

Use the import helper script:
```bash
cd infrastructure/Azure/terraform
../scripts/import-existing-resources.sh
```

Or manually import:
```bash
# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Import the resource group
terraform import azurerm_resource_group.main \
  "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg"

# Import other resources if they exist
terraform import 'module.networking.azurerm_virtual_network.main' \
  "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg/providers/Microsoft.Network/virtualNetworks/testcontainers-dev-vnet"

# Verify import
terraform state list
terraform plan
```

**Solution 2: Delete Existing Resources and Recreate**

⚠️ **WARNING:** This deletes all existing resources. Only use if you're sure!

```bash
# Delete the resource group (this deletes ALL resources inside it)
az group delete --name testcontainers-dev-rg --yes --no-wait

# Wait for deletion to complete (2-5 minutes)
az group wait --name testcontainers-dev-rg --deleted

# Run Terraform apply
terraform apply
```

**Solution 3: Clean State and Retry (GitHub Actions)**

If running in GitHub Actions and want to start fresh:

```bash
# Delete the state file container
az storage container delete \
  --name sit-test-container \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login

# Delete the resource group
az group delete --name testcontainers-dev-rg --yes

# Re-run the workflow
```

**Which Solution to Choose:**

| Scenario | Recommended Solution |
|----------|---------------------|
| Resources have important data | **Solution 1: Import** |
| Testing/Development environment | **Solution 2 or 3: Delete and recreate** |
| Production environment | **Solution 1: Import (ONLY)** |
| Rollback failed mid-execution | **Solution 2: Delete and recreate** |
| State file lost/corrupted | **Solution 1: Import all resources** |

**Prevention:**
- Always use Terraform for resource lifecycle
- Don't manually create resources that Terraform manages
- Keep state file backups (versioning enabled on backend)
- Use `terraform destroy` carefully and monitor completion
- Test rollbacks in dev environment first

---

### 3. Authorization_RequestDenied (Azure AD Application)

**Error:**
```
Error: Could not create application
ApplicationsClient.BaseClient.Post(): unexpected status 403 with OData error: 
Authorization_RequestDenied: Insufficient privileges to complete the operation.
```

**Cause:** The service principal or user running Terraform lacks Azure AD admin permissions to create applications.

**Solutions:**

#### Option A: Use Manual OIDC Setup (Recommended)
OIDC is already set up manually via scripts. The Terraform OIDC module is redundant and commented out.

```bash
# OIDC is managed manually
cd infrastructure/Azure/scripts
./setup-oidc-manually.sh alokkulkarni infrastructure dev
```

The Terraform OIDC module is disabled by default in `main.tf`.

#### Option B: Grant Azure AD Permissions
If you need Terraform to manage OIDC:

1. Grant Application.ReadWrite.All permission to the service principal
2. Requires Azure AD admin privileges
3. Uncomment the OIDC module in `terraform/main.tf`

**Prevention:** Keep OIDC management separate from infrastructure deployment.

---

### 4. Authentication Failures

**Error:**
```
Error: Unable to authenticate with Azure CLI
```

**Solutions:**

```bash
# Check current authentication
az account show

# Re-authenticate
az login

# Set correct subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# For GitHub Actions (OIDC)
# Verify these secrets are set:
# - AZURE_CLIENT_ID
# - AZURE_TENANT_ID
# - AZURE_SUBSCRIPTION_ID
```

---

### 5. Invalid Control Character in URL (Trailing Newlines)

**Error:**
```
Error: populating Resource Provider cache: loading results: building GET request: 
parse "https://management.azure.com/subscriptions/***\n/providers": 
net/url: invalid control character in URL
```

**Cause:** GitHub Secrets contain trailing newlines or whitespace characters, causing URL parsing errors.

**Solutions:**

#### Option 1: Re-create Secrets (Recommended)
```bash
# Get clean values from OIDC setup output
cd infrastructure/Azure/scripts
./setup-oidc-manually.sh alokkulkarni infrastructure dev

# Copy output values carefully (no trailing spaces/newlines)
# Go to: https://github.com/YOUR_ORG/YOUR_REPO/settings/secrets/actions
# Update each secret:
# - AZURE_CLIENT_ID
# - AZURE_TENANT_ID
# - AZURE_SUBSCRIPTION_ID

# When pasting:
# 1. Paste the value
# 2. DO NOT press Enter after pasting
# 3. Click "Update secret" immediately
```

#### Option 2: Verify Secret Values
```bash
# Check if secrets have newlines (they'll show as extra lines in workflow logs)
# In GitHub Actions logs, look for:
echo "Subscription: '${{ secrets.AZURE_SUBSCRIPTION_ID }}'"
# If you see extra blank lines, the secret has newlines

# Delete and recreate the secret without newlines
```

#### Option 3: Already Fixed in Workflow
The workflow now automatically sanitizes all secrets by:
- Removing newlines with `tr -d '\n\r'`
- Trimming whitespace with `xargs`

If you're still seeing this error:
1. Pull the latest workflow changes
2. Re-run the workflow

**Prevention:** 
- Always copy values from command output, not from text files
- Don't paste secrets from editors that add newlines
- Use the workflow output which provides clean values
- GitHub UI sometimes adds newlines when you press Enter - avoid this

---

### 6. Backend State Lock Timeout

**Error:**
```
Error: Error locking state: Error acquiring the state lock
```

**Cause:** Previous Terraform operation didn't complete cleanly, leaving state locked.

**Solutions:**

```bash
# Check lock status
az storage blob show \
  --account-name testcontainerstfstate2745ace7 \
  --container-name YOUR_CONTAINER \
  --name terraform.tfstate \
  --auth-mode login

# Force unlock (use with caution!)
terraform force-unlock LOCK_ID

# Alternative: Wait 2-5 minutes for auto-unlock
```

**Prevention:** Always let Terraform operations complete. If cancelled, run `terraform apply` again to clean up.

---

### 6. Subscription ID Not Found

**Error:**
```
Error: SubscriptionNotFound: The subscription was not found
```

**Cause:** Subscription context not set correctly or RBAC permissions missing.

**Solutions:**

```bash
# List available subscriptions
az account list --output table

# Set correct subscription
az account set --subscription "2745ace7-ad28-4d41-ae4c-eeb28f54ffd2"

# Verify
az account show --query id -o tsv

# In GitHub Actions workflow, ensure AZURE_SUBSCRIPTION_ID is set correctly
```

---

### 8. Storage Account Name Conflict

**Error:**
```
Error: The storage account name 'testcontainerstfstate...' is already taken
```

**Cause:** Storage account names are globally unique across all of Azure.

**Solutions:**

```bash
# Option 1: Use existing storage account
# The setup script checks for existing accounts and reuses them

# Option 2: Change project name
export PROJECT_NAME="myproject"
./setup-terraform-backend.sh

# Option 3: Manually set unique name
STORAGE_ACCOUNT="uniquename$(echo $SUBSCRIPTION_ID | cut -c1-8)"
```

---

### 8. Insufficient RBAC Permissions

**Error:**
```
Error: Authorization failed for this request
```

**Required Roles:**
- Contributor (create/modify resources)
- User Access Administrator (assign roles)
- Storage Account Contributor (backend state)
- Storage Blob Data Contributor (backend state blobs)

**Check permissions:**
```bash
az role assignment list \
  --assignee $(az account show --query user.name -o tsv) \
  --output table
```

**Request permissions from admin:**
```bash
# Admin grants permissions
az role assignment create \
  --assignee user@example.com \
  --role "Contributor" \
  --scope /subscriptions/YOUR_SUBSCRIPTION_ID
```

---

### 10. Resource Already Exists

**Error:**
```
Error: A resource with the ID already exists
```

**Cause:** Resource was created outside Terraform, or state is out of sync.

**Solutions:**

```bash
# Option 1: Import existing resource
terraform import azurerm_resource_group.main /subscriptions/.../resourceGroups/...

# Option 2: Remove from state (if recreating)
terraform state rm azurerm_resource_group.main

# Option 3: Refresh state
terraform refresh
```

---

### 11. Virtual Network Deployment Failures

**Error:**
```
Error: creating Virtual Network: unexpected status 409 (409 Conflict)
```

**Causes:**
- Provider not registered (see #1)
- Network CIDR conflicts with existing VNets
- Region quota exceeded

**Solutions:**

```bash
# Check existing VNets
az network vnet list -o table

# Check quotas
az vm list-usage --location eastus -o table | grep -i network

# Adjust CIDR ranges in terraform.tfvars
vnet_address_space = ["10.1.0.0/16"]  # Change to avoid conflicts
```

---

## Quick Diagnostic Commands

### Check Azure Configuration
```bash
# Current subscription
az account show --query "{Name:name, ID:id, Tenant:tenantId}" -o table

# Provider registration status
az provider list --query "[?registrationState!='Registered'].{Namespace:namespace, State:registrationState}" -o table

# Role assignments
az role assignment list --assignee $(az account show --query user.name -o tsv) --output table

# Resource group status
az group list --query "[].{Name:name, Location:location, State:properties.provisioningState}" -o table
```

### Check Terraform State
```bash
# List resources in state
terraform state list

# Show specific resource
terraform state show azurerm_resource_group.main

# Validate configuration
terraform validate

# Check plan
terraform plan -detailed-exitcode
```

### Check Backend Configuration
```bash
# List storage containers
az storage container list \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login \
  --output table

# Check blob properties
az storage blob show \
  --account-name testcontainerstfstate2745ace7 \
  --container-name YOUR_CONTAINER \
  --name terraform.tfstate \
  --auth-mode login \
  --query "{Name:name, Size:properties.contentLength, Modified:properties.lastModified}"
```

---

## Workflow-Specific Issues

### GitHub Actions Failures

**Check workflow logs:**
1. Go to Actions tab in GitHub
2. Select failed workflow run
3. Check each job's logs
4. Look for specific error messages

**Common issues:**

#### OIDC Authentication Fails
```
Error: Failed to get OIDC token
```

**Solution:**
- Verify GitHub Secrets are set correctly:
  - AZURE_CLIENT_ID
  - AZURE_TENANT_ID  
  - AZURE_SUBSCRIPTION_ID
- Check workflow has `id-token: write` permission
- Verify federated credentials in Azure AD app match repository

#### Backend Not Found
```
Error: Failed to get existing workspaces
```

**Solution:**
```bash
# Run backend setup first
cd infrastructure/Azure/scripts
./test-backend-setup-locally.sh SIT-test-$(date +%Y%m%d-%H%M)

# Or trigger setup-backend job in workflow
```

#### Environment Tag Missing
```
Error: variable environment_tag is required
```

**Solution:** Always provide environment_tag in workflow inputs or terraform.tfvars

---

## Prevention Best Practices

### 1. Test Locally First
```bash
# Always test scripts locally before GitHub Actions
cd infrastructure/Azure/scripts
./test-backend-setup-locally.sh SIT-local-test
```

### 2. Register Providers Early
```bash
# One-time setup per subscription
./register-azure-providers.sh
```

### 3. Verify Authentication
```bash
# Before any Terraform command
az account show
terraform validate
```

### 4. Use Environment Tags
```bash
# Always include environment_tag for isolation
terraform apply -var="environment_tag=SIT-myname-test"
```

### 5. Review Plans Carefully
```bash
# Always review before apply
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

---

## Emergency Procedures

### 1. Force Unlock State
```bash
# Get lock ID from error message
terraform force-unlock LOCK_ID

# Or wait for auto-unlock (2-5 minutes)
```

### 2. Reset Backend State
```bash
# Backup current state
az storage blob download \
  --account-name testcontainerstfstate2745ace7 \
  --container-name YOUR_CONTAINER \
  --name terraform.tfstate \
  --file backup.tfstate \
  --auth-mode login

# Delete container and recreate
az storage container delete \
  --name YOUR_CONTAINER \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login

# Run backend setup again
./setup-terraform-backend.sh
```

### 3. Clean Slate Deployment
```bash
# Remove all infrastructure (use with caution!)
terraform destroy -var="environment_tag=YOUR_TAG"

# Delete resource group
az group delete --name testcontainers-dev-rg --yes --no-wait

# Recreate from scratch
terraform apply -var="environment_tag=NEW_TAG"
```

---

## Support Resources

- **Azure CLI Documentation**: https://docs.microsoft.com/en-us/cli/azure/
- **Terraform Azure Provider**: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- **Azure Service Health**: https://status.azure.com/
- **Provider Registration**: https://aka.ms/rps-not-found

---

## Getting Help

1. Check this troubleshooting guide
2. Review error messages carefully (they usually contain the solution)
3. Test locally with detailed logging:
   ```bash
   export TF_LOG=DEBUG
   terraform apply
   ```
4. Check Azure Portal for resource state
5. Review GitHub Actions logs for CI/CD issues
6. Ask team members or Azure support

---

## Related Documentation

- [LOCAL_TESTING_GUIDE.md](./LOCAL_TESTING_GUIDE.md) - Test infrastructure locally
- [AUTOMATION_SETUP.md](./AUTOMATION_SETUP.md) - OIDC setup guide
- [ENVIRONMENT_TAG_GUIDE.md](./ENVIRONMENT_TAG_GUIDE.md) - Environment isolation
