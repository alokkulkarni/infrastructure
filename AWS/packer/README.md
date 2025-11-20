# Custom AMI for GitHub Actions Runner

This directory contains Packer configuration to build a custom AMI with all required packages pre-installed. This approach eliminates package installation issues during EC2 startup.

## Overview

**Problem**: The standard user-data script installs Docker, Nginx, AWS CLI, Node.js, Python, and other packages during EC2 startup, which can fail due to:
- Ubuntu repository connectivity issues
- Network timeouts
- Package conflicts
- Slow startup times (15-20 minutes)

**Solution**: Pre-build an AMI with all packages installed, then use a lightweight user-data script that only configures the GitHub Actions Runner (startup time: 2-3 minutes).

## Architecture

### Pre-built AMI Includes:
- ✅ Ubuntu 22.04 LTS (base)
- ✅ Docker & Docker Compose
- ✅ Nginx
- ✅ AWS CLI v2
- ✅ Node.js 20.x & npm
- ✅ Python 3.x & pip
- ✅ Git, curl, wget, jq
- ✅ GitHub Actions Runner (pre-downloaded)
- ✅ Runner user and directory structure
- ✅ IPv6 disabled
- ✅ Multi-mirror apt configuration

### Lightweight User-Data Script:
- Configure GitHub Actions Runner with token
- Start runner service
- Setup Nginx auto-configuration
- ~200 lines vs ~700 lines (original)

## Prerequisites

### 1. Install Packer
```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/packer

# Linux (Ubuntu/Debian)
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install packer

# Verify installation
packer version
```

### 2. AWS Credentials
Ensure AWS credentials are configured:
```bash
aws configure
# OR set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="eu-west-2"
```

### 3. IAM Permissions
Your AWS user/role needs permissions to:
- Create EC2 instances
- Create AMIs and snapshots
- Create temporary security groups
- Create temporary key pairs

## Building the AMI

### Method 1: Using the Build Script (Recommended)

```bash
cd AWS/packer
./build-ami.sh
```

The script will:
1. ✅ Check Packer installation
2. ✅ Verify AWS credentials
3. ✅ Initialize Packer plugins
4. ✅ Validate configuration
5. ✅ Build the AMI (~15-20 minutes)
6. ✅ Output AMI ID
7. ✅ Save AMI ID to `latest-ami-id.txt`

### Method 2: Manual Packer Commands

```bash
cd AWS/packer

# Initialize plugins
packer init github-runner-ami.pkr.hcl

# Validate configuration
packer validate github-runner-ami.pkr.hcl

# Build the AMI
packer build \
  -var "region=eu-west-2" \
  github-runner-ami.pkr.hcl
```

## Build Output

After successful build:
```
AMI Details:
  AMI ID:     ami-0123456789abcdef
  Region:     eu-west-2
  Build Time: 20251120204530
```

The AMI ID is saved to:
- `manifest.json` - Full build details
- `latest-ami-id.txt` - Just the AMI ID

## Using the Custom AMI

### Option 1: Via terraform.tfvars (Recommended)

Edit `AWS/terraform/terraform.tfvars`:
```hcl
# Custom AMI configuration
ami_id         = "ami-0123456789abcdef"  # Your AMI ID from build output
use_custom_ami = true                     # Use lightweight user-data script
```

### Option 2: Via GitHub Actions Workflow

When running the deployment workflow, provide:
- **Custom AMI ID**: `ami-0123456789abcdef`
- **Use Custom AMI**: `true`

### Option 3: Via Command Line

```bash
cd AWS/terraform

terraform plan \
  -var="ami_id=ami-0123456789abcdef" \
  -var="use_custom_ami=true"

terraform apply \
  -var="ami_id=ami-0123456789abcdef" \
  -var="use_custom_ami=true"
```

## Verifying the Deployment

### 1. Check EC2 Startup Time
With custom AMI, the instance should be ready in 2-3 minutes vs 15-20 minutes.

```bash
# Get instance ID
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=github-runner-*" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text

# Check console output
aws ec2 get-console-output --instance-id <INSTANCE_ID> --output text | grep "Configuration Complete"
```

### 2. Verify Runner Registration
```bash
gh api repos/alokkulkarni/sit-test-repo/actions/runners --jq '.runners[]'
```

