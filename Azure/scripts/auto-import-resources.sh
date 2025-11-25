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

# Calculate resource names (must match Terraform naming conventions)
RG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-rg"
VNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-vnet"
PUBLIC_SUBNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-public-subnet"
PRIVATE_SUBNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-private-subnet"
NSG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-nsg"
VM_NAME="${PROJECT_NAME}-${ENVIRONMENT}-runner"
NIC_NAME="${PROJECT_NAME}-${ENVIRONMENT}-nic"
VM_PUBLIC_IP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-vm-pip"
NAT_GATEWAY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-nat"
NAT_PUBLIC_IP_NAME="${NAT_GATEWAY_NAME}-pip"
KEY_VAULT_NAME="${PROJECT_NAME}${ENVIRONMENT}kv"  # Note: No dashes for KV name (Azure requirement)

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
    "module.networking.azurerm_subnet_nat_gateway_association.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${PRIVATE_SUBNET_NAME}" \
    "NAT Gateway Subnet Association"

# 8. NAT Gateway Public IP Association
import_if_exists \
    "module.networking.azurerm_nat_gateway_public_ip_association.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/natGateways/${NAT_GATEWAY_NAME}|${NAT_PUBLIC_IP_NAME}" \
    "NAT Gateway IP Association"

# 9. Network Security Group
import_if_exists \
    "module.security.azurerm_network_security_group.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/networkSecurityGroups/${NSG_NAME}" \
    "Network Security Group: ${NSG_NAME}"

# 10. NSG Rules (HTTP)
import_if_exists \
    "module.security.azurerm_network_security_rule.allow_http" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/networkSecurityGroups/${NSG_NAME}/securityRules/allow-http" \
    "NSG Rule: allow-http"

# 11. NSG Rules (HTTPS)
import_if_exists \
    "module.security.azurerm_network_security_rule.allow_https" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/networkSecurityGroups/${NSG_NAME}/securityRules/allow-https" \
    "NSG Rule: allow-https"

# 12. NSG Rules (Outbound)
import_if_exists \
    "module.security.azurerm_network_security_rule.allow_outbound" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/networkSecurityGroups/${NSG_NAME}/securityRules/allow-outbound" \
    "NSG Rule: allow-outbound"

# 13. NSG Subnet Association
import_if_exists \
    "module.security.azurerm_subnet_network_security_group_association.private" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${PRIVATE_SUBNET_NAME}" \
    "NSG Subnet Association"

# 14. VM Public IP
import_if_exists \
    "module.vm.azurerm_public_ip.vm" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/publicIPAddresses/${VM_PUBLIC_IP_NAME}" \
    "VM Public IP: ${VM_PUBLIC_IP_NAME}"

# 15. Network Interface
import_if_exists \
    "module.vm.azurerm_network_interface.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/networkInterfaces/${NIC_NAME}" \
    "Network Interface: ${NIC_NAME}"

# 16. NIC Security Group Association
import_if_exists \
    "module.vm.azurerm_network_interface_security_group_association.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/networkInterfaces/${NIC_NAME}|${NSG_NAME}" \
    "NIC Security Group Association"

# 17. Virtual Machine
import_if_exists \
    "module.vm.azurerm_linux_virtual_machine.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}" \
    "Virtual Machine: ${VM_NAME}"

# 18. Key Vault
import_if_exists \
    "module.vm.azurerm_key_vault.main" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
    "Key Vault: ${KEY_VAULT_NAME}"

