# AWS Infrastructure Setup - Complete Summary

## 📦 What Was Created

This infrastructure setup provides a complete, production-ready AWS environment for running GitHub Actions self-hosted runners with Docker support.

### File Structure

```
infrastructure/AWS/
├── README.md                          # Complete documentation
├── QUICKSTART.md                      # 5-minute setup guide
├── ARCHITECTURE.md                    # Architecture diagrams & details
├── .gitignore                         # Terraform-specific gitignore
│
├── terraform/                         # Terraform Infrastructure as Code
│   ├── main.tf                        # Root module
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Output values
│   ├── backend.tf                     # S3 backend configuration
│   ├── terraform.tfvars.example       # Example configuration
│   │
│   └── modules/                       # Modular Terraform code
│       ├── networking/                # VPC, subnets, NAT, IGW
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       ├── security/                  # Security groups
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       └── ec2/                       # EC2 instance & IAM
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── user-data.sh           # Bootstrap script
│
├── scripts/                           # Helper scripts
│   ├── setup-terraform-backend.sh     # Setup S3 & DynamoDB
│   ├── cleanup-backend.sh             # Cleanup backend resources
│   └── generate-runner-token.sh       # Generate GitHub runner token
│
.github/workflows/                     # GitHub Actions workflows (root)
├── README.md                          # Workflow documentation
├── deploy-aws-infrastructure.yml      # Deploy infrastructure
└── destroy-aws-infrastructure.yml     # Destroy infrastructure
```

## 🎯 Infrastructure Components

### 1. **Networking** (VPC Module)
- **VPC**: 10.0.0.0/16 with DNS support
- **Public Subnet**: 10.0.1.0/24 (for NAT Gateway)
- **Private Subnet**: 10.0.2.0/24 (for EC2 instance)
- **Internet Gateway**: Public internet access
- **NAT Gateway**: Egress-only for private subnet
- **Route Tables**: Properly configured routing
- **VPC Endpoint**: S3 gateway endpoint (cost savings)

### 2. **Security** (Security Module)
- **Security Group** with least-privilege access:
  - Ingress: SSH (22), HTTP (80), HTTPS (443)
  - Egress: All traffic (for GitHub, packages, Docker)

### 3. **Compute** (EC2 Module)
- **EC2 Instance**:
  - Type: t3.medium (configurable)
  - AMI: Ubuntu 22.04 LTS (latest)
  - Storage: 50GB encrypted EBS (gp3)
  - Location: Private subnet
  
- **IAM Role** with permissions for:
  - Amazon ECR (container registry)
  - Amazon S3 (storage)
  - CloudWatch Logs (monitoring)

- **Installed Software**:
  - Docker Engine & Docker Compose plugin
  - Nginx reverse proxy (port 80 → 8080)
  - GitHub Actions self-hosted runner
  - AWS CLI v2
  - Node.js 20.x
  - Python 3 & pip
  - Build essentials (gcc, make, etc.)

### 4. **State Management** (Backend)
- **S3 Bucket**: Versioned, encrypted state storage
- **DynamoDB Table**: State locking mechanism
- **Backend Configuration**: Automatic state management

### 5. **GitHub Actions Workflows**
- **Deploy Workflow**: Complete infrastructure deployment
  - Backend setup
  - Runner token generation
  - Terraform plan & apply
  - Environment protection

- **Destroy Workflow**: Safe infrastructure teardown
  - Confirmation requirement
  - Complete resource cleanup
  - Optional backend cleanup

## 🚀 Key Features

### ✅ Security
- [x] EC2 in private subnet (no direct internet access)
- [x] Egress-only internet via NAT Gateway
- [x] Encrypted EBS volumes
- [x] Encrypted S3 state files
- [x] IMDSv2 required (metadata security)
- [x] IAM roles (no static credentials)
- [x] Security groups with least privilege
- [x] Versioned state files for rollback

### ✅ Automation
- [x] Fully automated infrastructure deployment
- [x] GitHub Actions integration
- [x] Automatic runner registration
- [x] Dynamic token generation
- [x] Complete CI/CD pipeline
- [x] One-click deployment & destruction

### ✅ Modularity
- [x] Terraform modules for reusability
- [x] Separate networking, security, compute
- [x] Parameterized configuration
- [x] Environment-specific deployments
- [x] Easy to extend and customize

### ✅ Production-Ready
- [x] Comprehensive documentation
- [x] Error handling and validation
- [x] State locking and versioning
- [x] Cost optimization features
- [x] Monitoring and logging setup
- [x] Disaster recovery capabilities

## 📋 Prerequisites Checklist

Before deploying, ensure you have:

### Required Tools
- [ ] AWS CLI v2.x installed
- [ ] Terraform v1.6+ installed
- [ ] Git installed
- [ ] GitHub CLI (optional but helpful)

