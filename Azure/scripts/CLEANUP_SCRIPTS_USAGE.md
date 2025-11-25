# Cleanup Scripts Usage Guide

This guide explains how to use the parameterized cleanup scripts for Azure infrastructure.

## Overview

Two cleanup scripts are available, each serving different purposes:

1. **`emergency-cleanup.sh`** - Terraform-based cleanup (preferred method)
2. **`force-cleanup.sh`** - Azure CLI-based cleanup (when Terraform fails)

Both scripts now accept command-line arguments for flexibility across different deployments.

---

## emergency-cleanup.sh

**Purpose**: Clean up infrastructure using Terraform with the state file from Azure Storage.

**When to use**: 
- Normal cleanup scenario
- State file exists and is accessible
- Want Terraform to handle dependency ordering

### Command-Line Options

```bash
Usage: ./emergency-cleanup.sh [OPTIONS]

Options:
  -a, --account NAME         Storage Account name (required)
  -c, --container NAME       Storage Container name (required)
  -s, --state-file PATH      State file blob path (default: terraform.tfstate)
  -t, --tag TAG              Environment tag (optional, auto-detected from path)
  -r, --resource-group NAME  Resource group for tfstate (default: testcontainers-tfstate-rg)
  -h, --help                 Show help message
```

### Usage Examples

#### Example 1: Flat State File Path
```bash
# State file at root of container: terraform.tfstate
./emergency-cleanup.sh \
  -a tctfstate2745ace7 \
  -c sit-alok-teama-20251125-0921 \
  -s terraform.tfstate
```

#### Example 2: Nested State File Path
```bash
# State file in nested path: azure/dev/SIT-Team/terraform.tfstate
./emergency-cleanup.sh \
  -a tctfstate2745ace7 \
  -c dev \
  -s azure/dev/SIT-Team-20251125/terraform.tfstate \
  -t SIT-Team-20251125
```

#### Example 3: Auto-Detect Environment Tag
```bash
# Environment tag auto-detected from state path
./emergency-cleanup.sh \
  -a tctfstate2745ace7 \
  -c dev \
  -s azure/dev/SIT-Team-20251125/terraform.tfstate
```

#### Example 4: Custom State Resource Group
```bash
# Using a different resource group for state storage
./emergency-cleanup.sh \
  -a tctfstatecustom \
  -c production \
  -s terraform.tfstate \
  -r custom-tfstate-rg
```

### What It Does

1. **Downloads state file** from Azure Storage
2. **Removes Key Vault resources** from state (permissions workaround)
3. **Runs `terraform destroy`** with `-refresh=false` (avoids permission issues)
4. **Deletes Key Vaults** using Azure CLI
5. **Purges soft-deleted Key Vaults**
6. **Cleans up orphaned state entries** (resources already deleted)
7. **Deletes state file** from Azure Storage

### Environment Tag Detection

The script automatically extracts the environment tag from nested state paths:
- Pattern: `azure/{env}/{TAG}/terraform.tfstate`
- Falls back to container name if extraction fails
- Can be overridden with `-t` option

---

## force-cleanup.sh

**Purpose**: Force deletion using Azure CLI when Terraform cleanup fails.

**When to use**:
- Terraform destroy fails repeatedly
- State file is corrupted or inaccessible
- Need to bypass Terraform entirely

### Command-Line Options

```bash
Usage: ./force-cleanup.sh [OPTIONS]

Options:
  -g, --resource-group NAME  Azure Resource Group to delete (required)
  -t, --tag TAG              Environment tag (optional, for Key Vault cleanup)
  -a, --account NAME         Storage Account name (optional, for state cleanup)
  -c, --container NAME       Storage Container name (optional, for state cleanup)
  -s, --state-file PATH      State file blob path (optional, for state cleanup)
  -h, --help                 Show help message
```

### Usage Examples

#### Example 1: Basic Cleanup (Just Delete Resources)
```bash
# Delete resource group only
./force-cleanup.sh -g testcontainers-dev-rg
```

#### Example 2: Cleanup with Environment Tag
```bash
# Delete resources + purge Key Vaults by tag
./force-cleanup.sh \
  -g testcontainers-dev-rg \
  -t SIT-Team-20251125
```

#### Example 3: Full Cleanup (Resources + State File)
```bash
# Delete everything including state file
./force-cleanup.sh \
  -g testcontainers-dev-rg \
  -t SIT-Team-20251125 \
  -a tctfstate2745ace7 \
  -c dev \
  -s azure/dev/SIT-Team-20251125/terraform.tfstate
```

### What It Does

