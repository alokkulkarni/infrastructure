# AWS OIDC Setup Guide for GitHub Actions

This guide explains how to set up OpenID Connect (OIDC) authentication for GitHub Actions, eliminating the need for long-lived AWS credentials.

## 🔒 Why OIDC?

**Security Benefits:**
- ✅ No long-lived AWS credentials stored in GitHub
- ✅ Credentials are temporary and automatically rotated
- ✅ Fine-grained permission control via IAM policies
- ✅ Audit trail of all AWS actions via CloudTrail
- ✅ Follows AWS security best practices
- ✅ Eliminates risk of credential leakage

**vs Traditional Approach:**
- ❌ AWS Access Keys can be stolen if repository is compromised
- ❌ Keys have no automatic expiration
- ❌ Harder to audit and rotate
- ❌ Requires manual key management

## 📋 Prerequisites

- AWS Account with admin access
- GitHub repository
- AWS CLI installed (optional, for manual setup)

## 🚀 Setup Methods

### Method 1: Bootstrap with Terraform (Recommended)

This method creates the OIDC provider and IAM role using a separate Terraform configuration with temporary credentials.

#### Step 1: Create Bootstrap Configuration

Create a temporary directory for the bootstrap:

```bash
mkdir -p /tmp/aws-oidc-bootstrap
cd /tmp/aws-oidc-bootstrap
```

Create `main.tf`:

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
      # Allow this GitHub repo to assume the role
      values = [
        "repo:${var.github_org}/${var.github_repo}:*"
      ]
    }
  }
}

# Admin policy for initial setup (you can restrict this later)
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

Create `variables.tf`:

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
  description = "GitHub repository name"
  type        = string
}
```

Create `terraform.tfvars`:

```hcl
aws_region  = "us-east-1"
github_org  = "YOUR_GITHUB_ORG_OR_USERNAME"
github_repo = "YOUR_REPO_NAME"
```

#### Step 2: Apply Bootstrap Configuration

```bash
# Export temporary AWS credentials (these will be used only once)
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"

# Initialize and apply
terraform init
terraform plan
terraform apply

# IMPORTANT: Copy the role_arn from output
# Example: arn:aws:iam::123456789012:role/testcontainers-dev-github-actions-role
```

#### Step 3: Configure GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

Add the following secrets:

| Secret Name | Value | Description |
|------------|-------|-------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT:role/...` | From terraform output |
| `TERRAFORM_STATE_BUCKET` | `your-state-bucket` | S3 bucket for Terraform state |
| `TERRAFORM_LOCK_TABLE` | `your-lock-table` | DynamoDB table for locking |
| `PAT_TOKEN` | `ghp_...` | GitHub Personal Access Token for runner |

#### Step 4: Clean Up Bootstrap

```bash
# After confirming GitHub Actions works, you can clean up
cd /tmp/aws-oidc-bootstrap

# Option A: Keep the OIDC setup (recommended)
# Just delete the directory, resources remain in AWS
rm -rf /tmp/aws-oidc-bootstrap

# Option B: Remove bootstrap state but keep resources
terraform state rm aws_iam_openid_connect_provider.github
terraform state rm aws_iam_role.github_actions
terraform state rm aws_iam_role_policy_attachment.admin
rm -rf /tmp/aws-oidc-bootstrap
```

### Method 2: AWS Console Setup

#### Step 1: Create OIDC Provider

1. Go to AWS Console → IAM → Identity providers
2. Click "Add provider"
3. Choose "OpenID Connect"
4. Configure:
   - **Provider URL**: `https://token.actions.githubusercontent.com`
   - **Audience**: `sts.amazonaws.com`
5. Click "Add provider"

#### Step 2: Create IAM Role

1. Go to IAM → Roles → Create role
2. Select "Web identity"
3. Configure:
   - **Identity provider**: Choose the GitHub provider you just created
   - **Audience**: `sts.amazonaws.com`