### AWS Account
- [ ] AWS account with appropriate permissions
- [ ] AWS credentials configured (`aws configure`)
- [ ] EC2 key pair created
- [ ] Know your public IP for SSH access

### GitHub
- [ ] GitHub Personal Access Token (PAT)
  - Scopes: `repo`, `workflow`, `admin:org` (for runners)
- [ ] Repository with Actions enabled
- [ ] Admin access to repository settings

### Secrets to Configure
- [ ] `AWS_ACCESS_KEY_ID`
- [ ] `AWS_SECRET_ACCESS_KEY`
- [ ] `EC2_KEY_NAME`
- [ ] `PAT_TOKEN`
- [ ] `TERRAFORM_STATE_BUCKET` (optional)
- [ ] `TERRAFORM_LOCK_TABLE` (optional)
- [ ] `ALLOWED_SSH_CIDR` (optional)

## 🎓 Setup Options

### Option 1: GitHub Actions (Recommended)
**Best for**: Teams, production environments, automated deployments

1. Configure repository secrets
2. Setup Terraform backend (one-time)
3. Run "Deploy AWS Infrastructure" workflow
4. Monitor deployment progress
5. Verify runner is online

**Time**: ~15 minutes
**Pros**: Automated, tracked, requires approval, no local setup

### Option 2: Local Terraform
**Best for**: Development, testing, local experiments

1. Setup backend: `./scripts/setup-terraform-backend.sh`
2. Configure: `cp terraform.tfvars.example terraform.tfvars`
3. Generate token: `./scripts/generate-runner-token.sh owner/repo`
4. Deploy: `terraform init && terraform apply`
5. Verify runner

**Time**: ~10 minutes
**Pros**: Faster feedback, direct control, easier debugging

## 💡 Usage Examples

### Deploy to Development Environment

**GitHub Actions:**
```
1. Actions → Deploy AWS Infrastructure
2. Environment: dev
3. Region: us-east-1
4. Run workflow
```

**Local Terraform:**
```bash
cd infrastructure/AWS/terraform
terraform workspace new dev
terraform apply -var="environment=dev"
```

### Deploy to Production

**GitHub Actions:**
```
1. Actions → Deploy AWS Infrastructure
2. Environment: prod
3. Region: us-east-1
4. Wait for approval (if configured)
5. Run workflow
```

**Local Terraform:**
```bash
cd infrastructure/AWS/terraform
terraform workspace new prod
terraform apply -var="environment=prod" -var="instance_type=t3.large"
```

### Scale Resources

**Increase instance size:**
```hcl
# terraform.tfvars
instance_type = "t3.large"  # or t3.xlarge
```

**Add more storage:**
```hcl
# modules/ec2/main.tf
root_block_device {
  volume_size = 100  # Increase from 50GB
}
```

### Stop to Save Costs

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -raw ec2_instance_id)

# Stop instance (~$30/month savings)
aws ec2 stop-instances --instance-ids $INSTANCE_ID

# Start when needed
aws ec2 start-instances --instance-ids $INSTANCE_ID
```

## 🔍 What Happens During Deployment

### Phase 1: Backend Setup (1-2 minutes)
- Creates S3 bucket for state storage
- Enables versioning and encryption
- Creates DynamoDB table for state locking
- Configures bucket policies

### Phase 2: Runner Token Generation (< 1 minute)
- Calls GitHub API
- Generates registration token
- Token valid for 1 hour
- Securely passed to Terraform

### Phase 3: Terraform Plan (2-3 minutes)
- Initializes Terraform
- Downloads provider plugins
- Reads current state
- Plans infrastructure changes
- Shows what will be created

### Phase 4: Terraform Apply (5-8 minutes)
- Creates VPC and networking
- Creates NAT Gateway with Elastic IP
- Creates security groups
- Launches EC2 instance
- Runs user data script
- Installs all software
- Registers GitHub runner

### Phase 5: Verification (1 minute)
- Outputs infrastructure details
- Verifies runner registration
- Saves state to S3
- Uploads outputs as artifacts

**Total Time**: ~10-15 minutes

## 📊 Cost Breakdown

### Monthly Costs (us-east-1)

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| EC2 Instance | t3.medium (24/7) | ~$30 |
| NAT Gateway | 24/7 operation | ~$32 |
| NAT Gateway | Data processing (50GB) | ~$2 |
| EBS Volume | 50GB gp3 | ~$4 |
| Elastic IP | Attached to NAT | $0 |
| S3 Bucket | State storage | <$1 |
| DynamoDB | On-demand (light use) | <$1 |
| **TOTAL** | | **~$69/month** |

### Cost Optimization

**Scenario 1: Part-time use (8 hrs/day, weekdays)**
- Stop EC2 when not needed: **Save ~$20/month**
- Total: **~$49/month**

**Scenario 2: Smaller instance (t3.small)**
- Change instance type: **Save ~$15/month**
- Total: **~$54/month**

**Scenario 3: Dev environment (stop overnight)**
- Stop EC2 16 hours/day: **Save ~$20/month**
- Total: **~$49/month**

## 🔐 Security Best Practices Implemented

1. **Network Isolation**
   - EC2 in private subnet
   - No direct internet access
   - NAT Gateway for egress only

2. **Access Control**
   - IAM roles (no static credentials)
   - Security groups with least privilege
   - SSH restricted to specific IPs

3. **Encryption**
   - EBS volumes encrypted at rest
   - S3 state files encrypted
   - HTTPS for all GitHub communication

4. **Monitoring & Auditing**
   - CloudWatch integration ready
   - CloudTrail for API logging
   - Detailed logging in user-data script

5. **State Management**
   - Versioned state files
   - State locking prevents conflicts
   - Encrypted state storage

## 🛠️ Maintenance & Operations

### Regular Tasks

**Weekly:**
- [ ] Check runner status in GitHub
- [ ] Review CloudWatch metrics
- [ ] Check for security updates

**Monthly:**
- [ ] Review AWS costs
- [ ] Update runner software
- [ ] Review and rotate credentials

**Quarterly:**
- [ ] Update Terraform modules
- [ ] Review and update AMI
- [ ] Test disaster recovery

### Updates

**Terraform Updates:**
```bash
cd infrastructure/AWS/terraform
terraform init -upgrade
terraform plan
terraform apply
```

**Runner Updates:**
```bash
# SSH to instance via SSM
aws ssm start-session --target <instance-id>

