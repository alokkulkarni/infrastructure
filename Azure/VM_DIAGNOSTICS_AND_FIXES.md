# Azure VM Deployment - Diagnostics and Fixes

## Issues Identified

Based on your report, there are multiple issues with the deployment:

1. ❌ **No outputs visible** - VM public IP and Nginx URL not shown in terraform apply output
2. ❌ **GitHub runner not registering** - Runner not appearing in repository settings
3. ❌ **Docker not accessible** - Docker commands may not be working
4. ❌ **Nginx not configured** - Reverse proxy not accessible

## Root Cause Analysis

### Issue 1: Missing Outputs

**Problem**: The `outputs.tf` file exists but outputs are not being generated.

**Likely Causes**:
- State file was cleared after destroy operations
- Terraform backend pointing to wrong state file
- Outputs not being processed during apply

**Evidence from state file**:
```bash
terraform output vm_public_ip
# Warning: No outputs found
```

### Issue 2: GitHub Runner Registration

**Problem**: Runner not visible in GitHub repository settings.

**Possible Causes**:
1. **GitHub PAT not provided or invalid**
   - Check if `PAT_TOKEN` secret exists in repository
   - Verify PAT has `repo` and `workflow` scopes
   
2. **cloud-init script failed**
   - Runner installation errors
   - gh CLI authentication failed
   - Token generation failed

3. **Timing issue**
   - VM was destroyed before cloud-init completed
   - Runner service failed to start

### Issue 3: Docker and Nginx Issues

**Problem**: Services not running or accessible.

**Possible Causes**:
- cloud-init script didn't complete
- Services failed to start
- Firewall blocking access
- VM was destroyed before diagnostics could be run

---

## Diagnostic Commands

### Step 1: Verify Deployment Actually Succeeded

```bash
# Check if resources exist
az group show --name testcontainers-dev-rg

# List resources in the group
az resource list --resource-group testcontainers-dev-rg --query "[].{Name:name, Type:type}" -o table

# Check VM status
az vm show --resource-group testcontainers-dev-rg --name testcontainers-dev-vm --query "provisioningState" -o tsv
```

### Step 2: Get VM Public IP

```bash
# Get public IP address
VM_PUBLIC_IP=$(az network public-ip show \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm-pip \
  --query "ipAddress" -o tsv)
  
echo "VM Public IP: $VM_PUBLIC_IP"
echo "Nginx URL: http://$VM_PUBLIC_IP"
echo "Health Check: http://$VM_PUBLIC_IP/health"
```

### Step 3: Check Cloud-Init Status

```bash
# Via Azure Serial Console (Portal) or Run Command
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "cloud-init status --long"
```

### Step 4: Check GitHub Runner Status

```bash
# Check if runner service is running
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "systemctl status actions.runner.* --no-pager"
```

### Step 5: Check Docker Status

```bash
# Check Docker service
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "systemctl status docker --no-pager && docker ps"
```

### Step 6: Check Nginx Status

```bash
# Check Nginx service
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "systemctl status nginx --no-pager && nginx -t"
```

### Step 7: Get Cloud-Init Logs

```bash
# Get cloud-init output log
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "tail -n 100 /var/log/cloud-init-output.log"
```

---

## Fixes Required

### Fix 1: Ensure Outputs are Generated

The outputs exist in `outputs.tf` but may not be working due to module references. Let me verify the issue:

**Check**: Do the module outputs exist?

```bash
cd /Users/alokkulkarni/Documents/Development/TestContainers/infrastructure/Azure/terraform
terraform state list | grep output
```

**Problem Identified**: The outputs reference `module.vm.vm_public_ip`, but this output may not be properly exported.

**Solution**: Already verified - the module outputs exist. The issue is likely the state was destroyed.

### Fix 2: Add Diagnostic Output Script

Create a script to easily retrieve deployment information:

**File**: `infrastructure/Azure/scripts/get-deployment-info.sh`