4. Click "Next"
5. Attach policies (start with `AdministratorAccess` for initial setup)
6. Name the role: `testcontainers-dev-github-actions-role`
7. Click "Create role"

#### Step 3: Edit Trust Policy

1. Open the role you just created
2. Go to "Trust relationships" → Edit trust policy
3. Replace with:

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

Replace:
- `YOUR_ACCOUNT_ID` with your AWS account ID
- `YOUR_ORG/YOUR_REPO` with your GitHub org and repo

#### Step 4: Configure GitHub Secrets

Same as Method 1, Step 3 above.

## 🧪 Testing the Setup

### Test 1: Manual Workflow Run

1. Go to your repository → Actions
2. Select "Deploy AWS Infrastructure (OIDC)"
3. Click "Run workflow"
4. Select environment and region
5. Click "Run workflow"

If successful, you'll see:
- ✅ All jobs complete successfully
- ✅ No AWS credential errors
- ✅ Terraform outputs in the summary

### Test 2: Verify Assumed Role

Check CloudTrail for `AssumeRoleWithWebIdentity` events to confirm OIDC is working.

## 🔧 Migrating from Access Keys

If you're currently using `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`:

### Step 1: Keep Old Workflow as Backup

```bash
cp .github/workflows/deploy-aws-infrastructure.yml .github/workflows/deploy-aws-infrastructure-legacy.yml
```

### Step 2: Use New OIDC Workflow

```bash
mv .github/workflows/deploy-aws-infrastructure-oidc.yml .github/workflows/deploy-aws-infrastructure.yml
```

### Step 3: Test OIDC Workflow

Run the new workflow and verify it works.

### Step 4: Remove Old Secrets

Once confirmed working, remove:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Keep the legacy workflow file temporarily in case you need to rollback.

### Step 5: Rotate Access Keys

If the old keys were compromised or unused, rotate them in AWS IAM.

## 🎯 Least Privilege Permissions

After initial setup, replace `AdministratorAccess` with specific permissions.

The IAM OIDC module (`modules/iam-oidc/main.tf`) already includes fine-grained permissions for:
- EC2 management
- VPC/networking
- IAM role creation (for EC2 instances)
- S3 state bucket access
- DynamoDB state locking
- CloudWatch Logs
- Systems Manager (Session Manager)

To use these instead of admin access:

```hcl
# Remove admin policy attachment
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Use the module's fine-grained policy instead (already included in module)
```

## 🔍 Troubleshooting

### Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause**: Trust policy is incorrect or repository name doesn't match.

**Fix**: 
1. Check the trust policy includes your repo: `repo:YOUR_ORG/YOUR_REPO:*`
2. Ensure OIDC provider is created
3. Verify `AWS_ROLE_ARN` secret matches the role ARN

### Error: "No OIDC provider found"

**Cause**: OIDC provider not created or wrong URL.

**Fix**: 
1. Verify provider exists in IAM → Identity providers
2. Ensure URL is exactly: `https://token.actions.githubusercontent.com`

### Error: "Access Denied" during Terraform operations

**Cause**: IAM role lacks necessary permissions.

**Fix**: 
1. Temporarily attach `AdministratorAccess` to test
2. Review CloudTrail to see which actions are denied
3. Add specific permissions to the role policy

### Error: "Error assuming role"

**Cause**: Workflow doesn't have `id-token: write` permission.

**Fix**: Ensure job has:
```yaml
permissions:
  id-token: write
  contents: read
```

## 📚 Additional Resources

- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [AWS Security Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

## 🎉 Summary

After completing this setup:

✅ No AWS credentials stored in GitHub
✅ Temporary credentials per workflow run
✅ Fine-grained IAM permissions
✅ Complete audit trail
✅ Follows AWS security best practices

You can now run GitHub Actions workflows that interact with AWS securely without storing long-lived credentials!