# As runner user
sudo su - runner
cd ~/actions-runner
./svc.sh stop
# Download and install new version
./svc.sh start
```

**Security Updates:**
```bash
# SSH to instance
aws ssm start-session --target <instance-id>

# Update packages
sudo apt update
sudo apt upgrade -y
sudo reboot
```

## 🆘 Troubleshooting Guide

### Runner Not Showing Up

**Check 1: Instance is running**
```bash
aws ec2 describe-instances --instance-ids <id> \
  --query 'Reservations[0].Instances[0].State.Name'
```

**Check 2: User data completed**
```bash
aws ssm start-session --target <id>
tail -f /var/log/user-data.log
```

**Check 3: Runner service status**
```bash
sudo systemctl status github-runner
sudo journalctl -u github-runner -f
```

### Token Expired

**Solution**: Re-run deployment with fresh token
```bash
./scripts/generate-runner-token.sh owner/repo
terraform apply -var="github_runner_token=NEW_TOKEN"
```

### Can't Access Instance

**Solution**: Use AWS Systems Manager
```bash
# Install Session Manager plugin first
aws ssm start-session --target <instance-id>
```

### State Locked

**Solution**: Force unlock with lock ID
```bash
terraform force-unlock <LOCK_ID>
```

### High Costs

**Solution**: Stop instance when not needed
```bash
aws ec2 stop-instances --instance-ids <id>
```

## 📚 Additional Resources

### Documentation
- [Complete README](./README.md) - Full documentation
- [Quick Start Guide](./QUICKSTART.md) - 5-minute setup
- [Architecture Details](./ARCHITECTURE.md) - Technical diagrams
- [Workflow README](./.github/workflows/README.md) - GitHub Actions guide

### External Links
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [Docker Documentation](https://docs.docker.com/)

## 🎉 Next Steps

After successful deployment:

1. **Verify Runner**
   - Check: `https://github.com/owner/repo/settings/actions/runners`
   - Status should show "Idle" or "Active"

2. **Test Runner**
   - Create a test workflow using runner labels
   - Run a simple job to verify functionality

3. **Configure Monitoring**
   - Setup CloudWatch dashboards
   - Configure alerts for critical metrics

4. **Document Your Setup**
   - Record instance IDs and IPs
   - Document custom configurations
   - Share access procedures with team

5. **Plan Maintenance**
   - Schedule regular updates
   - Plan for credential rotation
   - Setup backup procedures

## ✅ Success Criteria

Your infrastructure is successfully deployed when:

- [x] Terraform apply completed without errors
- [x] EC2 instance is running
- [x] GitHub runner shows as "Online"
- [x] Docker is installed and working
- [x] Nginx is running on port 80
- [x] State file is stored in S3
- [x] All outputs are generated

## 🤝 Contributing

To improve this infrastructure:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly in dev environment
5. Update documentation
6. Submit pull request

## 📝 License

See LICENSE file in repository root.

---

**🚀 Ready to deploy? Follow the [Quick Start Guide](./QUICKSTART.md)!**

**❓ Questions? Check the [complete documentation](./README.md) or open an issue.**
