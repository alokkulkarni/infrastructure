# Custom AMI Quick Reference Card

## 🚀 Quick Start (3 Steps)

```bash
# 1. Build AMI (one-time, 15-20 min)
cd AWS/packer
./quickstart.sh

# 2. Update terraform.tfvars
ami_id         = "ami-0123456789abcdef"  # From build output
use_custom_ami = true

# 3. Deploy infrastructure
terraform apply
# OR via GitHub Actions workflow
```

---

## 📋 Commands Cheat Sheet

### Build AMI
```bash
# Interactive (recommended)
./quickstart.sh

# Automated
./build-ami.sh

# Manual with Packer
packer init github-runner-ami.pkr.hcl
packer validate github-runner-ami.pkr.hcl
packer build github-runner-ami.pkr.hcl
```

### Find AMI ID
```bash
# From local file
cat latest-ami-id.txt

# From AWS
aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=github-runner-ubuntu-22.04-*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text
```

### Deploy with Custom AMI
```bash
# Via tfvars
echo 'ami_id = "ami-xxx"' >> terraform.tfvars
echo 'use_custom_ami = true' >> terraform.tfvars
terraform apply

# Via CLI
terraform apply -var="ami_id=ami-xxx" -var="use_custom_ami=true"
```

### Verify Deployment
```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=github-runner-*" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Check console logs
aws ec2 get-console-output --instance-id $INSTANCE_ID \
  --output text | grep "Configuration Complete"

# Verify runner
gh api repos/alokkulkarni/sit-test-repo/actions/runners --jq '.runners[]'
```

### Cleanup Old AMI
```bash
# List AMIs
aws ec2 describe-images --owners self \
  --filters "Name=name,Values=github-runner-*" \
  --query 'Images[*].[ImageId,Name,CreationDate]' \
  --output table

# Deregister AMI
aws ec2 deregister-image --image-id ami-OLD_ID

# Delete snapshot
SNAPSHOT=$(aws ec2 describe-snapshots --owner-ids self \
  --filters "Name=description,Values=*ami-OLD_ID*" \
  --query 'Snapshots[0].SnapshotId' --output text)
aws ec2 delete-snapshot --snapshot-id $SNAPSHOT
```

---

## 📊 Comparison Table

| Aspect | Standard AMI | Custom AMI |
|--------|-------------|------------|
| **Startup** | 15-20 min ⏱️ | 2-3 min ⚡ |
| **Reliability** | ~20% ❌ | ~100% ✅ |
| **Script Lines** | 700+ 📄 | 200 📝 |
| **Build Time** | N/A | 15-20 min |
| **Cost/Month** | $0 | $0.25 |
| **Maintenance** | Update script | Rebuild AMI |

---

## 🔍 Troubleshooting Quick Fixes

### Build Issues

**Problem**: Packer build fails with "connection timeout"  
**Fix**: Check security group allows SSH from your IP
```bash
MY_IP=$(curl -s ifconfig.me)
echo "Add SSH from: $MY_IP/32"
```

**Problem**: "AWS credentials not found"  
**Fix**: Configure AWS CLI
```bash
aws configure
# OR
export AWS_ACCESS_KEY_ID="xxx"
export AWS_SECRET_ACCESS_KEY="xxx"
```

### Deployment Issues

**Problem**: Runner not registering  
**Fix**: Check token in logs
```bash
aws ec2 get-console-output --instance-id $INSTANCE_ID \
  --output text | grep "Token provided"
# Should show: Token provided: YES
```

**Problem**: Slow startup even with custom AMI  
**Fix**: Verify using correct AMI
```bash
aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].ImageId'
# Should match your custom AMI ID
```

**Problem**: Old user-data script still running  
**Fix**: Check terraform variable
```bash
terraform show | grep use_custom_ami
# Should show: use_custom_ami = true
```

---

## 📁 File Locations

```
AWS/packer/
├── github-runner-ami.pkr.hcl   ← Packer config
├── build-ami.sh                 ← Build script
├── quickstart.sh                ← Interactive setup
├── README.md                    ← Full documentation
├── IMPLEMENTATION_SUMMARY.md    ← What was built
├── ARCHITECTURE.md              ← Diagrams & workflow
├── QUICK_REFERENCE.md           ← This file
├── latest-ami-id.txt           ← Generated: Your AMI ID
└── manifest.json               ← Generated: Build metadata

AWS/terraform/modules/ec2/
├── user-data-ami.sh            ← Lightweight (custom AMI)
├── user-data.sh                ← Full (standard AMI)
└── user-data-full.sh.backup    ← Backup of original
```

---

## ⚙️ Configuration Options

### terraform.tfvars
```hcl
# Required for custom AMI
ami_id         = "ami-0123456789abcdef"
use_custom_ami = true

# Optional (with defaults)
instance_type  = "t3.medium"
aws_region     = "eu-west-2"

# Environment isolation
environment_tag = "SIT-Alok-TeamA-20251120-2100"
```

### Packer variables
```hcl
# Override in build command
packer build \
  -var "region=us-east-1" \
  -var "instance_type=t3.large" \
  github-runner-ami.pkr.hcl
```

