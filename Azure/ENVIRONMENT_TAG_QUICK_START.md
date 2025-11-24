# Environment Tag-Based Deployment - Quick Start

## Deploying Your Environment

### 1. Generate Environment Tag
```bash
# Format: SIT-{USERID}-{TEAMID}-{YYYYMMDD}-{HHMM}
# Example:
export ENVIRONMENT_TAG="SIT-alok-teamA-$(date +%Y%m%d-%H%M)"
echo "Your environment tag: $ENVIRONMENT_TAG"
```

### 2. Deploy via GitHub Actions

**Navigate to**: Actions → "Deploy Azure Infrastructure (OIDC)"

**Workflow Inputs**:
- **environment**: `dev` (or `staging`, `prod`)
- **environment_tag**: `SIT-alok-teamA-20251124-1530` (use generated tag)
- **location**: `uksouth` (or your preferred region)

**Click**: "Run workflow"

### 3. Monitor Deployment

The workflow will:
1. ✅ Create/reuse shared storage account
2. ✅ Create your environment-specific container
3. ✅ Deploy infrastructure with your environment tag
4. ✅ Configure GitHub runner with your labels

**Check**: Your runner appears with labels: `[self-hosted, azure, linux, docker, dev, SIT-alok-teamA-20251124-1530]`

## What Gets Created

### Shared (Across All Teams)
```
Resource Group: testcontainers-tfstate-rg
Storage Account: testcontainerstfstate2745ace7
```

### Your Environment-Specific Resources
```
Container: sit-alok-teama-20251124-1530
Infrastructure:
  - Resource Group: testcontainers-dev-sit-alok-teama-20251124-1530
  - VNet + Subnets
  - VM (GitHub Runner)
  - Key Vault
  - OIDC Configuration
  - Security Resources
```

## Cleanup Your Environment

### Automatic (Workflow)
**Coming Soon**: Destroy workflow accepting environment tag

### Manual Cleanup

#### Step 1: Destroy Infrastructure
```bash
# Clone repo locally
cd infrastructure/Azure/terraform

# Configure backend
cat > backend.tf <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "testcontainers-tfstate-rg"
    storage_account_name = "testcontainerstfstate2745ace7"  # Update with your actual name
    container_name       = "sit-alok-teama-20251124-1530"    # Your environment tag
    key                  = "terraform.tfstate"
    use_oidc             = false  # Use Azure CLI auth
  }
}
EOF

# Login and destroy
az login
az account set --subscription YOUR_SUBSCRIPTION_ID

terraform init
terraform destroy -auto-approve
```

#### Step 2: Delete Container
```bash
# Delete your environment container
az storage container delete \
  --account-name testcontainerstfstate2745ace7 \
  --name sit-alok-teama-20251124-1530 \
  --auth-mode login
```

#### Step 3: Purge Soft-Deleted Resources
```bash
# Find and purge Key Vault
KV_NAME=$(az keyvault list-deleted \
  --query "[?tags.EnvironmentTag=='SIT-alok-teamA-20251124-1530'].name" -o tsv)

if [ -n "$KV_NAME" ]; then
  az keyvault purge --name "$KV_NAME"
  echo "✅ Purged Key Vault: $KV_NAME"
fi
```

## Common Operations

### Check Your Deployment Status
```bash
# List your resources
az resource list \
  --tag EnvironmentTag=SIT-alok-teamA-20251124-1530 \
  --query "[].{Name:name, Type:type, Location:location}" -o table
```

### View Your State File
```bash
az storage blob download \
  --account-name testcontainerstfstate2745ace7 \
  --container-name sit-alok-teama-20251124-1530 \
  --name terraform.tfstate \
  --file my-state.tfstate \
  --auth-mode login

# Inspect locally
cat my-state.tfstate | jq '.resources[] | {type, name}'
```

### List All Active Environments
```bash
# Shows all team deployments
az storage container list \
  --account-name testcontainerstfstate2745ace7 \
  --auth-mode login \
  --query "[].name" -o table
```

### SSH to Your Runner VM
```bash
# Get VM public IP
VM_IP=$(az vm show \
  -g testcontainers-dev-sit-alok-teama-20251124-1530 \
  -n vm-sit-alok-teama-20251124-1530 \
  --show-details \
  --query publicIps -o tsv)

# SSH using your key
ssh -i ~/.ssh/azure_vm_key azureuser@$VM_IP
```

## Troubleshooting

### Deployment Failed
**Check**: GitHub Actions workflow logs
**Rollback**: Automatic - failed deployments trigger rollback job

