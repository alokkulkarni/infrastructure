# AWS Infrastructure for TestContainers

This directory contains Terraform code and GitHub Actions workflows to provision and manage AWS infrastructure for running GitHub Actions self-hosted runners with Docker support.

> **🔒 Security Update**: SSH access has been removed. The EC2 instance is now completely isolated with no SSH ingress. See [SECURITY_UPDATE.md](./SECURITY_UPDATE.md) for details.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [GitHub Actions Setup](#github-actions-setup)
- [Nginx Reverse Proxy](#nginx-reverse-proxy)
- [Usage](#usage)
- [Terraform Modules](#terraform-modules)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## 🎯 Overview

This infrastructure provides:

- **VPC** with public and private subnets in a single availability zone
- **NAT Gateway** for egress-only internet access from private subnet
- **EC2 Instance** in private subnet with:
  - Docker Engine and Docker Compose
  - Nginx reverse proxy (as Docker container)
  - GitHub Actions self-hosted runner
  - Automated setup and configuration
- **S3 Backend** for Terraform state management
- **DynamoDB** table for state locking
- **Security Groups** with least-privilege access
- **No SSH Access** - completely isolated instance

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                   │
│                                                             │
│  ┌─────────────────────┐      ┌─────────────────────┐     │
│  │  Public Subnet      │      │  Private Subnet     │     │
│  │  (10.0.1.0/24)      │      │  (10.0.2.0/24)      │     │
│  │                     │      │                     │     │
│  │  ┌──────────────┐   │      │  ┌──────────────┐  │     │
│  │  │              │   │      │  │   EC2        │  │     │
│  │  │ NAT Gateway  │◄──┼──────┼──│   - Docker   │  │     │
│  │  │              │   │      │  │   - Nginx    │  │     │
│  │  └──────┬───────┘   │      │  │   - Runner   │  │     │
│  │         │           │      │  │   (No SSH)   │  │     │
│  │         │           │      │  └──────────────┘  │     │
│  └─────────┼───────────┘      └─────────────────────┘     │
│            │                                               │
│  ┌─────────▼───────────┐                                  │
│  │  Internet Gateway   │                                  │
│  └─────────────────────┘                                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
                   Internet
          (GitHub.com + Package Repos)

Service Flow:
Internet → EC2:80 → Nginx Container → app-network → Your Services
```

**Key Security Features:**
- ✅ No SSH access - instance is completely isolated
- ✅ EC2 in private subnet - no direct internet access
- ✅ Egress-only through NAT Gateway
- ✅ Nginx runs as Docker container with service discovery
```

## ✅ Prerequisites

### 1. Required Tools

- **AWS CLI** (v2.x): [Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (v1.6+): [Installation Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- **GitHub CLI** (optional): [Installation Guide](https://cli.github.com/)
- **Git**: [Installation Guide](https://git-scm.com/downloads)

### 2. AWS Account Setup

1. **AWS Account** with appropriate permissions
2. **IAM User** or **IAM Role** with the following permissions:
   - EC2 (full access)
   - VPC (full access)
   - S3 (full access)
   - DynamoDB (full access)
   - IAM (role creation)
   - Systems Manager (for accessing instance without SSH)

3. **AWS Credentials** configured:
   ```bash
   aws configure
   # Or set environment variables:
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_DEFAULT_REGION="us-east-1"
   ```

> **Note**: SSH key pairs are no longer required. Access the instance using AWS Systems Manager Session Manager if needed.

### 3. GitHub Setup

1. **GitHub Personal Access Token (PAT)** with the following scopes:
   - `repo` (full control)
   - `workflow`
   - `admin:org` (if using organization runners)

2. Create PAT at: https://github.com/settings/tokens/new

## 🚀 Quick Start

### Step 1: Clone Repository

```bash
git clone https://github.com/yourusername/your-repo.git
cd your-repo/infrastructure/AWS
```

### Step 2: Setup Terraform Backend

```bash
# Set up S3 bucket and DynamoDB table for state management
export AWS_REGION="us-east-1"
export TERRAFORM_STATE_BUCKET="testcontainers-terraform-state"
export TERRAFORM_LOCK_TABLE="testcontainers-terraform-locks"

./scripts/setup-terraform-backend.sh
```

### Step 3: Configure Terraform Variables

```bash
cd terraform

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

Update the following required variables:
- `key_name`: Your EC2 key pair name
- `github_repo_url`: Your GitHub repository URL
- `allowed_ssh_cidr`: Your IP address for SSH access

### Step 4: Generate GitHub Runner Token

```bash
# Option 1: Using GitHub CLI
cd ../scripts
./generate-runner-token.sh yourusername/your-repo

# Option 2: Using GitHub API
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: token YOUR_PAT_TOKEN" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/registration-token
```

### Step 5: Deploy Infrastructure

```bash
cd ../terraform

# Initialize Terraform
terraform init

# Preview changes
terraform plan -var="github_runner_token=YOUR_TOKEN"

# Apply changes
terraform apply -var="github_runner_token=YOUR_TOKEN"
```

### Step 6: Verify Deployment

```bash
# Check outputs
terraform output

# Verify runner is online in GitHub
# Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/settings/actions/runners
```

## ⚙️ Configuration

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region to deploy | `us-east-1` | No |
| `project_name` | Project name for resource naming | `testcontainers` | No |
| `environment` | Environment (dev/staging/prod) | `dev` | No |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` | No |
| `availability_zone` | Availability zone | `us-east-1a` | No |
| `public_subnet_cidr` | Public subnet CIDR | `10.0.1.0/24` | No |
| `private_subnet_cidr` | Private subnet CIDR | `10.0.2.0/24` | No |
| `instance_type` | EC2 instance type | `t3.medium` | No |
| `github_repo_url` | GitHub repository URL | - | **Yes** |
| `github_runner_token` | Runner registration token | - | **Yes** (auto-generated in workflows) |
| `github_runner_name` | Runner name | `aws-ec2-runner` | No |
| `github_runner_labels` | Runner labels | `["self-hosted", "aws", "linux"]` | No |

> **🔒 Security Note**: `key_name` and `allowed_ssh_cidr` have been removed. No SSH access is provided.

### Environment Variables

For GitHub Actions, these should be set as secrets:

```bash
# Required Secrets
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
PAT_TOKEN                    # For GitHub runner registration

# Optional Secrets (with defaults)
TERRAFORM_STATE_BUCKET      # Default: testcontainers-terraform-state
TERRAFORM_LOCK_TABLE         # Default: testcontainers-terraform-locks
```

## 🔄 GitHub Actions Setup

### Configure Repository Secrets

1. Go to your repository on GitHub
2. Navigate to: **Settings → Secrets and variables → Actions**
3. Add the following secrets:

#### Required Secrets:

```
AWS_ACCESS_KEY_ID          = Your AWS Access Key ID
AWS_SECRET_ACCESS_KEY      = Your AWS Secret Access Key
PAT_TOKEN                  = GitHub Personal Access Token with repo & workflow scopes
```

#### Optional Secrets (with defaults):

```
TERRAFORM_STATE_BUCKET    = testcontainers-terraform-state
TERRAFORM_LOCK_TABLE      = testcontainers-terraform-locks
```

> **🔒 Note**: `EC2_KEY_NAME` and `ALLOWED_SSH_CIDR` are no longer needed as SSH has been disabled.

### Create GitHub Environments (Optional but Recommended)

For production safety, create environments:

1. Go to **Settings → Environments**
2. Create environments: `dev`, `staging`, `prod`, `dev-destroy`, etc.
3. Add protection rules:
   - Required reviewers
   - Wait timer
   - Deployment branches

### Using the Workflows

#### Deploy Infrastructure

1. Go to **Actions** tab
2. Select **Deploy AWS Infrastructure**
3. Click **Run workflow**
4. Choose:
   - Environment (dev/staging/prod)
   - AWS Region
5. Click **Run workflow**

The workflow will:
1. Setup Terraform backend (S3 + DynamoDB)
2. Generate GitHub runner token
3. Run `terraform plan`
4. Wait for approval (if environment protection is enabled)
5. Run `terraform apply`
6. Output infrastructure details

#### Destroy Infrastructure

1. Go to **Actions** tab
2. Select **Destroy AWS Infrastructure**
3. Click **Run workflow**
4. Choose:
   - Environment to destroy
   - AWS Region
   - Type "destroy" to confirm
5. Click **Run workflow**

⚠️ **Warning**: This will permanently delete all infrastructure!

## 🌐 Nginx Reverse Proxy

The infrastructure includes Nginx running as a Docker container that acts as a reverse proxy for all your services.

### How It Works

1. **Docker Network**: A shared network `app-network` is created
2. **Nginx Container**: Runs on this network with ports 80/443 exposed
3. **Service Discovery**: Services reference each other by container name
4. **Dynamic Routing**: Add config files to route traffic to your services

### Quick Example

Deploy a service:
```bash
docker run -d \
  --name my-api \
  --network app-network \
  -p 8080:8080 \
  my-api:latest
```

Add Nginx config (`/opt/nginx/conf.d/my-api.conf`):
```nginx
upstream api_backend {
    server my-api:8080;
}

server {
    listen 80;
    location /api/ {
        proxy_pass http://api_backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Reload Nginx:
```bash
docker exec nginx nginx -s reload
```

Access: `http://<ec2-public-ip>/api/`

### Complete Guide

For detailed configuration examples, routing patterns, and troubleshooting:
- **[NGINX_CONFIGURATION.md](./NGINX_CONFIGURATION.md)** - Complete Nginx setup guide

## 📦 Terraform Modules

### Module Structure

```
terraform/
├── main.tf                 # Root module
├── variables.tf            # Input variables
├── outputs.tf             # Output values
├── backend.tf             # S3 backend configuration
├── terraform.tfvars.example
└── modules/
    ├── networking/        # VPC, subnets, NAT, IGW
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── security/          # Security groups
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── ec2/               # EC2 instance, IAM role
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── user-data.sh   # Instance initialization
```

### Networking Module

Creates:
- VPC with DNS support
- Public subnet (for NAT Gateway)
- Private subnet (for EC2)
- Internet Gateway
- NAT Gateway with Elastic IP
- Route tables and associations
- VPC endpoint for S3

### Security Module

Creates:
- Security group for EC2 with:
  - Ingress: SSH (22), HTTP (80), HTTPS (443)
  - Egress: All traffic (for GitHub, package downloads)

### EC2 Module

Creates:
- IAM role and instance profile
- EC2 instance in private subnet
- User data script that installs:
  - Docker Engine
  - Docker Compose plugin
  - Nginx reverse proxy
  - GitHub Actions runner
  - AWS CLI
  - Node.js, Python
  - Additional build tools

## 🔍 Troubleshooting

### SSH Access to EC2 Instance

Since the EC2 is in a private subnet, you need to use AWS Systems Manager Session Manager or SSH through a bastion:

#### Option 1: AWS Systems Manager (Recommended)

```bash
# Install Session Manager plugin
# https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

# Connect to instance
aws ssm start-session --target i-1234567890abcdef0
```

#### Option 2: SSH Tunnel through NAT

```bash
# Get NAT Gateway public IP
terraform output nat_gateway_public_ip

# Note: Direct SSH won't work as NAT doesn't forward traffic
# Consider adding a bastion host for SSH access
```

### Check Runner Status

```bash
# On the EC2 instance
sudo systemctl status github-runner

# Check runner logs
sudo journalctl -u github-runner -f

# Manual runner logs
sudo su - runner
cd ~/actions-runner
tail -f _diag/Runner_*.log
```

### View User Data Logs

```bash
# SSH to instance (via Session Manager)
tail -f /var/log/user-data.log
```

### Common Issues

#### 1. Runner Not Registering

**Problem**: Runner token expired (tokens expire after 1 hour)

**Solution**: Generate a new token and update:
```bash
./scripts/generate-runner-token.sh yourusername/your-repo
terraform apply -var="github_runner_token=NEW_TOKEN"
```

#### 2. EC2 Instance Can't Access Internet

**Check**:
- NAT Gateway is running
- Route table has route to NAT
- Security group allows egress

```bash
terraform state show module.networking.aws_nat_gateway.main
terraform state show module.networking.aws_route_table.private
```

#### 3. Terraform State Locked

**Problem**: Previous operation was interrupted

**Solution**:
```bash
# Get lock ID from error message
terraform force-unlock LOCK_ID
```

#### 4. Cannot SSH to Instance

**Problem**: Instance is in private subnet

**Solution**: Use AWS Systems Manager Session Manager or add bastion host

### Debug Mode

Enable Terraform debug logging:

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log
terraform apply
```

## 🧹 Cleanup

### Option 1: Using GitHub Actions

1. Go to **Actions → Destroy AWS Infrastructure**
2. Run workflow with confirmation

### Option 2: Manual Terraform Destroy

```bash
cd terraform
terraform destroy -var="github_runner_token=dummy"
```

### Option 3: Complete Cleanup (including backend)

```bash
# Destroy infrastructure
cd terraform
terraform destroy

# Remove backend
cd ../scripts
./cleanup-backend.sh
```

⚠️ **Warning**: This removes all Terraform state files permanently!

## 📊 Cost Estimation

Approximate monthly costs (us-east-1):

| Resource | Cost |
|----------|------|
| EC2 t3.medium (24/7) | ~$30/month |
| NAT Gateway (24/7) | ~$32/month |
| NAT Gateway data processing | ~$0.045/GB |
| EBS 50GB gp3 | ~$4/month |
| S3 state storage | <$1/month |
| DynamoDB (on-demand) | <$1/month |
| **Total** | **~$67/month** |

### Cost Optimization Tips

1. **Stop EC2 when not needed**:
   ```bash
   aws ec2 stop-instances --instance-ids i-xxxxx
   ```
   Saves ~$30/month

2. **Use smaller instance type** for light workloads:
   - Change `instance_type = "t3.small"` (~$15/month)

3. **Schedule runner operation** using Lambda and EventBridge

4. **Use NAT Instance instead of NAT Gateway** for dev environments

## 🔐 Security Best Practices

1. **Restrict SSH access**: Update `allowed_ssh_cidr` to your IP only
2. **Use IAM roles**: Don't store AWS credentials on EC2
3. **Enable CloudTrail**: Monitor all AWS API calls
4. **Regular updates**: Keep runner and Docker updated
5. **Secrets management**: Use AWS Secrets Manager for sensitive data
6. **Network isolation**: EC2 is in private subnet with egress-only access
7. **Encryption**: EBS volumes and S3 state are encrypted

## 📝 Additional Notes

- Runner tokens expire after 1 hour - generate fresh token for each deployment
- The EC2 instance has IAM role with permissions for ECR, S3, and CloudWatch
- Nginx is configured as reverse proxy on port 80 → 8080
- Docker and Docker Compose are installed and configured
- All logs are available in `/var/log/user-data.log`

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

See the LICENSE file in the repository root.

## 🆘 Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Check existing documentation
- Review AWS and Terraform documentation

---

**Happy Infrastructure Building! 🚀**
