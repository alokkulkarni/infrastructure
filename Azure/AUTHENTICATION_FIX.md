# Azure Storage Backend Authentication Fix

## Issue

The destroy workflow was consistently failing with **"Bad Request - Invalid URL"** error when trying to access the Azure Storage backend:

```
Error: Failed to get existing workspaces: Error retrieving keys for Storage Account "tctfstate2745ace7": 
storage.AccountsClient#ListKeys: Failure responding to request: StatusCode=400 -- 
Original Error: autorest/azure: error response cannot be parsed: 
{"<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\"...
<TITLE>Bad Request</TITLE>
<h2>Bad Request - Invalid URL</h2>
<p>HTTP Error 400. The request URL is invalid.</p>
```

## Root Cause Analysis

The error occurred because the destroy workflow was missing **three critical authentication configurations** that the deploy workflow had:

### 1. Missing `use_oidc = true` in Backend Configuration

**Deploy workflow (CORRECT):**
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "..."
    storage_account_name = "..."
    container_name       = "..."
    key                  = "..."
    use_oidc             = true  # ← REQUIRED for OIDC authentication
  }
}
```

**Destroy workflow (INCORRECT - Before Fix):**
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "..."
    storage_account_name = "..."
    container_name       = "..."
    key                  = "..."
    # Missing: use_oidc = true
  }
}
```

Without `use_oidc = true`, Terraform couldn't properly authenticate to the backend storage account using OIDC credentials.

### 2. Missing Secret Sanitization

**Deploy workflow (CORRECT):**
```yaml
- name: Sanitize Azure secrets
  run: |
    # Strip any trailing newlines/whitespace from secrets to prevent URL parsing errors
    echo "ARM_CLIENT_ID=$(echo -n '${{ secrets.AZURE_CLIENT_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
    echo "ARM_TENANT_ID=$(echo -n '${{ secrets.AZURE_TENANT_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
    echo "ARM_SUBSCRIPTION_ID=$(echo -n '${{ secrets.AZURE_SUBSCRIPTION_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
    echo "ARM_USE_OIDC=true" >> $GITHUB_ENV
    echo "ARM_USE_AZUREAD=true" >> $GITHUB_ENV
```

**Destroy workflow (INCORRECT - Before Fix):**
- No secret sanitization step
- Secrets passed directly with potential newlines/whitespace
- This causes URL parsing errors in Azure API calls

**Why this matters:**
- GitHub Secrets can contain trailing newlines or whitespace
- Azure REST APIs reject URLs with embedded newlines
- Results in "Bad Request - Invalid URL" errors

### 3. Missing `ARM_USE_AZUREAD` Environment Variable

**Deploy workflow (CORRECT):**
```yaml
- name: Terraform Init
  run: terraform init
  env:
    ARM_USE_OIDC: true
    ARM_USE_AZUREAD: true  # ← REQUIRED for Azure AD authentication
```

**Destroy workflow (INCORRECT - Before Fix):**
```yaml
- name: Terraform Init
  run: terraform init
  env:
    ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
    ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
    ARM_USE_OIDC: true
    # Missing: ARM_USE_AZUREAD
```

**Why this matters:**
- `ARM_USE_AZUREAD=true` tells Terraform to use Azure AD authentication for storage access
- Without it, Terraform tries to use storage account keys instead of OIDC tokens
- Storage account key retrieval fails with OIDC-only credentials

## The Fix (Commit 153295f)

### 1. Added Secret Sanitization Step

```yaml
- name: Sanitize Azure secrets
  run: |
    # Strip any trailing newlines/whitespace from secrets to prevent URL parsing errors
    echo "ARM_CLIENT_ID=$(echo -n '${{ secrets.AZURE_CLIENT_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
    echo "ARM_TENANT_ID=$(echo -n '${{ secrets.AZURE_TENANT_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
    echo "ARM_SUBSCRIPTION_ID=$(echo -n '${{ secrets.AZURE_SUBSCRIPTION_ID }}' | tr -d '\n\r' | xargs)" >> $GITHUB_ENV
    echo "ARM_USE_OIDC=true" >> $GITHUB_ENV
    echo "ARM_USE_AZUREAD=true" >> $GITHUB_ENV
```

**Effect:**
- Removes newlines (`\n`) and carriage returns (`\r`) from secrets
- Sets all required environment variables in `GITHUB_ENV`
- Ensures clean URLs in Azure API requests

### 2. Added Backend Output Validation

```yaml
- name: Update backend configuration
  working-directory: Azure/terraform
  run: |
    # Validate outputs are not empty
    if [ -z "${{ needs.setup-backend.outputs.backend_resource_group }}" ] || 
       [ -z "${{ needs.setup-backend.outputs.backend_storage_account }}" ] || 
       [ -z "${{ needs.setup-backend.outputs.backend_container }}" ]; then
      echo "ERROR: Backend outputs are empty!"
      echo "Resource Group: '${{ needs.setup-backend.outputs.backend_resource_group }}'"
      echo "Storage Account: '${{ needs.setup-backend.outputs.backend_storage_account }}'"
      echo "Container: '${{ needs.setup-backend.outputs.backend_container }}'"
      exit 1
    fi
```

**Effect:**
- Catches configuration errors early
- Provides clear error messages
- Prevents cryptic failures downstream

### 3. Added `use_oidc = true` to Backend Configuration

```yaml
cat > backend.tf <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "${{ needs.setup-backend.outputs.backend_resource_group }}"
    storage_account_name = "${{ needs.setup-backend.outputs.backend_storage_account }}"
    container_name       = "${{ needs.setup-backend.outputs.backend_container }}"
    key                  = "azure/${{ env.ENVIRONMENT }}/${{ env.ENVIRONMENT_TAG }}/terraform.tfstate"
    use_oidc             = true  # ← ADDED
  }
}
EOF
```

