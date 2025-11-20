# GitHub Actions Runner Fix Scripts

Emergency fix scripts for manually configuring the GitHub Actions runner on an existing EC2 instance when user-data script fails or needs to be re-run.

## Scripts

### 1. `fix-runner-on-ec2.sh`
**Purpose**: Core script that configures the GitHub Actions runner on the EC2 instance.

**Usage**:
```bash
sudo bash fix-runner-on-ec2.sh <repo_url> <token> [runner_name] [labels]
```

**Parameters**:
- `repo_url`: GitHub repository URL (e.g., `https://github.com/alokkulkarni/sit-test-repo`)
- `token`: GitHub runner registration token (generate via GitHub API)
- `runner_name`: Name for the runner (optional, defaults to `aws-ec2-runner-SIT-Alok-TeamA-YYYYMMDD-HHMM`)
- `labels`: Comma-separated runner labels (optional, defaults to `self-hosted,aws,linux,docker,dev,<environment_tag>`)

**Example**:
```bash
TOKEN=$(gh api -X POST repos/alokkulkarni/sit-test-repo/actions/runners/registration-token --jq .token)
sudo bash fix-runner-on-ec2.sh \
    'https://github.com/alokkulkarni/sit-test-repo' \
    "$TOKEN" \
    'aws-ec2-runner-SIT-Alok-TeamA-20251120-1751' \
    'self-hosted,aws,linux,docker,dev,SIT-Alok-TeamA-20251120-1751'
```

**Features**:
- Creates runner user if doesn't exist
- Downloads GitHub Actions runner if not present
- Tests GitHub connectivity before registration
- Configures runner with proper labels and settings
- Installs and starts runner as systemd service
- Verifies service is running

---

### 2. `deploy-fix-to-ec2.sh`
**Purpose**: Automated deployment script that copies and executes the fix script on the EC2 instance via SSH through bastion host.

**Prerequisites**:
- SSH access to bastion host
- SSH key configured on bastion and private instance
- `gh` CLI installed and authenticated

**Configuration** (edit script variables):
```bash
INSTANCE_ID="i-0e687c0770fbe76f6"     # EC2 instance ID
BASTION_IP="13.134.57.181"            # Bastion host public IP
PRIVATE_IP="10.0.2.225"               # Private instance IP
```

**Usage**:
```bash
bash deploy-fix-to-ec2.sh
```

**What it does**:
1. Generates fresh GitHub runner registration token
2. Copies fix script to bastion host
3. Copies fix script from bastion to private instance
4. Executes fix script with proper parameters
5. Verifies runner registration via GitHub API

**Note**: This script will fail if SSH keys are not configured on the instances.

---

### 3. `fix-via-ssm.sh`
**Purpose**: Alternative deployment method using AWS Systems Manager Session Manager (no SSH required).

**Prerequisites**:
- SSM agent installed and running on EC2 instance
- Instance has IAM role with SSM permissions (`AmazonSSMManagedInstanceCore`)
- AWS CLI configured

**Configuration** (edit script variables):
```bash
INSTANCE_ID="i-0e687c0770fbe76f6"     # EC2 instance ID
```

**Usage**:
```bash
bash fix-via-ssm.sh
```

**What it does**:
1. Generates fresh GitHub runner registration token
2. Sends fix script to instance via SSM SendCommand
3. Monitors command execution status
4. Displays command output
5. Verifies runner registration via GitHub API

**Advantages**:
- No SSH keys required
- Works through AWS API
- Includes built-in logging and monitoring

**Limitations**:
- Requires SSM agent to be pre-installed on instance
- Instance must have proper IAM role attached

---

## When to Use These Scripts

### Scenario 1: User-Data Script Failed
If the cloud-init user-data script failed before configuring the runner (e.g., missing function, syntax error), use these scripts to manually complete the runner setup without destroying and recreating the instance.

### Scenario 2: Runner Configuration Update
If you need to change runner labels, name, or re-register the runner without redeploying infrastructure.

### Scenario 3: Runner Service Crashed
If the runner service stopped and needs to be reconfigured and restarted.

### Scenario 4: Testing Runner Setup
For development/testing of runner configuration without full infrastructure deployment.

---

## Generating Runner Registration Tokens

Tokens expire after 1 hour. Generate a fresh token before running any script:

**Using GitHub CLI**:
```bash
gh api -X POST repos/alokkulkarni/sit-test-repo/actions/runners/registration-token --jq .token
```

**Using curl**:
```bash
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/alokkulkarni/sit-test-repo/actions/runners/registration-token \
  | jq -r .token
```

---

## Verification

After running any fix script, verify the runner registered successfully:

```bash
# List all runners
gh api repos/alokkulkarni/sit-test-repo/actions/runners --jq '.runners[] | {name: .name, status: .status, labels: [.labels[].name]}'

# Check specific runner
gh api repos/alokkulkarni/sit-test-repo/actions/runners --jq '.runners[] | select(.name == "aws-ec2-runner-SIT-Alok-TeamA-20251120-1751")'
```

On the EC2 instance, check service status:
```bash
systemctl status actions.runner.* --no-pager
sudo journalctl -u actions.runner.* -n 50
```

---

## Troubleshooting

### SSH Connection Fails
- Verify bastion IP is correct
- Verify private IP is correct
- Check security groups allow SSH (port 22)
- Ensure SSH keys are configured

### SSM Command Fails
- Verify SSM agent is installed: `systemctl status amazon-ssm-agent`
- Check IAM role has `AmazonSSMManagedInstanceCore` policy
- Verify instance is registered: `aws ssm describe-instance-information --instance-id <ID>`

### Runner Registration Fails
- Verify token hasn't expired (valid for 1 hour)
- Check GitHub connectivity: `curl -Is https://github.com`
- Verify repository URL is correct
- Check PAT token has `repo`, `workflow`, `admin:repo_hook` scopes

### Service Won't Start
- Check logs: `sudo journalctl -u actions.runner.* -n 100`
- Verify runner user exists: `id runner`
- Check runner directory permissions: `ls -la /home/runner/actions-runner`
- Ensure Docker is running: `systemctl status docker`

---

## Related Files

- **User-Data Script**: `AWS/terraform/modules/ec2/user-data.sh` - Main script executed during instance launch
- **Deployment Workflow**: `.github/workflows/deploy-aws-infrastructure-oidc.yml` - Workflow that deploys infrastructure
- **EC2 Module**: `AWS/terraform/modules/ec2/main.tf` - Terraform configuration for EC2 instance

---

## History

**Created**: 2025-11-20  
**Reason**: User-data script failed due to missing `log()` function, preventing runner registration. These scripts allow manual recovery without full redeploy.

**Root Cause**: The user-data script had 10 calls to `log()` function which was never defined, causing script to fail at line 416 before reaching runner configuration code.

**Fixes Applied**:
- Added `log()` function definition to user-data.sh
- Created these emergency fix scripts for manual intervention
