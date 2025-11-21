# GitHub Actions Runner AMI Build Guide

**Last Updated:** 2025-11-21  
**Runner Version:** 2.330.0 (Latest stable)  
**Base OS:** Ubuntu 22.04 LTS  
**Region:** eu-west-2 (London)

---

## Prerequisites

- AWS Console access with EC2 permissions
- Understanding that the AMI is region-specific (must be created in eu-west-2)
- Time required: ~25-30 minutes

---

## Phase 1: Launch Base Instance

### Step 1.1: Navigate to EC2
1. Log into AWS Console
2. Select **eu-west-2 (London)** region (top right)
3. Navigate to **EC2 → Instances**
4. Click **Launch instances**

### Step 1.2: Configure Instance
**Name:** `github-runner-ami-build`

**Application and OS Images (AMI):**
- Click **Quick Start**
- Select **Ubuntu**
- Choose **Ubuntu Server 22.04 LTS (HVM), SSD Volume Type**
- Architecture: **64-bit (x86)**
- AMI ID should be: `ami-0b9932f4918a00c4f` or similar recent Ubuntu 22.04

**Instance type:** `t3.medium`
- 2 vCPUs, 4 GB RAM (sufficient for building)

**Key pair:** 
- Select existing key pair OR
- Create new key pair: `github-runner-build-key`
- Type: RSA, Format: .pem

**Network settings:**
- VPC: **Default VPC** (or your custom VPC with internet access)
- Subnet: **Any public subnet** (must have internet gateway)
- Auto-assign public IP: **Enable**
- Firewall (security groups):
  - Create security group OR use existing
  - Name: `github-runner-build-sg`
  - Rules:
    - SSH (22) from **My IP** only (for security)

**Configure storage:**
- Root volume: **30 GB gp3** (minimum 25 GB recommended)
- Delete on termination: **Unchecked** (optional, for safety)

**Advanced details:** (leave defaults)

### Step 1.3: Launch
1. Review all settings
2. Click **Launch instance**
3. Wait ~2-3 minutes for instance to be in **running** state
4. Note the **Instance ID** and **Public IPv4 address**

---

## Phase 2: Connect and Update System

### Step 2.1: Connect via SSH
```bash
# From your local terminal
chmod 400 ~/Downloads/github-runner-build-key.pem  # Adjust path to your key
ssh -i ~/Downloads/github-runner-build-key.pem ubuntu@<PUBLIC_IP>
```

**Alternative:** Use AWS Session Manager (browser-based):
- Select instance → **Connect** → **Session Manager** → **Connect**

### Step 2.2: Update System
```bash
sudo apt-get update -y
sudo apt-get upgrade -y

# Verify base system
lsb_release -a  # Should show Ubuntu 22.04
```

---

## Phase 3: Install Required Packages

### Step 3.1: Install Core Tools
```bash
# Essential packages
sudo apt-get install -y \
    curl \
    wget \
    git \
    jq \
    unzip \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common
```

### Step 3.2: Install Docker
```bash
# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker
docker --version  # Should show: Docker version 27.x.x or newer
docker compose version  # Should show: Docker Compose version v2.x.x

# Test Docker
sudo docker run hello-world
```

### Step 3.3: Install Nginx
```bash
sudo apt-get install -y nginx

# Verify
nginx -v  # Should show: nginx version: nginx/1.18.0
```

### Step 3.4: Install AWS CLI v2
```bash
# Download and install
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Cleanup
rm -rf aws awscliv2.zip

# Verify
aws --version  # Should show: aws-cli/2.x.x
```

### Step 3.5: Install GitHub CLI (gh)
```bash
# Install GitHub CLI (required for PAT-based token generation)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update
sudo apt-get install -y gh

# Verify
gh --version  # Should show: gh version 2.x.x
```

**Why gh CLI?** The runner configuration uses GitHub PAT + gh CLI to generate registration tokens on-instance, eliminating token expiration issues and matching the proven test script pattern.

### Step 3.6: Install Node.js 20 LTS
```bash
# Install Node.js via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify
node --version  # Should show: v20.x.x
npm --version   # Should show: 10.x.x
```

