# Quick Fix Guide: Runner 2.330.0 Bug

## Problem
Runner 2.330.0 calls wrong API endpoint → 404 error → Registration fails

## Solution
Use runner 2.329.0 instead

## Steps to Fix

### 1. Rebuild AMI with 2.329.0

```bash
# Launch Ubuntu 22.04 instance in eu-west-2
# SSH to instance

# Switch to runner user
sudo su - runner
cd /home/runner/actions-runner

# Download 2.329.0 (NOT 2.330.0!)
RUNNER_VERSION="2.329.0"
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Verify checksum
sha256sum actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
# Expected: 194f1e1e4bd02f80b7e9633fc546084d8d4e19f3928a324d512ea53430102e1d

# Extract
tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Install dependencies
sudo ./bin/installdependencies.sh

# Verify
./config.sh --version  # Should show 2.329.0
```

### 2. Create AMI

Via AWS Console:
- Right-click instance → Image and templates → Create image
- Name: `github-runner-ubuntu-2204-v2.329.0-20251121`
- Description: `Runner Version: 2.329.0, Node.js: 20.x.x, Docker: 29.x.x`
- Tags:
  - `Name`: `github-runner-ubuntu-2204-v2.329.0`
  - `RunnerVersion`: `2.329.0`
  - `OS`: `Ubuntu 22.04`

### 3. Update Terraform

```bash
cd infrastructure/AWS/terraform/modules/ec2

# Edit main.tf
# Update ami_id variable with new AMI ID

# Example:
variable "ami_id" {
  description = "AMI ID for the GitHub Actions runner (2.329.0)"
  type        = string
  default     = "ami-NEW_AMI_ID_HERE"  # Replace with actual AMI ID
}
```

### 4. Deploy and Test

```bash
# Deploy via workflow or terraform apply
# Check runner registration in GitHub:
# https://github.com/alokkulkarni/sit-test-repo/settings/actions/runners

# Verify runner appears with status "Idle" ✅
```

## Files Already Updated

✅ `infrastructure/AWS/AMI_BUILD_GUIDE.md` - Now specifies 2.329.0  
✅ `infrastructure/AWS/terraform/modules/ec2/user-data.sh` - Now uses 2.329.0  
✅ `infrastructure/AWS/RUNNER_2.330.0_BUG_REPORT.md` - Full bug documentation

## What Changed

**Before (broken):**
```bash
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
# This downloads 2.330.0 which has the bug
```

**After (working):**
```bash
RUNNER_VERSION="2.329.0"
# Explicitly using 2.329.0 which works correctly
```

## Why This Fixes It

Runner 2.330.0 has a bug in PR #4086 where it incorrectly detects self-hosted runners as hosted infrastructure, causing it to call:
- ❌ `POST https://api.github.com/actions/runner-registration` (deprecated, returns 404)

Instead of:
- ✅ `POST https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token`

Runner 2.329.0 doesn't have this bug and calls the correct endpoint.

## When to Upgrade

Wait for runner 2.331.0+ and check release notes for fixes to:
- PR #4086
- IsHostedServer detection
- Self-hosted registration issues

## Quick Verification

After deploying with 2.329.0, check console output:
```
✅ Runner version: 2.329.0
✅ Successfully added the runner
✅ Runner successfully registered
```

Instead of:
```
❌ Http response code: NotFound from 'POST https://api.github.com/actions/runner-registration'
```

## References

- Full bug report: `infrastructure/AWS/RUNNER_2.330.0_BUG_REPORT.md`
- AMI build guide: `infrastructure/AWS/AMI_BUILD_GUIDE.md`
- Runner 2.329.0 release: https://github.com/actions/runner/releases/tag/v2.329.0
