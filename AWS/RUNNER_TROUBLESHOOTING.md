# GitHub Actions Runner Troubleshooting Guide

## Current Issue Summary

**Instance:** i-0b408427ba396fb0b  
**Status:** Runner configuration failed with 404 error  
**Root Cause:** Runner's config.sh calling wrong API endpoint

## Error Analysis

Console output shows:
```
POST https://api.github.com/actions/runner-registration
Http response code: NotFound from 'POST https://api.github.com/actions/runner-registration'
{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}
```

**Expected endpoint:**
```
POST https://api.github.com/repos/alokkulkarni/sit-test-repo/actions/runners/registration-token
```

## Root Causes

### 1. Outdated GitHub Actions Runner Version
The runner version in your AMI might be outdated and using deprecated API endpoints.

**Solution:** Update the runner during AMI creation.

### 2. Token Format Issue
The token being passed might be malformed or incorrect.

##Solution Steps

### Option 1: Update AMI with Latest Runner (RECOMMENDED)

When creating your AMI, use the **latest runner version**:

```bash
# In your AMI build script, replace the runner version
RUNNER_VERSION="2.321.0"  # Check https://github.com/actions/runner/releases

# Download latest runner
cd /home/runner
mkdir actions-runner
cd actions-runner
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Set ownership
chown -R runner:runner /home/runner/actions-runner
```

### Option 2: Fix Current Deployment

#### Step A: Wait for SSM Agent Registration
SSM agent takes 5-10 minutes to register after boot.

Check status:
```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-0b408427ba396fb0b" \
  --region eu-west-2 \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text
```

When it shows `Online`, proceed to Step B.

#### Step B: Connect via SSM
```bash
aws ssm start-session --target i-0b408427ba396fb0b --region eu-west-2
```

#### Step C: Check Runner Version
```bash
sudo su - runner
cd /home/runner/actions-runner
./config.sh --version
```

If version is older than 2.310.0, the runner needs updating.

#### Step D: Update Runner (if needed)
```bash
# As runner user
cd /home/runner
RUNNER_VERSION="2.321.0"

# Backup old runner
mv actions-runner actions-runner.old

# Download new runner
mkdir actions-runner
cd actions-runner
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
```

#### Step E: Configure Runner with Fresh Token
```bash
# Generate fresh token (from your machine)
TOKEN=$(gh api --method POST repos/alokkulkarni/sit-test-repo/actions/runners/registration-token --jq '.token')
echo $TOKEN

# On EC2 instance (as runner user)
cd /home/runner/actions-runner
./config.sh \
    --url https://github.com/alokkulkarni/sit-test-repo \
    --token [PASTE_TOKEN_HERE] \
    --name aws-ec2-runner-SIT-Alok-TeamA-20251121-1146 \
    --labels self-hosted,aws,linux,docker,dev,SIT-Alok-TeamA-20251121-1146 \
    --unattended

# If successful, install and start service
exit  # Back to ubuntu user
cd /home/runner/actions-runner
sudo ./svc.sh install runner
sudo ./svc.sh start
sudo ./svc.sh status
```

### Option 3: Redeploy with Fixed AMI (BEST LONG-TERM)

1. **Terminate current instance**
2. **Create new AMI with latest runner** (follow guide in your previous conversation)
3. **Update AMI ID** in terraform variables or workflow input
4. **Redeploy** infrastructure

## Verification

After configuration, verify runner registration:

```bash
# On your machine
gh api repos/alokkulkarni/sit-test-repo/actions/runners --jq '.runners[] | {id, name, status, busy}'
```

You should see your runner listed with `status: "online"`.

## Prevention for Future

### 1. Add Runner Version Check to AMI Build
Add to your Packer build script:
```bash
# Get latest runner version
LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
echo "Installing runner version: $LATEST_VERSION"
```

### 2. Add AMI Validation
Before promoting AMI, test it:
```bash
# Launch test instance
# Connect via SSM
# Check runner version
cd /home/runner/actions-runner
./config.sh --version
# Should show version 2.310.0 or newer
```

### 3. Add Token Validation to User Data Script
Add to user-data-ami.sh before configuration:
```bash
# Validate token format (should be 29 characters, alphanumeric)
if [ ${#RUNNER_TOKEN} -ne 29 ]; then
    log "❌ Invalid token format (length: ${#RUNNER_TOKEN}, expected: 29)"
    exit 1
fi
```

## Quick Commands Reference

```bash
# Check SSM status
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-0b408427ba396fb0b" --region eu-west-2

# Connect to instance
aws ssm start-session --target i-0b408427ba396fb0b --region eu-west-2

# Generate new token
gh api --method POST repos/alokkulkarni/sit-test-repo/actions/runners/registration-token --jq '.token'

# List registered runners
gh api repos/alokkulkarni/sit-test-repo/actions/runners --jq '.runners[]'

# Check runner service status (on instance)
sudo systemctl status actions.runner.alokkulkarni-sit-test-repo.*
```

## Next Steps

1. **Immediate:** Wait for SSM agent to connect (check every 2-3 minutes)
2. **Short-term:** Manually configure runner once SSM is available
3. **Long-term:** Update AMI build process with latest runner version