### Step 3.7: Install Python 3 and Pip
```bash
# Usually pre-installed on Ubuntu 22.04, but ensure latest
sudo apt-get install -y python3 python3-pip

# Verify
python3 --version  # Should show: Python 3.10.x
pip3 --version
```

### Step 3.8: Install Additional Build Tools
```bash
# For various build scenarios
sudo apt-get install -y \
    build-essential \
    maven \
    gradle
```

---

## Phase 4: Create Runner User and Setup

### Step 4.1: Create Runner User
```bash
# Create dedicated user for runner
sudo useradd -m -s /bin/bash runner

# Add to docker group (critical for Docker access)
sudo usermod -aG docker runner

# Verify user
id runner
# Should show: uid=1001(runner) gid=1001(runner) groups=1001(runner),999(docker)
```

### Step 4.2: Create Runner Directory
```bash
# Create actions-runner directory
sudo mkdir -p /home/runner/actions-runner

# Set ownership
sudo chown -R runner:runner /home/runner

# Verify
ls -la /home/runner/
# Should show: drwxr-xr-x ... runner runner ... actions-runner
```

---

## Phase 5: Install GitHub Actions Runner

### Step 5.1: Download Latest Runner
```bash
# Switch to runner user
sudo su - runner

# Navigate to actions-runner directory
cd /home/runner/actions-runner

# Download latest runner version
RUNNER_VERSION="2.330.0"
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Verify download
ls -lh actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
# Should show ~150-200 MB file
```

**Note:** You can also fetch the latest version dynamically:
```bash
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep -oP '"tag_name": "v\K[^"]+')  
```

### Step 5.2: Verify Download (Optional but Recommended)
```bash
# Get SHA256 from GitHub releases page
# Compare with downloaded file
sha256sum actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Official SHA256 for 2.330.0:
# (Check https://github.com/actions/runner/releases/tag/v2.330.0 for correct hash)
```

### Step 5.3: Extract Runner
```bash
# Extract
tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Remove tarball to save space
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Verify extraction
ls -la
# Should show: config.sh, run.sh, bin/, externals/, etc.
```

### Step 5.4: Verify Runner Version
```bash
# Critical: Verify version is 2.310.0 or newer
./config.sh --version

# Should output just the version number:
# 2.330.0

# Alternative check
./bin/Runner.Listener --version
```

**⚠️ CRITICAL CHECK:**
```bash
# Version MUST be >= 2.310.0 for correct API endpoint
INSTALLED_VERSION=$(./config.sh --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)
echo "Installed version: $INSTALLED_VERSION"

# This should NOT be empty and should be >= 2.310.0
```

### Step 5.5: Install Runner Dependencies
```bash
# Exit back to ubuntu user first
exit

# Now install dependencies as ubuntu user (has sudo privileges)
# Use full path since we're not in the runner user's session
sudo /home/runner/actions-runner/bin/installdependencies.sh
```

---

## Phase 6: Verify All Components

### Step 6.1: Run Verification Script
```bash
# Create verification script
cat > /tmp/verify-ami-build.sh << 'VERIFY_EOF'
#!/bin/bash

echo "=========================================="
echo "AMI Build Verification"
echo "=========================================="
echo ""

# Check packages
echo "Package Versions:"
echo "  Docker: $(docker --version)"
echo "  Docker Compose: $(docker compose version)"
echo "  Nginx: $(nginx -v 2>&1)"
echo "  AWS CLI: $(aws --version)"
echo "  gh CLI: $(gh --version | head -1)"
echo "  Node.js: $(node --version)"
echo "  npm: $(npm --version)"
echo "  Python: $(python3 --version)"
echo "  Git: $(git --version)"
echo "  jq: $(jq --version)"
echo "  Maven: $(mvn --version | head -1)"
echo "  Gradle: $(gradle --version | grep 'Gradle' | head -1)"
echo ""

# Check runner user
echo "Runner User:"
id runner
echo ""

# Check runner directory (use sudo to access)
echo "Runner Directory:"
sudo ls -la /home/runner/actions-runner/ | head -10
echo "... (showing first 10 entries)"
echo ""

# Check runner version (use sudo to access directory)
echo "Runner Version:"
RUNNER_VERSION=$(sudo -u runner /home/runner/actions-runner/config.sh --version 2>&1)
echo "$RUNNER_VERSION"
echo ""

# Check Docker group membership
echo "Docker Group:"
getent group docker
echo ""

# Verify runner can access docker
echo "Runner Docker Access Test:"
sudo -u runner docker ps 2>&1 | head -5
echo ""

echo "=========================================="
echo "Verification Complete"
echo "=========================================="
VERIFY_EOF

# Run verification
chmod +x /tmp/verify-ami-build.sh
bash /tmp/verify-ami-build.sh
```

