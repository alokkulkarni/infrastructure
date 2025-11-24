# Environment Tag-Based Isolation Architecture

## Overview

This implementation uses **environment tag-based isolation** for managing multiple concurrent deployments. A single shared storage account stores all Terraform state, with each environment tag getting its own isolated container.

## Architecture

### Shared Resources
- **Resource Group**: `testcontainers-tfstate-rg` (shared across all environment tags)
- **Storage Account**: `testcontainerstfstate{8-char-subscription-id}` (shared across all environment tags)

### Environment-Specific Resources
- **Container**: One unique container per environment tag (e.g., `sit-alok-teama-20251124-1530`)
- **State File**: `terraform.tfstate` (stored in environment-specific container)
- **Infrastructure**: Each environment tag deploys completely isolated infrastructure resources

## Environment Tag Format

```
SIT-{USERID}-{TEAMID}-{YYYYMMDD}-{HHMM}
```

**Example**: `SIT-alok-teamA-20251124-1530`

**Constraints**:
- Converted to lowercase for container naming
- Underscores replaced with hyphens
- Must be URL-safe and DNS-compliant

## How It Works

### 1. Setup Backend (First Run)
```bash
# Creates shared resources if they don't exist
- Resource Group: testcontainers-tfstate-rg
- Storage Account: testcontainerstfstate2745ace7 (example)

# Creates environment-specific container
- Container: sit-alok-teama-20251124-1530
```

### 2. Terraform Backend Configuration
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "testcontainers-tfstate-rg"      # Shared
    storage_account_name = "testcontainerstfstate2745ace7"  # Shared
    container_name       = "sit-alok-teama-20251124-1530"   # Environment-specific
    key                  = "terraform.tfstate"              # Simple name in isolated container
    use_oidc             = true
  }
}
```

### 3. Multiple Environments
Each team member can run concurrent deployments:

```
Storage Account: testcontainerstfstate2745ace7/
├── Container: sit-alok-teama-20251124-1530/
│   └── terraform.tfstate
├── Container: sit-john-teamb-20251124-1545/
│   └── terraform.tfstate
├── Container: sit-sarah-teama-20251125-0900/
│   └── terraform.tfstate
└── ...
```

## Benefits

### ✅ Complete Isolation
- Each environment tag has its own container
- No state file conflicts between teams
- Safe concurrent deployments

### ✅ Easy Cleanup
- Delete entire container to clean up environment
- No impact on other environments
- Simple rollback on failure

### ✅ Cost Efficient
- Single storage account for entire team
- Pay only for storage used
- Shared RBAC management

### ✅ Resource Organization
- Clear ownership per environment tag
- Easy to track who deployed what
- Audit trail through container names

## Workflow Integration

### Deploy
```yaml
inputs:
  environment_tag:
    description: 'Environment Tag (Format: SIT-USERID-TEAMID-YYYYMMDD-HHMM)'
    required: true
    type: string
```

**Steps**:
1. Setup backend creates/reuses shared storage account
2. Creates new container for environment tag
3. Configures Terraform backend with environment-specific container
4. Deploys infrastructure with environment tag

### Rollback on Failure
```bash
# Destroys infrastructure resources
terraform destroy -target=module.vm -target=module.security ...

# Deletes environment-specific container
az storage container delete \
  --account-name testcontainerstfstate2745ace7 \
  --name sit-alok-teama-20251124-1530
```

**Result**: Complete cleanup with no impact on other environments

## Manual Operations

### List All Environments
```bash
STORAGE_ACCOUNT="testcontainerstfstate2745ace7"
az storage container list \
  --account-name $STORAGE_ACCOUNT \
  --auth-mode login \
  --query "[].name" -o table
```

### View Specific Environment State
```bash
STORAGE_ACCOUNT="testcontainerstfstate2745ace7"
CONTAINER="sit-alok-teama-20251124-1530"

az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name $CONTAINER \
  --auth-mode login \
  --query "[].{Name:name, Size:properties.contentLength}" -o table
