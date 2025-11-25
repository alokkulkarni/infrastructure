# Idempotent Terraform Operations Guide

## Overview

Terraform operations are now **idempotent** - they can be run multiple times safely without failing if resources already exist. This solves the common "resource already exists" error that occurs when a previous rollback or destroy operation fails.

## How It Works

The deployment workflow now includes an **auto-import** step that:

1. ✅ **Checks Azure** for existing resources
2. ✅ **Imports** any found resources into Terraform state
3. ✅ **Continues** with apply seamlessly
4. ✅ **Handles** partial deployments gracefully

## Using Idempotent Apply

### Option 1: GitHub Actions (Recommended)

Just run or re-run the workflow - it handles everything automatically:

```yaml
# The workflow includes this step automatically:
- name: Auto-import existing resources (Idempotency)
  run: ../scripts/auto-import-resources.sh
```

**To deploy:**
1. Go to GitHub Actions
2. Run "Deploy Azure Infrastructure" workflow
3. Enter your parameters
4. If it fails and resources exist, **just re-run** - it will import and continue

### Option 2: Local Testing

Use the idempotent apply script:

```bash
cd infrastructure/Azure/scripts
./idempotent-apply.sh
```

This script:
- Initializes Terraform
- Auto-imports existing resources
- Shows you the plan
- Applies changes

### Option 3: Manual Auto-Import

Run just the auto-import step:

```bash
cd infrastructure/Azure/terraform
../scripts/auto-import-resources.sh
terraform plan
terraform apply
```

## What Gets Auto-Imported

The script checks and imports these resources if they exist:

| Resource | Terraform Address | Azure Resource |
|----------|------------------|----------------|
| Resource Group | `azurerm_resource_group.main` | testcontainers-dev-rg |
| Virtual Network | `module.networking.azurerm_virtual_network.main` | testcontainers-dev-vnet |
| Public Subnet | `module.networking.azurerm_subnet.public` | testcontainers-dev-public-subnet |
| Private Subnet | `module.networking.azurerm_subnet.private` | testcontainers-dev-private-subnet |
| NAT Gateway | `module.networking.azurerm_nat_gateway.main` | testcontainers-dev-nat |
| NAT Public IP | `module.networking.azurerm_public_ip.nat` | testcontainers-dev-nat-pip |
| NSG | `module.security.azurerm_network_security_group.main` | testcontainers-dev-nsg |
| VM | `module.vm.azurerm_linux_virtual_machine.main` | testcontainers-dev-runner |
| VM NIC | `module.vm.azurerm_network_interface.main` | testcontainers-dev-nic |
| VM Public IP | `module.vm.azurerm_public_ip.main` | testcontainers-dev-pip |

## Example Scenarios

### Scenario 1: Rollback Failed Mid-Execution

**Before (Error):**
```
Error: A resource with the ID "/subscriptions/***/resourceGroups/testcontainers-dev-rg" already exists
```

**Now (Automatic):**
```bash
# Just re-run the workflow or:
cd infrastructure/Azure/scripts
./idempotent-apply.sh

# Output:
🔄 Checking for existing resources to import...
✓ Imported: Resource Group: testcontainers-dev-rg
✓ Imported: Virtual Network: testcontainers-dev-vnet
ℹ Not in Azure: VM (will be created)
✓ Successfully imported 2 resource(s)!
```

### Scenario 2: Testing Multiple Times

**Before:** Had to manually delete resources between tests

**Now:**
```bash
# First run - creates everything
./idempotent-apply.sh

# Second run - no errors, idempotent
./idempotent-apply.sh  # ✅ Just works!

# Output:
ℹ Already in state: Resource Group: testcontainers-dev-rg
ℹ Already in state: Virtual Network: testcontainers-dev-vnet
✓ No imports needed - state is up to date!
```

### Scenario 3: Partial Deployment

**Situation:** Network resources deployed, but VM creation failed

**Solution:**
```bash
./idempotent-apply.sh

# Output:
✓ Imported: Resource Group
✓ Imported: Virtual Network
✓ Imported: Subnets
✓ Imported: NSG
ℹ Not in Azure: VM (will be created)
✓ Successfully imported 4 resource(s)!

# Now applying remaining resources...
# VM will be created successfully
```