### Step 6.2: Expected Output
All checks should show:
- ✅ Docker 27.x or newer
- ✅ Node.js 20.x
- ✅ gh CLI 2.x or newer
- ✅ Runner version 2.330.0
- ✅ Runner user can execute docker commands
- ✅ All required files present in /home/runner/actions-runner/

**⚠️ If any check fails, DO NOT proceed to create AMI. Fix the issue first.**

---

## Phase 7: Clean Up Before AMI Creation

### Step 7.1: Clean Package Caches
```bash
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove -y
```

### Step 7.2: Clear Logs and History
```bash
# Clear bash history
cat /dev/null > ~/.bash_history
history -c

# Clear cloud-init logs (optional)
sudo rm -rf /var/lib/cloud/instances/*
sudo rm -rf /var/lib/cloud/instance
```

### Step 7.3: Remove SSH Keys (Security)
```bash
# Remove authorized_keys (will be recreated by new instances)
sudo rm -f /home/ubuntu/.ssh/authorized_keys
sudo rm -f /root/.ssh/authorized_keys

# Clear system logs (optional)
sudo find /var/log -type f -exec truncate -s 0 {} \;
```

### Step 7.4: Final Verification
```bash
# Ensure runner directory is intact
sudo ls -la /home/runner/actions-runner/config.sh

# Ensure ownership is correct
sudo stat -c "%U:%G" /home/runner/actions-runner
# Should output: runner:runner
```

---

## Phase 8: Create AMI

### Step 8.1: Stop Instance (Optional but Recommended)
**In AWS Console:**
1. Select your `github-runner-ami-build` instance
2. **Instance state** → **Stop instance**
3. Wait until state is **Stopped** (~1-2 minutes)

**Why stop?** 
- Ensures filesystem consistency
- Prevents data corruption
- Creates cleaner snapshot

### Step 8.2: Create AMI
1. With instance selected (stopped or running)
2. **Actions** → **Image and templates** → **Create image**

3. **Configure AMI:**
   - **Image name:** `github-runner-ubuntu-2204-v2.329.0-YYYYMMDD` (replace YYYYMMDD with current date)
     - Format: `github-runner-ubuntu-<OS_VERSION>-v<RUNNER_VERSION>-<DATE>`
   
   - **Image description:**
     ```
     GitHub Actions Self-Hosted Runner - Ubuntu 22.04 LTS
     Runner Version: 2.330.0
     Includes: Docker 27.x, Nginx, AWS CLI v2, Node.js 20, Python 3.10
     Built: 2025-11-21
     Region: eu-west-2
     ```
   
   - **Tags:**
     - Key: `Name`, Value: `github-runner-ubuntu-2204-v2.330.0`
     - Key: `Environment`, Value: `production`
     - Key: `ManagedBy`, Value: `terraform`
     - Key: `RunnerVersion`, Value: `2.330.0`
     - Key: `OS`, Value: `Ubuntu-22.04`
     - Key: `BuildDate`, Value: `2025-11-21`
   
   - **Instance volumes:**
     - Leave default (automatically includes root volume)
     - Volume size: 30 GB (or whatever you configured)
     - Volume type: gp3
     - Delete on termination: Yes

4. **Advanced settings:** (leave defaults)

5. Click **Create image**

### Step 8.3: Wait for AMI Creation
1. Navigate to **EC2 → Images → AMIs**
2. Find your AMI: `github-runner-ubuntu-2204-v2.329.0-YYYYMMDD`
3. Status will show **pending** → **available** (~5-10 minutes)
4. **Do not proceed until status is "available"**

### Step 8.4: Note the AMI ID
Once available, note the **AMI ID**:
- Format: `ami-0123456789abcdef0`
- Example: `ami-0f8a3d99e5b1234ab`