---

## 📈 Metrics & Monitoring

### Key Metrics
```bash
# Build time
Time to AMI: 15-20 minutes

# Deployment time
With custom AMI: 2-3 minutes
With standard AMI: 15-20 minutes

# Success rate
Custom AMI: ~100%
Standard AMI: ~20%

# Cost
Build: $0.10 once
Storage: $0.25/month
Savings: Time & debugging
```

### Health Checks
```bash
# EC2 health
aws ec2 describe-instance-status --instance-ids $INSTANCE_ID

# Runner status
gh api repos/OWNER/REPO/actions/runners

# Service status (via SSM)
aws ssm start-session --target $INSTANCE_ID
systemctl status actions.runner.*
```

---

## 🔐 Security Checklist

- [ ] AMI built from official Canonical Ubuntu
- [ ] All packages from official repositories
- [ ] No custom binaries or scripts in AMI
- [ ] AMI private to your AWS account
- [ ] Security groups restrict access
- [ ] IAM roles follow least privilege
- [ ] Monthly AMI rebuilds scheduled
- [ ] Old AMIs cleaned up regularly

---

## 📅 Maintenance Schedule

### Monthly
- [ ] Rebuild AMI for security patches
- [ ] Test new AMI in dev environment
- [ ] Update production terraform.tfvars
- [ ] Clean up AMIs older than 3 months

### Quarterly
- [ ] Review and update Packer config
- [ ] Update Node.js/Python versions if needed
- [ ] Review GitHub runner version
- [ ] Update documentation

### On-Demand
- [ ] GitHub runner major version update
- [ ] Docker major version update
- [ ] Security vulnerabilities discovered
- [ ] New tools needed pre-installed

---

## 🆘 Emergency Procedures

### Rollback to Standard AMI
```hcl
# terraform.tfvars
ami_id         = ""           # Empty = use Ubuntu marketplace
use_custom_ami = false        # Use full user-data script
```

### Rollback to Previous Custom AMI
```hcl
# terraform.tfvars
ami_id         = "ami-OLD_ID"  # Previous working AMI
use_custom_ami = true
```

### Debug Runner Issues
```bash
# 1. SSH into instance (via SSM)
aws ssm start-session --target $INSTANCE_ID

# 2. Check logs
sudo cat /var/log/user-data.log
sudo journalctl -u actions.runner.* -f

# 3. Check runner status
cd /home/runner/actions-runner
sudo -u runner ./run.sh --check

# 4. Manually reconfigure
sudo -u runner ./config.sh remove
sudo -u runner ./config.sh --url REPO_URL --token NEW_TOKEN --name RUNNER_NAME
```

---

## 💡 Pro Tips

1. **Keep 2-3 recent AMIs** for rollback capability
2. **Tag AMIs** with build date and version
3. **Test in dev first** before updating production
4. **Document changes** when modifying Packer config
5. **Schedule monthly rebuilds** for security patches
6. **Monitor build time** - should be consistent ~15-20 min
7. **Use latest-ami-id.txt** for quick reference
8. **Backup terraform.tfvars** before major changes

---

## 📞 Getting Help

### Documentation
- Full docs: `AWS/packer/README.md`
- Implementation: `IMPLEMENTATION_SUMMARY.md`
- Architecture: `ARCHITECTURE.md`

### Logs
- Packer build: Console output
- User-data: `/var/log/user-data.log`
- Runner: `/home/runner/actions-runner/_diag/`

### Useful Commands
```bash
# Packer verbose mode
PACKER_LOG=1 packer build github-runner-ami.pkr.hcl

# Terraform debug
TF_LOG=DEBUG terraform apply

# AWS CLI help
aws ec2 help
aws ec2 describe-images help
```

---

## ✅ Pre-Flight Checklist

Before building AMI:
- [ ] Packer installed
- [ ] AWS CLI configured
- [ ] AWS credentials valid
- [ ] Correct AWS region selected
- [ ] Sufficient IAM permissions

Before deploying:
- [ ] AMI built successfully
- [ ] AMI ID noted
- [ ] terraform.tfvars updated
- [ ] GitHub token generated
- [ ] Environment tag chosen

After deployment:
- [ ] Instance launches (2-3 min)
- [ ] Runner registers
- [ ] Runner shows "idle" status
- [ ] Test workflow runs successfully

---

## 🎯 Success Indicators

### AMI Build Success
```
✅ Packer build complete
✅ AMI ID: ami-0123456789abcdef
✅ manifest.json created
✅ latest-ami-id.txt created
```

### Deployment Success
```
✅ EC2 instance running
✅ User-data completed in 2-3 minutes
✅ Runner registered with GitHub
✅ Runner status: idle or active
✅ ALB health check passing
```

### Workflow Success
```
✅ Workflow triggered
✅ Runner picked up job
✅ Build completed
✅ Application deployed
✅ Accessible via ALB URL
```

---

**Last Updated**: November 2025  
**Version**: 1.0  
**Region**: eu-west-2  
**Compatibility**: Ubuntu 22.04 LTS
