# GitHub Runner Repository Configuration

## Problem

The GitHub runner was registering to the `alokkulkarni/infrastructure` repository instead of the intended `alokkulkarni/sit-test-repo` repository. This happened because the Azure deployment workflow was hardcoded to use `${{ github.repository }}` (the repository where the workflow is running) instead of allowing users to specify which repository should receive the runner.

## Solution

Added a new workflow input parameter `github_runner_repo` to the Azure deployment workflow (`deploy-azure-infrastructure.yml`) that allows users to specify the target repository for runner registration.

### Changes Made

#### 1. Added Workflow Input Parameter

**Location**: `.github/workflows/deploy-azure-infrastructure.yml`

Added new input after `location`:

```yaml
github_runner_repo:
  description: 'GitHub repository for runner registration (format: owner/repo)'
  required: true
  default: 'alokkulkarni/sit-test-repo'
  type: string
```

**Benefits**:
- Users can now specify the target repository for runner registration
- Default points to `sit-test-repo` (the intended target)
- Still allows flexibility to register to other repositories if needed

#### 2. Updated Terraform Variable Assignments

Updated `github_repo_url` in three locations within the workflow:

**terraform-plan job** (line ~165):
```yaml
github_repo_url = "https://github.com/${{ github.event.inputs.github_runner_repo }}"
```

**terraform-apply job** (line ~295):
```yaml
github_repo_url = "https://github.com/${{ github.event.inputs.github_runner_repo }}"
```

**rollback-on-failure job** (line ~513):
```yaml
github_repo_url = "https://github.com/${{ github.event.inputs.github_runner_repo }}"
```

**Previous**: All used `${{ github.repository }}` → registered to `alokkulkarni/infrastructure`
**Now**: All use `${{ github.event.inputs.github_runner_repo }}` → registers to specified repo (default: `alokkulkarni/sit-test-repo`)

## How Runner Registration Works

### Cloud-init Process

The `github_repo_url` variable is passed to the cloud-init script which:

1. **Extracts owner and repo** from the URL:
   ```bash
   GITHUB_OWNER=$(echo "$GITHUB_REPO_URL" | sed -n 's/.*github.com\/\([^/]*\).*/\1/p')
   GITHUB_REPO=$(echo "$GITHUB_REPO_URL" | sed -n 's/.*github.com\/[^/]*\/\([^/]*\).*/\1/p')
   ```

2. **Authenticates with GitHub CLI** using PAT:
   ```bash
   echo "${GITHUB_PAT}" | gh auth login --with-token
   ```

3. **Obtains runner token** for the specified repository:
   ```bash
   RUNNER_TOKEN=$(gh api \
     --method POST \
     "/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/registration-token" \
     --jq .token)
   ```

4. **Configures runner** with the obtained token:
   ```bash
   ./config.sh \
     --url "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
     --token "$RUNNER_TOKEN" \
     --name "$RUNNER_NAME" \
     --labels "$RUNNER_LABELS" \
     --work _work \
     --unattended
   ```

5. **Starts runner service**:
   ```bash
   sudo ./svc.sh install azureuser
   sudo ./svc.sh start
   ```

### Verification

After deployment, verify the runner is registered:

1. **In GitHub UI**:
   - Navigate to repository: https://github.com/alokkulkarni/sit-test-repo
   - Go to **Settings** → **Actions** → **Runners**
   - Look for runner named: `azure-vm-runner-<ENVIRONMENT_TAG>`

2. **Via Azure CLI** (check cloud-init logs):
   ```bash
   az vm run-command invoke \
     --resource-group <rg-name> \
     --name <vm-name> \
     --command-id RunShellScript \
     --scripts "tail -100 /var/log/cloud-init-output.log | grep -A 20 'Runner successfully added'"
   ```

3. **Via Azure CLI** (check runner service):
   ```bash
   az vm run-command invoke \
     --resource-group <rg-name> \
     --name <vm-name> \
     --command-id RunShellScript \
     --scripts "systemctl status actions.runner.*.service"
   ```

## Usage Example

When triggering the deployment workflow, specify the repository:

### Via GitHub UI

1. Go to **Actions** tab in infrastructure repository
2. Select **Deploy Azure Infrastructure (OIDC)** workflow
3. Click **Run workflow**
4. Fill in inputs:
   - **Environment**: `dev`
   - **Environment Tag**: `SIT-Alok-TeamA-20251125-1430`
   - **Azure Region**: `uksouth`
   - **GitHub Runner Repo**: `alokkulkarni/sit-test-repo` (default)
5. Click **Run workflow**

### Via GitHub CLI

```bash
gh workflow run deploy-azure-infrastructure.yml \
  --repo alokkulkarni/infrastructure \
  --field environment=dev \
  --field environment_tag=SIT-Alok-TeamA-20251125-1430 \
  --field location=uksouth \
  --field github_runner_repo=alokkulkarni/sit-test-repo
```

## Comparison with AWS

The Azure workflow now matches the AWS pattern:

### AWS Workflow
```yaml
# Input (implicit from ${{ github.repository }})
github_repo_url = "https://github.com/${{ github.repository }}"
```

**Note**: AWS workflow uses the repository where workflow runs, which works because the deployment workflows should be triggered from the target repository's workflows.

### Azure Workflow (Updated)
```yaml
# Input (explicit via workflow parameter)
github_runner_repo:
  description: 'GitHub repository for runner registration (format: owner/repo)'
  required: true
  default: 'alokkulkarni/sit-test-repo'

# Usage
github_repo_url = "https://github.com/${{ github.event.inputs.github_runner_repo }}"
```

**Benefit**: More explicit and flexible - allows infrastructure repository to deploy runners for any target repository.

## Best Practices

1. **Always verify runner registration** after deployment
2. **Use meaningful runner names** with environment tags for easy identification
3. **Apply appropriate labels** to runners for workflow targeting
4. **Monitor runner status** in GitHub Settings → Actions → Runners
5. **Clean up runners** when destroying infrastructure (handled automatically in destroy workflow)

## Troubleshooting

### Runner Not Appearing in GitHub

**Check cloud-init logs**:
```bash
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "grep 'Runner successfully added\|Failed to add the runner' /var/log/cloud-init-output.log"
```

**Common issues**:
- **PAT_TOKEN invalid or expired**: Update GitHub secret `PAT_TOKEN` with valid token
- **Insufficient permissions**: PAT needs `repo` and `workflow` scopes
- **Wrong repository**: Check `github_runner_repo` input matches target repository
- **Network issues**: Verify VM can reach api.github.com

### Runner Shows as Offline

**Check runner service**:
```bash
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "systemctl status actions.runner.*.service"
```

**Restart runner**:
```bash
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "systemctl restart actions.runner.*.service"
```

## Related Files

- **Workflow**: `.github/workflows/deploy-azure-infrastructure.yml`
- **Cloud-init**: `infrastructure/Azure/terraform/modules/vm/cloud-init.yaml`
- **Terraform Variables**: `infrastructure/Azure/terraform/variables.tf`
- **VM Module**: `infrastructure/Azure/terraform/modules/vm/main.tf`

## Future Enhancements

1. **Auto-detect repository** from workflow trigger context
2. **Support multiple runners** for the same repository
3. **Runner pool management** with scale sets
4. **Health monitoring** and auto-recovery
5. **Runner metrics** and usage reporting