# 19. Key Vault Access Policy
# Note: Access policies require special handling - get object_id from current client config
print_info "Checking Key Vault Access Policy..."
if az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RG_NAME}" &>/dev/null; then
    # Get the current object ID
    CURRENT_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || az account show --query user.name -o tsv)
    
    if [ -n "$CURRENT_OBJECT_ID" ]; then
        # Access policy import requires key_vault_id and object_id
        KV_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"
        ACCESS_POLICY_ID="${KV_ID}/objectId/${CURRENT_OBJECT_ID}"
        
        if ! in_state "module.vm.azurerm_key_vault_access_policy.terraform"; then
            # Check if access policy exists
            POLICY_EXISTS=$(az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RG_NAME}" --query "properties.accessPolicies[?objectId=='${CURRENT_OBJECT_ID}'].objectId" -o tsv 2>/dev/null)
            
            if [ -n "$POLICY_EXISTS" ]; then
                print_warning "Found Key Vault Access Policy not in Terraform state"
                print_info "Attempting import..."
                
                # Try import first
                if terraform import "module.vm.azurerm_key_vault_access_policy.terraform" "${ACCESS_POLICY_ID}" 2>&1 | tee /tmp/import_output.log | grep -q "Import successful"; then
                    print_success "Imported: Key Vault Access Policy"
                    IMPORTS_DONE=$((IMPORTS_DONE + 1))
                else
                    # Import failed - check if it's the "already exists" error
                    if grep -q "already exists" /tmp/import_output.log || grep -q "already associated" /tmp/import_output.log; then
                        print_warning "Access policy already exists but import failed"
                        print_info "Auto-cleaning up conflicting access policy..."
                        
                        if az keyvault delete-policy --name "${KEY_VAULT_NAME}" --object-id "${CURRENT_OBJECT_ID}" &>/dev/null; then
                            print_success "Deleted existing access policy - Terraform will recreate it"
                            echo "  Note: Terraform will recreate the access policy with correct permissions"
                        else
                            print_error "Could not delete access policy automatically"
                            print_info "Manual cleanup required:"
                            echo "  az keyvault delete-policy --name ${KEY_VAULT_NAME} --object-id ${CURRENT_OBJECT_ID}"
                        fi
                    else
                        print_warning "Import failed for unknown reason"
                        print_info "Check logs and consider manual cleanup if needed"
                    fi
                fi
                
                # Cleanup temp file
                rm -f /tmp/import_output.log
            else
                print_info "Access policy not in Azure (will be created)"
            fi
        else
            print_info "Already in state: Key Vault Access Policy"
        fi
    else
        print_warning "Could not determine current object ID for access policy"
    fi
else
    print_info "Key Vault not found in Azure (will be created)"
fi

# 20. Key Vault Secret (SSH Key)
SSH_SECRET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-ssh-key"
print_info "Checking Key Vault Secret (SSH Key)..."
if ! in_state "module.vm.azurerm_key_vault_secret.ssh_private_key"; then
    if az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name "${SSH_SECRET_NAME}" &>/dev/null 2>&1; then
        print_warning "SSH Key secret exists in Key Vault but not in Terraform state"
        print_info "Secrets contain sensitive data and cannot be imported"
        print_info "Auto-cleaning up existing secret..."
        
        # Try to delete the existing secret
        if az keyvault secret delete --vault-name "${KEY_VAULT_NAME}" --name "${SSH_SECRET_NAME}" &>/dev/null; then
            print_success "Deleted existing secret - Terraform will recreate it"
            
            # Purge the secret to completely remove it
            print_info "Purging deleted secret..."
            if az keyvault secret purge --vault-name "${KEY_VAULT_NAME}" --name "${SSH_SECRET_NAME}" &>/dev/null 2>&1; then
                print_success "Secret fully purged"
            else
                print_warning "Secret soft-deleted but purge not available (may be in recovery)"
                echo "  Note: Terraform may need to wait for purge protection period"
            fi
        else
            print_error "Could not delete secret automatically"
            print_info "Manual cleanup required:"
            echo "  az keyvault secret delete --vault-name ${KEY_VAULT_NAME} --name ${SSH_SECRET_NAME}"
            echo "  az keyvault secret purge --vault-name ${KEY_VAULT_NAME} --name ${SSH_SECRET_NAME}"
        fi
    else
        print_info "SSH Key secret not in Azure (will be created)"
    fi
else
    print_info "Already in state: Key Vault Secret"
fi

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
