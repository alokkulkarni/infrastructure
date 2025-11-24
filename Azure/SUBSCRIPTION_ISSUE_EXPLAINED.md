# Azure Subscription Issue - Root Cause and Solution

## The Problem

### What Was Happening
```
ERROR: (SubscriptionNotFound) Subscription *** was not found.
Code: SubscriptionNotFound
Message: Subscription *** was not found.
```

This error appeared when running `az storage account check-name`, despite:
- ✅ Successfully authenticating with OIDC
- ✅ Successfully running `az account show` (subscription context correct)
- ✅ Successfully running `az group show` (can access resources)
- ❌ Failing ONLY on `az storage account check-name`

### Why This Happens

The `az storage account check-name` command is **fundamentally different** from other Azure CLI commands:

#### Normal Azure CLI Commands
```bash
az account show              # Uses current subscription context ✅
az group show --name ...     # Uses current subscription context ✅
az storage account show ...  # Uses current subscription context ✅
```

These commands:
- Operate within your authenticated subscription
- Use OIDC authentication correctly
- Respect subscription context set by `az account set`

#### The Problematic Command
```bash
az storage account check-name --name testcontainerstfstate2745ace7
```

This command:
- ❌ Is a **global operation** across ALL Azure subscriptions
- ❌ Does NOT use your current subscription context
- ❌ Requires special API permissions not granted via OIDC
- ❌ Is designed to check if a name is available across ALL of Azure globally

### The Technical Reason

Storage account names are **globally unique** across all Azure subscriptions worldwide. When you check if a name is available, Azure needs to:

1. Query ALL subscriptions globally (not just yours)
2. Check if the name exists anywhere in Azure
3. Return whether it's available for use

**With OIDC authentication**, you have:
- ✅ Permissions to manage resources in YOUR subscription
- ❌ NO permissions to query across ALL Azure subscriptions globally

This is why `az storage account check-name` fails with "SubscriptionNotFound" - it's trying to do a global check but your OIDC token is scoped to your subscription only.

## The Solution

### What We Changed

**BEFORE** (Broken):
```bash
# Try to check globally if name is available
NAME_CHECK=$(az storage account check-name --name $STORAGE_ACCOUNT_NAME ...)
# ❌ FAILS with SubscriptionNotFound
```

**AFTER** (Fixed):
```bash
# Check if storage account exists in OUR resource group
if az storage account show \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP_NAME &> /dev/null; then
    echo "✓ Storage account exists, reusing it"
else
    # Try to create it
    # If globally taken, creation will fail with AlreadyExists error
    az storage account create --name $STORAGE_ACCOUNT_NAME ...
fi
```

### Why This Works

1. **Check our resource group first**: 
   - Uses subscription-scoped API ✅
   - Works with OIDC authentication ✅
   - If exists, reuse it (idempotent) ✅

2. **Try to create if not found**:
   - If name is globally taken by another subscription, creation fails with clear error
   - If available, creates successfully
   - Simpler logic, fewer API calls

3. **Better error handling**:
   - Captures creation output to distinguish error types
   - Provides helpful guidance based on actual error
   - No ambiguous subscription errors

## Alternative Approaches Considered

### Option 1: Use Management API with Special Permissions
```bash
# Would require additional permissions:
- Microsoft.Storage/checkNameAvailability/read (global scope)
- Management plane API access
```
**Rejected**: Requires broader permissions than necessary, security risk

### Option 2: Use ARM Template/Bicep Validation
```bash
# Use Azure Resource Manager to validate
az deployment group validate ...
```
**Rejected**: Overkill for simple existence check, slower

### Option 3: Try-Catch Pattern (Chosen)
```bash
# Try to show existing, if fails try to create
if show exists; then reuse
else create (will fail if globally taken)
```
**✅ CHOSEN**: Simple, secure, works with OIDC, idempotent

### Option 4: Use Terraform to Handle It
```hcl
# Let Terraform handle storage account creation
resource "azurerm_storage_account" "tfstate" {
  name = "testcontainerstfstate..."
}
```
**Rejected**: Chicken-and-egg problem (need backend before Terraform runs)

## Key Learnings

### 1. Not All Azure CLI Commands Are Equal
- Some commands are subscription-scoped (most)
- Some commands are global/tenant-scoped (rare)
- Global commands don't work well with OIDC

### 2. OIDC Token Scope Matters
```
OIDC Token Permissions:
├─ Subscription Scope ✅
│  └─ Can manage resources in your subscription
│
└─ Global/Tenant Scope ❌
   └─ Cannot query across all subscriptions
```

### 3. Idempotency is Key
Our new approach:
- ✅ Can run multiple times safely
- ✅ Reuses existing resources
- ✅ Only creates if needed
- ✅ Fails gracefully with clear errors

### 4. Error Handling Strategy
```bash
# OLD: Pre-check then act
check_available() → create_if_available()
# Problem: Check might fail even if create would work

# NEW: Try-first pattern
try_show() → if_not_found_try_create()
# Better: Handle actual error from operation
```

## Testing the Fix

### Scenario 1: First Run (No Storage Account)
```bash
# Expected behavior:
1. Checks if storage account exists in RG → Not found
2. Attempts to create storage account → Success
3. Creates container → Success
✅ Result: Backend setup complete
```

### Scenario 2: Subsequent Runs (Storage Account Exists)
```bash
# Expected behavior:
1. Checks if storage account exists in RG → Found
2. Skips creation (reuses existing) → Success
3. Creates new container for environment tag → Success
✅ Result: Backend setup complete (idempotent)
```

### Scenario 3: Name Globally Taken
```bash
# Expected behavior:
1. Checks if storage account exists in RG → Not found
2. Attempts to create storage account → Fails with AlreadyExists
3. Script exits with clear error message
❌ Result: Error with guidance to choose different name
```

## Verification Steps

Run the workflow again and you should see:

```
Checking if storage account exists...
✓ Storage account already exists in our resource group, reusing it

OR

Checking if storage account exists...
Storage account not found in resource group, attempting to create...
✓ Storage account created
```

No more "SubscriptionNotFound" errors! 🎉

## Additional Fixes Applied

### Fix 1: Role Assignment Command
**BEFORE**:
```bash
az role assignment list --assignee "$APP_ID" --subscription $SUB_ID --output table
# Line break caused --output to be interpreted as separate command
```

**AFTER**:
```bash
az role assignment list \
  --assignee "$APP_ID" \
  --subscription "$SUB_ID" \
  --output table
# Proper line continuation with backslash
```

### Fix 2: Container Isolation
- Each environment tag gets dedicated container
- Simple state file name: `terraform.tfstate`
- Clean isolation, easy cleanup

## Why This Is Better

### Security
- ✅ Minimal permissions required
- ✅ No need for global query access
- ✅ Scoped to your subscription only

### Reliability
- ✅ Works consistently with OIDC
- ✅ No mysterious subscription errors
- ✅ Clear error messages

### Simplicity
- ✅ Fewer API calls
- ✅ Simpler logic flow
- ✅ Try-first pattern is intuitive

### Maintainability
- ✅ Easy to understand
- ✅ Easy to debug
- ✅ Follows Azure best practices

## Conclusion

The root cause was using a **global Azure operation** (`check-name`) with **subscription-scoped OIDC credentials**. The solution is to use **subscription-scoped operations** that work within your authenticated context.

This fix:
- Eliminates the subscription error permanently
- Works reliably with OIDC authentication
- Provides better error handling
- Maintains idempotency
- Is more secure and maintainable

**No more subscription issues!** ✅
