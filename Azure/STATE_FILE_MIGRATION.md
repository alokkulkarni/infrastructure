# State File Path Migration

## Issue Summary

The deploy workflow was creating Terraform state files at the wrong path, causing the destroy workflow to report "0 resources destroyed" despite resources still existing in Azure.

### Root Cause

- **Deploy workflow** was using: `terraform.tfstate` (flat path at container root)
- **Destroy workflow** was using: `azure/${{ env.ENVIRONMENT }}/${{ env.ENVIRONMENT_TAG }}/terraform.tfstate` (nested path)

When destroy ran, it initialized a new empty state file at the nested path, while the actual resources were tracked in the flat-path state file.

## The Correct Pattern

The **nested path pattern** is the enterprise-standard approach:

```
azure/{environment}/{environment-tag}/terraform.tfstate
```

Example: `azure/dev/SIT-Alok-TeamA-20251125-0921/terraform.tfstate`

### Why Nested Paths?

1. **Environment Isolation**: Separate dev/staging/prod states
2. **Tag Isolation**: Multiple deployments can coexist (team/user/timestamp)
3. **Conflict Prevention**: No state file collisions between simultaneous deployments
4. **Traceability**: Easy to identify which state belongs to which deployment
5. **Scalability**: Supports large organizations with many teams/environments

## Changes Made

### Deploy Workflow (`.github/workflows/deploy-azure-infrastructure.yml`)

Updated **3 locations** where backend is configured:

1. **terraform-plan job** (line 192)
2. **terraform-apply job** (line 322)
3. **import-resources job** (line 523)

**Before:**
```yaml
key                  = "terraform.tfstate"
```

**After:**
```yaml
key                  = "azure/${{ env.ENVIRONMENT }}/${{ env.ENVIRONMENT_TAG }}/terraform.tfstate"
```

### Destroy Workflow (`.github/workflows/destroy-azure-infrastructure.yml`)

Already correct - was using the nested path pattern from previous fixes.

## Migration Process

### For Existing Resources (One-Time Cleanup)

Use the emergency cleanup script to destroy resources tracked in the old state file:

```bash
cd infrastructure/Azure/scripts
./emergency-cleanup.sh
```

This script:
1. Downloads the old flat-path state file from Azure Storage
2. Uses it to destroy all tracked resources
3. Cleans up soft-deleted Key Vaults
4. Removes local state files

### For Future Deployments

After the deploy workflow fix:
- ✅ New deployments will use the correct nested path
- ✅ Destroy workflow will find and use the correct state file
- ✅ No manual intervention needed

## Azure Storage Structure

### Before Fix

```
Container: sit-alok-teama-20251125-0921
├── terraform.tfstate (77,934 bytes) ← Resources here
└── azure/
    └── dev/
        └── SIT-Alok-TeamA-20251125-0921/
            └── terraform.tfstate (180 bytes) ← Empty
```

### After Fix

```
Container: {environment-tag}
└── azure/
    └── {environment}/
        └── {environment-tag}/
            └── terraform.tfstate ← All resources here
```

## Verification Steps

1. **Check state file location** in Azure Storage:
   ```bash
   az storage blob list \
     --account-name tctfstate2745ace7 \
     --container-name {container} \
     --account-key {key}
   ```

2. **Verify state content**:
   ```bash
   az storage blob download \
     --account-name tctfstate2745ace7 \
     --container-name {container} \
     --name "azure/dev/{env-tag}/terraform.tfstate" \
     --file check-state.json \
     --account-key {key}
   
   cat check-state.json | jq '.resources | length'
   ```

3. **Test destroy workflow**:
   - Should report correct number of resources
   - Should successfully destroy all infrastructure
   - Should show proper state file path in logs

## Prevention

- Both workflows now use **identical** state file path patterns
- Backend configurations are consistent across all jobs
- State files are properly organized and isolated
- Multiple simultaneous deployments are supported

## Related Files

- `.github/workflows/deploy-azure-infrastructure.yml` - Deploy workflow (FIXED)
- `.github/workflows/destroy-azure-infrastructure.yml` - Destroy workflow (Already correct)
- `scripts/emergency-cleanup.sh` - One-time cleanup script

## References

- Azure Storage Backend: https://developer.hashicorp.com/terraform/language/settings/backends/azurerm
- Backend Configuration: https://developer.hashicorp.com/terraform/language/settings/backends/configuration
- State File Management: https://developer.hashicorp.com/terraform/language/state
