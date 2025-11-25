#!/bin/bash

# Auto-Import Existing Resources Before Terraform Apply
# This script checks for existing resources and imports them into Terraform state
# making Terraform operations idempotent

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Auto-Import: Making Terraform Idempotent${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Get variables from Terraform or environment
PROJECT_NAME="${TF_VAR_project_name:-testcontainers}"
ENVIRONMENT="${TF_VAR_environment:-dev}"
LOCATION="${TF_VAR_location:-eastus}"

print_info "Configuration:"
echo "  Project: ${PROJECT_NAME}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Location: ${LOCATION}"
echo ""

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
if [ -z "$SUBSCRIPTION_ID" ]; then
    print_error "Not authenticated with Azure. Please run: az login"
    exit 1
fi

print_success "Authenticated with Azure"
echo "  Subscription: ${SUBSCRIPTION_ID}"
echo ""

# Calculate resource names
RG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-rg"
VNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-vnet"
PUBLIC_SUBNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-public-subnet"
PRIVATE_SUBNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-private-subnet"
NSG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-nsg"
VM_NAME="${PROJECT_NAME}-${ENVIRONMENT}-runner"
NIC_NAME="${PROJECT_NAME}-${ENVIRONMENT}-nic"
PUBLIC_IP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-pip"
NAT_GATEWAY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-nat"

# Track if any imports were done
IMPORTS_DONE=0

# Function to check if resource is in Terraform state
in_state() {
    terraform state list 2>/dev/null | grep -q "^$1$"
}

# Function to import resource if it exists in Azure but not in state
import_if_exists() {
    local tf_resource=$1
    local azure_resource_id=$2
    local resource_name=$3
    
    # Check if already in state
    if in_state "$tf_resource"; then
        print_info "Already in state: ${resource_name}"
        return 0
    fi
    
    # Check if exists in Azure
    print_info "Checking Azure for: ${resource_name}..."
    
    # Use az resource show to check if resource exists
    if az resource show --ids "$azure_resource_id" &>/dev/null; then
        print_warning "Found in Azure but not in state: ${resource_name}"
        print_info "Importing: ${tf_resource}"
        
        if terraform import "$tf_resource" "$azure_resource_id" 2>&1 | grep -v "Importing from ID"; then
            print_success "Imported: ${resource_name}"
            IMPORTS_DONE=$((IMPORTS_DONE + 1))
        else
            print_error "Failed to import: ${resource_name}"
            return 1
        fi
    else
        print_info "Not in Azure: ${resource_name} (will be created)"
    fi
}

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    print_info "Initializing Terraform..."
    terraform init -input=false
fi

echo ""
print_info "Scanning for existing resources..."
echo ""

# 1. Resource Group
import_if_exists \
    "azurerm_resource_group.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}" \
    "Resource Group: ${RG_NAME}"

# 2. Virtual Network
import_if_exists \
    "module.networking.azurerm_virtual_network.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}" \
    "Virtual Network: ${VNET_NAME}"

# 3. Public Subnet
import_if_exists \
    "module.networking.azurerm_subnet.public" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${PUBLIC_SUBNET_NAME}" \
    "Public Subnet: ${PUBLIC_SUBNET_NAME}"

# 4. Private Subnet
import_if_exists \
    "module.networking.azurerm_subnet.private" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${PRIVATE_SUBNET_NAME}" \
    "Private Subnet: ${PRIVATE_SUBNET_NAME}"

# 5. NAT Gateway Public IP
import_if_exists \
    "module.networking.azurerm_public_ip.nat" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/publicIPAddresses/${NAT_GATEWAY_NAME}-pip" \
    "NAT Gateway Public IP"

# 6. NAT Gateway
import_if_exists \
    "module.networking.azurerm_nat_gateway.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/natGateways/${NAT_GATEWAY_NAME}" \
    "NAT Gateway: ${NAT_GATEWAY_NAME}"

# 7. NAT Gateway Subnet Association
import_if_exists \
    "module.networking.azurerm_subnet_nat_gateway_association.private" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${PRIVATE_SUBNET_NAME}" \
    "NAT Gateway Association"

# 8. Network Security Group
import_if_exists \
    "module.security.azurerm_network_security_group.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/networkSecurityGroups/${NSG_NAME}" \
    "Network Security Group: ${NSG_NAME}"

# 9. NSG Association
import_if_exists \
    "module.security.azurerm_subnet_network_security_group_association.private" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${PRIVATE_SUBNET_NAME}" \
    "NSG Association"

# 10. Public IP for VM
import_if_exists \
    "module.vm.azurerm_public_ip.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/publicIPAddresses/${PUBLIC_IP_NAME}" \
    "VM Public IP: ${PUBLIC_IP_NAME}"

# 11. Network Interface
import_if_exists \
    "module.vm.azurerm_network_interface.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/networkInterfaces/${NIC_NAME}" \
    "Network Interface: ${NIC_NAME}"

# 12. Virtual Machine
import_if_exists \
    "module.vm.azurerm_linux_virtual_machine.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}" \
    "Virtual Machine: ${VM_NAME}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

if [ $IMPORTS_DONE -eq 0 ]; then
    print_success "No imports needed - state is up to date!"
    echo ""
    print_info "All resources are either:"
    echo "  • Already tracked in Terraform state, or"
    echo "  • Don't exist in Azure (will be created on apply)"
else
    print_success "Successfully imported ${IMPORTS_DONE} resource(s)!"
    echo ""
    print_info "Next steps:"
    echo "  1. Run 'terraform plan' to verify imported configuration"
    echo "  2. Fix any configuration drift if needed"
    echo "  3. Run 'terraform apply' to create/update remaining resources"
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

exit 0
