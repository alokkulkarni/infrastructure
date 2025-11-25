# Storage Account Name Length Fix

## Problem

The destroy workflow was failing at `terraform init` with this error:

```
Error: Failed to get existing workspaces: Error retrieving keys for Storage Account "testcontainerstfstate2745ace7": 
storage.AccountsClient#ListKeys: Invalid input: autorest/validation: validation failed: 
parameter=accountName constraint=MaxLength value="testcontainerstfstate2745ace7" details: 
value length must be less than or equal to 24
```

## Root Cause

**Azure storage account names have a maximum length of 24 characters.**

The destroy workflow was using an inconsistent naming convention:
- **Deploy workflow** (via setup script): `tctfstate{8-chars}` = 17 characters ✅
- **Destroy workflow**: `testcontainerstfstate{8-chars}` = **29 characters** ❌

Example:
- ✅ Correct: `tctfstate2745ace7` (17 chars)
- ❌ Wrong: `testcontainerstfstate2745ace7` (29 chars)

## Fix Applied

Updated the destroy workflow to use the same shortened naming as the deploy workflow:

```yaml
# OLD (29 chars - TOO LONG)
BACKEND_SA="${PROJECT_NAME}tfstate${SUBSCRIPTION_SHORT}"
# Result: testcontainerstfstate2745ace7

# NEW (17 chars - CORRECT)
BACKEND_SA="tctfstate${SUBSCRIPTION_SHORT}"
# Result: tctfstate2745ace7
```

## Validation Added

Added length validation to the setup script to catch this error early:

```bash
# Validate storage account name length (Azure limit is 24 characters)
if [ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]; then
    echo "ERROR: Storage account name too long: ${STORAGE_ACCOUNT_NAME} (${#STORAGE_ACCOUNT_NAME} chars)"
    echo "Azure storage account names must be 24 characters or less"
    exit 1
fi
```

## Storage Account Naming Convention

**Format:** `tctfstate{subscription_short}`

Where:
- `tc` = "testcontainers" abbreviated
- `tfstate` = terraform state
- `{subscription_short}` = First 8 characters of subscription ID (no dashes)

**Examples:**
- Subscription: `2745ace7-1234-5678-9abc-def012345678`
- Short: `2745ace7`
- Storage Account: `tctfstate2745ace7` (17 characters)

**Why this works:**
- Prefix: `tctfstate` = 9 characters
- Subscription: 8 characters
- Total: 17 characters (well within 24 limit)
- Buffer: 7 characters for future changes

## Azure Naming Constraints

### Storage Account Names
- **Length:** 3-24 characters
- **Characters:** Lowercase letters and numbers only
- **Uniqueness:** Must be globally unique across Azure
- **No:** Hyphens, uppercase letters, special characters

### Container Names
- **Length:** 3-63 characters
- **Characters:** Lowercase letters, numbers, and hyphens
- **Format:** Must start and end with letter or number
- **No:** Consecutive hyphens, uppercase letters

## Testing

### Verify Correct Name Generation

```bash
# Test the naming logic locally
SUBSCRIPTION_ID="2745ace7-1234-5678-9abc-def012345678"
SUBSCRIPTION_SHORT=$(echo "$SUBSCRIPTION_ID" | tr -d '-' | cut -c1-8)
STORAGE_ACCOUNT_NAME="tctfstate${SUBSCRIPTION_SHORT}"

echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo "Length: ${#STORAGE_ACCOUNT_NAME}"

# Expected output:
# Storage Account: tctfstate2745ace7
# Length: 17
```

### Verify in Azure

```bash
# After deployment, check the actual storage account
az storage account list \
  --resource-group testcontainers-tfstate-rg \
  --query "[].{Name:name, Length:name}" \
  --output table

# Should show: tctfstate2745ace7 (17 chars)
```

## Impact

### What Changed
1. ✅ Destroy workflow now uses correct 17-character name
2. ✅ Deploy workflow unchanged (already correct)
3. ✅ Setup script adds validation for name length
4. ✅ Both workflows now use identical naming logic

### What Didn't Change
- Storage account location
- Container naming
- Resource group name
- Backend configuration structure
- State file paths

### Migration Not Required
If you already have a deployment with the old name:
- **Don't worry** - The deploy workflow already creates the correct name
- The destroy workflow will now find it correctly
- No manual migration needed

## Files Modified

1. **`.github/workflows/destroy-azure-infrastructure.yml`**
   - Line 56: Changed from `${PROJECT_NAME}tfstate` to `tctfstate`
   - Added comment explaining the 24-character limit

2. **`Azure/scripts/setup-terraform-backend.sh`**
   - Lines 91-98: Added length validation
   - Shows character count in output for verification

## Related Issues

This fix resolves:
- ✅ Destroy workflow failing at terraform init
- ✅ Inconsistent naming between deploy and destroy
- ✅ Future potential issues with long names

## Prevention

To prevent similar issues in the future:

1. **Always validate Azure naming constraints** when generating resource names
2. **Keep deploy and destroy workflows in sync** for backend configuration
3. **Test destroy workflow** after deploy workflow changes
4. **Use shortened prefixes** for frequently used resources
5. **Add validation** in scripts to catch length issues early

## Azure Naming Best Practices

### For Shared/Backend Resources
Use short, consistent prefixes:
- ✅ `tc` for "testcontainers"
- ✅ `tfstate` for "terraform state"
- ✅ Keep total under 20 chars for safety

### For Application Resources
Can use longer, descriptive names:
- `testcontainers-dev-vm` (VM names: up to 64 chars)
- `testcontainers-dev-rg` (Resource groups: up to 90 chars)
- `testcontainersdevkv` (Key Vaults: 3-24 chars, no dashes)

### Critical Constraints to Remember
| Resource Type | Max Length | Special Rules |
|--------------|------------|---------------|
| Storage Account | **24** | Lowercase alphanumeric only |
| Key Vault | **24** | Lowercase alphanumeric, no dashes |
| VM | 64 | Letters, numbers, hyphens, underscores |
| Resource Group | 90 | Letters, numbers, hyphens, underscores, periods, parentheses |
| Container | 63 | Lowercase alphanumeric, hyphens |

## Summary

- **Problem:** Destroy workflow used 29-char storage account name (limit is 24)
- **Root Cause:** Inconsistent naming between deploy and destroy workflows  
- **Fix:** Changed destroy workflow to use shortened `tctfstate` prefix (17 chars)
- **Validation:** Added length check to prevent future issues
- **Impact:** Destroy workflow now works correctly, no migration needed

The fix is backward compatible and resolves the terraform init failure immediately.