## Manual Import (If Needed)

If you need to manually import a specific resource:

```bash
# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Import resource group
terraform import azurerm_resource_group.main \
  "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg"

# Import VNet in module
terraform import 'module.networking.azurerm_virtual_network.main' \
  "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg/providers/Microsoft.Network/virtualNetworks/testcontainers-dev-vnet"

# Verify
terraform state list
```

## Troubleshooting

### Import Script Shows Warnings

**Normal for first run:**
```
ℹ Not in Azure: Resource Group (will be created)
ℹ Not in Azure: Virtual Network (will be created)
✓ No imports needed - state is up to date!
```

This is expected when resources don't exist yet.

### Import Failed for Some Resources

**Check authentication:**
```bash
az login
az account show
```

**Check permissions:**
```bash
# Verify you have Contributor role
az role assignment list \
  --assignee $(az account show --query user.name -o tsv) \
  --output table
```

### State Still Shows Conflicts

**Option 1: Clean state and let auto-import rebuild it**
```bash
# Remove problematic resource from state
terraform state rm azurerm_resource_group.main

# Re-run auto-import
../scripts/auto-import-resources.sh
```

**Option 2: Start fresh**
```bash
# Delete resource group (if safe to do so)
az group delete --name testcontainers-dev-rg --yes

# Apply from scratch
terraform apply
```

## Benefits

### Before Idempotent Approach

❌ Rollback fails → Resources left in Azure  
❌ Re-run workflow → "Resource already exists" error  
❌ Manual cleanup required → Delete resources manually  
❌ Lost time → 15-30 minutes troubleshooting  

### After Idempotent Approach

✅ Rollback fails → Resources left in Azure  
✅ Re-run workflow → Auto-imports existing resources  
✅ Seamless continuation → Apply completes successfully  
✅ Time saved → 2-3 minutes total  

## Configuration

### Environment Variables

The auto-import script uses these variables:

```bash
# Set in GitHub Actions or export locally
export TF_VAR_project_name=testcontainers
export TF_VAR_environment=dev
export TF_VAR_location=eastus

# These determine resource names:
# Resource Group: ${project_name}-${environment}-rg
# VNet: ${project_name}-${environment}-vnet
```

### Customization

To add more resources to auto-import, edit:
```bash
vim infrastructure/Azure/scripts/auto-import-resources.sh

# Add import_if_exists calls for additional resources
import_if_exists \
    "module.my_module.azurerm_my_resource.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Service/resources/${RESOURCE_NAME}" \
    "My Resource: ${RESOURCE_NAME}"
```

## Related Documentation

- [auto-import-resources.sh](./scripts/auto-import-resources.sh) - Main auto-import script
- [idempotent-apply.sh](./scripts/idempotent-apply.sh) - Wrapper for local testing
- [import-existing-resources.sh](./scripts/import-existing-resources.sh) - Interactive import tool
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Section #2: Resource Already Exists

## Best Practices

### 1. Always Use Idempotent Scripts

```bash
# ✅ Good - idempotent
./idempotent-apply.sh

# ⚠️  Avoid - may fail on existing resources
terraform apply
```

### 2. Re-run on Failure

```bash
# GitHub Actions failed? Just click "Re-run failed jobs"
# Local apply failed? Just run ./idempotent-apply.sh again
```

### 3. Verify Import Success

```bash
# Check what's in state
terraform state list

# Verify plan is clean after import
terraform plan
# Should show only new resources, not existing ones
```

### 4. Clean Testing

```bash
# For clean testing, delete the resource group
az group delete --name testcontainers-dev-rg --yes

# Then apply creates everything fresh
./idempotent-apply.sh
```

## Summary

**Quick Command Reference:**

```bash
# Local idempotent apply (recommended)
cd infrastructure/Azure/scripts
./idempotent-apply.sh

# Just auto-import (no apply)
cd infrastructure/Azure/terraform
../scripts/auto-import-resources.sh

# Check what's in state
terraform state list

# Manual import if needed
terraform import azurerm_resource_group.main "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg"
```

**Key Takeaway:** Terraform operations are now idempotent - just re-run them if they fail, and they'll automatically handle existing resources. No more "resource already exists" errors! 🎉
