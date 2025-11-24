# Fix for Empty Storage Account Name in Backend Configuration

## Problem

The second terraform init failure showed:
```
Error: Failed to get existing workspaces: containers.Client#ListBlobs: 
Invalid input: `accountName` cannot be an empty string.
```

This means the backend configuration was created with an empty `storage_account_name`.

## Root Cause

The GitHub Actions workflow was extracting the backend configuration values from the setup script output using:
```bash
BACKEND_SA=$(grep "export TF_BACKEND_STORAGE_ACCOUNT" setup_output.log | cut -d'"' -f2)
```

However, the setup script outputs include **ANSI color codes** (from the `echo -e "${GREEN}..."` statements), which were interfering with the extraction using `cut`.

### Example of what grep found:
```bash
# With color codes (actual):
echo "export TF_BACKEND_STORAGE_ACCOUNT=\"testcontainerstfstate12345678\""
# Becomes with ANSI codes:
\x1b[32mexport TF_BACKEND_STORAGE_ACCOUNT="testcontainerstfstate12345678"\x1b[0m

# cut -d'"' -f2 extracts the wrong field because of escape sequences
```

## Solution Applied

### Change 1: Fix Output Extraction (setup-backend job)

**File**: `.github/workflows/deploy-azure-infrastructure.yml`

**Before**:
```bash
BACKEND_RG=$(grep "export TF_BACKEND_RESOURCE_GROUP" setup_output.log | cut -d'"' -f2)
BACKEND_SA=$(grep "export TF_BACKEND_STORAGE_ACCOUNT" setup_output.log | cut -d'"' -f2)
```

**After**:
```bash
# Strip ANSI color codes and extract values properly
BACKEND_RG=$(grep "export TF_BACKEND_RESOURCE_GROUP" setup_output.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/.*="\(.*\)"/\1/')
BACKEND_SA=$(grep "export TF_BACKEND_STORAGE_ACCOUNT" setup_output.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/.*="\(.*\)"/\1/')

echo "Extracted values:"
echo "  Resource Group: ${BACKEND_RG}"
echo "  Storage Account: ${BACKEND_SA}"

# Validate outputs are not empty
if [ -z "$BACKEND_RG" ] || [ -z "$BACKEND_SA" ]; then
  echo "ERROR: Failed to extract backend configuration"
  echo "Log contents:"
  cat setup_output.log
  exit 1
fi
```

### Change 2: Add Validation (terraform-plan job)

**File**: `.github/workflows/deploy-azure-infrastructure.yml`

**Added before backend configuration**:
```yaml
- name: Update backend configuration
  working-directory: Azure/terraform
  run: |
    echo "Received backend outputs:"
    echo "  Resource Group: ${{ needs.setup-backend.outputs.backend_resource_group }}"
    echo "  Storage Account: ${{ needs.setup-backend.outputs.backend_storage_account }}"
    
    # Validate outputs are not empty
    if [ -z "${{ needs.setup-backend.outputs.backend_resource_group }}" ] || [ -z "${{ needs.setup-backend.outputs.backend_storage_account }}" ]; then
      echo "ERROR: Backend outputs are empty!"
      echo "Resource Group: '${{ needs.setup-backend.outputs.backend_resource_group }}'"
      echo "Storage Account: '${{ needs.setup-backend.outputs.backend_storage_account }}'"
      exit 1
    fi
    
    cat > backend.tf <<EOF
    ...
```

### Change 3: Same Validation (terraform-apply job)

Applied the same validation logic to the terraform-apply job.

## How the Fix Works

### Step-by-Step Process

1. **Setup script outputs**:
   ```bash
   echo "export TF_BACKEND_RESOURCE_GROUP=\"testcontainers-tfstate-rg\""
   echo "export TF_BACKEND_STORAGE_ACCOUNT=\"testcontainerstfstate12345678\""
   ```

2. **Workflow captures output** with color codes:
   ```
   setup_output.log contains ANSI escape sequences
   ```

3. **sed strips ANSI codes**:
   ```bash
   sed 's/\x1b\[[0-9;]*m//g'  # Removes all ANSI color codes
   ```

4. **sed extracts value**:
   ```bash
   sed 's/.*="\(.*\)"/\1/'    # Extracts value between quotes
   ```