**Effect:**
- Enables OIDC authentication for backend access
- Matches deploy workflow configuration
- Required for GitHub Actions OIDC identity

### 4. Updated Environment Variables

```yaml
- name: Terraform Init
  run: terraform init
  env:
    ARM_USE_OIDC: true
    ARM_USE_AZUREAD: true  # ← ADDED

- name: Terraform Destroy
  run: terraform destroy ...
  env:
    ARM_USE_OIDC: true
    ARM_USE_AZUREAD: true  # ← ADDED
```

**Effect:**
- Enables Azure AD authentication for storage
- Credentials from `GITHUB_ENV` are automatically available
- No need to pass secrets explicitly in each step

## Authentication Flow

### OIDC Authentication Flow (Now Working)

1. **GitHub Actions Login** (`azure/login@v1`):
   - Uses OIDC token from GitHub
   - Authenticates to Azure AD
   - Establishes identity for the workflow

2. **Secret Sanitization**:
   - Cleans up Azure credential values
   - Sets environment variables in `GITHUB_ENV`
   - Ensures proper URL formatting

3. **Terraform Backend Init**:
   - Reads backend configuration with `use_oidc = true`
   - Uses `ARM_USE_AZUREAD=true` for storage authentication
   - Authenticates using OIDC token (not storage keys)
   - Accesses state file in container

4. **Terraform Operations**:
   - All operations use same OIDC credentials
   - No storage account keys required
   - Consistent authentication throughout workflow

## Why This Approach is Better

### Old Approach (Storage Account Keys)
```yaml
# Would require managing storage account keys
# Keys must be rotated regularly
# Keys provide full access to storage account
# Keys can be leaked/compromised
```

### New Approach (OIDC + Azure AD)
```yaml
# No keys to manage or rotate
# Identity-based authentication
# Least-privilege access via RBAC
# Short-lived tokens
# Auditable in Azure AD logs
```

## Azure RBAC Requirements

For this authentication to work, the Azure service principal (or managed identity) must have:

1. **Storage Account Access**:
   - Role: `Storage Blob Data Contributor` or higher
   - Scope: Storage account or container
   - Allows: Read/write access to state files

2. **Resource Group Access** (for resource operations):
   - Role: `Contributor` or higher
   - Scope: Resource group where infrastructure is deployed
   - Allows: Create/update/delete Azure resources

## Validation Steps

To verify the fix works:

1. **Check Azure AD authentication**:
   ```bash
   az login --service-principal \
     -u $ARM_CLIENT_ID \
     -t $ARM_TENANT_ID \
     --federated-token "$(cat $AZURE_FEDERATED_TOKEN_FILE)"
   ```

2. **Verify storage access**:
   ```bash
   az storage blob list \
     --account-name tctfstate{subscription-id} \
     --container-name {env-tag-lowercase} \
     --auth-mode login
   ```

3. **Test terraform init**:
   ```bash
   export ARM_USE_OIDC=true
   export ARM_USE_AZUREAD=true
   terraform init
   ```

4. **Run destroy workflow**:
   - Should successfully initialize backend
   - Should find and read state file
   - Should proceed with resource destruction

## Common Issues and Solutions

### Issue: "Bad Request - Invalid URL"
**Cause**: Newlines in secrets or missing `use_oidc`  
**Solution**: Ensure secret sanitization step runs and `use_oidc = true` is set

### Issue: "Failed to get existing workspaces"
**Cause**: Missing `ARM_USE_AZUREAD` environment variable  
**Solution**: Add `ARM_USE_AZUREAD: true` to terraform init/destroy steps

### Issue: "Access denied"
**Cause**: Service principal lacks RBAC permissions  
**Solution**: Grant `Storage Blob Data Contributor` role on storage account

### Issue: "Container not found"
**Cause**: Wrong container name (covered in previous fix)  
**Solution**: Use dynamic container name from environment tag

## Files Modified

- `.github/workflows/destroy-azure-infrastructure.yml`:
  - Added secret sanitization step
  - Added backend output validation
  - Added `use_oidc = true` to backend config
  - Updated environment variables for init and destroy

## Related Documentation

- [Backend Container Name Fix](./BACKEND_CONTAINER_FIX.md) - Previous fix for container mismatch
- [Storage Account Name Fix](./STORAGE_ACCOUNT_NAME_FIX.md) - First fix for name length
- [Destroy Validation Guide](./DESTROY_VALIDATION.md) - Complete resource destruction documentation
- [Azure OIDC Guide](./OIDC_GUIDE.md) - Setting up OIDC authentication

## Summary of All Destroy Workflow Fixes

1. ✅ **Storage Account Name Length** (Commit ea9f85a)
   - Problem: 29 chars exceeded 24-char limit
   - Solution: Shortened to 17 chars

2. ✅ **Container Name Mismatch** (Commit 0287b5b)
   - Problem: Hardcoded "tfstate" vs dynamic environment-specific names
   - Solution: Derive container name from environment tag

3. ✅ **OIDC Authentication** (Commit 153295f - THIS FIX)
   - Problem: Missing `use_oidc`, secret sanitization, and `ARM_USE_AZUREAD`
   - Solution: Match deploy workflow's complete authentication setup

## Expected Result

After all three fixes, the destroy workflow should:
1. ✅ Derive correct storage account name (17 chars)
2. ✅ Derive correct container name from environment tag
3. ✅ Authenticate properly using OIDC + Azure AD
4. ✅ Initialize Terraform backend successfully
5. ✅ Find and read state file
6. ✅ Destroy all 22 resources in correct order
7. ✅ Complete cleanup successfully
