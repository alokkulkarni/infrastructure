# Fully Automated Azure OIDC Setup

This guide explains how to set up **fully automated** Azure infrastructure deployment using GitHub Actions and Terraform, without any manual intervention.

## Overview

The automation consists of two workflows:

1. **Bootstrap OIDC Workflow** (One-time): Creates initial OIDC resources
2. **Deploy Infrastructure Workflow** (Recurring): Uses OIDC to deploy infrastructure

## Prerequisites

You need **ONE** secret to bootstrap everything:

### AZURE_CREDENTIALS

This is a Service Principal with credentials in JSON format. Create it once:

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Create service principal with Contributor role
az ad sp create-for-rbac \
  --name "github-actions-bootstrap" \
  --role "Contributor" \
  --scopes "/subscriptions/$(az account show --query id -o tsv)" \
  --sdk-auth

# Also assign User Access Administrator role (needed to create OIDC roles)
SP_ID=$(az ad sp list --display-name "github-actions-bootstrap" --query "[0].appId" -o tsv)
az role assignment create \
  --assignee "$SP_ID" \
  --role "User Access Administrator" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
```

The output will be JSON like this:

```json
{
  "clientId": "12345678-1234-1234-1234-123456789012",
  "clientSecret": "your-secret-here",
  "subscriptionId": "87654321-4321-4321-4321-210987654321",
  "tenantId": "abcdefgh-abcd-abcd-abcd-abcdefghijkl",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
```

**IMPORTANT:** Copy the **entire JSON output** (not just individual fields).

### Add to GitHub Secrets

1. Go to your repository: `https://github.com/YOUR_ORG/YOUR_REPO/settings/secrets/actions`
2. Click **"New repository secret"**
3. Name: `AZURE_CREDENTIALS`
4. Value: Paste the **entire JSON** from above
5. Click **"Add secret"**

That's it! This is the **only** manual step required.

## Step-by-Step Automation

### Step 1: Bootstrap OIDC (One-Time)

Run the bootstrap workflow to create OIDC resources:

1. Go to **Actions** tab in GitHub
2. Select **"Bootstrap Azure OIDC (One-Time Setup)"**
3. Click **"Run workflow"**
4. Select environment: `dev`
5. Click **"Run workflow"** button

This workflow will:
- ✅ Create Azure AD Application: `testcontainers-dev-github-actions`
- ✅ Create Service Principal
- ✅ Create 3 Federated Identity Credentials:
  - Main branch: `repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main`
  - Pull requests: `repo:YOUR_ORG/YOUR_REPO:pull_request`
  - Environment: `repo:YOUR_ORG/YOUR_REPO:environment:dev`
- ✅ Assign Contributor role
- ✅ Assign User Access Administrator role
- ✅ Output the required secret values

The workflow will display the three IDs needed in the Summary:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

### Step 2: Add OIDC Secrets

After the bootstrap workflow completes:

1. Click on the workflow run
2. Scroll to **"Display Summary"** job
3. Copy the three IDs shown
4. Go to: `https://github.com/YOUR_ORG/YOUR_REPO/settings/secrets/actions`
5. Add three new secrets:

| Secret Name | Value | Source |
|-------------|-------|--------|
| `AZURE_CLIENT_ID` | Application ID | From workflow output |
| `AZURE_TENANT_ID` | Tenant ID | From workflow output |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID | From workflow output |

**Pro tip:** The workflow output has the exact values to copy - no newlines or extra spaces.

### Step 3: Deploy Infrastructure

Now you can deploy infrastructure using OIDC authentication:

1. Go to **Actions** tab
2. Select **"Deploy Azure Infrastructure (OIDC)"**
3. Click **"Run workflow"**
4. Fill in parameters:
   - **environment**: `dev`
   - **environment_tag**: `SIT-yourname-teamA-20251124-1500`
   - **location**: `uksouth`
5. Click **"Run workflow"**

The workflow will:
- ✅ Authenticate using OIDC (no passwords!)
- ✅ Setup Terraform backend
- ✅ Run Terraform plan
- ✅ Deploy infrastructure with Terraform apply

## What Gets Created

### By Bootstrap Workflow

| Resource Type | Name | Purpose |
|--------------|------|---------|
| Azure AD Application | `testcontainers-dev-github-actions` | OIDC application |
| Service Principal | (auto-created) | Identity for OIDC |
| Federated Credential | `github-main` | Authenticate main branch pushes |
| Federated Credential | `github-pr` | Authenticate pull requests |
| Federated Credential | `github-environment` | Authenticate environment deployments |
| Role Assignment | Contributor | Create/manage resources |
| Role Assignment | User Access Administrator | Manage IAM |

### By Deploy Workflow

| Resource Type | Name Pattern | Purpose |
|--------------|-------------|---------|
| Resource Group | `testcontainers-tfstate-rg` | Terraform state storage |
| Storage Account | `testcontainerstfstate{subid}` | Terraform state backend |
| Blob Container | `{environment-tag}` | Isolated state per environment |
| Resource Group | `testcontainers-{env}-rg` | Application resources |
| Virtual Network | `testcontainers-{env}-vnet` | Networking |
| Subnets | Public/Private subnets | Network isolation |
| NSGs | Security rules | Network security |
| (And more...) | (Based on your Terraform) | Application infrastructure |

## Secrets Reference

You'll have these secrets configured:

| Secret | When to Create | Used By |
|--------|---------------|---------|
| `AZURE_CREDENTIALS` | **Before Step 1** | Bootstrap workflow |
| `AZURE_CLIENT_ID` | **After Step 1** | Deploy workflow |
| `AZURE_TENANT_ID` | **After Step 1** | Deploy workflow |
| `AZURE_SUBSCRIPTION_ID` | **After Step 1** | Deploy workflow |
| `PAT_TOKEN` | (Optional) | If you need GitHub API access |

## Workflow Comparison

| Aspect | Bootstrap Workflow | Deploy Workflow |
|--------|-------------------|----------------|
| **Runs** | Once per environment | Every deployment |
| **Authentication** | Service Principal (password) | OIDC (passwordless) |
| **Requires** | `AZURE_CREDENTIALS` secret | Three OIDC secrets |
| **Creates** | OIDC resources | Infrastructure resources |
| **When** | First-time setup | Ongoing deployments |

## Security Benefits of OIDC

After bootstrap, all deployments use OIDC:

✅ **No passwords in GitHub Secrets** - Just IDs, which aren't sensitive  
✅ **Short-lived tokens** - Automatically expire after workflow  
✅ **Scoped access** - Only works for your specific repo/environment  
✅ **Auditable** - Azure logs show exactly which workflow made changes  
✅ **Revocable** - Disable federated credential to block all access  

## Troubleshooting

### Bootstrap Workflow Fails

**Error:** "Insufficient privileges to complete the operation"

**Solution:** The service principal needs **both** roles:
```bash
SP_ID=$(az ad sp list --display-name "github-actions-bootstrap" --query "[0].appId" -o tsv)
az role assignment create \
  --assignee "$SP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
az role assignment create \
  --assignee "$SP_ID" \
  --role "User Access Administrator" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
```

**Error:** "Application already exists"

**Solution:** This is fine! The workflow is idempotent - it will reuse existing resources and create only what's missing.

### Deploy Workflow Fails

**Error:** "AADSTS700213: No matching federated identity record found"

**Solution:** Run the bootstrap workflow again for this environment:
```bash
# The workflow should have created this credential
az ad app federated-credential list \
  --id $(az ad app list --display-name "testcontainers-dev-github-actions" --query "[0].id" -o tsv) \
  --query "[].subject" -o tsv
```

Expected output should include:
```
repo:YOUR_ORG/YOUR_REPO:environment:dev
```

If missing, re-run bootstrap workflow.

**Error:** "Client secret is expired"

**Solution:** This shouldn't happen with OIDC! If you see this:
1. Verify you're using the **Deploy** workflow (not Bootstrap)
2. Check that `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` are set
3. Verify the secrets don't contain newlines: `echo -n "value" | od -c`

### Secrets Have Trailing Newlines

**Problem:** Copied secrets with accidental newlines.

**Solution:** The deploy workflow automatically sanitizes secrets, but to be safe:

```bash
# In your terminal, copy like this
echo -n "YOUR_VALUE" | pbcopy   # macOS
echo -n "YOUR_VALUE" | xclip    # Linux
```

Then paste into GitHub Secrets. The `echo -n` prevents newline.

## Advanced: Multiple Environments

To support multiple environments (dev, staging, prod):

### Option 1: Run Bootstrap for Each

Run the bootstrap workflow three times:
1. Select `dev` → Creates `testcontainers-dev-github-actions`
2. Select `staging` → Creates `testcontainers-staging-github-actions`
3. Select `prod` → Creates `testcontainers-prod-github-actions`

Then deploy to each environment separately.

### Option 2: Use GitHub Environments

1. Create GitHub Environments:
   - Go to `Settings → Environments`
   - Create: `dev`, `staging`, `prod`
2. Run bootstrap for each environment
3. Add environment-specific secrets to each environment
4. Deploy workflow will use the correct environment secrets

## Advanced: Terraform Manages OIDC

After the initial bootstrap, you can let Terraform manage OIDC resources:

1. Bootstrap creates initial resources
2. First Terraform run imports them:
   ```bash
   terraform import module.oidc.azuread_application.github_actions <app-id>
   terraform import module.oidc.azuread_service_principal.github_actions <sp-id>
   ```
3. Future runs: Terraform updates OIDC resources as code changes
4. Bootstrap workflow becomes optional (only for new environments)

The OIDC module in `modules/oidc/main.tf` is already configured for this.

## Summary

**One-Time Setup:**
1. ✅ Create `AZURE_CREDENTIALS` secret (Service Principal with password)
2. ✅ Run Bootstrap OIDC workflow once per environment
3. ✅ Add three OIDC secrets (`CLIENT_ID`, `TENANT_ID`, `SUBSCRIPTION_ID`)

**Ongoing Deployments:**
1. ✅ Run Deploy Infrastructure workflow anytime
2. ✅ Uses OIDC (passwordless authentication)
3. ✅ Fully automated - no manual steps

**Result:**
- 🎉 Fully automated infrastructure deployment
- 🔒 Secure OIDC authentication (no passwords)
- 🚀 Deploy in minutes, not hours
- ✅ Repeatable and auditable

## Next Steps

1. **Now:** Create `AZURE_CREDENTIALS` secret
2. **Now:** Run Bootstrap workflow
3. **Now:** Add OIDC secrets
4. **Now:** Run Deploy workflow
5. **Done:** Infrastructure deployed!

Need help? Check the workflow logs - they show exactly what's happening at each step.
