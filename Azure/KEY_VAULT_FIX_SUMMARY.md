# Key Vault Resource Import Fix - Summary

## Problem Statement

When running Terraform apply, you encountered this error:

```
Error: A resource with the ID "/subscriptions/.../vaults/testcontainersdevkv/objectId/e7157a7c-45c3-4323-8caf-3d47e6497006" already exists
```

This occurred because Key Vault access policies from a previous incomplete deployment were left in Azure but not in Terraform state.

## Root Cause

The initial idempotent solution (commit 3c1e70e) covered core infrastructure resources but didn't handle the complexity of Key Vault resources:

1. **Key Vault Access Policies** - Cannot be easily imported due to special objectId-based resource IDs
2. **Key Vault Secrets** - Cannot be imported at all (contain sensitive data)
3. **Module Resources** - The VM module creates Key Vault resources that weren't covered by the original auto-import script

## Solution Implemented

### Enhanced Auto-Import Script (commit 2ee4803)

Added intelligent handling for Key Vault resources that automatically:

#### 1. Access Policy Auto-Cleanup
```bash
# If import fails due to "already exists" error:
1. Detect the failure from import output
2. Automatically delete the conflicting access policy
3. Let Terraform recreate it with correct permissions
4. Provides fallback manual command if automatic cleanup fails
```

#### 2. Secret Auto-Cleanup
```bash
# Secrets cannot be imported (sensitive data):
1. Detect if secret exists in Key Vault
2. Automatically delete the existing secret
3. Attempt to purge (handle soft-delete)
4. Let Terraform recreate it with new key
5. Provides fallback manual commands if needed
```

### Key Improvements

**Automatic Error Detection**
- Captures import command output to detect "already exists" errors
- Intelligently decides whether to retry import or clean up

**Safe Cleanup**
- Only deletes resources that are confirmed to exist in Azure
- Only triggers cleanup if import fails with specific error patterns
- Provides manual fallback commands if automatic cleanup fails

**Better User Experience**
- Clear color-coded output showing what actions are taken
- Explains why cleanup is needed
- Shows exact commands being run for transparency

## What Resources Are Now Covered

The auto-import script now handles **all 20+ Terraform resources**:

### Core Infrastructure (6)
1. Resource Group
2. Virtual Network
3. Public Subnet
4. Private Subnet
5. NAT Gateway Public IP 1 & 2

### NAT Gateway (2)
7. NAT Gateway
8. NAT Gateway Public IP Association

### Network Security (5)
9. Network Security Group
10. NSG Rule: Allow HTTP (80)
11. NSG Rule: Allow HTTPS (443)
12. NSG Rule: Allow Outbound
13. NSG Subnet Association

### Virtual Machine (4)
14. VM Public IP
15. Network Interface
16. NIC Security Group Association
17. Virtual Machine

### Key Vault (3) - **NEWLY ENHANCED**
18. Key Vault
19. Key Vault Access Policy (with auto-cleanup)
20. Key Vault Secret (with auto-cleanup)

## How to Use

### Option 1: GitHub Actions (Automatic)
The workflow now includes the enhanced auto-import:

```yaml
- name: Auto-import existing resources (Idempotency)
  run: ../scripts/auto-import-resources.sh
```

**Just re-run your failed deployment** - it will automatically clean up conflicting Key Vault resources.

### Option 2: Local Testing
```bash
cd infrastructure/Azure/scripts
./idempotent-apply.sh
```

The script will:
1. Check all 20+ resources
2. Import what it can
3. Auto-cleanup access policies and secrets that can't be imported
4. Proceed with terraform apply

### Option 3: Manual Cleanup (if needed)
If automatic cleanup fails, the script provides exact commands:

```bash
# For Access Policy
az keyvault delete-policy \
  --name testcontainersdevkv \
  --object-id e7157a7c-45c3-4323-8caf-3d47e6497006

# For Secret
az keyvault secret delete \
  --vault-name testcontainersdevkv \
  --name testcontainers-dev-ssh-key

az keyvault secret purge \
  --vault-name testcontainersdevkv \
  --name testcontainers-dev-ssh-key
```

## Testing the Fix

### Test 1: Clean State
```bash
# Should show "No imports needed"
cd infrastructure/Azure/terraform
../scripts/auto-import-resources.sh
```

### Test 2: With Existing Resources
```bash
# Should import existing resources and clean up conflicts
cd infrastructure/Azure/terraform
terraform destroy -auto-approve  # Leave some resources
# Manually cancel mid-destroy to leave resources
../scripts/auto-import-resources.sh
terraform apply
```

### Test 3: Full Workflow
```bash
# Use the GitHub Actions workflow
# It will automatically handle everything
```

## Expected Output

### Successful Import
```
✓ Authenticated with Azure
ℹ Checking Key Vault Access Policy...
⚠ Found Key Vault Access Policy not in Terraform state
ℹ Attempting import...
✗ Import failed - already exists error detected
ℹ Auto-cleaning up conflicting access policy...
✓ Deleted existing access policy - Terraform will recreate it
```

### Successful Secret Cleanup
```
ℹ Checking Key Vault Secret (SSH Key)...
⚠ SSH Key secret exists in Key Vault but not in Terraform state
ℹ Secrets contain sensitive data and cannot be imported
ℹ Auto-cleaning up existing secret...
✓ Deleted existing secret - Terraform will recreate it
ℹ Purging deleted secret...
✓ Secret fully purged
```

## Troubleshooting

### If Access Policy Cleanup Fails
```bash
# Get your object ID
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Manually delete
az keyvault delete-policy \
  --name testcontainersdevkv \
  --object-id $OBJECT_ID

# Then run terraform apply
```

### If Secret Purge Fails
This can happen if purge protection is enabled:

```bash
# Check purge protection status
az keyvault show \
  --name testcontainersdevkv \
  --query properties.enablePurgeProtection

# If true, you'll need to wait for the purge protection period
# Or disable it (requires appropriate permissions)
```

### If Soft-Delete Issues Occur
```bash
# List soft-deleted secrets
az keyvault secret list-deleted --vault-name testcontainersdevkv

# Recover or purge as needed
az keyvault secret recover \
  --vault-name testcontainersdevkv \
  --name testcontainers-dev-ssh-key

# Or
az keyvault secret purge \
  --vault-name testcontainersdevkv \
  --name testcontainers-dev-ssh-key
```

## Benefits

1. **Fully Idempotent** - Can run terraform apply multiple times safely
2. **Automatic Recovery** - Handles incomplete deployments automatically
3. **No Manual Intervention** - Cleans up conflicts without user action
4. **Transparent** - Shows exactly what's being done
5. **Safe** - Only affects resources not in Terraform state
6. **Comprehensive** - Covers all 20+ Terraform resources

## Related Documentation

- [IDEMPOTENT_TERRAFORM_GUIDE.md](./IDEMPOTENT_TERRAFORM_GUIDE.md) - Complete guide to idempotent operations
- [Azure/scripts/auto-import-resources.sh](./Azure/scripts/auto-import-resources.sh) - The enhanced import script
- [Azure/scripts/idempotent-apply.sh](./Azure/scripts/idempotent-apply.sh) - Local wrapper script

## Commits

- **3c1e70e** - Initial idempotent solution (core resources)
- **2ee4803** - Enhanced Key Vault handling with auto-cleanup (this fix)

## Next Steps

1. **Re-run your deployment** - The fix is now in place
2. **Monitor the output** - Watch for the auto-cleanup messages
3. **Verify success** - Check that terraform apply completes without errors

The script will automatically handle the Key Vault access policy and secret cleanup, allowing your deployment to succeed.
