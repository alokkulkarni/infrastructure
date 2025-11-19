# Complete AWS OIDC Setup Guide for GitHub Actions

## Table of Contents

1. [Overview](#overview)
2. [Why OIDC?](#why-oidc)
3. [How It Works](#how-it-works)
4. [Prerequisites](#prerequisites)
5. [Setup Methods](#setup-methods)
6. [Testing](#testing)
7. [Migration from Access Keys](#migration-from-access-keys)
8. [Security Best Practices](#security-best-practices)
9. [Troubleshooting](#troubleshooting)

---

## Overview

OpenID Connect (OIDC) allows GitHub Actions to authenticate with AWS without storing long-lived credentials. This guide covers everything you need to set up and use OIDC for secure AWS deployments.

### What You'll Achieve

- ✅ No AWS credentials stored in GitHub
- ✅ Temporary credentials per workflow run
- ✅ Fine-grained IAM permissions
- ✅ Complete audit trail via CloudTrail
- ✅ Automatic credential rotation

---

## Why OIDC?

### Problems with Access Keys

**Traditional Approach:**
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

**Security Risks:**
- ❌ Long-lived credentials (no expiration)
- ❌ Can be stolen if repository is compromised
- ❌ Manual rotation required
- ❌ Hard to audit and track usage
- ❌ Repository-wide access (no granularity)
- ❌ Risk of accidental exposure in logs

### Benefits of OIDC

**Modern Approach:**
```yaml
permissions:
  id-token: write   # Required for OIDC
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: us-east-1
```

**Security Benefits:**
- ✅ Temporary credentials (auto-expire after ~1 hour)
- ✅ No static credentials in GitHub
- ✅ Automatic credential rotation
- ✅ Full CloudTrail audit trail
- ✅ Fine-grained permissions per branch/environment
- ✅ Cannot be reused outside GitHub Actions context
- ✅ Follows AWS security best practices

### Comparison

| Feature | Access Keys | OIDC |
|---------|-------------|------|
| **Setup Time** | 2 minutes | 5 minutes (one-time) |
| **Security Level** | ⚠️ Low | ✅ High |
| **Credential Lifetime** | Indefinite | ~1 hour |
| **Rotation** | Manual | Automatic |
| **Audit Trail** | Limited | Full CloudTrail |
| **Risk if Leaked** | High | None (context-bound) |
| **AWS Best Practice** | ❌ No | ✅ Yes |
| **Granular Access** | No | Yes (branch/env) |

---

## How It Works

### Authentication Flow

```
┌─────────────────────┐
│  GitHub Actions     │
│  Workflow           │
└──────────┬──────────┘
           │ 1. Request OIDC token
           ▼
┌─────────────────────┐
│  GitHub OIDC        │
│  Provider           │
└──────────┬──────────┘
           │ 2. Issue signed JWT token
           ▼
┌─────────────────────┐
│  AWS STS            │
│  (AssumeRoleWith    │
│   WebIdentity)      │
└──────────┬──────────┘
           │ 3. Validate token
           │ 4. Issue temporary AWS credentials
           ▼
┌─────────────────────┐
│  AWS Services       │
│  (EC2, S3, etc.)    │
└─────────────────────┘
```

### Token Claims

The OIDC token includes claims that AWS uses to validate access:

| Claim | Description | Example |
|-------|-------------|---------|
| **iss** (Issuer) | GitHub OIDC endpoint | `https://token.actions.githubusercontent.com` |
| **aud** (Audience) | AWS STS service | `sts.amazonaws.com` |
| **sub** (Subject) | Workflow context | `repo:org/repo:ref:refs/heads/main` |

### Subject Patterns

Configure different trust policies for different contexts:

#### Repository-Level (Specific Repo)

| Context | Subject Pattern |
|---------|----------------|
| Main branch | `repo:ORG/REPO:ref:refs/heads/main` |
| Specific branch | `repo:ORG/REPO:ref:refs/heads/BRANCH` |
| Any branch | `repo:ORG/REPO:ref:refs/heads/*` |
| Pull requests | `repo:ORG/REPO:pull_request` |
| Environment | `repo:ORG/REPO:environment:ENV` |
| Any repo action | `repo:ORG/REPO:*` |

#### Organization-Level (All Repos in Org)

| Context | Subject Pattern | Description |
|---------|----------------|-------------|
| **All repos, all branches** | `repo:ORG/*:*` | Any workflow in any repo under organization |
| **All repos, main only** | `repo:ORG/*:ref:refs/heads/main` | Only main branch workflows across all repos |
| **All repos, PRs only** | `repo:ORG/*:pull_request` | Only PR workflows across all repos |
| **All repos, specific env** | `repo:ORG/*:environment:production` | Only production environment across all repos |

#### User-Level (All Repos for User)

| Context | Subject Pattern | Description |
|---------|----------------|-------------|
| **All user repos** | `repo:USERNAME/*:*` | Any workflow in any repo under username |
| **User repos, main only** | `repo:USERNAME/*:ref:refs/heads/main` | Only main branch workflows for user repos |

#### Enterprise-Level (GitHub Enterprise)

| Context | Subject Pattern | Description |
|---------|----------------|-------------|
| **All enterprise repos** | `repo:*/*:*` | ⚠️ **Not recommended** - Too broad |
| **Enterprise with filter** | Use multiple specific patterns | Combine org-level patterns for better control |

**💡 Best Practice:** Use organization-level patterns for shared infrastructure roles, and repository-specific patterns for sensitive operations.

---

## Prerequisites

- AWS account with admin access
- GitHub repository with Actions enabled
- AWS CLI installed (optional, for verification)
- Terraform >= 1.0 (for Method 1)

### Required AWS Permissions

Your AWS user needs:
- IAM permissions to create OIDC providers
- IAM permissions to create and manage roles
- IAM permissions to attach policies

Check your permissions:
```bash
aws sts get-caller-identity
aws iam get-user
```

---

## Setup Methods

Choose one of three methods to set up OIDC:

### Method 1: Bootstrap with Terraform (Recommended)

This method creates the OIDC provider and IAM role using Terraform with temporary credentials.

#### Step 1: Create Bootstrap Directory

```bash
mkdir -p /tmp/aws-oidc-bootstrap
cd /tmp/aws-oidc-bootstrap
```

#### Step 2: Create Terraform Configuration

**Create `main.tf`:**

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's thumbprints (updated as of 2024)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name      = "github-oidc-provider"
    ManagedBy = "terraform-bootstrap"
  }
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-${var.environment}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name      = "${var.project_name}-${var.environment}-github-actions-role"
    ManagedBy = "terraform-bootstrap"
  }
}

# Trust policy - allows GitHub Actions to assume the role
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Choose ONE of the following patterns based on your needs:
      
      # Option 1: Single repository (most restrictive)
      # values = ["repo:${var.github_org}/${var.github_repo}:*"]
      
      # Option 2: All repositories in organization (recommended for shared infra)
      values = ["repo:${var.github_org}/*:*"]
      
      # Option 3: All repos, but only main branch
      # values = ["repo:${var.github_org}/*:ref:refs/heads/main"]
      
      # Option 4: Multiple specific repos
      # values = [
      #   "repo:${var.github_org}/repo1:*",
      #   "repo:${var.github_org}/repo2:*",
      #   "repo:${var.github_org}/repo3:*"
      # ]
      
      # Option 5: All repos in organization, only production environment
      # values = ["repo:${var.github_org}/*:environment:production"]
    }
  }
}

# Admin policy for initial setup (restrict this later for production)
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Outputs
output "role_arn" {
  description = "ARN of the IAM role - add this to GitHub secrets as AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
```

**Create `variables.tf`:**

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "testcontainers"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (optional - only needed for repo-specific access)"
  type        = string
  default     = "*"  # Wildcard for org-level access
}
```

**Create `terraform.tfvars`:**

```hcl
aws_region  = "us-east-1"
github_org  = "YOUR_GITHUB_ORG_OR_USERNAME"

# For organization-level access (recommended for shared infrastructure):
# Leave github_repo as default "*" or omit it

# For repository-specific access:
# github_repo = "YOUR_REPO_NAME"
```

#### Step 3: Apply Bootstrap Configuration

```bash
# Set temporary AWS credentials (one-time use)
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
# Optional: export AWS_SESSION_TOKEN="token" (if using MFA)

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (creates OIDC provider and role)
terraform apply

# ⚠️ IMPORTANT: Copy the role_arn from output
# Example: arn:aws:iam::123456789012:role/testcontainers-dev-github-actions-role
```

#### Step 4: Configure GitHub Secrets

Go to GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these secrets:

| Secret Name | Value | Description |
|------------|-------|-------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT:role/...` | From terraform output above |
| `AWS_REGION` | `us-east-1` | Your AWS region |
| `TERRAFORM_STATE_BUCKET` | `your-state-bucket` | S3 bucket for Terraform state |
| `TERRAFORM_LOCK_TABLE` | `your-lock-table` | DynamoDB table for locking |
| `PAT_TOKEN` | `ghp_...` | GitHub Personal Access Token (for runner) |

#### Step 5: Clean Up Bootstrap

```bash
cd /tmp/aws-oidc-bootstrap

# Option A: Keep resources, delete directory (recommended)
cd ..
rm -rf aws-oidc-bootstrap

# Option B: Destroy everything (not recommended)
# terraform destroy
```

The OIDC provider and role remain in AWS and can be managed through your main Terraform configuration going forward.

---

### Method 2: AWS Console Setup

#### Step 1: Create OIDC Provider

1. Open [AWS Console](https://console.aws.amazon.com)
2. Go to **IAM** → **Identity providers**
3. Click **Add provider**
4. Select **OpenID Connect**
5. Configure:
   - **Provider URL**: `https://token.actions.githubusercontent.com`
   - **Audience**: `sts.amazonaws.com`
6. Click **Get thumbprint** (auto-populated)
7. Click **Add provider**

#### Step 2: Create IAM Role

1. Go to **IAM** → **Roles** → **Create role**
2. Select **Web identity**
3. Configure:
   - **Identity provider**: Select the GitHub provider you created
   - **Audience**: `sts.amazonaws.com`
4. Click **Next**
5. Attach permissions policies:
   - For testing: `AdministratorAccess`
   - For production: Create custom policy (see Security Best Practices)
6. Name: `testcontainers-dev-github-actions-role`
7. Click **Create role**

#### Step 3: Edit Trust Policy

1. Open the role you created
2. Go to **Trust relationships** → **Edit trust policy**
3. Replace with one of the following options:

**Option A: Organization-Level (All Repos in Org) - Recommended**

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
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/*:*"
        }
      }
    }
  ]
}
```

**Option B: Repository-Specific**

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

**Option C: User-Level (All Repos for Username)**

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
          "token.actions.githubusercontent.com:sub": "repo:YOUR_USERNAME/*:*"
        }
      }
    }
  ]
}
```

**Replace:**
- `YOUR_ACCOUNT_ID` with your AWS account ID
- `YOUR_ORG` with your GitHub organization name
- `YOUR_REPO` with repository name (Option B only)
- `YOUR_USERNAME` with your GitHub username (Option C only)

4. Click **Update policy**

#### Step 4: Copy Role ARN

1. In the role summary, copy the **ARN**
2. Example: `arn:aws:iam::123456789012:role/testcontainers-dev-github-actions-role`
3. Add this to GitHub Secrets as `AWS_ROLE_ARN`

---

### Method 3: AWS CLI Setup

#### Step 1: Set Variables

```bash
export AWS_REGION="us-east-1"
export ROLE_NAME="testcontainers-dev-github-actions-role"
export GITHUB_ORG="YOUR_GITHUB_ORG"  # or USERNAME for user-level
# export GITHUB_REPO="YOUR_REPO_NAME"  # Only needed for repo-specific access
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

#### Step 2: Create OIDC Provider

```bash
# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd

# Get provider ARN
export OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text)

echo "OIDC Provider ARN: $OIDC_PROVIDER_ARN"
```

#### Step 3: Create Trust Policy

Choose the appropriate pattern for your use case:

```bash
# Option A: Organization-Level (All repos in org) - Recommended
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$OIDC_PROVIDER_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_ORG/*:*"
        }
      }
    }
  ]
}
EOF

# Option B: Repository-Specific
# Change "repo:$GITHUB_ORG/*:*" to "repo:$GITHUB_ORG/$GITHUB_REPO:*"

# Option C: User-Level (all repos for a user)
# Change "repo:$GITHUB_ORG/*:*" to "repo:$YOUR_USERNAME/*:*"

# Option D: Organization-Level, Main Branch Only
# Change "repo:$GITHUB_ORG/*:*" to "repo:$GITHUB_ORG/*:ref:refs/heads/main"
```

#### Step 4: Create IAM Role

```bash
# Create role
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://trust-policy.json

# Attach admin policy (for initial setup)
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Get role ARN
export ROLE_ARN=$(aws iam get-role \
  --role-name $ROLE_NAME \
  --query Role.Arn \
  --output text)

echo "Role ARN: $ROLE_ARN"
echo "Add this to GitHub Secrets as AWS_ROLE_ARN"
```

#### Step 5: Verify Setup

```bash
# List OIDC providers
aws iam list-open-id-connect-providers

# Get role details
aws iam get-role --role-name $ROLE_NAME

# List attached policies
aws iam list-attached-role-policies --role-name $ROLE_NAME
```

---

## Testing

### Test 1: Verify OIDC Provider

```bash
# Check OIDC provider exists
aws iam list-open-id-connect-providers

# Get provider details
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn <provider-arn>
```

### Test 2: Verify IAM Role

```bash
# Get role
aws iam get-role --role-name testcontainers-dev-github-actions-role

# Get trust policy
aws iam get-role --role-name testcontainers-dev-github-actions-role \
  --query Role.AssumeRolePolicyDocument
```

### Test 3: Manual Workflow Run

1. Go to GitHub repository → **Actions**
2. Select **Deploy AWS Infrastructure (OIDC)**
3. Click **Run workflow**
4. Select environment and region
5. Click **Run workflow**

**Expected Results:**
- ✅ All jobs complete successfully
- ✅ No AWS credential errors
- ✅ Terraform outputs in summary
- ✅ Resources created in AWS

### Test 4: Check CloudTrail

```bash
# View recent AssumeRoleWithWebIdentity events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 10
```

You should see events showing GitHub Actions assuming your role.

### Test 5: Verify Workflow Output

Check the workflow logs for:

```
Run aws-actions/configure-aws-credentials@v4
✓ Credentials loaded from OIDC
✓ Using role: arn:aws:iam::ACCOUNT:role/testcontainers-dev-github-actions-role
✓ Session name: GitHubActions
```

---

## Migration from Access Keys

If you're currently using `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, follow these steps to migrate safely.

### Step 1: Keep Old Workflow as Backup

```bash
# Backup current workflow
cp .github/workflows/deploy-aws-infrastructure.yml \
   .github/workflows/deploy-aws-infrastructure-legacy.yml
```

### Step 2: Update Workflow to Use OIDC

**Old workflow (access keys):**
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1
```

**New workflow (OIDC):**
```yaml
permissions:
  id-token: write   # Required for OIDC
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS credentials using OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
          role-session-name: GitHubActions
```

### Step 3: Test OIDC Workflow

1. Run the new OIDC workflow
2. Verify all steps complete successfully
3. Check resources are created correctly
4. Confirm no credential errors

### Step 4: Remove Old Secrets

Once OIDC is confirmed working:

1. Go to GitHub repository → **Settings** → **Secrets and variables** → **Actions**
2. Delete:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
3. Keep `AWS_ROLE_ARN` and other OIDC secrets

### Step 5: Rotate Access Keys

If the old keys were compromised or no longer needed:

```bash
# List access keys
aws iam list-access-keys --user-name YOUR_IAM_USER

# Deactivate old key
aws iam update-access-key \
  --access-key-id AKIAIOSFODNN7EXAMPLE \
  --status Inactive \
  --user-name YOUR_IAM_USER

# Delete old key (after confirming OIDC works)
aws iam delete-access-key \
  --access-key-id AKIAIOSFODNN7EXAMPLE \
  --user-name YOUR_IAM_USER
```

### Step 6: Clean Up Legacy Workflow

After confirming OIDC works for a week:

```bash
# Delete legacy workflow file
rm .github/workflows/deploy-aws-infrastructure-legacy.yml
```

---

## Security Best Practices

### 1. Use Least Privilege Permissions

Replace `AdministratorAccess` with specific permissions:

**Example custom policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "vpc:*",
        "iam:GetRole",
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PassRole",
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

Apply the policy:
```bash
aws iam put-role-policy \
  --role-name testcontainers-dev-github-actions-role \
  --policy-name CustomPermissions \
  --policy-document file://custom-policy.json

# Remove admin access
aws iam detach-role-policy \
  --role-name testcontainers-dev-github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### 2. Restrict by Branch/Environment

**Allow only main branch:**
```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:ref:refs/heads/main"
    }
  }
}
```

**Allow specific environments:**
```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": [
        "repo:ORG/REPO:environment:production",
        "repo:ORG/REPO:environment:staging"
      ]
    }
  }
}
```

### 3. Enable CloudTrail Logging

```bash
# Create CloudTrail for audit logging
aws cloudtrail create-trail \
  --name github-actions-audit \
  --s3-bucket-name my-cloudtrail-bucket

# Start logging
aws cloudtrail start-logging --name github-actions-audit
```

### 4. Set Session Duration

Limit how long the temporary credentials are valid:

```bash
# Set max session duration to 1 hour
aws iam update-role \
  --role-name testcontainers-dev-github-actions-role \
  --max-session-duration 3600
```

### 5. Monitor with CloudWatch

Create alarms for suspicious activity:

```bash
# Example: Alert on AssumeRole failures
aws cloudwatch put-metric-alarm \
  --alarm-name github-oidc-assume-role-failures \
  --alarm-description "Alert on OIDC AssumeRole failures" \
  --metric-name AssumeRoleFailures \
  --namespace AWS/IAM \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold
```

### 6. Use Separate Roles per Environment

```bash
# Development role (more permissive)
testcontainers-dev-github-actions-role

# Staging role (restricted)
testcontainers-staging-github-actions-role

# Production role (most restricted, requires approval)
testcontainers-prod-github-actions-role
```

### 7. Regular Audits

```bash
# List all OIDC providers
aws iam list-open-id-connect-providers

# Check role trust policies
aws iam get-role --role-name <role-name>

# Review role permissions
aws iam list-attached-role-policies --role-name <role-name>
aws iam list-role-policies --role-name <role-name>

# Check recent AssumeRole events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity
```

---

## Troubleshooting

### Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause:** Trust policy is incorrect or repository name doesn't match.

**Solutions:**

1. **Check trust policy:**
```bash
aws iam get-role --role-name testcontainers-dev-github-actions-role \
  --query Role.AssumeRolePolicyDocument
```

2. **Verify subject matches your repo:**
```json
{
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
    }
  }
}
```

3. **Check OIDC provider exists:**
```bash
aws iam list-open-id-connect-providers
```

### Error: "No OIDC provider found"

**Cause:** OIDC provider not created or wrong URL.

**Solution:**

```bash
# Check if provider exists
aws iam list-open-id-connect-providers

# Create provider if missing
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Error: "Access Denied" during Terraform operations

**Cause:** IAM role lacks necessary permissions.

**Solutions:**

1. **Check attached policies:**
```bash
aws iam list-attached-role-policies \
  --role-name testcontainers-dev-github-actions-role
```

2. **Temporarily attach AdministratorAccess for testing:**
```bash
aws iam attach-role-policy \
  --role-name testcontainers-dev-github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

3. **Check CloudTrail to see which actions are denied:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AccessDenied \
  --max-results 10
```

### Error: "Error assuming role"

**Cause:** Workflow doesn't have `id-token: write` permission.

**Solution:**

Ensure job has proper permissions:
```yaml
permissions:
  id-token: write   # Required for OIDC
  contents: read
```

### Error: "Invalid identity token"

**Cause:** Token expired or workflow configuration issue.

**Solutions:**

1. **Check workflow syntax:**
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: us-east-1
    role-session-name: GitHubActions
```

2. **Verify AWS_ROLE_ARN secret is correct:**
- Go to Settings → Secrets → Check `AWS_ROLE_ARN`
- Should be: `arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME`

3. **Check role ARN format:**
```bash
echo $AWS_ROLE_ARN | grep -E '^arn:aws:iam::[0-9]+:role/.+$'
```

### Debugging Tips

**Enable debug logging in workflow:**
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: us-east-1
  env:
    ACTIONS_RUNNER_DEBUG: true
    ACTIONS_STEP_DEBUG: true
```

**Check workflow logs:**
Look for lines containing:
- `Requesting OIDC token`
- `Token claims`
- `Assuming role`
- `Credentials loaded`

**Verify from AWS CLI:**
```bash
# Check if provider exists
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com

# Get role trust policy
aws iam get-role --role-name testcontainers-dev-github-actions-role

# Simulate AssumeRole (requires the OIDC token)
# This can only be done from within GitHub Actions
```

---

## Additional Resources

- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
- [AWS Security Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS STS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)

---

## Summary

### What You've Achieved

✅ **Secure Authentication**: No AWS credentials stored in GitHub
✅ **Temporary Credentials**: Auto-expire after ~1 hour
✅ **Fine-Grained Access**: Control per branch/environment
✅ **Complete Audit Trail**: CloudTrail logs all actions
✅ **AWS Best Practices**: Follows AWS security recommendations
✅ **Automatic Rotation**: No manual credential management

### Quick Reference

**Required GitHub Secrets:**
- `AWS_ROLE_ARN` - IAM role ARN
- `AWS_REGION` - AWS region
- `TERRAFORM_STATE_BUCKET` - S3 bucket for state
- `TERRAFORM_LOCK_TABLE` - DynamoDB table for locking
- `PAT_TOKEN` - GitHub PAT for runner

**Workflow Configuration:**
```yaml
permissions:
  id-token: write
  contents: read

- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ${{ secrets.AWS_REGION }}
```

**Key Commands:**
```bash
# List OIDC providers
aws iam list-open-id-connect-providers

# Get role details
aws iam get-role --role-name ROLE_NAME

# Check recent OIDC authentications
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity
```

You can now run GitHub Actions workflows that interact with AWS securely without storing long-lived credentials!
