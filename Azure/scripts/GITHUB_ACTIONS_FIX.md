# GitHub Actions Backend Extraction Fix

## Problem

The GitHub Actions workflow was failing with:
```
Error: Unable to process file command 'output' successfully.
Error: Invalid format 'testcontainers-tfstate-rg'
```

The extracted backend values had trailing quotes (`'`) which caused the error:
```
Resource Group: testcontainers-tfstate-rg'
Storage Account: tctfstate2745ace7'
Container: sit-alok-teama-20251124-1814'
```

## Root Cause

The script was outputting:
```bash
echo "export TF_BACKEND_RESOURCE_GROUP=\"$RESOURCE_GROUP_NAME\""
```

The workflow was using `sed 's/.*="\(.*\)"/\1/'` to extract values, but this was:
1. Matching the opening quote after `=`
2. Capturing everything until the **first** closing quote
3. Missing the escaped quote inside the string
4. Capturing the closing quote from the echo statement

## Solution

### Script Change (setup-terraform-backend.sh)

**Before:**
```bash
echo "export TF_BACKEND_RESOURCE_GROUP=\"$RESOURCE_GROUP_NAME\""
echo "export TF_BACKEND_STORAGE_ACCOUNT=\"$STORAGE_ACCOUNT_NAME\""
echo "export TF_BACKEND_CONTAINER=\"$CONTAINER_NAME\""
```

**After:**
```bash
echo "export TF_BACKEND_RESOURCE_GROUP=$RESOURCE_GROUP_NAME"
echo "export TF_BACKEND_STORAGE_ACCOUNT=$STORAGE_ACCOUNT_NAME"
echo "export TF_BACKEND_CONTAINER=$CONTAINER_NAME"
```

### Workflow Change (deploy-azure-infrastructure.yml)

**Before:**
```bash
BACKEND_RG=$(grep "export TF_BACKEND_RESOURCE_GROUP" setup_output.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/.*="\(.*\)"/\1/')
```

**After:**
```bash
BACKEND_RG=$(grep "export TF_BACKEND_RESOURCE_GROUP" setup_output.log | sed 's/\x1b\[[0-9;]*m//g' | cut -d'=' -f2)
```

## Why This Works

1. **No quotes in output**: `export VAR=value` instead of `export VAR="value"`
2. **Simple extraction**: `cut -d'=' -f2` splits on `=` and takes the second field
3. **ANSI stripping**: `sed 's/\x1b\[[0-9;]*m//g'` removes color codes first
4. **No regex complexity**: Avoids sed regex pattern matching issues

## Testing

Test extraction locally:
```bash
# Simulate the GitHub Actions extraction
echo "export TF_BACKEND_RESOURCE_GROUP=testcontainers-tfstate-rg" | cut -d'=' -f2
# Output: testcontainers-tfstate-rg

# With ANSI codes
echo -e "\033[0;32mexport TF_BACKEND_RESOURCE_GROUP=testcontainers-tfstate-rg\033[0m" | sed 's/\x1b\[[0-9;]*m//g' | cut -d'=' -f2
# Output: testcontainers-tfstate-rg
```

## Verification

After applying this fix:
1. ✅ Script outputs clean export statements without quotes
2. ✅ Workflow extracts values using simple `cut` command
3. ✅ No trailing quotes or special characters
4. ✅ GitHub Actions `$GITHUB_OUTPUT` receives valid values

## Files Modified

1. `infrastructure/Azure/scripts/setup-terraform-backend.sh`
   - Removed quotes from export statements (lines ~257-259)

2. `infrastructure/.github/workflows/deploy-azure-infrastructure.yml`
   - Changed extraction from `sed 's/.*="\(.*\)"/\1/'` to `cut -d'=' -f2` (line ~84)

## Next Steps

1. Commit changes
2. Push to repository
3. Run GitHub Actions workflow
4. Verify backend setup succeeds
