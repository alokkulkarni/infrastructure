# Emergency Cleanup Quick Start

## When to Use This Script

Use `emergency-cleanup.sh` when:
- The destroy workflow reports "0 resources destroyed" but resources still exist
- You need to clean up resources tracked in an old/misplaced state file
- State file path has changed and you need to migrate

## Prerequisites

1. **Azure CLI** installed and authenticated:
   ```bash
   az login
   ```

2. **Terraform** installed (version 1.6.0 or compatible):
   ```bash
   terraform version
   ```

3. **Permissions** in Azure:
   - Reader on subscription
   - Contributor on resource groups
   - Storage Blob Data Contributor OR Storage Account Key access

## Usage

### Step 1: Review Configuration

Edit `emergency-cleanup.sh` and verify:

```bash
STORAGE_ACCOUNT="tctfstate2745ace7"           # Your storage account
CONTAINER="sit-alok-teama-20251125-0921"      # Your container
OLD_STATE_BLOB="terraform.tfstate"            # State file name
ENVIRONMENT_TAG="SIT-Alok-TeamA-20251125-0921" # Environment tag
```

### Step 2: Run the Script

```bash
cd infrastructure/Azure/scripts
./emergency-cleanup.sh
```

### Step 3: Confirmations

You'll be asked to confirm **twice**:

1. **Initial confirmation**: Type `destroy` to proceed
2. **Final confirmation**: Type `yes` after reviewing the plan

### Step 4: Follow Prompts

The script will ask additional questions:
- Force delete resource group? (if not empty)
- Purge soft-deleted Key Vaults? (to free up names)

## What the Script Does

1. ✅ Downloads the old state file from Azure Storage
2. ✅ Configures Terraform to use the local state
3. ✅ Creates necessary terraform.tfvars
4. ✅ Initializes Terraform
5. ✅ Shows destruction plan
6. ✅ Destroys resources in dependency order:
   - VM and Key Vault resources
   - Security resources (NSG)
   - Networking resources (VNet, IPs, NAT Gateway)
   - Resource group
7. ✅ Verifies cleanup
8. ✅ Purges soft-deleted Key Vaults (optional)
9. ✅ Cleans up local state files

## Expected Output

```
========================================
  Emergency Infrastructure Cleanup
========================================

Configuration:
  Storage Account: tctfstate2745ace7
  Container: sit-alok-teama-20251125-0921
  State File: terraform.tfstate
  Environment Tag: SIT-Alok-TeamA-20251125-0921

⚠️  WARNING: This will DESTROY all infrastructure!
This action cannot be undone.

Are you sure you want to proceed? Type 'destroy' to confirm: destroy

Working directory: /path/to/infrastructure/Azure/terraform

Step 1: Downloading state file from Azure Storage...
✅ State file downloaded successfully

State file contains approximately 22 resource references

Step 2: Configuring Terraform to use local state...
✅ Backend configured for local state

Step 3: Creating terraform.tfvars...
✅ Variables configured

Step 4: Initializing Terraform...
[Terraform init output]

Step 5: Planning destruction...
[Terraform plan output]

Proceed with destroying ALL resources? Type 'yes' to continue: yes

Step 6: Destroying infrastructure...
[Destruction progress]

✅ Terraform destroy completed

Step 7: Verifying cleanup...
✅ Resource group successfully deleted

Step 8: Checking for soft-deleted Key Vaults...
[Key Vault cleanup]

========================================
  Emergency Cleanup Completed
========================================
```

## Troubleshooting

### Permission Denied on Storage

```bash
# Get storage account key
az storage account keys list \
  --account-name tctfstate2745ace7 \
  --resource-group testcontainers-tfstate-rg \
  --query "[0].value" \
  -o tsv
```

### Resource Group Still Exists

If resources remain after destroy:

```bash
# List remaining resources
az resource list \
  --resource-group testcontainers-dev-rg \
  --query "[].{Name:name, Type:type}" \
  -o table

# Force delete (use with caution)
az group delete \
  --name testcontainers-dev-rg \
  --yes \
  --no-wait
```

### Soft-Deleted Key Vault Blocking

If you get "vault name already exists" errors:

```bash
# List soft-deleted vaults
az keyvault list-deleted

# Purge specific vault
az keyvault purge --name {vault-name}
```

### State File Not Found

Verify the blob exists:

```bash
az storage blob list \
  --account-name tctfstate2745ace7 \
  --container-name sit-alok-teama-20251125-0921 \
  --account-key {key} \
  --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" \
  -o table
```

## After Cleanup

1. ✅ Verify all resources deleted in Azure Portal
2. ✅ Check for orphaned resources (public IPs, disks, etc.)
3. ✅ Confirm Key Vaults are purged (if needed for next deployment)
4. ✅ Future deployments will use the correct nested state path

## Safety Features

- **Two-stage confirmation** required
- **Plan shown** before destruction
- **Dependency-ordered** destruction prevents errors
- **Backups** created of existing local state
- **Verification** steps after cleanup
- **No auto-approve** for final destroy (explicit confirmation)

## Important Notes

⚠️ **This is a ONE-TIME script** for migration purposes only.

⚠️ **After running this script**, all future deployments should use the deploy workflow with the corrected state file path.

⚠️ **Do NOT run this script** if the destroy workflow is already working correctly.

## See Also

- [STATE_FILE_MIGRATION.md](STATE_FILE_MIGRATION.md) - Detailed explanation of the fix
- [INFRA_DEPLOYMENT_GUIDE.md](../INFRA_DEPLOYMENT_GUIDE.md) - Standard deployment process