```

### Download State for Inspection
```bash
STORAGE_ACCOUNT="testcontainerstfstate2745ace7"
CONTAINER="sit-alok-teama-20251124-1530"

az storage blob download \
  --account-name $STORAGE_ACCOUNT \
  --container-name $CONTAINER \
  --name terraform.tfstate \
  --file local-state.tfstate \
  --auth-mode login
```

### Manually Clean Up Environment
```bash
STORAGE_ACCOUNT="testcontainerstfstate2745ace7"
CONTAINER="sit-alok-teama-20251124-1530"

# Delete entire container (removes state)
az storage container delete \
  --account-name $STORAGE_ACCOUNT \
  --name $CONTAINER \
  --auth-mode login

# Purge soft-deleted Key Vault (if exists)
az keyvault list-deleted --query "[?tags.EnvironmentTag=='SIT-alok-teamA-20251124-1530'].name" -o tsv
az keyvault purge --name <vault-name>
```

## Key Differences from Previous Architecture

| Aspect | Old (Blob Path) | New (Container) |
|--------|----------------|-----------------|
| **Isolation** | Blob path: `azure/dev/TAG/terraform.tfstate` | Dedicated container per tag |
| **Container** | Single shared `tfstate` container | One container per environment tag |
| **State Key** | Long path with environment | Simple `terraform.tfstate` |
| **Cleanup** | Delete specific blob | Delete entire container |
| **Visibility** | Hard to see all environments | List containers = list environments |
| **Conflicts** | Possible with path typos | Impossible (container-level isolation) |

## Security

### RBAC Permissions Required
- **Storage Blob Data Contributor**: Read/write state files
- **Storage Account Contributor**: Create containers
- **Contributor**: Deploy infrastructure
- **User Access Administrator**: Manage OIDC

### Access Control
```bash
# Service principal has access to storage account
# Can create containers and manage blobs
# OIDC authentication via Entra ID

# Each container is isolated but accessible by same principal
# No cross-environment interference possible
```

## Troubleshooting

### Container Already Exists
```
❌ Error: Container 'sit-alok-teama-20251124-1530' already exists
```

**Solution**: Use a different environment tag (change timestamp) or clean up existing deployment

### Storage Account Name Conflict
```
❌ Error: Storage account name 'testcontainerstfstate...' is not available
```

**Solution**: 
1. Name is globally taken by another subscription
2. Check if it exists in your subscription: `az storage account show --name testcontainerstfstate...`
3. If not accessible, the script will try to use it (may be in different subscription)

### State File Not Found
```
❌ Error: Failed to retrieve backend config: blob not found
```

**Solution**: First run for this environment tag - Terraform will create new state

## Best Practices

1. **Use Consistent Format**: Always follow `SIT-USERID-TEAMID-YYYYMMDD-HHMM` format
2. **Clean Up Regularly**: Delete old environment containers to save costs
3. **Tag Resources**: All infrastructure resources should have `EnvironmentTag` tag
4. **Document Deployments**: Keep track of active environment tags
5. **Automate Cleanup**: Use workflow dispatch to destroy old environments

## Cost Considerations

- **Storage Account**: Minimal cost (~$0.02/GB/month for LRS)
- **Container Operations**: Negligible cost
- **State File Size**: Typically < 1MB per environment
- **Total Cost**: < $1/month for 100 environments

## Migration from Old Architecture

If migrating from blob-path-based isolation:

```bash
# Old: azure/dev/SIT-alok-teamA-20251124-1530/terraform.tfstate
# New: Container 'sit-alok-teama-20251124-1530' with 'terraform.tfstate'

# No automatic migration needed
# New deployments use new architecture
# Old state files remain in old location (can be manually cleaned up)
```

## Summary

This architecture provides **true isolation** at the container level while maintaining **cost efficiency** through a shared storage account. Each team member can safely deploy and destroy their environment without affecting others, and cleanup is as simple as deleting a container.