```bash
#!/bin/bash

set -e

RG_NAME="${1:-testcontainers-dev-rg}"
VM_NAME="${2:-testcontainers-dev-vm}"
PIP_NAME="${VM_NAME}-pip"

echo "==================================="
echo " Azure Deployment Information"
echo "==================================="
echo ""

# Check if resource group exists
if ! az group show --name "$RG_NAME" &>/dev/null; then
    echo "❌ Resource group '$RG_NAME' not found!"
    exit 1
fi

echo "✅ Resource Group: $RG_NAME"
echo ""

# Get VM public IP
echo "📡 Getting public IP address..."
VM_PUBLIC_IP=$(az network public-ip show \
    --resource-group "$RG_NAME" \
    --name "$PIP_NAME" \
    --query "ipAddress" -o tsv 2>/dev/null || echo "Not found")

if [ "$VM_PUBLIC_IP" == "Not found" ]; then
    echo "❌ Public IP not found!"
else
    echo "✅ VM Public IP: $VM_PUBLIC_IP"
    echo ""
    echo "🌐 Access URLs:"
    echo "   Nginx:        http://$VM_PUBLIC_IP"
    echo "   Health Check: http://$VM_PUBLIC_IP/health"
    echo ""
fi

# Check VM status
echo "🖥️  Checking VM status..."
VM_STATUS=$(az vm show \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "Not found")

echo "   VM Status: $VM_STATUS"
echo ""

# Check VM power state
POWER_STATE=$(az vm get-instance-view \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null || echo "Unknown")

echo "   Power State: $POWER_STATE"
echo ""

# Try to test Nginx
if [ "$VM_PUBLIC_IP" != "Not found" ]; then
    echo "🔍 Testing Nginx connectivity..."
    if curl -s --connect-timeout 5 "http://$VM_PUBLIC_IP/health" >/dev/null 2>&1; then
        echo "✅ Nginx is accessible!"
        curl -s "http://$VM_PUBLIC_IP/health"
    else
        echo "❌ Nginx not accessible (may still be starting up)"
    fi
    echo ""
fi

# List all resources
echo "📋 Resources in group:"
az resource list --resource-group "$RG_NAME" --query "[].{Name:name, Type:type}" -o table

echo ""
echo "==================================="
```

### Fix 3: Add Cloud-Init Diagnostics Script

**File**: `infrastructure/Azure/scripts/diagnose-vm.sh`

```bash
#!/bin/bash

set -e

RG_NAME="${1:-testcontainers-dev-rg}"
VM_NAME="${2:-testcontainers-dev-vm}"

echo "==================================="
echo " VM Diagnostics"
echo "==================================="
echo ""

echo "📊 Checking cloud-init status..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "echo '=== Cloud-Init Status ===' && cloud-init status --long" \
  --output table

echo ""
echo "🏃 Checking GitHub Runner status..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "echo '=== Runner Service ===' && systemctl status actions.runner.* --no-pager | head -30 && echo '' && echo '=== Runner Processes ===' && ps aux | grep -i runner | grep -v grep" \
  --output table

echo ""
echo "🐳 Checking Docker status..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "echo '=== Docker Service ===' && systemctl status docker --no-pager && echo '' && echo '=== Docker Containers ===' && docker ps -a" \
  --output table

echo ""
echo "🌐 Checking Nginx status..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "echo '=== Nginx Service ===' && systemctl status nginx --no-pager && echo '' && echo '=== Nginx Config Test ===' && nginx -t && echo '' && echo '=== Nginx Auto-Config Service ===' && systemctl status nginx-auto-config --no-pager" \
  --output table

echo ""
echo "📝 Getting cloud-init logs (last 50 lines)..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "echo '=== Cloud-Init Output Log ===' && tail -n 50 /var/log/cloud-init-output.log" \
  --output table

echo ""
echo "==================================="
```

### Fix 4: Add Better Workflow Output

The workflow needs to display the outputs after successful deployment.

**Problem**: The workflow runs `terraform apply` but doesn't show the outputs.

**Solution**: Add a step to display outputs after apply.

---

