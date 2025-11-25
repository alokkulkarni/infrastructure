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
    echo ""
    echo "Deployment may have failed or been destroyed."
    echo "Check GitHub Actions workflow logs or run terraform apply."
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
    NGINX_RESPONSE=$(curl -s --connect-timeout 5 "http://$VM_PUBLIC_IP/health" 2>&1 || echo "Connection failed")
    
    if [[ "$NGINX_RESPONSE" == *"Nginx"* ]]; then
        echo "✅ Nginx is accessible!"
        echo "   Response: $NGINX_RESPONSE"
    else
        echo "❌ Nginx not accessible"
        echo "   This could mean:"
        echo "   - Cloud-init is still running (wait 3-5 minutes)"
        echo "   - Nginx failed to start (check logs with diagnose-vm.sh)"
        echo "   - NSG rules blocking HTTP traffic"
    fi
    echo ""
fi

# List all resources
echo "📋 Resources in group:"
az resource list --resource-group "$RG_NAME" --query "[].{Name:name, Type:type, Location:location}" -o table

echo ""
echo "==================================="
echo ""
echo "💡 Next Steps:"
echo "   1. If Nginx not accessible, wait 3-5 minutes for cloud-init"
echo "   2. Run diagnose-vm.sh for detailed status"
echo "   3. Check GitHub repository settings for runner registration"
echo ""
