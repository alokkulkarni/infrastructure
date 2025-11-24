# Azure OIDC Quick Reference Card

## 🚨 The Problem
```
Error: Either an Access Key / SAS Token or the Resource Group 
for the Storage Account must be specified - or Azure AD 
Authentication must be enabled

OR

Error: Failed to get existing workspaces: containers.Client#ListBlobs: 
Invalid input: `accountName` cannot be an empty string.
```

## ✅ The Solution (4 Changes)

### 1. Backend Setup Script
**Added RBAC**: Storage Blob Data Contributor + Storage Account Contributor

### 2. GitHub Workflow  
**Added**: `ARM_USE_AZUREAD: true` in all Terraform init steps

### 3. Pass ARM_CLIENT_ID
**Added**: `ARM_CLIENT_ID` to backend setup script environment

### 4. Fix Output Extraction
**Fixed**: Strip ANSI color codes when extracting backend values from setup script

## 🔑 Required Environment Variables

```bash
# In GitHub Actions workflow:
ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
ARM_USE_OIDC: true
ARM_USE_AZUREAD: true  # ← THE CRITICAL ONE!
```

## 📋 Required RBAC Roles

| Role | Scope | Auto? |
|------|-------|-------|
| Storage Blob Data Contributor | Storage Account | ✅ Yes |
| Storage Account Contributor | Storage Account | ✅ Yes |
| Contributor | Subscription | ❌ Manual |
| User Access Administrator | Subscription | ❌ Manual |

## 🧪 Quick Test

```bash
# 1. Set env vars
export AZURE_CLIENT_ID="<your-id>"
export AZURE_TENANT_ID="<your-tenant>"
export AZURE_SUBSCRIPTION_ID="<your-subscription>"

# 2. Run verification
cd infrastructure/Azure
./scripts/verify-oidc-config.sh

# 3. Expected result:
# ✓ All checks passed! OIDC is properly configured
```

## 🔍 What to Check in Logs

### ✅ Success Indicators

**Setup Backend:**
```
✓ RBAC permissions configured
```

**Terraform Init:**
```
Successfully configured the backend "azurerm"!
```

### ❌ Failure Indicators

**Missing ARM_USE_AZUREAD:**
```
Error: Either an Access Key / SAS Token... must be specified
```

**Missing RBAC:**
```
Error: insufficient privileges
```

## 🛠️ Manual RBAC Fix (if needed)

```bash
STORAGE_ID="/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/testcontainers-tfstate-rg/providers/Microsoft.Storage/storageAccounts/testcontainerstfstate..."

az role assignment create \
  --assignee $AZURE_CLIENT_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID

az role assignment create \
  --assignee $AZURE_CLIENT_ID \
  --role "Storage Account Contributor" \
  --scope $STORAGE_ID
```

## 📖 Documentation Files

| File | What's Inside |
|------|---------------|
| `FINAL_SOLUTION_SUMMARY.md` | Complete overview |
| `OIDC_BACKEND_FIX.md` | Detailed fix guide |
| `OIDC_GUIDE.md` | Full OIDC setup guide |
| `verify-oidc-config.sh` | Configuration checker |

## 🎯 One-Liner

**The fix**: Add `ARM_USE_AZUREAD=true` + auto-assign storage RBAC roles.

---

**Status**: ✅ Azure OIDC now works seamlessly like AWS!