1. **Checks if resource group exists**
2. **Lists all resources** in the group
3. **Deletes Key Vaults** individually (handles permissions better)
4. **Deletes VMs** (deallocates first)
5. **Deletes entire resource group** (--no-wait for async)
6. **Purges soft-deleted Key Vaults** by tag or resource group
7. **Optionally deletes state file** from Azure Storage

---

## Choosing the Right Script

| Scenario | Recommended Script |
|----------|-------------------|
| Normal cleanup | `emergency-cleanup.sh` |
| First-time cleanup | `emergency-cleanup.sh` |
| State file exists | `emergency-cleanup.sh` |
| Terraform fails | `force-cleanup.sh` |
| State corrupted | `force-cleanup.sh` |
| Permission errors | `force-cleanup.sh` |
| Already-deleted resources | `emergency-cleanup.sh` (handles this) |

---

## Common Scenarios

### Scenario 1: Clean Up After Failed Deployment

```bash
# Try Terraform first
./emergency-cleanup.sh -a tctfstate2745ace7 -c dev -s terraform.tfstate

# If that fails, use force cleanup
./force-cleanup.sh -g testcontainers-dev-rg
```

### Scenario 2: Multiple Environments in Same Container

```bash
# Dev environment
./emergency-cleanup.sh -a tctfstate2745ace7 -c shared -s azure/dev/my-tag/terraform.tfstate

# Staging environment
./emergency-cleanup.sh -a tctfstate2745ace7 -c shared -s azure/staging/my-tag/terraform.tfstate

# Production environment
./emergency-cleanup.sh -a tctfstate2745ace7 -c shared -s azure/prod/my-tag/terraform.tfstate
```

### Scenario 3: Team Collaboration

```bash
# Team A's environment
./emergency-cleanup.sh -a tctfstate2745ace7 -c dev -s azure/dev/TeamA-20251125/terraform.tfstate

# Team B's environment
./emergency-cleanup.sh -a tctfstate2745ace7 -c dev -s azure/dev/TeamB-20251201/terraform.tfstate
```

---

## Troubleshooting

### Issue: "State file not found"
**Solution**: Verify the state file path using:
```bash
az storage blob list \
  --account-name tctfstate2745ace7 \
  --container-name dev \
  --query "[].name" -o table
```

### Issue: "Permission denied on Key Vault"
**Solution**: This is expected. The script removes Key Vault from state and uses Azure CLI instead.

### Issue: "Resource not found"
**Solution**: Resource was already deleted (cascading delete). Script handles this automatically.

### Issue: "Cannot find resource group"
**Solution**: Verify resource group name:
```bash
az group list --query "[].name" -o table
```

### Issue: Script shows help instead of running
**Solution**: Check if you provided required arguments. Use `-h` to see requirements.

---

## Verification Commands

After running cleanup scripts, verify deletion:

```bash
# Check resource group
az group show --name testcontainers-dev-rg
# Expected: ResourceGroupNotFound

# Check soft-deleted Key Vaults
az keyvault list-deleted

# Check state file
az storage blob list \
  --account-name tctfstate2745ace7 \
  --container-name dev \
  --query "[?name=='terraform.tfstate'].name" -o table
# Expected: empty
```

---

## Best Practices

1. **Always use `emergency-cleanup.sh` first** - It's safer and maintains proper Terraform workflow
2. **Verify state file path** before running - Use `az storage blob list` to confirm
3. **Keep environment tags consistent** - Use same tag format across deployments
4. **Use force cleanup as last resort** - Only when Terraform cleanup fails
5. **Check Azure Portal** after cleanup - Confirm resources are actually gone
6. **Document your cleanup** - Note which script was used and why
7. **Test in dev first** - Try cleanup on development environment before production

---

## Script Comparison

| Feature | emergency-cleanup.sh | force-cleanup.sh |
|---------|---------------------|------------------|
| Method | Terraform destroy | Azure CLI delete |
| State File | Required | Optional |
| Dependency Order | Handled by Terraform | Manual (KV, VMs first) |
| Permissions | May have issues | More flexible |
| Speed | Slower (safer) | Faster (riskier) |
| Cleanup Orphans | Yes | No |
| State File Deletion | Yes | Optional |

---

## Getting Help

Both scripts have built-in help:

```bash
./emergency-cleanup.sh -h
./force-cleanup.sh -h
```

For more information, see:
- `EMERGENCY_CLEANUP_GUIDE.md` - Detailed troubleshooting
- `../terraform/README.md` - Infrastructure documentation
- `INFRA_DEPLOYMENT_GUIDE.md` - Deployment procedures