**You will need this AMI ID for Terraform configuration.**

---

## Phase 9: Update Terraform Configuration

### Step 9.1: Update AMI ID in Workflow
**File:** `.github/workflows/deploy-aws-infrastructure-oidc.yml`

Find the `ami_id` input and update:
```yaml
# Around line 60-65
ami_id:
  description: 'AMI ID for EC2 instances'
  required: false
  default: 'ami-0f8a3d99e5b1234ab'  # ← Update this with your new AMI ID
```

**OR** update in `terraform.tfvars`:

**File:** `AWS/terraform/environments/sit/terraform.tfvars`
```hcl
ami_id = "ami-0f8a3d99e5b1234ab"  # ← Update this with your new AMI ID
```

### Step 9.2: Commit Changes
```bash
cd /path/to/infrastructure

# Edit the workflow file or terraform.tfvars
# Then commit
git add .github/workflows/deploy-aws-infrastructure-oidc.yml
# OR
git add AWS/terraform/environments/sit/terraform.tfvars

git commit -m "chore: Update AMI ID to v2.329.0 (ami-0f8a3d99e5b1234ab)"
git push origin main
```

### Step 9.3: Trigger Deployment
**Option 1: Via GitHub Actions UI**
1. Go to GitHub repository → **Actions**
2. Select **Deploy AWS Infrastructure (OIDC)**
3. Click **Run workflow**
4. Select branch: `main`
5. Environment: `sit`
6. Action: `apply`
7. Runner repository: `sit-test-repo`
8. Destroy after: `false`
9. Click **Run workflow**

**Option 2: Via Git Push**
- If workflow has `push` trigger, just push your commit
- Workflow will automatically deploy with new AMI

---

## Phase 10: Verify Deployment

### Step 10.1: Monitor Workflow
1. Watch the GitHub Actions workflow execution
2. Check **terraform-apply** job logs
3. Look for: 
   - EC2 instance creation
   - Console output showing runner registration

### Step 10.2: Check Runner Registration
**In GitHub:**
1. Go to `alokkulkarni/sit-test-repo`
2. Navigate to **Settings** → **Actions** → **Runners**
3. Look for your runner (should appear within 2-3 minutes)
4. Status should be **Idle** (green)

**Expected runner name format:** `gh-runner-sit-20251121-xxxxxx`

### Step 10.3: Verify Console Logs
**In AWS Console:**
1. EC2 → Instances
2. Find the new instance (launched ~2-3 minutes ago)
3. **Actions** → **Monitor and troubleshoot** → **Get system log**
4. Look for:
   ```
   [timestamp] ✅ Runner configuration successful
   [timestamp] ✅ Runner registration file created
   [timestamp] ✅ Runner service is running
   ```

### Step 10.4: Test Runner with Workflow
Create a test workflow in `sit-test-repo`:

**File:** `.github/workflows/test-runner.yml`
```yaml
name: Test Self-Hosted Runner

on:
  workflow_dispatch:

jobs:
  test:
    runs-on: self-hosted
    steps:
      - name: Test runner
        run: |
          echo "Runner is working!"
          docker --version
          node --version
          aws --version
```

Run this workflow and verify it completes successfully on your self-hosted runner.

---

## Phase 11: Cleanup Build Instance

### Step 11.1: Terminate Build Instance
**⚠️ Only after verifying new AMI works:**

1. EC2 → Instances
2. Select `github-runner-ami-build` instance
3. **Instance state** → **Terminate instance**
4. Confirm termination

### Step 11.2: Verify AMI Still Available
1. EC2 → Images → AMIs
2. Your AMI should still show **available**
3. Snapshots are independent of source instance

---

## Troubleshooting

### Issue: Runner Not Registering

**Check 1: Verify Runner Version**
```bash
# SSH to new instance
aws ssm start-session --target <instance-id>

# Check version
cd /home/runner/actions-runner
sudo -u runner ./config.sh --version
# Must be >= 2.310.0
```

**Check 2: Verify Token**
- Token expires in 1 hour
- Workflow must generate fresh token for each deployment
- Check workflow logs for token generation