### Container Already Exists
**Error**: `Container 'sit-alok-teama-20251124-1530' already exists`
**Fix**: Use new environment tag with current timestamp

### State Lock
**Error**: `Error acquiring the state lock`
**Fix**: 
```bash
# Force unlock (use with caution!)
terraform force-unlock LOCK_ID
```

### Storage Account Not Found
**Error**: `SubscriptionNotFound` when creating storage account
**Cause**: Storage account name might be globally taken
**Check**: 
```bash
az storage account check-name --name testcontainerstfstate2745ace7
```

### OIDC Authentication Failed
**Error**: `Failed to obtain OIDC token`
**Fix**: 
1. Verify secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
2. Check federated credentials in Entra ID
3. Verify RBAC roles assigned to service principal

## Best Practices

### Environment Tag Naming
✅ **Good**:
- `SIT-alok-teamA-20251124-1530` (clear, timestamped)
- `SIT-john-backend-20251125-0900` (identifies team/component)

❌ **Bad**:
- `test123` (not descriptive)
- `MY_ENV` (underscores cause issues)
- `SIT-alok` (no timestamp, conflicts likely)

### Resource Tagging
All your infrastructure should have:
```hcl
tags = {
  Environment    = "dev"
  EnvironmentTag = "SIT-alok-teamA-20251124-1530"
  ManagedBy      = "Terraform"
  Owner          = "alok"
  Team           = "teamA"
}
```

### Cleanup Schedule
- **Daily**: Check for unused environments
- **Weekly**: Clean up old development environments
- **Monthly**: Review storage costs

### Concurrent Deployments
- ✅ Multiple team members can deploy simultaneously
- ✅ Each uses unique environment tag
- ✅ No state conflicts
- ❌ Don't reuse environment tags

## Examples

### Team Deployment Scenario
```
Team A (3 members) working on different features:

Storage Account: testcontainerstfstate2745ace7/
├── sit-alok-teama-20251124-1530/     # Alok: working on API
├── sit-sarah-teama-20251124-1545/    # Sarah: testing database
├── sit-mike-teama-20251124-1600/     # Mike: frontend changes
└── sit-john-teamb-20251124-1615/     # John (Team B): separate feature

All deploying concurrently with zero conflicts!
```

### Multi-Environment Scenario
```
Same team member testing different configurations:

Storage Account: testcontainerstfstate2745ace7/
├── sit-alok-teama-20251124-1530/     # Test with Standard_D2s_v3
├── sit-alok-teama-20251124-1700/     # Test with Standard_D4s_v3
└── sit-alok-teama-20251124-1830/     # Test with different network config

Compare results, keep best, destroy others!
```

## Need Help?

### Documentation
- [Architecture Guide](./ENVIRONMENT_TAG_ISOLATION_ARCHITECTURE.md)
- [OIDC Setup](./OIDC_GUIDE.md)
- [Terraform Docs](./terraform/README.md)

### Common Questions

**Q: Can I have multiple environments with same user/team?**  
A: Yes! Use different timestamps in environment tag

**Q: Do I need to delete storage account?**  
A: No! Storage account is shared. Only delete your container.

**Q: How much does my environment cost?**  
A: ~$50-100/month depending on VM size and resources

**Q: Can I pause my environment to save costs?**  
A: Yes! Deallocate VM: `az vm deallocate -g RESOURCE_GROUP -n VM_NAME`

**Q: How do I share access with team members?**  
A: Share environment tag and grant them RBAC on resource group

## Quick Commands Cheat Sheet

```bash
# Generate environment tag
export ENV_TAG="SIT-$(whoami)-teamA-$(date +%Y%m%d-%H%M)"

# Check if container exists
az storage container exists \
  --account-name testcontainerstfstate2745ace7 \
  --name $(echo $ENV_TAG | tr '[:upper:]' '[:lower:]' | tr '_' '-') \
  --auth-mode login

# List my resources
az resource list --tag EnvironmentTag=$ENV_TAG -o table

# Get resource group name
az group list --tag EnvironmentTag=$ENV_TAG --query "[].name" -o tsv

# Delete my environment container
az storage container delete \
  --account-name testcontainerstfstate2745ace7 \
  --name $(echo $ENV_TAG | tr '[:upper:]' '[:lower:]' | tr '_' '-') \
  --auth-mode login

# Purge my Key Vault
az keyvault purge --name $(az keyvault list-deleted --query "[?tags.EnvironmentTag=='$ENV_TAG'].name" -o tsv)
```

---

**Remember**: Your environment tag is your identity. Keep it unique, keep it clean! 🚀