Expected: Runner online with status "idle" or "active"

### 3. Check Pre-installed Packages
```bash
# Via SSM Session Manager
aws ssm start-session --target <INSTANCE_ID>

# Verify packages
docker --version
docker compose version
nginx -v
aws --version
node --version
python3 --version
ls -la /home/runner/actions-runner/
```

## Updating the AMI

### When to Update:
- Security patches for Ubuntu
- Docker or Nginx version updates
- GitHub Actions Runner updates
- Adding new pre-installed tools

### Update Process:
1. **Build new AMI**: Run `./build-ami.sh`
2. **Test the AMI**: Deploy to a test environment first
3. **Update terraform.tfvars**: Replace old AMI ID with new one
4. **Deploy**: Run infrastructure deployment workflow
5. **Clean up old AMI** (optional):
   ```bash
   # Deregister old AMI
   aws ec2 deregister-image --image-id ami-OLD_ID
   
   # Delete associated snapshot
   aws ec2 describe-snapshots --owner-ids self --filters "Name=description,Values=*ami-OLD_ID*"
   aws ec2 delete-snapshot --snapshot-id snap-XXXXXX
   ```

## Troubleshooting

### Build Fails with "Timeout waiting for SSH"
- Check security group allows SSH from your IP
- Verify subnet has internet access
- Try increasing timeout in Packer config

### AMI Build Succeeds but Runner Doesn't Work
- Check user-data logs: `cat /var/log/user-data.log`
- Verify GitHub token: `echo $RUNNER_TOKEN` (should not be empty)
- Check runner status: `systemctl status actions.runner.*`

### Package Installation Fails During Build
- Mirror timeout: Packer has direct internet access during build
- Update apt sources in Packer config if mirrors changed
- Try different instance type (t3.medium recommended)

## Cost Optimization

### AMI Storage Costs:
- AMI snapshot: ~$0.05 per GB-month (eu-west-2)
- Typical AMI size: 4-6 GB
- Monthly cost: ~$0.25 per AMI

### Recommendations:
- Keep only 2-3 recent AMIs
- Delete old AMIs after successful new deployment
- Use lifecycle policies for automated cleanup

## Files in This Directory

```
AWS/packer/
├── github-runner-ami.pkr.hcl   # Packer HCL configuration
├── build-ami.sh                # Automated build script
├── README.md                   # This file
├── manifest.json               # Generated: Build metadata
└── latest-ami-id.txt          # Generated: Latest AMI ID
```

## Comparison: Standard vs Custom AMI

| Aspect | Standard Ubuntu AMI | Custom AMI |
|--------|-------------------|------------|
| **Startup Time** | 15-20 minutes | 2-3 minutes |
| **Network Issues** | Frequent failures | Rare (only runner config) |
| **User-Data Script** | 700+ lines | ~200 lines |
| **Package Installation** | Every deployment | Once during AMI build |
| **Maintenance** | Update user-data script | Rebuild AMI periodically |
| **Cost** | Free | ~$0.25/month per AMI |
| **Reliability** | ❌ Medium | ✅ High |

## GitHub Actions Integration

The deployment workflow automatically supports custom AMI:

```yaml
# .github/workflows/deploy-aws-infrastructure-oidc.yml
inputs:
  custom_ami_id:
    description: 'Custom AMI ID (optional)'
    required: false
    default: ''
  
  use_custom_ami:
    description: 'Use custom AMI with pre-installed packages'
    required: false
    default: 'false'
```

## Security Considerations

1. **AMI Encryption**: AMIs are not encrypted by default. Consider enabling EBS encryption.
2. **Access Control**: Restrict AMI sharing to your AWS account only.
3. **Vulnerability Scanning**: Run security scans before using AMI in production.
4. **Update Frequency**: Rebuild AMI monthly for security patches.

## Next Steps

1. ✅ Build your first custom AMI: `./build-ami.sh`
2. ✅ Update `terraform.tfvars` with the AMI ID
3. ✅ Deploy infrastructure with `use_custom_ami = true`
4. ✅ Verify runner starts in 2-3 minutes
5. ✅ Schedule monthly AMI rebuilds for security updates

## Support

For issues or questions:
- Check logs: `/var/log/user-data.log`
- Review Packer docs: https://www.packer.io/docs
- AWS AMI guide: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html
