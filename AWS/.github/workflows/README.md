# GitHub Actions Workflows

This directory contains GitHub Actions workflows for deploying and managing AWS infrastructure.

## Available Workflows

### 1. Deploy AWS Infrastructure (`deploy-aws-infrastructure.yml`)

**Trigger**: Manual (workflow_dispatch)

**Purpose**: Deploys complete AWS infrastructure including VPC, EC2, and GitHub Actions runner.

**Jobs**:
1. **setup-backend**: Creates S3 bucket and DynamoDB table for Terraform state
2. **generate-runner-token**: Generates GitHub Actions runner registration token
3. **terraform-plan**: Plans infrastructure changes
4. **terraform-apply**: Applies infrastructure (requires environment approval if configured)

**Inputs**:
- `environment`: Environment to deploy (dev/staging/prod)
- `aws_region`: AWS region (default: us-east-1)

**Usage**:
```
1. Go to Actions tab
2. Select "Deploy AWS Infrastructure"
3. Click "Run workflow"
4. Choose environment and region
5. Click "Run workflow" button
```

### 2. Destroy AWS Infrastructure (`destroy-aws-infrastructure.yml`)

**Trigger**: Manual (workflow_dispatch)

**Purpose**: Destroys all AWS infrastructure resources.

**Jobs**:
1. **validate-confirmation**: Ensures user types "destroy" to confirm
2. **terraform-destroy**: Destroys all resources
3. **cleanup-backend-option**: Optional backend cleanup (dev environment only)

**Inputs**:
- `environment`: Environment to destroy
- `aws_region`: AWS region
- `confirm_destroy`: Type "destroy" to confirm (required)

**Usage**:
```
1. Go to Actions tab
2. Select "Destroy AWS Infrastructure"
3. Click "Run workflow"
4. Choose environment and region
5. Type "destroy" in confirmation field
6. Click "Run workflow" button
```

## Required Secrets

Configure these secrets in your repository:

**Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Description | Required | Example |
|------------|-------------|----------|---------|
| `AWS_ACCESS_KEY_ID` | AWS Access Key ID | ✅ Yes | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Access Key | ✅ Yes | `wJalrXUtnFEMI/K7MDENG/...` |
| `EC2_KEY_NAME` | EC2 Key Pair Name | ✅ Yes | `testcontainers-runner` |
| `PAT_TOKEN` | GitHub Personal Access Token | ✅ Yes | `ghp_xxxxxxxxxxxx` |
| `TERRAFORM_STATE_BUCKET` | S3 Bucket for State | ❌ No | `testcontainers-terraform-state` |
| `TERRAFORM_LOCK_TABLE` | DynamoDB Lock Table | ❌ No | `testcontainers-terraform-locks` |
| `ALLOWED_SSH_CIDR` | CIDR for SSH Access | ❌ No | `203.0.113.0/32` |

### Creating Required Secrets

#### 1. AWS Credentials

```bash
# If using AWS CLI profile
aws configure get aws_access_key_id
aws configure get aws_secret_access_key
```

Or create new IAM user with programmatic access:
1. AWS Console → IAM → Users → Add User
2. Enable "Programmatic access"
3. Attach policies: EC2, VPC, S3, DynamoDB, IAM
4. Save Access Key ID and Secret Access Key

#### 2. EC2 Key Pair

```bash
# Create new key pair
aws ec2 create-key-pair \
  --key-name testcontainers-runner \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/testcontainers-runner.pem

chmod 400 ~/.ssh/testcontainers-runner.pem

# Use the name (without .pem): testcontainers-runner
```

#### 3. GitHub Personal Access Token (PAT)

1. Go to: https://github.com/settings/tokens/new
2. Note: "Terraform Infrastructure Deployment"
3. Expiration: Choose appropriate duration
4. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
   - ✅ `admin:org` → `manage_runners:org` (if using org runners)
5. Generate token and save securely

#### 4. Get Your IP for SSH Access

```bash
# Get your public IP
curl -4 ifconfig.me

# Use as: YOUR_IP/32 (e.g., 203.0.113.25/32)
```

## Environment Configuration (Optional but Recommended)

Environments provide additional protection for production deployments.

### Creating Environments

1. Go to **Settings → Environments**
2. Click **New environment**
3. Create: `dev`, `staging`, `prod`, `dev-destroy`, `staging-destroy`, `prod-destroy`

### Environment Protection Rules

For `prod` and `prod-destroy`:

1. **Required reviewers**: Add team members who must approve
2. **Wait timer**: Optional delay before deployment (e.g., 5 minutes)
3. **Deployment branches**: Restrict to `main` or `production` branch

Example configuration:
```
Environment: prod
├── Required reviewers: @devops-team
├── Wait timer: 300 seconds (5 minutes)
└── Deployment branches: main, release/*
```

## Workflow Execution Flow

### Deploy Workflow

```mermaid
graph TD
    A[Manual Trigger] --> B[Setup Backend]
    B --> C[Generate Runner Token]
    C --> D[Terraform Plan]
    D --> E{Environment<br/>Approval?}
    E -->|Required| F[Wait for Approval]
    E -->|Not Required| G[Terraform Apply]
    F --> G
    G --> H[Output Results]
    H --> I[Upload Outputs]
```

### Destroy Workflow