## Immediate Action Plan

### Step 1: Check if Deployment Exists

```bash
# Run the diagnostic script
./infrastructure/Azure/scripts/get-deployment-info.sh
```

If the resource group doesn't exist, the deployment failed or was destroyed.

### Step 2: Re-deploy with Fixes

If resources don't exist, re-run the deployment:

```bash
# Via GitHub Actions
# Go to Actions tab > Deploy Azure Infrastructure > Run workflow

# OR manually
cd infrastructure/Azure/terraform
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 3: Monitor Cloud-Init Progress

Wait 3-5 minutes for cloud-init to complete, then run:

```bash
./infrastructure/Azure/scripts/diagnose-vm.sh
```

### Step 4: Check GitHub Runner Registration

Go to your repository settings:
- Settings > Actions > Runners
- Look for runner with name pattern: `azure-{environment}-{tag}`

### Step 5: Test Access

```bash
# Get the public IP
VM_PUBLIC_IP=$(az network public-ip show \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm-pip \
  --query "ipAddress" -o tsv)

# Test Nginx health check
curl http://$VM_PUBLIC_IP/health

# Should return: "Nginx reverse proxy is running"
```

---

## Common Issues and Solutions

### Issue: "PAT_TOKEN secret not found"

**Solution**: Add the GitHub PAT to repository secrets:

```bash
# In GitHub repository:
# Settings > Secrets and variables > Actions > New repository secret
# Name: PAT_TOKEN
# Value: Your GitHub Personal Access Token (ghp_...)
# Required scopes: repo, workflow
```

### Issue: "Runner registration failed"

**Symptoms**: Runner not visible in GitHub, logs show authentication errors

**Solution**: 
1. Verify PAT has correct scopes (`repo`, `workflow`)
2. Check PAT is not expired
3. Verify repository URL is correct in variables

### Issue: "Nginx not accessible"

**Symptoms**: Connection timeout, connection refused

**Solutions**:
1. **Security Group Issue**: Check NSG rules allow HTTP (port 80)
   ```bash
   az network nsg rule list --resource-group testcontainers-dev-rg --nsg-name testcontainers-dev-nsg -o table
   ```

2. **Nginx not started**: Check nginx status via Run Command
   ```bash
   az vm run-command invoke \
     --resource-group testcontainers-dev-rg \
     --name testcontainers-dev-vm \
     --command-id RunShellScript \
     --scripts "systemctl status nginx && systemctl start nginx"
   ```

3. **Cloud-init still running**: Wait for completion
   ```bash
   az vm run-command invoke \
     --resource-group testcontainers-dev-rg \
     --name testcontainers-dev-vm \
     --command-id RunShellScript \
     --scripts "cloud-init status --wait"
   ```

### Issue: "Docker not working in runner"

**Symptoms**: Runner jobs fail with "docker: command not found" or permission errors

**Solution**: Runner user needs to be in docker group (already configured in cloud-init)

Check via:
```bash
az vm run-command invoke \
  --resource-group testcontainers-dev-rg \
  --name testcontainers-dev-vm \
  --command-id RunShellScript \
  --scripts "groups azureuser && id azureuser"
```

---

## Next Steps

1. **Create the diagnostic scripts** (get-deployment-info.sh and diagnose-vm.sh)
2. **Run diagnostics** to identify current state
3. **Fix workflow** to display outputs after deployment
4. **Re-deploy** if necessary
5. **Monitor** cloud-init logs until completion
6. **Verify** all services are running
7. **Test** access to Nginx and runner functionality

## Verification Checklist

After deployment, verify:

- [ ] Resource group exists
- [ ] VM is running (power state)
- [ ] Public IP is assigned
- [ ] Nginx health check responds
- [ ] GitHub runner appears in repository settings
- [ ] Docker service is running
- [ ] Nginx auto-config service is running
- [ ] NSG allows HTTP traffic (port 80)
- [ ] Cloud-init completed successfully (status: done)
- [ ] No errors in `/var/log/cloud-init-output.log`
