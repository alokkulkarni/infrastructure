# Multi-Team Environment Isolation Guide (Azure)

## Overview

The Azure infrastructure deployment workflow now supports **multi-team environment isolation** through an environment tagging system. This allows different teams and testers to create isolated virtual environments without resource conflicts or state file collisions.

## Environment Tag Format

**Required Format**: `SIT-USERID-TEAMID-YYYYMMDD-HHMM`

**Components**:
- `SIT`: Static prefix (System Integration Testing)
- `USERID`: User identifier (e.g., username or ID)
- `TEAMID`: Team identifier
- `YYYYMMDD`: Date (Year-Month-Day)
- `HHMM`: Time (Hour-Minute, 24-hour format)

**Examples**:
- `SIT-john-teamA-20251120-1430`
- `SIT-sarah-backend-20251120-1545`
- `SIT-mike-qa-20251121-0900`

## How It Works

### 1. State File Isolation

Each deployment creates a separate Terraform state file based on the environment tag:

**State Path Pattern**: `azure/{environment}/{environment_tag}/terraform.tfstate`

**Example**:
```
azure/dev/SIT-john-teamA-20251120-1430/terraform.tfstate
azure/dev/SIT-sarah-backend-20251120-1545/terraform.tfstate
```

This ensures that:
- Multiple teams can deploy simultaneously without state conflicts
- Each deployment tracks its own infrastructure independently
- State operations (plan, apply, destroy) target the correct environment

### 2. Resource Tagging

All Azure resources are automatically tagged with:
- `Environment`: The environment name (dev, staging, prod)
- **`EnvironmentTag`**: The unique environment tag provided during deployment
- `Project`: Project name
- `ManagedBy`: Terraform

This allows:
- Easy identification of resources by team/user
- Cost tracking per team or test environment
- Resource filtering and organization in Azure Portal

### 3. Resource Naming

The GitHub self-hosted runner is named using the environment tag:
- **Runner Name**: `azure-vm-runner-{environment_tag}`
- **Example**: `azure-vm-runner-SIT-john-teamA-20251120-1430`

This ensures unique runner names and prevents registration conflicts.

## Using the Workflows

### Deploy Infrastructure (OIDC Authentication)

**Workflow**: `deploy-azure-infrastructure.yml`

1. Go to **Actions** → **Deploy Azure Infrastructure (OIDC)**
2. Click **Run workflow**
3. Select the branch
4. Choose environment (dev, staging, prod)
5. **Enter environment tag** using the required format
6. Select Azure region
7. Click **Run workflow**

**Example Input**:
```
Environment: dev
Environment Tag: SIT-john-teamA-20251120-1430
Location: eastus
```

### Destroy Infrastructure

**Workflow**: `destroy-azure-infrastructure.yml`

**CRITICAL**: You must use the **exact same environment tag** that was used during deployment.

1. Go to **Actions** → **Destroy Azure Infrastructure**
2. Click **Run workflow**
3. Select the branch
4. Choose the **same environment** used during deployment
5. **Enter the exact environment tag** from deployment
6. Type "destroy" to confirm
7. Click **Run workflow**

**Example**:
If you deployed with:
```
Environment: dev
Environment Tag: SIT-john-teamA-20251120-1430
```

You must destroy with the **exact same** tag: `SIT-john-teamA-20251120-1430`

**What Gets Destroyed**:
- Virtual Machine (GitHub Runner)
- Network Security Groups specific to this tag
- Virtual Network resources specific to this tag
- Resource Group for this environment

**What Gets Preserved** (OIDC Preservation Feature):
- **OIDC Application Registration** (shared across all environments)
- **OIDC Federated Credentials** (shared authentication)
- Backend Storage Account
- Backend Resource Group

## Multi-Team Usage Scenarios

### Scenario 1: Multiple Teams Testing in Parallel

**Team A**:
```
Environment: dev
Tag: SIT-alice-teamA-20251120-1400
Region: eastus
```

**Team B**:
```
Environment: dev
Tag: SIT-bob-teamB-20251120-1415
Region: westus
```

