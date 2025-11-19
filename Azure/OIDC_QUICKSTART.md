# Azure OIDC Quick Reference

## TL;DR

OIDC = No more managing Azure service principal secrets in GitHub. Tokens are short-lived and automatically rotated.

## Quick Comparison

| Aspect | Service Principal + Secret | OIDC |
|--------|---------------------------|------|
| Setup Time | 5 minutes | 10 minutes (one-time) |
| Secret Management | Manual rotation every 90 days | None |
| Security Risk | High (long-lived secrets) | Low (short-lived tokens) |
| Audit Trail | Limited | Full Azure AD logs |
| Access Control | Repository-wide | Branch/environment-specific |

## Prerequisites Checklist

- [ ] Azure subscription
- [ ] Azure CLI installed
- [ ] Terraform >= 1.0
- [ ] GitHub repository with Actions enabled
- [ ] Azure permissions: `Application.ReadWrite.All`, `Contributor`, `User Access Administrator`

## 5-Minute Setup (Using Terraform)

```bash
# 1. Login to Azure
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# 2. Setup Terraform backend
cd infrastructure/Azure
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="terraform-state-rg"
export STORAGE_ACCOUNT_NAME="tfstate$(openssl rand -hex 4)"
./scripts/setup-terraform-backend.sh

# 3. Configure Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 4. Deploy (creates OIDC app automatically)
terraform init
terraform apply

# 5. Get the Application ID
terraform output github_actions_app_id
```

## Required GitHub Secrets

| Secret | Value | Command to Get |
|--------|-------|---------------|
| `AZURE_CLIENT_ID` | Application ID | `terraform output github_actions_app_id` |
| `AZURE_TENANT_ID` | Tenant ID | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID | `az account show --query id -o tsv` |
| `TERRAFORM_STATE_RG` | Backend RG | `terraform-state-rg` |
| `TERRAFORM_STATE_STORAGE` | Backend storage | From setup script output |
| `PAT_TOKEN` | GitHub PAT | Generate at https://github.com/settings/tokens |

## Workflow Usage

```yaml
name: Deploy to Azure

on:
  push:
    branches: [main]

permissions:
  id-token: write   # ← Required for OIDC
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login using OIDC
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Run Azure CLI commands
        run: |
          az group list --output table
```

## Federated Credential Subjects

Our setup creates 3 federated credentials:

| Use Case | Subject Pattern |
|----------|----------------|
| Main branch | `repo:ORG/REPO:ref:refs/heads/main` |
| Pull requests | `repo:ORG/REPO:pull_request` |
| Environments | `repo:ORG/REPO:environment:dev` |

## Common Issues & Fixes

### "Application not found"
```bash
# List apps to find correct ID
az ad app list --display-name "github-actions" --output table
```

### "Subject does not match"
```bash
# Verify federated credentials
az ad app federated-credential list --id $APP_ID
# Make sure subject matches your branch/environment
```

### "Insufficient privileges"
```bash
# Re-assign roles
export SP_ID=$(az ad sp list --display-name "$APP_NAME" --query "[0].id" -o tsv)
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az role assignment create \
  --role "Contributor" \
  --assignee $SP_ID \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Backend initialization failed
```bash
# Re-run backend setup
cd infrastructure/Azure
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="terraform-state-rg"
export STORAGE_ACCOUNT_NAME="your-storage-account-name"
./scripts/setup-terraform-backend.sh
```

## Testing

```bash
# Test 1: Verify app exists
az ad app show --id $APP_ID

# Test 2: Verify federated credentials
az ad app federated-credential list --id $APP_ID

# Test 3: Verify role assignments
az role assignment list --assignee $SP_ID --output table

# Test 4: Manual workflow run
# Go to Actions > Deploy Azure Infrastructure (OIDC) > Run workflow
```

## Migration from Secrets

**Old way (with secrets):**
```yaml
- uses: azure/login@v1
  with:
    creds: ${{ secrets.AZURE_CREDENTIALS }}
```

**New way (with OIDC):**
```yaml
permissions:
  id-token: write

- uses: azure/login@v1
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

## Manual CLI Setup (Without Terraform)

```bash
export APP_NAME="github-actions-oidc-testcontainers"
export GITHUB_ORG="YOUR_ORG"
export GITHUB_REPO="YOUR_REPO"

# Create app
az ad app create --display-name "$APP_NAME"
export APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)

# Create service principal
az ad sp create --id $APP_ID
export SP_ID=$(az ad sp list --display-name "$APP_NAME" --query "[0].id" -o tsv)

# Add federated credential for main branch
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "main-branch",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Assign roles
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az role assignment create --role "Contributor" --assignee $SP_ID --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --role "User Access Administrator" --assignee $SP_ID --scope "/subscriptions/$SUBSCRIPTION_ID"
```

## Architecture

```
GitHub Actions (main branch)
    ↓ Request OIDC token with subject
GitHub OIDC Provider
    ↓ Issue signed JWT
Azure AD
    ↓ Validate token against federated credential
    ↓ Issue Azure access token
Azure Resources
    ↓ Terraform manages infrastructure
```

## Security Highlights

- ✅ Tokens valid for ~10 minutes only
- ✅ No secrets in GitHub (just identifiers)
- ✅ Branch/environment-specific access
- ✅ Full audit trail in Azure AD
- ✅ Automatic token refresh
- ✅ Can't be exfiltrated or reused outside GitHub Actions

## Useful Links

- [Full Setup Guide](./OIDC_SETUP.md) - Comprehensive documentation
- [Azure OIDC Docs](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
- [GitHub OIDC Docs](https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

## Next Steps

1. Complete setup using [OIDC_SETUP.md](./OIDC_SETUP.md)
2. Configure GitHub Secrets
3. Run workflow: Actions > Deploy Azure Infrastructure (OIDC)
4. Verify resources: `az resource list --resource-group testcontainers-dev-rg`
5. Check runner: Settings > Actions > Runners

## Support

For issues:
1. Check [Troubleshooting](./OIDC_SETUP.md#troubleshooting) section
2. Verify all secrets are set correctly
3. Check workflow logs for specific errors
4. Verify Azure permissions: `az ad signed-in-user show`
