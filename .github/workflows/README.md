# GitHub Actions Workflows for Infrastructure Deployment

This directory contains GitHub Actions workflows for deploying and managing infrastructure on AWS and Azure using Terraform with self-hosted GitHub runners.

## 📋 Table of Contents

- [Overview](#overview)
- [AWS Workflows](#aws-workflows)
  - [deploy-aws-infrastructure.yml (Hybrid Authentication)](#deploy-aws-infrastructureyml-hybrid-authentication)
  - [deploy-aws-infrastructure-oidc.yml (Pure OIDC) ⭐](#deploy-aws-infrastructure-oidcyml-pure-oidc-)
  - [destroy-aws-infrastructure.yml](#destroy-aws-infrastructureyml)
- [Azure Workflows](#azure-workflows)
  - [deploy-azure-infrastructure.yml (Pure OIDC)](#deploy-azure-infrastructureyml-pure-oidc)
  - [destroy-azure-infrastructure.yml](#destroy-azure-infrastructureyml)
- [Prerequisites](#prerequisites)
- [Secrets Configuration](#secrets-configuration)
- [Security Best Practices](#security-best-practices)
- [Setup Guides](#setup-guides)
- [Troubleshooting](#troubleshooting)

---

## Overview

All workflows deploy infrastructure to run self-hosted GitHub Actions runners on cloud VMs (AWS EC2 or Azure VM) with Docker support. This enables TestContainers to run in CI/CD pipelines.

**Key Features:**
- Terraform-based infrastructure as code
- Self-hosted GitHub runners with Docker
- Environment-based deployments (dev/staging/prod)
- Remote state management (S3/Azure Storage)
- OIDC authentication for zero standing privileges

---

## AWS Workflows

### deploy-aws-infrastructure.yml (Hybrid Authentication)

**What it does:**
- Deploys AWS infrastructure (VPC, subnets, EC2 instance, security groups)
- Installs self-hosted GitHub runner with Docker on EC2
- Uses **hybrid authentication**: OIDC for read operations (plan), AWS access keys for write operations (apply)

**Authentication Model:**
```yaml
# setup-backend & terraform-plan jobs
permissions:
  id-token: write  # OIDC enabled
Configure AWS credentials using OIDC:
  role-to-assume: ${{ secrets.AWS_ROLE_ARN }}

# terraform-apply job
Configure AWS credentials:
  aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}      # ⚠️ Long-lived credentials
  aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

**Required Secrets:**
| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_ROLE_ARN` | IAM Role ARN for OIDC (plan/backend) | `arn:aws:iam::123456789012:role/GitHubActionsRole` |
| `AWS_ACCESS_KEY_ID` | IAM User access key (apply) | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | IAM User secret key (apply) | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `PAT_TOKEN` | GitHub Personal Access Token (runner registration) | `ghp_xxxxxxxxxxxxx` |

**Note:** Terraform backend resources (S3 bucket and DynamoDB table) are automatically created with names derived from your AWS Account ID. No secrets required for backend configuration.

**When to use:**
- Migrating from pure access key authentication to OIDC
- Organizations requiring access keys for compliance/approval workflows
- Learning OIDC before full adoption

**Security Considerations:**
- ⚠️ Access keys are long-lived credentials (90-day rotation recommended)
- ⚠️ Access keys can be compromised if leaked in logs or code
- ✅ OIDC tokens used for plan operations are short-lived (1 hour)
- ⚠️ Mixed authentication model increases complexity

**Prerequisites:**
1. AWS OIDC Identity Provider configured (for plan/backend jobs)
2. IAM Role with trust policy for GitHub OIDC (for plan/backend)
3. IAM User with programmatic access (for apply job)
4. GitHub PAT with `repo` and `admin:org` scopes

**Note:** Backend resources and SSH access no longer required - see "Backend Resource Management" section below.

---

### deploy-aws-infrastructure-oidc.yml (Pure OIDC) ⭐

**RECOMMENDED** for new deployments and security-conscious environments.

**What it does:**
- Deploys AWS infrastructure (VPC, subnets, EC2 instance, security groups)
- Installs self-hosted GitHub runner with Docker on EC2
- Uses **pure OIDC authentication** for ALL operations (backend setup, plan, apply)

**Authentication Model:**
```yaml
# ALL jobs (setup-backend, terraform-plan, terraform-apply)
permissions:
  id-token: write  # OIDC enabled

Configure AWS credentials using OIDC:
  role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
  role-session-name: GitHubActions-<JobName>  # ✅ Short-lived (1 hour), traceable
```

**Key Differences from Hybrid:**
| Aspect | Hybrid | Pure OIDC |
|--------|--------|-----------|
| **Apply Authentication** | AWS Access Keys | OIDC |
| **Credential Lifecycle** | 90 days (manual rotation) | 1 hour (auto-expiring) |
| **Required Secrets** | 4 secrets | 2 secrets |
| **Security Posture** | Mixed | Zero standing privileges ✅ |
| **AWS Recommendations** | Legacy | Best practice ✅ |
| **Audit Trail** | CloudTrail (IAM User) | CloudTrail (Role session name) |

**Required Secrets:**
| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_ROLE_ARN` | IAM Role ARN for OIDC (all operations) | `arn:aws:iam::123456789012:role/GitHubActionsRole` |
| `PAT_TOKEN` | GitHub Personal Access Token | `ghp_xxxxxxxxxxxxx` |

**Note:** Terraform backend resources (S3 bucket and DynamoDB table) are automatically created with names derived from your AWS Account ID. No secrets required for backend configuration.

**When to use:**
- ✅ New infrastructure deployments
- ✅ Security-first environments
- ✅ Compliance requirements (SOC2, ISO 27001, PCI-DSS)
- ✅ Zero-trust security model adoption
- ✅ Reducing secret sprawl and rotation burden

**Security Advantages:**
- ✅ Zero long-lived credentials
- ✅ Automatic credential expiration (1 hour)
- ✅ No credential rotation management
- ✅ Impossible to leak credentials (tokens generated at runtime)
- ✅ Fine-grained IAM permissions via trust policy conditions
- ✅ Clear audit trail with session names

**Prerequisites:**
1. AWS OIDC Identity Provider configured
2. IAM Role with comprehensive trust policy for GitHub OIDC
3. GitHub PAT with `repo` and `admin:org` scopes

**Note:** Backend resources and SSH access no longer required - see "Backend Resource Management" section below.

---

### destroy-aws-infrastructure.yml

**What it does:**
- Destroys all AWS infrastructure for a specified environment
- Requires explicit confirmation ("destroy" typed in workflow input)
- Provides optional cleanup instructions for Terraform backend

**Authentication Model:**
```yaml
# Uses AWS access keys (legacy approach)
Configure AWS credentials:
  aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
  aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

**Required Secrets:**
Same as `deploy-aws-infrastructure.yml` (hybrid):
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Note:** Terraform backend resources are automatically derived from AWS Account ID - no secrets required for backend configuration.

**Safety Features:**
- ✅ Manual workflow dispatch only (no automatic triggers)
- ✅ Confirmation input required (`confirm_destroy: "destroy"`)
- ✅ Separate `<env>-destroy` GitHub environment (allows manual approvals)
- ✅ Terraform plan destroy before actual destroy
- ✅ Summary output with timestamp

**When to use:**
- Tearing down dev/staging environments
- Cost optimization (destroying unused resources)
- Complete environment cleanup before redeployment

**⚠️ Warning:**
- This workflow uses access keys instead of OIDC
- Recommendation: Create a destroy-aws-infrastructure-oidc.yml variant for consistency

---

## Azure Workflows

### deploy-azure-infrastructure.yml (Pure OIDC)

**What it does:**
- Deploys Azure infrastructure (VNet, subnets, VM, NSG)
- Installs self-hosted GitHub runner with Docker on Azure VM
- Uses **pure OIDC authentication** (Azure Federated Credentials) for ALL operations

**Authentication Model:**
```yaml
# ALL jobs use OIDC
permissions:
  id-token: write  # Required for Azure OIDC

Azure Login using OIDC:
  client-id: ${{ secrets.AZURE_CLIENT_ID }}
  tenant-id: ${{ secrets.AZURE_TENANT_ID }}
  subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

# Terraform uses ARM environment variables
ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
ARM_USE_OIDC: true  # ✅ Enables OIDC authentication
```

**Required Secrets:**
| Secret | Description | Example |
|--------|-------------|---------|
| `AZURE_CLIENT_ID` | Service Principal Application (client) ID | `12345678-1234-1234-1234-123456789012` |
| `AZURE_TENANT_ID` | Microsoft Entra ID Tenant ID | `87654321-4321-4321-4321-210987654321` |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | `abcdef12-3456-7890-abcd-ef1234567890` |
| `PAT_TOKEN` | GitHub Personal Access Token | `ghp_xxxxxxxxxxxxx` |
| `TERRAFORM_STATE_RG` | Resource group for Terraform state storage | `terraform-state-rg` |
| `TERRAFORM_STATE_STORAGE` | Storage account for Terraform state | `tfstatexxxxx` |

**When to use:**
- Azure-based infrastructure deployments
- Organizations using Azure as primary cloud
- Leveraging Azure's native OIDC support (Federated Credentials)

**Security Advantages:**
- ✅ Pure OIDC from the start (Azure has excellent OIDC support)
- ✅ No Service Principal secrets required
- ✅ Federated Credentials tied to specific GitHub repos/branches
- ✅ Automatic token expiration and rotation
- ✅ Simplified secret management (3 IDs instead of client secrets)

**Prerequisites:**
1. Azure Service Principal created
2. Federated Credentials configured for GitHub Actions
3. Service Principal assigned appropriate roles (Contributor or custom)
4. Resource group and storage account for Terraform state
5. GitHub PAT with `repo` and `admin:org` scopes

---

### destroy-azure-infrastructure.yml

**What it does:**
- Destroys all Azure infrastructure for a specified environment
- Requires explicit confirmation ("destroy" typed in workflow input)
- Uses pure OIDC authentication (consistent with deploy workflow)

**Authentication Model:**
```yaml
# Uses OIDC (consistent with deploy workflow) ✅
permissions:
  id-token: write

Azure Login using OIDC:
  client-id: ${{ secrets.AZURE_CLIENT_ID }}
  tenant-id: ${{ secrets.AZURE_TENANT_ID }}
  subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

**Required Secrets:**
Same as `deploy-azure-infrastructure.yml`:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TERRAFORM_STATE_RG`
- `TERRAFORM_STATE_STORAGE`

**Safety Features:**
- ✅ Manual workflow dispatch only
- ✅ Confirmation input required (`confirm_destroy: "destroy"`)
- ✅ Separate GitHub environment (allows manual approvals)
- ✅ OIDC authentication (secure, consistent)
- ✅ Summary output with status

**Key Difference from AWS Destroy:**
- ✅ Uses OIDC instead of access keys (Azure destroy workflow is more secure)
- ✅ Consistent authentication model with deploy workflow

---

## Prerequisites

### AWS Prerequisites (OIDC Setup)

#### 1. Create OIDC Identity Provider

```bash
# Using AWS CLI
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

#### 2. Create IAM Role with Trust Policy

Create `github-actions-trust-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

Create the role:
```bash
aws iam create-role \
  --role-name GitHubActionsRole \
  --assume-role-policy-document file://github-actions-trust-policy.json

# Attach required policies
aws iam attach-role-policy \
  --role-name GitHubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess  # Or custom policy
```

#### 3. Backend Resource Management (Automatic)

**No manual setup required!** The workflows automatically create and manage backend resources:

**How it works:**
1. The `setup-backend` job runs the setup script which:
   - Derives unique resource names using your AWS Account ID
   - Creates S3 bucket: `testcontainers-terraform-state-{AWS_ACCOUNT_ID}`
   - Creates DynamoDB table: `testcontainers-terraform-locks`
   - Enables versioning and encryption on the S3 bucket
   - Sets up lifecycle policies for cost optimization

2. Backend configuration is dynamically generated in workflows:
   ```yaml
   # Generated at runtime - no secrets needed
   terraform {
     backend "s3" {
       bucket         = "testcontainers-terraform-state-123456789012"
       key            = "aws/ec2-runner/dev/terraform.tfstate"
       region         = "us-east-1"
       encrypt        = true
       dynamodb_table = "testcontainers-terraform-locks"
     }
   }
   ```

**Benefits:**
- ✅ No secrets required for backend configuration
- ✅ Globally unique bucket names (using AWS Account ID)
- ✅ Idempotent (can run multiple times safely)
- ✅ Consistent naming across environments

**Manual setup option (optional):**
If you want to pre-create resources before running workflows:
```bash
cd infrastructure/AWS
chmod +x scripts/setup-terraform-backend.sh
export AWS_REGION=us-east-1
export PROJECT_NAME=testcontainers  # Optional, defaults to "testcontainers"
./scripts/setup-terraform-backend.sh
```

#### 4. Create GitHub PAT

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with scopes:
   - `repo` (Full control of private repositories)
   - `admin:org` → `manage_runners:org` (Manage organization runners)
3. Copy token (starts with `ghp_`)

---

### Azure Prerequisites (OIDC Setup)

#### 1. Create Service Principal

```bash
# Login to Azure
az login

# Create Service Principal
az ad sp create-for-rbac \
  --name "testcontainers-github-actions" \
  --role contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID

# Note the output:
# {
#   "appId": "YOUR_CLIENT_ID",
#   "displayName": "testcontainers-github-actions",
#   "password": "NOT_NEEDED_FOR_OIDC",
#   "tenant": "YOUR_TENANT_ID"
# }
```

#### 2. Configure Federated Credentials

```bash
# Get Service Principal Object ID
SP_OBJECT_ID=$(az ad sp list --display-name "testcontainers-github-actions" --query "[0].id" -o tsv)

# Create Federated Credential
az ad app federated-credential create \
  --id $SP_OBJECT_ID \
  --parameters '{
    "name": "testcontainers-github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main",
    "description": "GitHub Actions OIDC for main branch",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# For pull requests and other branches, add additional credentials:
az ad app federated-credential create \
  --id $SP_OBJECT_ID \
  --parameters '{
    "name": "testcontainers-github-all",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:pull_request",
    "description": "GitHub Actions OIDC for pull requests",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

#### 3. Create Terraform Backend Resources

```bash
cd infrastructure/Azure
chmod +x scripts/setup-terraform-backend.sh
export AZURE_LOCATION=eastus
export RESOURCE_GROUP_NAME=terraform-state-rg
export STORAGE_ACCOUNT_NAME=tfstatexxxxx  # Globally unique name
./scripts/setup-terraform-backend.sh
```

---

### AWS Prerequisites (Access Keys - Legacy)

For `deploy-aws-infrastructure.yml` (hybrid) and `destroy-aws-infrastructure.yml`:

#### 1. Create IAM User

```bash
aws iam create-user --user-name github-actions-terraform

# Attach policy (use least privilege in production)
aws iam attach-user-policy \
  --user-name github-actions-terraform \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

#### 2. Create Access Keys

```bash
aws iam create-access-key --user-name github-actions-terraform

# Output:
# {
#   "AccessKey": {
#     "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
#     "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
#     "Status": "Active"
#   }
# }
```

⚠️ **Security Warning:** Store access keys securely. Never commit to Git. Rotate every 90 days.

---

## Secrets Configuration

### Adding Secrets to GitHub

1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each required secret based on workflow choice

### AWS Secrets (OIDC - Pure)

Required for `deploy-aws-infrastructure-oidc.yml`:

```
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/GitHubActionsRole
PAT_TOKEN=ghp_xxxxxxxxxxxxx
```

**Note:** Backend resources (S3 bucket and DynamoDB table) are automatically created with names derived from your AWS Account ID:
- S3 Bucket: `testcontainers-terraform-state-{AWS_ACCOUNT_ID}`
- DynamoDB Table: `testcontainers-terraform-locks`

No secrets required for backend configuration or SSH access.

### AWS Secrets (Hybrid)

Additional secrets for `deploy-aws-infrastructure.yml`:

```
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**Note:** Backend resources are automatically managed (same as OIDC pure).

### Azure Secrets (OIDC - Pure)

Required for `deploy-azure-infrastructure.yml` and `destroy-azure-infrastructure.yml`:

```
AZURE_CLIENT_ID=12345678-1234-1234-1234-123456789012
AZURE_TENANT_ID=87654321-4321-4321-4321-210987654321
AZURE_SUBSCRIPTION_ID=abcdef12-3456-7890-abcd-ef1234567890
PAT_TOKEN=ghp_xxxxxxxxxxxxx
TERRAFORM_STATE_RG=terraform-state-rg
TERRAFORM_STATE_STORAGE=tfstatexxxxx
```

---

## Security Best Practices

### ✅ Recommended: Pure OIDC Authentication

**Why OIDC?**
1. **Zero Standing Privileges**: No long-lived credentials stored anywhere
2. **Automatic Expiration**: Tokens expire in 1 hour (cannot be reused)
3. **Impossible to Leak**: Tokens generated at runtime, never stored in secrets
4. **Fine-grained Control**: IAM trust policies can restrict by repo, branch, environment
5. **Better Audit Trail**: CloudTrail shows role session names (GitHubActions-TerraformApply)
6. **No Rotation Burden**: No need to rotate credentials every 90 days
7. **Compliance**: Meets SOC2, ISO 27001, PCI-DSS requirements

**OIDC Trust Policy Example (Restrictive):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:YourOrg/YourRepo:environment:prod"
        }
      }
    }
  ]
}
```

This restricts the role to only the `prod` environment of a specific repository.

### ⚠️ Legacy: Access Keys

**When access keys might be used:**
- Legacy systems not yet migrated to OIDC
- Organizations with compliance requirements for specific approval workflows
- Gradual migration path (hybrid approach)

**If using access keys:**
1. ✅ Rotate every 90 days (AWS recommendation)
2. ✅ Use least privilege IAM policies (not AdministratorAccess)
3. ✅ Enable CloudTrail logging
4. ✅ Use AWS Secrets Manager or GitHub encrypted secrets
5. ✅ Never commit keys to Git
6. ✅ Use separate IAM users for different environments
7. ✅ Enable MFA for IAM user console access
8. ✅ Set up AWS Config rules to detect overly permissive policies

### 🎯 Migration Path: Access Keys → Hybrid → Pure OIDC

**Phase 1: Access Keys (Current State)**
```yaml
# All jobs use access keys
aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

**Phase 2: Hybrid (Gradual Adoption)**
```yaml
# Read operations use OIDC
role-to-assume: ${{ secrets.AWS_ROLE_ARN }}  # Plan, backend setup

# Write operations use access keys
aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}  # Apply
aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

**Phase 3: Pure OIDC (Target State) ✅**
```yaml
# All operations use OIDC
role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
```

**Migration Steps:**
1. Set up AWS OIDC provider and IAM role (see Prerequisites)
2. Test OIDC with read-only operations (terraform plan)
3. Gradually move write operations (terraform apply) to OIDC
4. Monitor CloudTrail for any authentication issues
5. Once stable, remove access keys from IAM and secrets

### 📊 Comparison Table

| Feature | Access Keys | Hybrid | Pure OIDC |
|---------|-------------|--------|-----------|
| **Security Posture** | ⚠️ Low | ⚠️ Medium | ✅ High |
| **Credential Lifetime** | 90 days | Mixed | 1 hour |
| **Rotation Burden** | Manual | Partial | None |
| **Leak Risk** | High | Medium | None |
| **Compliance** | Requires controls | Partial | ✅ Full |
| **Audit Granularity** | IAM User | Mixed | Session names |
| **Setup Complexity** | Low | Medium | Medium |
| **AWS Recommendation** | ❌ Legacy | ⚠️ Transitional | ✅ Best Practice |

---

## Setup Guides

### Quick Start: Deploy AWS Infrastructure (OIDC)

1. **Complete AWS OIDC prerequisites** (see Prerequisites section)
2. **Add secrets to GitHub** (6 required secrets)
3. **Run workflow:**
   - Go to Actions → Deploy AWS Infrastructure (OIDC)
   - Click "Run workflow"
   - Select environment (dev/staging/prod)
   - Select AWS region
   - Click "Run workflow"
4. **Monitor deployment:**
   - Watch workflow logs for progress
   - Check Terraform outputs in job summary
5. **Verify runner:**
   - Go to Settings → Actions → Runners
   - Confirm self-hosted runner is online

### Quick Start: Deploy Azure Infrastructure

1. **Complete Azure OIDC prerequisites** (see Prerequisites section)
2. **Add secrets to GitHub** (6 required secrets)
3. **Run workflow:**
   - Go to Actions → Deploy Azure Infrastructure (OIDC)
   - Click "Run workflow"
   - Select environment (dev/staging/prod)
   - Select Azure location (eastus/westus2/etc.)
   - Click "Run workflow"
4. **Monitor deployment:**
   - Watch workflow logs
   - Check Terraform outputs
5. **Verify runner:**
   - Confirm Azure VM runner appears in GitHub

### Destroying Infrastructure

**AWS:**
1. Go to Actions → Destroy AWS Infrastructure
2. Click "Run workflow"
3. Select environment to destroy
4. **Type "destroy" in confirmation field**
5. Click "Run workflow"
6. Review destruction plan in logs
7. Confirm resources are deleted

**Azure:**
1. Go to Actions → Destroy Azure Infrastructure
2. Click "Run workflow"
3. Select environment to destroy
4. **Type "destroy" in confirmation field**
5. Click "Run workflow"
6. Review destruction in logs
7. Confirm resources are deleted

---

## Troubleshooting

### OIDC Authentication Failures

**Error:** `Error: Could not assume role with OIDC`

**Solutions:**
1. Verify OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```
2. Check IAM role trust policy (ensure repo matches)
3. Verify `id-token: write` permission in workflow
4. Check IAM role ARN is correct in secrets

### Terraform State Locking Issues

**Error:** `Error acquiring the state lock`

**Solutions:**
1. Check DynamoDB table exists
2. Verify state lock item in DynamoDB
3. Manually release lock (if stale):
   ```bash
   terraform force-unlock <LOCK_ID>
   ```

### Runner Registration Failures

**Error:** `Failed to register runner`

**Solutions:**
1. Verify PAT token has correct scopes (`repo`, `admin:org`)
2. Check PAT token hasn't expired
3. Ensure organization allows self-hosted runners
4. Verify runner labels are correct

### Azure Federated Credential Issues

**Error:** `AADSTS700016: Application not found in directory`

**Solutions:**
1. Verify Service Principal exists:
   ```bash
   az ad sp list --display-name "testcontainers-github-actions"
   ```
2. Check federated credential configuration:
   ```bash
   az ad app federated-credential list --id <APP_OBJECT_ID>
   ```
3. Ensure `subject` matches your repo exactly

---

## Contributing

When adding new workflows:
1. Follow OIDC authentication pattern (avoid access keys)
2. Include confirmation inputs for destructive operations
3. Use separate GitHub environments for prod deployments
4. Add comprehensive documentation to this README
5. Test in dev environment before merging

---

## References

- [AWS OIDC with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Azure OIDC with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [GitHub Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)

---

**Last Updated:** 2024  
**Maintained By:** TestContainers Infrastructure Team