**Result**: Both teams have completely isolated Azure infrastructure and state files.

### Scenario 2: Daily Test Environments

**Monday**:
```
Tag: SIT-qa-daily-20251118-0900
```

**Tuesday**:
```
Tag: SIT-qa-daily-20251119-0900
```

**Result**: Each day has its own isolated environment that can be destroyed independently.

### Scenario 3: Feature Branch Testing

**Feature 1**:
```
Tag: SIT-dev-feature123-20251120-1000
```

**Feature 2**:
```
Tag: SIT-dev-feature456-20251120-1100
```

**Result**: Each feature branch has isolated infrastructure for testing.

## State Management

### Viewing State Files

State files are stored in the Azure Storage Account configured in `backend.tf`:

**Blob Path**: `tfstate/azure/{environment}/{environment_tag}/terraform.tfstate`

You can list all environments using Azure CLI:
```bash
az storage blob list \
  --account-name <storage-account-name> \
  --container-name tfstate \
  --prefix azure/dev/ \
  --output table
```

### State File Organization

```
tfstate/
├── azure/
│   ├── dev/
│   │   ├── SIT-john-teamA-20251120-1430/
│   │   │   └── terraform.tfstate
│   │   ├── SIT-sarah-backend-20251120-1545/
│   │   │   └── terraform.tfstate
│   │   └── SIT-mike-qa-20251121-0900/
│   │       └── terraform.tfstate
│   ├── staging/
│   │   └── SIT-test-staging-20251120-1600/
│   │       └── terraform.tfstate
│   └── prod/
│       └── SIT-prod-release-20251120-1700/
│           └── terraform.tfstate
```

## Best Practices

### 1. Tag Naming Conventions

**DO**:
- Use consistent user IDs (lowercase, alphanumeric)
- Use descriptive team IDs (teamA, backend, qa, dev)
- Always include current date and time
- Keep tags under 50 characters total

**DON'T**:
- Use special characters (except hyphens)
- Reuse tags across deployments
- Use ambiguous identifiers

### 2. Environment Lifecycle

**Creation**:
1. Generate tag with current timestamp
2. Deploy infrastructure
3. Record tag for later cleanup
4. Use infrastructure for testing

**Cleanup**:
1. Retrieve the exact tag used during deployment
2. Run destroy workflow with matching tag
3. Verify resources cleaned up in Azure Portal
4. Confirm state file removed from Storage

### 3. Cost Management

- **Short-lived environments**: Destroy daily test environments after testing
- **Track costs**: Use EnvironmentTag for cost allocation in Azure Cost Management
- **Monitor resources**: Set up budget alerts per tag
- **Clean up**: Regularly destroy unused environments

### 4. Coordination

- **Document active tags**: Maintain a list of active environment tags
- **Communicate deployments**: Inform team when creating/destroying environments
- **Avoid collisions**: Don't reuse tags or timestamps
- **Track ownership**: Include user ID for accountability

## Troubleshooting

### Issue: Destroy fails with "State file not found"

**Cause**: Environment tag doesn't match the one used during deployment.

**Solution**:
1. List state files in Azure Storage to find the correct tag
2. Use the exact tag from deployment
3. Ensure environment (dev/staging/prod) also matches

### Issue: Resources not destroyed

**Cause**: Some resources may have dependencies.

**Solution**:
1. Check Azure Portal for remaining resources with your EnvironmentTag
2. Manually delete dependent resources if needed
3. Re-run destroy workflow

### Issue: Runner name conflict

**Cause**: Another environment is using the same tag.

**Solution**:
- Generate a new tag with updated timestamp
- Never reuse tags across deployments

### Issue: Can't find my environment

**Cause**: Lost track of environment tag.

**Solution**:
1. List Storage blobs:
   ```bash
   az storage blob list --account-name <storage-account> --container-name tfstate --prefix azure/dev/
   ```
2. Check VMs in Azure Portal for EnvironmentTag
3. Filter GitHub self-hosted runners by name pattern

## Integration with OIDC Authentication

