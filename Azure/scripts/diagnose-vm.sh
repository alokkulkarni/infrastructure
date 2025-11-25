#!/bin/bash

set -e

RG_NAME="${1:-testcontainers-dev-rg}"
VM_NAME="${2:-testcontainers-dev-vm}"

echo "==================================="
echo " VM Diagnostics for $VM_NAME"
echo "==================================="
echo ""

# Check if VM exists
if ! az vm show --resource-group "$RG_NAME" --name "$VM_NAME" &>/dev/null; then
    echo "❌ VM '$VM_NAME' not found in resource group '$RG_NAME'!"
    exit 1
fi

echo "📊 Checking cloud-init status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "cloud-init status --long" \
  --query "value[0].message" -o tsv 2>/dev/null || echo "Failed to check cloud-init status"

echo ""
echo "🏃 Checking GitHub Runner status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "systemctl status actions.runner.* --no-pager 2>&1 | head -30 || echo 'Runner service not found'" \
  --query "value[0].message" -o tsv 2>/dev/null

echo ""
echo "🐳 Checking Docker status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "systemctl is-active docker && docker --version && docker ps -a | head -10" \
  --query "value[0].message" -o tsv 2>/dev/null

echo ""
echo "🌐 Checking Nginx status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "systemctl is-active nginx && nginx -v 2>&1 && echo '' && systemctl is-active nginx-auto-config" \
  --query "value[0].message" -o tsv 2>/dev/null

echo ""
echo "📝 Cloud-Init Output Log (last 50 lines)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "tail -n 50 /var/log/cloud-init-output.log" \
  --query "value[0].message" -o tsv 2>/dev/null

echo ""
echo "🔍 Checking for errors in cloud-init log..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "grep -i 'error\|fail\|fatal' /var/log/cloud-init-output.log | tail -20 || echo 'No errors found'" \
  --query "value[0].message" -o tsv 2>/dev/null

echo ""
echo "==================================="
echo ""
echo "💡 Interpretation Guide:"
echo ""
echo "Cloud-Init Status:"
echo "  • 'status: done' = Setup completed successfully"
echo "  • 'status: running' = Still installing/configuring (wait a few minutes)"
echo "  • 'status: error' = Setup failed (check error logs above)"
echo ""
echo "GitHub Runner:"
echo "  • 'active (running)' = Runner is working"
echo "  • 'inactive (dead)' = Runner failed to start"
echo "  • 'not found' = Runner not configured yet"
echo ""
echo "Docker:"
echo "  • 'active' = Docker is running"
echo "  • 'inactive' = Docker not started"
echo ""
echo "Nginx:"
echo "  • Both 'active' = Nginx and auto-config working"
echo "  • One 'inactive' = Service failed"
echo ""
