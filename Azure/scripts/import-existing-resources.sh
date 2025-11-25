#!/bin/bash

# Import Existing Azure Resources into Terraform State
# This script imports existing Azure resources when Terraform reports "resource already exists"

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Import Existing Azure Resources to Terraform State${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Function to print colored messages
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Check if we're in the terraform directory
if [ ! -f "main.tf" ]; then
    print_error "This script must be run from the terraform directory"
    echo "Please run: cd infrastructure/Azure/terraform"
    exit 1
fi

# Check if Terraform is initialized
if [ ! -d ".terraform" ]; then
    print_error "Terraform not initialized. Please run: terraform init"
    exit 1
fi

# Get required variables
print_info "Reading Terraform variables..."

# Try to get variables from terraform.tfvars
if [ -f "terraform.tfvars" ]; then
    PROJECT_NAME=$(grep '^project_name' terraform.tfvars | cut -d '=' -f2 | tr -d ' "')
    ENVIRONMENT=$(grep '^environment' terraform.tfvars | cut -d '=' -f2 | tr -d ' "')
    LOCATION=$(grep '^location' terraform.tfvars | cut -d '=' -f2 | tr -d ' "')
fi

# Prompt for missing variables
if [ -z "$PROJECT_NAME" ]; then
    read -p "Enter project name (default: testcontainers): " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-testcontainers}
fi

if [ -z "$ENVIRONMENT" ]; then
    read -p "Enter environment (default: dev): " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-dev}
fi

if [ -z "$LOCATION" ]; then
    read -p "Enter location (default: eastus): " LOCATION
    LOCATION=${LOCATION:-eastus}
fi

# Calculate resource names (must match Terraform naming convention)
RG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-rg"

echo ""
print_info "Configuration:"
echo "  Project Name: ${PROJECT_NAME}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Location: ${LOCATION}"
echo "  Resource Group: ${RG_NAME}"
echo ""

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
if [ -z "$SUBSCRIPTION_ID" ]; then
    print_error "Not authenticated with Azure CLI. Please run: az login"
    exit 1
fi

print_success "Authenticated with Azure"
echo "  Subscription ID: ${SUBSCRIPTION_ID}"
echo ""

# Check if resource group exists in Azure
print_info "Checking if resource group exists in Azure..."
RG_EXISTS=$(az group exists --name "${RG_NAME}")

if [ "$RG_EXISTS" = "true" ]; then
    print_success "Resource group '${RG_NAME}' exists in Azure"
    
    # Get resource group details
    RG_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}"
    
    echo ""
    print_warning "This will import the following resource into Terraform state:"
    echo "  Resource: azurerm_resource_group.main"
    echo "  Azure ID: ${RG_ID}"
    echo ""
    
    # Check if already in state
    print_info "Checking if resource is already in Terraform state..."
    if terraform state list | grep -q "azurerm_resource_group.main"; then
        print_success "Resource group is already in Terraform state"
        echo ""
        print_info "You can:"
        echo "  1. Run 'terraform state show azurerm_resource_group.main' to see current state"
        echo "  2. Run 'terraform plan' to see if configuration matches Azure"
        echo "  3. Run 'terraform state rm azurerm_resource_group.main' to remove and re-import"
        exit 0
    fi
    
    read -p "Continue with import? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Import cancelled"
        exit 0
    fi
    
    echo ""
    print_info "Importing resource group..."
    
    # Import the resource
    if terraform import azurerm_resource_group.main "${RG_ID}"; then
        print_success "Successfully imported resource group!"
        echo ""
        
        # Show the imported state
        print_info "Imported resource state:"
        terraform state show azurerm_resource_group.main
        
        echo ""
        print_success "Import complete!"
        echo ""
        print_info "Next steps:"
        echo "  1. Run 'terraform plan' to verify configuration matches Azure"
        echo "  2. Fix any configuration drift if needed"
        echo "  3. Run 'terraform apply' to create remaining resources"
        echo ""
        
        # Check for other resources that might need importing
        print_info "Checking for other existing resources..."
        echo ""
        
        # Check for VNet
        VNET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-vnet"
        if az network vnet show --resource-group "${RG_NAME}" --name "${VNET_NAME}" &>/dev/null; then
            print_warning "VNet '${VNET_NAME}' also exists - may need to import module resources"
        fi
        
        # Check for VM
        VM_NAME="${PROJECT_NAME}-${ENVIRONMENT}-runner"
        if az vm show --resource-group "${RG_NAME}" --name "${VM_NAME}" &>/dev/null; then
            print_warning "VM '${VM_NAME}' also exists - may need to import module resources"
        fi
        
        echo ""
        print_info "To import module resources, use:"
        echo "  terraform import 'module.networking.azurerm_virtual_network.main' \\"
        echo "    '/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}'"
        
    else
        print_error "Import failed!"
        echo ""
        print_info "Troubleshooting:"
        echo "  1. Verify resource group exists: az group show --name '${RG_NAME}'"
        echo "  2. Check Terraform is initialized: terraform init"
        echo "  3. Verify Azure CLI authentication: az account show"
        echo "  4. Check resource ID format is correct"
        exit 1
    fi
    
else
    print_warning "Resource group '${RG_NAME}' does NOT exist in Azure"
    echo ""
    print_info "This means:"
    echo "  - The rollback may have partially completed"
    echo "  - The resource was deleted manually"
    echo "  - The resource name doesn't match your configuration"
    echo ""
    print_info "You should:"
    echo "  1. Run 'terraform plan' to see what will be created"
    echo "  2. Run 'terraform apply' to create the resources"
    echo "  3. No import needed since resources don't exist"
    exit 0
fi