**Check 3: Check Console Output**
```bash
# Look for error messages
aws ec2 get-console-output --instance-id <instance-id> --output text
```

### Issue: Version Shows "unknown"

**Solution:** Runner not properly extracted
```bash
# Re-extract runner
cd /home/runner/actions-runner
sudo -u runner tar xzf actions-runner-linux-x64-2.329.0.tar.gz
```

### Issue: Docker Permission Denied

**Solution:** Runner user not in docker group
```bash
sudo usermod -aG docker runner
# Must create AMI again after this fix
```

---

## AMI Naming Convention

**Format:** `github-runner-ubuntu-<OS>-v<RUNNER>-<DATE>`

**Examples:**
- `github-runner-ubuntu-2204-v2.329.0-YYYYMMDD`
- `github-runner-ubuntu-2204-v2.331.0-20251201`

**Tags:**
- `Name`: Full AMI name
- `Environment`: `production` or `sit`
- `ManagedBy`: `terraform`
- `RunnerVersion`: `2.329.0`
- `OS`: `Ubuntu-22.04`
- `BuildDate`: `YYYYMMDD`

---

## Maintenance

### When to Rebuild AMI

**Update Runner Version:**
- New runner released with security fixes
- New API endpoints or features
- Every 2-3 months as maintenance

**Update System Packages:**
- Security updates to Ubuntu
- Docker version updates
- Node.js LTS updates
- Every 3-6 months

**Update Tools:**
- AWS CLI v2 updates
- Build tool updates (Maven, Gradle)
- As needed based on requirements

### Quick Rebuild Process

1. Launch instance from **current AMI** (faster than fresh Ubuntu)
2. Update only what changed:
   ```bash
   # Update runner
   cd /home/runner/actions-runner
   # Download new version, extract, verify
   
   # Update packages
   sudo apt-get update && sudo apt-get upgrade -y
   ```
3. Create new AMI with incremented version
4. Update Terraform configuration
5. Deploy and verify

---

## Reference

**Runner Version History:**
- 2.329.0 (2024-10-14) - Recommended, no IsHostedServer bug ✅
- 2.330.0 (2025-11-21) - ⚠️ DO NOT USE - Has IsHostedServer detection bug (PR #4086) ❌
- 2.321.0 (User claimed but was actually older) ❌
- 2.310.0 (Minimum required for correct API) ⚠️

**Key Files in AMI:**
- `/home/runner/actions-runner/config.sh` - Configuration script
- `/home/runner/actions-runner/run.sh` - Runner execution
- `/home/runner/actions-runner/bin/` - Runner binaries

**API Endpoints:**
- ✅ Correct: `POST https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token`
- ❌ Deprecated: `POST https://api.github.com/actions/runner-registration` (404)

---

## Appendix: One-Line Installer Script (Advanced)

For experienced users, here's a complete install script:

```bash
#!/bin/bash
# Quick AMI build script - Run as ubuntu user on fresh Ubuntu 22.04

set -e

RUNNER_VERSION="2.329.0"

# Update system
sudo apt-get update -y && sudo apt-get upgrade -y

# Install essentials
sudo apt-get install -y curl wget git jq unzip apt-transport-https ca-certificates gnupg lsb-release software-properties-common build-essential maven gradle

# Install Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Nginx
sudo apt-get install -y nginx

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Create runner user
sudo useradd -m -s /bin/bash runner
sudo usermod -aG docker runner

# Install runner
sudo mkdir -p /home/runner/actions-runner
cd /home/runner/actions-runner
sudo curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
sudo tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
sudo rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
sudo chown -R runner:runner /home/runner

# Install runner dependencies (run before changing ownership)
cd /home/runner/actions-runner
sudo ./bin/installdependencies.sh

# Verify
echo "=========================================="
echo "Verification:"
echo "Docker: $(docker --version)"
echo "Node: $(node --version)"
echo "AWS CLI: $(aws --version)"
echo "Runner: $(sudo -u runner ./config.sh --version)"
echo "=========================================="
echo "✅ AMI build complete - ready to create image"
```

**Usage:**
```bash
curl -fsSL https://raw.githubusercontent.com/alokkulkarni/infrastructure/main/AWS/scripts/build-ami.sh | bash
```

---

**End of Guide**
