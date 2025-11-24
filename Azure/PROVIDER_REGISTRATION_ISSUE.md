# ACTUAL ROOT CAUSE FOUND: Microsoft.Storage Provider Not Registered

## 🎯 The REAL Issue

The error `SubscriptionNotFound` was NOT about GitHub Actions masking. It was because:

**Microsoft.Storage resource provider was not registered in your Azure subscription.**

## What Happened

```bash
az storage account create ...
ERROR: (SubscriptionNotFound) Subscription 2745ace7-... was not found.
```

This confusing error message actually means: "The Microsoft.Storage API doesn't recognize your subscription because the provider isn't registered."

## Verification

```bash
$ az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv
NotRegistered
```

## Solution Applied

### 1. Registered the Provider (Manual - Already Done)

```bash
az provider register --namespace Microsoft.Storage
```

Registration takes 1-2 minutes. Check status with:
```bash
az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv
```

### 2. Updated Script (Automatic)

Added provider registration check to `setup-terraform-backend.sh`:
- Checks if Microsoft.Storage is registered
- Auto-registers if not
- Waits up to 120 seconds for registration
- Continues if already registered

## Test Again

Once registration completes (check with command above showing "Registered"), run:

```bash
cd infrastructure/Azure/scripts
./test-backend-setup-locally.sh SIT-test-$(date +%Y%m%d-%H%M)
```

## Why This Happened

New Azure subscriptions don't have all resource providers registered by default. You must explicitly register each provider you want to use:

- ✅ Microsoft.Resources - Auto-registered (for resource groups)
- ❌ Microsoft.Storage - Must register manually
- ❌ Microsoft.Compute - Must register manually
- ❌ Microsoft.Network - Must register manually
- ... and so on

## Other Providers You May Need

For full infrastructure deployment, you'll likely need:

```bash
# Check which providers are registered
az provider list --query "[?registrationState=='Registered'].namespace" -o table

# Register additional providers as needed
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.ContainerRegistry
# etc.
```

## Current Status

- ✅ Microsoft.Storage registration initiated
- ⏳ Waiting for registration to complete (1-2 minutes)
- ✅ Script updated to auto-check and register
- ⏳ Ready to test once registration completes

## Verify Registration Complete

```bash
# Check status - should show "Registered"
az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv

# When it shows "Registered", test the script
./test-backend-setup-locally.sh SIT-test-$(date +%Y%m%d-%H%M)
```

## Previous Masking Issue

The GitHub Actions masking issue we identified WAS real, but it wasn't the cause of THIS error in local testing. The masking fix is still correct and needed for GitHub Actions.

**Two separate issues:**
1. ✅ GitHub Actions masking - Fixed by removing `--subscription` parameters
2. ✅ Provider not registered - Fixed by adding provider registration check

Both fixes are now in place.
