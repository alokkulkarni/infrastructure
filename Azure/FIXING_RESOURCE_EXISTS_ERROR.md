# Quick Fix: Resource Already Exists Error

## The Problem

```
Error: A resource with the ID "/subscriptions/***/resourceGroups/testcontainers-dev-rg" already exists - 
to be managed via Terraform this resource needs to be imported into the State.
```

**What happened:** A previous Terraform operation (like `destroy` or `rollback`) failed partway through, leaving resources in Azure but not in Terraform's state file.

## Quick Decision Tree

```
Does the resource group have data you need?
│
├── YES (Production/Important data)
│   └── ✅ Solution 1: Import resources into Terraform state
│
└── NO (Testing/Development)
    └── ✅ Solution 2: Delete everything and start fresh
```

---

## Solution 1: Import Resources (SAFE - Keeps Existing Resources)

### Option A: Automated Import (Easiest)

```bash
cd infrastructure/Azure/terraform
../scripts/import-existing-resources.sh
```

The script will:
- ✅ Check what exists in Azure
- ✅ Import resource group into Terraform state
- ✅ Show you what else might need importing
- ✅ Verify the import succeeded

### Option B: Manual Import

```bash
cd infrastructure/Azure/terraform

# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Import the resource group
terraform import azurerm_resource_group.main \
  "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg"

# Verify
terraform state list
terraform plan
```

### After Import

```bash
# Check what Terraform wants to do
terraform plan

# If plan looks good, apply remaining resources
terraform apply
```

---

## Solution 2: Delete and Recreate (FAST - Loses Existing Resources)

⚠️ **WARNING:** This deletes ALL resources in the resource group!

### Step 1: Delete Resource Group

```bash
# Delete everything
az group delete --name testcontainers-dev-rg --yes --no-wait

# Wait for deletion (2-5 minutes)
az group wait --name testcontainers-dev-rg --deleted

# Verify deletion
az group exists --name testcontainers-dev-rg
# Should return: false
```

### Step 2: Clean State File (GitHub Actions Only)

If using GitHub Actions, also delete the state container:

```bash
# Get backend storage account name
STORAGE_ACCOUNT="testcontainerstfstate2745ace7"
CONTAINER_NAME="sit-test-container"  # Use your actual container name

# Delete the container (removes state file)
az storage container delete \
  --name "${CONTAINER_NAME}" \
  --account-name "${STORAGE_ACCOUNT}" \
  --auth-mode login

# Verify deletion
az storage container list \
  --account-name "${STORAGE_ACCOUNT}" \
  --auth-mode login
```

### Step 3: Re-run Terraform

```bash
cd infrastructure/Azure/terraform

# Initialize backend (will create new state)
terraform init -reconfigure

# Apply from scratch
terraform apply
```

Or re-run GitHub Actions workflow.

---

## Solution 3: GitHub Actions Workflow Cleanup

If error occurred during GitHub Actions workflow:

### Using GitHub UI

1. Go to: `https://github.com/YOUR_ORG/YOUR_REPO/actions`
2. Find the failed workflow run
3. Click **"Re-run failed jobs"**
4. If that fails, manually clean up:

```bash
# Connect to Azure
az login

# Delete resource group
az group delete --name testcontainers-dev-rg --yes

# Delete state container
az storage container delete \
  --name sit-test-container \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login
```

5. Run workflow again from GitHub Actions UI

---

## Common Scenarios

### Scenario 1: Rollback Failed

**Symptom:** Previous `terraform destroy` failed, some resources still exist

**Solution:** Delete and recreate (Solution 2)

**Why:** State is inconsistent, easier to start fresh

**Steps:**
```bash
az group delete --name testcontainers-dev-rg --yes --no-wait
# Wait 2-5 minutes
terraform apply
```

### Scenario 2: Testing Multiple Environments

**Symptom:** Created resources manually, now want Terraform to manage them

**Solution:** Import resources (Solution 1)

**Why:** Don't lose existing configuration

**Steps:**
```bash
cd infrastructure/Azure/terraform
../scripts/import-existing-resources.sh
terraform plan
terraform apply
```

### Scenario 3: Lost State File

**Symptom:** State file deleted/corrupted, but resources exist in Azure

**Solution:** Import all resources (Solution 1)

**Why:** Resources exist and may have data

**Steps:**
```bash
# Import resource group
terraform import azurerm_resource_group.main "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg"

# Import VNet
terraform import 'module.networking.azurerm_virtual_network.main' \
  "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg/providers/Microsoft.Network/virtualNetworks/testcontainers-dev-vnet"

# Continue for other resources...
```

### Scenario 4: GitHub Actions Failed Mid-Apply

**Symptom:** Workflow showed "Error: Process completed with exit code 1"

**Solution:** Clean up and retry (Solution 2 or 3)

**Why:** Partial deployment, state unclear

