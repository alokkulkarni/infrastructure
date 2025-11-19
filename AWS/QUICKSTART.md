# Quick Setup Guide - AWS Infrastructure

## ⚡ 5-Minute Setup

### Prerequisites Checklist

- [ ] AWS CLI installed and configured
- [ ] Terraform installed (v1.6+)
- [ ] AWS EC2 key pair created
- [ ] GitHub PAT token with repo/workflow scopes

### Step-by-Step Commands

```bash
# 1. Navigate to infrastructure directory
cd infrastructure/AWS

# 2. Setup Terraform backend
export AWS_REGION="us-east-1"
./scripts/setup-terraform-backend.sh

# 3. Configure Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars

# 4. Edit terraform.tfvars - REQUIRED VALUES:
# - key_name: "your-ec2-key-name"
# - github_repo_url: "https://github.com/your-username/your-repo"
# - allowed_ssh_cidr: ["YOUR_IP/32"]
nano terraform.tfvars

# 5. Generate runner token
cd ../scripts
./generate-runner-token.sh your-username/your-repo
# Copy the token from output

# 6. Deploy infrastructure
cd ../terraform
terraform init
terraform plan -var="github_runner_token=PASTE_TOKEN_HERE"
terraform apply -var="github_runner_token=PASTE_TOKEN_HERE"

# 7. Verify runner
# Go to: https://github.com/your-username/your-repo/settings/actions/runners
```

## 🎯 GitHub Actions Setup (Alternative)

If you prefer using GitHub Actions instead of manual deployment:

### 1. Configure Secrets

Go to your repo: **Settings → Secrets → Actions → New repository secret**

Add these secrets:

```
AWS_ACCESS_KEY_ID          = <your-aws-access-key>
AWS_SECRET_ACCESS_KEY      = <your-aws-secret-key>
EC2_KEY_NAME              = <your-ec2-key-name>
PAT_TOKEN                 = <github-personal-access-token>
TERRAFORM_STATE_BUCKET    = testcontainers-terraform-state
TERRAFORM_LOCK_TABLE      = testcontainers-terraform-locks
ALLOWED_SSH_CIDR         = <your-ip>/32
```

### 2. Create Backend Manually (One-time)

```bash
cd infrastructure/AWS
./scripts/setup-terraform-backend.sh
```

### 3. Run Workflow

1. Go to **Actions** tab
2. Select **Deploy AWS Infrastructure**
3. Click **Run workflow**
4. Select environment and region
5. Click **Run workflow** button

## 🔑 Required GitHub Secrets Reference

| Secret Name | Description | Example |
|------------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS Access Key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `EC2_KEY_NAME` | EC2 Key Pair Name | `testcontainers-runner` |
| `PAT_TOKEN` | GitHub Personal Access Token | `ghp_xxxxxxxxxxxxxxxxxxxx` |
| `TERRAFORM_STATE_BUCKET` | S3 Bucket Name (optional) | `testcontainers-terraform-state` |
| `TERRAFORM_LOCK_TABLE` | DynamoDB Table (optional) | `testcontainers-terraform-locks` |
| `ALLOWED_SSH_CIDR` | Your IP for SSH (optional) | `203.0.113.0/32` |

## 📋 Common Commands

### Check Infrastructure Status

```bash
cd infrastructure/AWS/terraform
terraform show
terraform output
```

### Update Infrastructure

```bash
# Modify terraform.tfvars or variables
terraform plan -var="github_runner_token=NEW_TOKEN"
terraform apply -var="github_runner_token=NEW_TOKEN"
```

### Destroy Infrastructure

```bash
# Option 1: Terraform
terraform destroy

# Option 2: GitHub Actions
# Go to Actions → Destroy AWS Infrastructure → Run workflow
```

### Access EC2 Instance

```bash
# Using AWS Systems Manager (Recommended)
INSTANCE_ID=$(terraform output -raw ec2_instance_id)
aws ssm start-session --target $INSTANCE_ID

# Check runner status on instance
sudo systemctl status github-runner
sudo journalctl -u github-runner -f
```

### Generate New Runner Token

```bash
cd infrastructure/AWS/scripts
./generate-runner-token.sh owner/repo
```

## 🐛 Quick Troubleshooting

### Runner Not Appearing

```bash
# SSH to instance (via SSM)
aws ssm start-session --target $(terraform output -raw ec2_instance_id)

# Check logs
tail -f /var/log/user-data.log
sudo journalctl -u github-runner -f
```

### Token Expired

```bash
# Tokens expire in 1 hour - generate new one
./scripts/generate-runner-token.sh owner/repo
terraform apply -var="github_runner_token=NEW_TOKEN"
```

### Can't Connect to Instance

```bash
# Verify NAT Gateway is running
terraform state show module.networking.aws_nat_gateway.main

# Check security group
terraform state show module.security.aws_security_group.ec2
```

### State Locked

```bash
# If interrupted, unlock with ID from error message
terraform force-unlock <LOCK_ID>
```

## 💰 Cost Control

```bash
# Stop EC2 to save costs (~$30/month savings)
INSTANCE_ID=$(terraform output -raw ec2_instance_id)
aws ec2 stop-instances --instance-ids $INSTANCE_ID

# Start when needed
aws ec2 start-instances --instance-ids $INSTANCE_ID
```

## 🔄 Update Runner

```bash
# SSH to instance
aws ssm start-session --target $(terraform output -raw ec2_instance_id)

# Update runner
sudo su - runner
cd ~/actions-runner
./svc.sh stop
# Download latest version and extract
./config.sh remove --token YOUR_TOKEN
# Re-run setup
```

## 📊 Monitoring

```bash
# Check EC2 status
aws ec2 describe-instances \
  --instance-ids $(terraform output -raw ec2_instance_id) \
  --query 'Reservations[0].Instances[0].State.Name'

# View CloudWatch logs (if configured)
aws logs tail /aws/ec2/runner --follow
```

## 🎓 Learning Resources

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [Docker Documentation](https://docs.docker.com/)

## ✅ Validation Checklist

After deployment, verify:

- [ ] VPC created with public and private subnets
- [ ] NAT Gateway operational
- [ ] EC2 instance running in private subnet
- [ ] GitHub runner shows as "Online" in repo settings
- [ ] Docker and Docker Compose installed on EC2
- [ ] Nginx running on port 80
- [ ] Security groups configured correctly
- [ ] Terraform state stored in S3

---

**Need Help?** Check the full [README.md](./README.md) or open an issue on GitHub.