The environment tagging system works seamlessly with OIDC authentication preservation:

- **OIDC Application**: Shared across all teams (never destroyed)
- **Federated Credentials**: Shared authentication (preserved)
- **Infrastructure**: Fully isolated per environment tag
- **State Files**: Separate per environment tag
- **Cleanup**: Targeted per tag, preserving OIDC configuration

## Azure-Specific Considerations

### Resource Groups

Each environment gets its own resource group:
- **Naming Pattern**: `{project_name}-{environment}-rg`
- **Tagged with**: EnvironmentTag for cost tracking
- **Contains**: All resources for that specific deployment

### OIDC vs Access Keys

This guide assumes OIDC authentication. Benefits:
- No secret rotation required
- Better security (no long-lived credentials)
- Federated identity with GitHub Actions
- Shared across all team environments

### Regional Deployment

Teams can deploy to different Azure regions:
- Each region can host multiple environments
- Use region parameter in workflow
- Consider latency and compliance requirements

## Examples

### Example 1: Deploy and Destroy Single Environment

**Deploy**:
```
Workflow: deploy-azure-infrastructure.yml
Environment: dev
Tag: SIT-alice-feature1-20251120-1000
Location: eastus
```

**Use Infrastructure**: Run tests, workflows, etc.

**Destroy**:
```
Workflow: destroy-azure-infrastructure.yml
Environment: dev
Tag: SIT-alice-feature1-20251120-1000  # Same tag!
Confirm: destroy
```

### Example 2: Parallel Team Deployments

**Team 1 - Frontend**:
```
Tag: SIT-frontend-sprint5-20251120-0900
Region: eastus
Deploy at 9:00 AM
Test frontend changes
Destroy at 5:00 PM
```

**Team 2 - Backend**:
```
Tag: SIT-backend-sprint5-20251120-0930
Region: westus
Deploy at 9:30 AM
Test backend changes
Destroy at 6:00 PM
```

**Result**: Both teams work independently in different regions without conflicts.

### Example 3: Rolling Daily Environments

**Day 1**:
```
Tag: SIT-qa-daily-20251120-0800
Deploy, test, keep overnight
```

**Day 2**:
```
Tag: SIT-qa-daily-20251121-0800
Deploy new environment
Destroy previous day: SIT-qa-daily-20251120-0800
```

## Technical Details

### Terraform Variables

The `environment_tag` variable is passed through the entire Terraform configuration:

**Root** (`variables.tf`):
```terraform
variable "environment_tag" {
  description = "Environment tag for resource isolation (Format: SIT-USERID-TEAMID-YYYYMMDD-HHMM)"
  type        = string
}
```

**Modules** (all modules accept this parameter):
- `oidc`
- `networking`
- `security`
- `vm`

### Resource Tagging

Tags applied to all Azure resources via `local.common_tags`:

```terraform
locals {
  common_tags = {
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
    Project        = var.project_name
    ManagedBy      = "Terraform"
  }
}
```

### State Backend Configuration

```hcl
terraform {
  backend "azurerm" {
    container_name = "tfstate"
    key = "azure/${environment}/${environment_tag}/terraform.tfstate"
  }
}
```

### Targeted Destroy (OIDC Preservation)

The destroy workflow uses Terraform's `-target` flag to preserve OIDC:

```bash
terraform destroy \
  -target=module.vm \
  -target=module.security \
  -target=module.networking \
  -target=azurerm_resource_group.main \
  -auto-approve
```

This explicitly excludes `module.oidc` from destruction.

## Summary

The environment tagging system provides:

✅ **Isolation**: Separate state files and resources per team/tester  
✅ **Flexibility**: Multiple parallel deployments without conflicts  
✅ **Traceability**: Clear ownership and tracking via tags  
✅ **Safety**: Targeted destroy operations prevent accidental deletions  
✅ **Cost Control**: Easy cost allocation and tracking per team  
✅ **Integration**: Works seamlessly with OIDC authentication  
✅ **Security**: OIDC resources preserved across all deployments  

**Remember**: Always use the exact same environment tag for deployment and destruction!