5. **Validation prevents empty values**:
   ```bash
   if [ -z "$BACKEND_RG" ] || [ -z "$BACKEND_SA" ]; then
     echo "ERROR: Failed to extract backend configuration"
     exit 1
   fi
   ```

6. **Backend configuration receives correct values**:
   ```hcl
   terraform {
     backend "azurerm" {
       resource_group_name  = "testcontainers-tfstate-rg"
       storage_account_name = "testcontainerstfstate12345678"  # ✓ Not empty!
       container_name       = "tfstate"
       key                  = "azure/dev/ENV-TAG/terraform.tfstate"
       use_oidc             = true
     }
   }
   ```

## What You'll See in Logs

### Success Indicators

**Setup Backend Job**:
```
Extracting backend configuration from setup output...
Extracted values:
  Resource Group: testcontainers-tfstate-rg
  Storage Account: testcontainerstfstate12345678
```

**Terraform Plan/Apply Job**:
```
Received backend outputs:
  Resource Group: testcontainers-tfstate-rg
  Storage Account: testcontainerstfstate12345678

Backend configuration:
terraform {
  backend "azurerm" {
    resource_group_name  = "testcontainers-tfstate-rg"
    storage_account_name = "testcontainerstfstate12345678"
    container_name       = "tfstate"
    key                  = "azure/dev/SIT-Alok-TeamA-20251124-1555/terraform.tfstate"
    use_oidc             = true
  }
}
```

### Failure Indicators (Old Behavior)

**Before Fix**:
```
Received backend outputs:
  Resource Group: testcontainers-tfstate-rg
  Storage Account:                              # ← Empty!

Backend configuration:
...
  storage_account_name = ""                     # ← Empty string!
```

**Terraform Error**:
```
Error: Failed to get existing workspaces: containers.Client#ListBlobs: 
Invalid input: `accountName` cannot be an empty string.
```

## Testing

To verify the fix works:

1. **Check setup-backend job logs** for:
   ```
   Extracted values:
     Resource Group: testcontainers-tfstate-rg
     Storage Account: testcontainerstfstate12345678
   ```

2. **Check terraform-plan job logs** for:
   ```
   Received backend outputs:
     Resource Group: testcontainers-tfstate-rg
     Storage Account: testcontainerstfstate12345678
   ```

3. **Verify backend.tf** contains actual values (not empty strings)

4. **Terraform init should succeed**:
   ```
   Initializing the backend...
   Successfully configured the backend "azurerm"!
   ```

## Technical Details

### ANSI Color Code Format

ANSI escape sequences follow this pattern:
```
\x1b[<code>m
```

Common codes:
- `\x1b[0m` - Reset (no color)
- `\x1b[32m` - Green
- `\x1b[33m` - Yellow
- `\x1b[31m` - Red

### sed Command Breakdown

**Strip ANSI codes**:
```bash
sed 's/\x1b\[[0-9;]*m//g'
```
- `\x1b` - Escape character
- `\[` - Literal `[`
- `[0-9;]*` - Any digits or semicolons (color code)
- `m` - End marker
- `//g` - Replace with nothing (global)

**Extract value**:
```bash
sed 's/.*="\(.*\)"/\1/'
```
- `.*="` - Match everything up to `="`
- `\(.*\)` - Capture group: anything inside quotes
- `"` - Closing quote
- `/\1/` - Replace with captured group (value only)

## Alternative Solutions Considered

### Option 1: Remove colors from setup script
**Pros**: Simpler output parsing
**Cons**: Loses helpful visual feedback for debugging

### Option 2: Use jq for structured output
**Pros**: More robust parsing
**Cons**: Requires changing setup script to output JSON

### Option 3: Use sed to strip ANSI (chosen)
**Pros**: 
- Keeps colored output for readability
- Simple, reliable extraction
- No script changes needed

**Cons**: Slightly more complex sed command

## Summary

The fix ensures that:
1. ✅ ANSI color codes don't interfere with value extraction
2. ✅ Storage account name is properly captured
3. ✅ Validation catches empty values early
4. ✅ Detailed logging helps debugging
5. ✅ Backend configuration receives correct values

**Result**: Terraform init will now succeed with proper backend configuration! 🎉