```mermaid
graph TD
    A[Manual Trigger] --> B{Type 'destroy'?}
    B -->|No| C[Fail - Confirmation Required]
    B -->|Yes| D{Environment<br/>Approval?}
    D -->|Required| E[Wait for Approval]
    D -->|Not Required| F[Terraform Destroy]
    E --> F
    F --> G[Verify Destruction]
    G --> H{Dev Environment?}
    H -->|Yes| I[Show Backend Cleanup Info]
    H -->|No| J[Complete]
    I --> J
```

## Monitoring Workflow Runs

### View Workflow Status

1. Go to **Actions** tab
2. Select workflow from left sidebar
3. Click on specific run to view details

### Understanding Job Status

- 🟢 **Green**: Job completed successfully
- 🟡 **Yellow**: Job in progress or waiting
- 🔴 **Red**: Job failed
- ⚪ **Gray**: Job skipped or not run

### Viewing Logs

1. Click on workflow run
2. Click on specific job (e.g., "Terraform Apply")
3. Click on step to view detailed logs
4. Download logs: Click "⋯" → "Download log archive"

## Advanced Usage

### Running with Custom Variables

Workflows use default values from `terraform.tfvars.example`. To override:

1. **Fork workflow file**
2. **Add workflow inputs** for custom values
3. **Modify terraform commands** to use inputs

Example:
```yaml
inputs:
  instance_type:
    description: 'EC2 Instance Type'
    required: false
    default: 't3.medium'
    type: choice
    options:
      - t3.small
      - t3.medium
      - t3.large
```

### Multiple Environments

Deploy to different environments:

```bash
# Dev environment (default)
Workflow → Run → environment: dev

# Staging environment
Workflow → Run → environment: staging

# Production environment
Workflow → Run → environment: prod
```

Each environment gets its own:
- State file: `aws/ec2-runner/{environment}/terraform.tfstate`
- Resources: Tagged with environment name
- Runner: Named with environment suffix

### Scheduled Destruction (Cost Saving)

To automatically destroy dev environment at night:

```yaml
# Add to destroy-aws-infrastructure.yml
on:
  schedule:
    - cron: '0 22 * * *'  # 10 PM UTC daily
  workflow_dispatch:
    # ... existing inputs
```

## Troubleshooting Workflows

### Common Issues

#### 1. "Terraform state locked"

**Cause**: Previous run was cancelled

**Solution**:
```bash
# Get lock ID from workflow logs
# Then manually unlock:
cd infrastructure/AWS/terraform
terraform init
terraform force-unlock <LOCK_ID>
```

#### 2. "Invalid AWS credentials"

**Cause**: Credentials expired or incorrect

**Solution**:
1. Verify secrets are set correctly
2. Check IAM user permissions
3. Generate new credentials if needed

#### 3. "Runner token expired"

**Cause**: Token is only valid for 1 hour

**Solution**: Re-run workflow (it generates fresh token automatically)

#### 4. "S3 bucket already exists"

**Cause**: Backend already setup

**Solution**: This is normal - backend setup is idempotent

### Debug Mode

Enable debug logging for workflows:

1. **Settings → Secrets → Actions**
2. Add secret: `ACTIONS_STEP_DEBUG` = `true`
3. Add secret: `ACTIONS_RUNNER_DEBUG` = `true`
4. Re-run workflow

## Security Best Practices

1. ✅ Use environment protection rules for production
2. ✅ Rotate AWS credentials regularly
3. ✅ Use minimal IAM permissions (principle of least privilege)
4. ✅ Never commit secrets to repository
5. ✅ Use GitHub environment secrets for sensitive values
6. ✅ Enable branch protection for main branch
7. ✅ Require code reviews for workflow changes
8. ✅ Set PAT token expiration
9. ✅ Monitor AWS CloudTrail for API calls
10. ✅ Enable GitHub audit log

## Workflow Maintenance

### Updating Terraform Version

Edit both workflow files:

```yaml
env:
  TF_VERSION: '1.7.0'  # Update version
```

### Updating AWS Region

Default region can be changed in workflow:

```yaml
env:
  AWS_REGION: 'us-west-2'  # Change default
```

### Modifying Resource Tags

Tags are applied via Terraform provider:

```hcl
# In main.tf
provider "aws" {
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = var.project_name
      Environment = var.environment
      Team        = "DevOps"        # Add custom tags
      CostCenter  = "Engineering"
    }
  }
}
```

## CI/CD Integration

### Using Self-Hosted Runner in Workflows

Once deployed, use the runner:

```yaml
name: My Workflow
on: [push]

jobs:
  build:
    runs-on: [self-hosted, aws, linux, docker]
    steps:
      - uses: actions/checkout@v4
      - name: Build with Docker
        run: docker build -t myapp .
```

### Runner Labels

Default labels:
- `self-hosted`
- `aws`
- `linux`
- `docker`
- `{environment}` (e.g., `dev`, `prod`)

Customize labels in workflow inputs or terraform.tfvars.

## Cost Monitoring

Track costs of workflow runs:

1. **AWS Cost Explorer**: Monitor EC2, NAT Gateway costs
2. **GitHub Actions Usage**: Settings → Billing → Actions
3. **Set Budget Alerts**: AWS Budgets for cost thresholds

## Getting Help

- 📖 **Full Documentation**: [README.md](../README.md)
- 🚀 **Quick Start**: [QUICKSTART.md](../QUICKSTART.md)
- 🐛 **Issues**: [Open GitHub Issue](../../issues)
- 💬 **Discussions**: [GitHub Discussions](../../discussions)

---

**Happy Deploying! 🚀**