**Steps:**
```bash
# Clean everything
az group delete --name testcontainers-dev-rg --yes
az storage container delete --name sit-test-container --account-name testcontainerstfstate2745ace7 --auth-mode login

# Re-run workflow from GitHub UI
```

---

## How to Check What Exists

### Check Resource Group

```bash
# Does resource group exist?
az group exists --name testcontainers-dev-rg

# Show resource group details
az group show --name testcontainers-dev-rg

# List all resources in group
az resource list --resource-group testcontainers-dev-rg --output table
```

### Check Terraform State

```bash
cd infrastructure/Azure/terraform

# List resources in state
terraform state list

# Show specific resource
terraform state show azurerm_resource_group.main

# Check if state file exists
ls -la .terraform/
```

### Check State File in Azure Storage

```bash
# List containers
az storage container list \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login

# List blobs in container
az storage blob list \
  --container-name sit-test-container \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login \
  --output table
```

---

## Prevention Tips

1. **Always Monitor Destroy Operations**
   ```bash
   # Watch the destroy carefully
   terraform destroy -auto-approve
   
   # Verify everything was deleted
   az group exists --name testcontainers-dev-rg
   ```

2. **Use Environment Tags for Testing**
   ```bash
   # Each test gets unique environment
   terraform apply -var="environment_tag=SIT-test-$(date +%Y%m%d-%H%M)"
   
   # Easy to identify and clean up later
   az group list --query "[?tags.EnvironmentTag=='SIT-test-20251124-1500']"
   ```

3. **Enable State File Versioning** (Already configured)
   ```bash
   # Verify versioning is enabled
   az storage blob service-properties show \
     --account-name testcontainerstfstate2745ace7 \
     --auth-mode login \
     --query isVersioningEnabled
   ```

4. **Test in Dev First**
   ```bash
   # Always test destroy in dev environment
   terraform apply -var="environment=dev"
   terraform destroy -var="environment=dev"
   
   # Then deploy to production
   terraform apply -var="environment=prod"
   ```

5. **Check State Before Destroy**
   ```bash
   # See what will be destroyed
   terraform state list
   
   # Confirm with plan
   terraform plan -destroy
   
   # Then destroy
   terraform destroy
   ```

---

## Troubleshooting Import

### Import Failed: "Resource not found"

**Cause:** Resource ID is incorrect or resource doesn't exist

**Solution:**
```bash
# Verify resource exists
az group show --name testcontainers-dev-rg

# Check exact resource ID
az group show --name testcontainers-dev-rg --query id -o tsv

# Use exact ID in import
terraform import azurerm_resource_group.main "$(az group show --name testcontainers-dev-rg --query id -o tsv)"
```

### Import Succeeded but Plan Shows Changes

**Cause:** Terraform configuration doesn't match Azure resource

**Solution:**
```bash
# Show what's different
terraform plan

# Update terraform configuration to match Azure
vim main.tf

# Verify plan is clean
terraform plan
# Should show: "No changes. Your infrastructure matches the configuration."
```

### Need to Import Module Resources

**Cause:** Resources inside modules require special syntax

**Solution:**
```bash
# Module resources use single quotes and module path
terraform import 'module.networking.azurerm_virtual_network.main' \
  "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg/providers/Microsoft.Network/virtualNetworks/testcontainers-dev-vnet"

terraform import 'module.vm.azurerm_linux_virtual_machine.main' \
  "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/testcontainers-dev-rg/providers/Microsoft.Compute/virtualMachines/testcontainers-dev-runner"
```

---

## When to Use Which Solution

| Situation | Use Solution | Reason |
|-----------|-------------|---------|
| Production environment | **1: Import** | Preserve data and resources |
| Development/Testing | **2: Delete** | Faster, cleaner start |
| Rollback failed | **2: Delete** | State is inconsistent |
| Manual resources exist | **1: Import** | Preserve existing work |
| State file lost | **1: Import** | Recover state from Azure |
| GitHub Actions failed | **2 or 3: Delete** | Start fresh, avoid state issues |
| Multiple environments | **1: Import** | Keep other environments |
| Learning/Experimenting | **2: Delete** | Quick iteration |

---

## Related Documentation

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Section #2: Resource Already Exists
- [Azure/scripts/import-existing-resources.sh](./scripts/import-existing-resources.sh) - Automated import script
- [Terraform Import Documentation](https://www.terraform.io/cli/import)
- [Azure CLI Resource Group Commands](https://docs.microsoft.com/en-us/cli/azure/group)

---

## Summary

**Quick Import (Safe):**
```bash
cd infrastructure/Azure/terraform
../scripts/import-existing-resources.sh
terraform apply
```

**Quick Delete (Fast):**
```bash
az group delete --name testcontainers-dev-rg --yes --no-wait
# Wait 2-5 minutes
cd infrastructure/Azure/terraform
terraform apply
```

**Choose Based On:**
- 🔒 **Data matters** → Import
- ⚡ **Speed matters** → Delete
- 🧪 **Testing** → Delete
- 🏭 **Production** → Import (ONLY)
