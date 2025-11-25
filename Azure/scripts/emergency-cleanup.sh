#!/bin/bash

# Emergency Cleanup Script
# This script destroys Azure infrastructure by downloading and using the old state file
# Use this ONLY when the destroy workflow cannot access the correct state file

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Emergency Infrastructure Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Configuration
STORAGE_ACCOUNT="tctfstate2745ace7"
CONTAINER="sit-alok-teama-20251125-0921"
OLD_STATE_BLOB="terraform.tfstate"
RESOURCE_GROUP="testcontainers-tfstate-rg"
ENVIRONMENT_TAG="SIT-Alok-TeamA-20251125-0921"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  Container: $CONTAINER"
echo "  State File: $OLD_STATE_BLOB"
echo "  Environment Tag: $ENVIRONMENT_TAG"
echo ""

# Confirmation
echo -e "${RED}⚠️  WARNING: This will DESTROY all infrastructure!${NC}"
echo -e "${RED}This action cannot be undone.${NC}"
echo ""
read -p "Are you sure you want to proceed? Type 'destroy' to confirm: " CONFIRMATION

if [ "$CONFIRMATION" != "destroy" ]; then
    echo -e "${RED}Cleanup cancelled.${NC}"
    exit 1
fi

# Change to terraform directory
cd "$(dirname "$0")/../terraform"
echo -e "${GREEN}Working directory: $(pwd)${NC}"
echo ""

# Clean up any previous failed runs
echo -e "${YELLOW}Cleaning up any previous failed runs...${NC}"
if [ -d ".terraform" ]; then
    echo -e "${YELLOW}Removing old .terraform directory...${NC}"
    rm -rf .terraform
fi
if [ -f ".terraform.lock.hcl" ]; then
    echo -e "${YELLOW}Removing old lock file...${NC}"
    rm -f .terraform.lock.hcl
fi
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

# Step 1: Download the old state file from Azure Storage
echo -e "${YELLOW}Step 1: Downloading state file from Azure Storage...${NC}"
ACCOUNT_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" \
    -o tsv)

if [ -z "$ACCOUNT_KEY" ]; then
    echo -e "${RED}ERROR: Failed to retrieve storage account key${NC}"
    exit 1
fi

# Backup existing state if present
if [ -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}Backing up existing local state file...${NC}"
    mv terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
fi

# Download the old state file
az storage blob download \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --name "$OLD_STATE_BLOB" \
    --file "terraform.tfstate" \
    --account-key "$ACCOUNT_KEY"

if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}ERROR: Failed to download state file${NC}"
    exit 1
fi

echo -e "${GREEN}✅ State file downloaded successfully${NC}"
echo ""

# Check state file content
RESOURCE_COUNT=$(cat terraform.tfstate | grep -o '"type":' | wc -l | tr -d ' ')
echo -e "${YELLOW}State file contains approximately $RESOURCE_COUNT resource references${NC}"
echo ""

# Step 2: Remove backend configuration and backup existing one
echo -e "${YELLOW}Step 2: Configuring Terraform to use local state...${NC}"

# Backup existing backend.tf
if [ -f "backend.tf" ]; then
    echo -e "${YELLOW}Backing up existing backend.tf...${NC}"
    mv backend.tf backend.tf.backup.$(date +%Y%m%d_%H%M%S)
fi

# Remove .terraform directory to force clean initialization
if [ -d ".terraform" ]; then
    echo -e "${YELLOW}Removing existing .terraform directory...${NC}"
    rm -rf .terraform
fi

# Create minimal backend.tf for local state
cat > backend.tf <<EOF
# Temporary configuration - using local state for emergency cleanup
terraform {
  # No backend configuration - using local state file
}
EOF

echo -e "${GREEN}✅ Backend configured for local state${NC}"
echo ""

# Step 3: Create terraform.tfvars
echo -e "${YELLOW}Step 3: Creating terraform.tfvars...${NC}"
cat > terraform.tfvars <<EOF
location     = "uksouth"
project_name = "testcontainers"
environment  = "dev"
environment_tag = "$ENVIRONMENT_TAG"

vnet_address_space    = ["10.0.0.0/16"]
public_subnet_address_prefix   = ["10.0.1.0/24"]
private_subnet_address_prefix  = ["10.0.2.0/24"]

vm_size        = "Standard_D2s_v3"
admin_username = "azureuser"

github_repo_url      = "https://github.com/alokkulkarni/infrastructure"
github_runner_name   = "azure-vm-runner-$ENVIRONMENT_TAG"
github_runner_labels = ["self-hosted", "azure", "linux", "docker", "dev", "$ENVIRONMENT_TAG"]

# OIDC Configuration
github_org  = "alokkulkarni"
github_repo = "infrastructure"
EOF

echo -e "${GREEN}✅ Variables configured${NC}"
echo ""

# Step 4: Initialize Terraform with reconfigure flag
echo -e "${YELLOW}Step 4: Initializing Terraform...${NC}"
terraform init -reconfigure

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Terraform initialization failed${NC}"
    echo -e "${YELLOW}Trying with -migrate-state flag...${NC}"
    terraform init -migrate-state -auto-approve || {
        echo -e "${RED}ERROR: Terraform initialization failed even with migration${NC}"
        exit 1
    }
fi

echo ""

# Step 5: Show what will be destroyed
echo -e "${YELLOW}Step 5: Planning destruction...${NC}"
echo -e "${YELLOW}Note: Skipping Key Vault secret refresh due to permissions${NC}"
terraform plan -destroy -refresh=false

echo ""
echo -e "${YELLOW}Resource summary from state file:${NC}"
terraform state list | head -20
TOTAL_RESOURCES=$(terraform state list | wc -l | tr -d ' ')
echo ""
echo -e "${YELLOW}Total resources to destroy: $TOTAL_RESOURCES${NC}"

echo ""
echo -e "${RED}⚠️  Final confirmation required${NC}"
read -p "Proceed with destroying ALL resources? Type 'yes' to continue: " FINAL_CONFIRMATION

if [ "$FINAL_CONFIRMATION" != "yes" ]; then
    echo -e "${RED}Cleanup cancelled.${NC}"
    exit 1
fi

# Step 6: Remove problematic resources from state first
echo -e "${YELLOW}Step 6: Removing Key Vault resources from state (permission issues)...${NC}"
terraform state rm module.vm.azurerm_key_vault_secret.ssh_private_key 2>/dev/null || echo "Secret not in state"
terraform state rm module.vm.azurerm_key_vault_access_policy.terraform 2>/dev/null || echo "Access policy not in state"
echo ""

# Step 7: Destroy infrastructure using Azure CLI and Terraform hybrid approach
echo -e "${YELLOW}Step 7: Destroying infrastructure...${NC}"
echo ""

# Get resource names from state
RG_NAME="testcontainers-dev-rg"
echo -e "${YELLOW}Resource Group: $RG_NAME${NC}"

# Delete Key Vault first via Azure CLI (avoids permission issues)
echo -e "${YELLOW}Deleting Key Vault via Azure CLI...${NC}"
KV_NAME=$(az keyvault list --resource-group "$RG_NAME" --query "[0].name" -o tsv 2>/dev/null)
if [ ! -z "$KV_NAME" ]; then
    echo -e "${YELLOW}Found Key Vault: $KV_NAME${NC}"
    az keyvault delete --name "$KV_NAME" --resource-group "$RG_NAME" 2>/dev/null || echo "Key Vault already deleted or inaccessible"
    terraform state rm module.vm.azurerm_key_vault.main 2>/dev/null || true
    echo -e "${GREEN}✅ Key Vault handled${NC}"
else
    echo -e "${YELLOW}No Key Vault found${NC}"
fi

echo ""
echo -e "${YELLOW}Destroying remaining resources with Terraform...${NC}"
echo -e "${YELLOW}Note: Ignoring 'not found' errors for already-deleted resources${NC}"

# Unset any previous TF_CLI_ARGS
unset TF_CLI_ARGS

terraform destroy \
  -refresh=false \
  -auto-approve 2>&1 | tee /tmp/terraform-destroy.log

# Check if destroy completed (exit code might be non-zero due to already-deleted resources)
if grep -q "Destroy complete!" /tmp/terraform-destroy.log; then
    echo -e "${GREEN}✅ Destroy completed successfully${NC}"
elif grep -q "was not found" /tmp/terraform-destroy.log; then
    echo -e "${YELLOW}⚠️  Some resources were already deleted. Cleaning up state...${NC}"
    
    # Remove resources from state that were already deleted
    terraform state list 2>/dev/null | grep -E "(network_interface|public_ip|virtual_machine|key_vault|nat_gateway)" | while read resource; do
        echo -e "${YELLOW}Removing orphaned resource from state: $resource${NC}"
        terraform state rm "$resource" 2>/dev/null || true
    done
    
    # Try destroy again
    echo -e "${YELLOW}Attempting final cleanup...${NC}"
    terraform destroy -refresh=false -auto-approve 2>&1 | grep -v "was not found" || echo -e "${YELLOW}Cleanup completed with some resources already deleted${NC}"
fi

echo ""
echo -e "${GREEN}✅ Terraform destroy completed${NC}"
echo ""

# Step 7: Verify cleanup
echo -e "${YELLOW}Step 8: Verifying cleanup...${NC}"

# Check state file
REMAINING=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
if [ "$REMAINING" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $REMAINING resources still in state:${NC}"
    terraform state list
    echo ""
else
    echo -e "${GREEN}✅ Terraform state is clean${NC}"
fi

# Check Azure
RG_NAME="testcontainers-dev-rg"

if az group show --name "$RG_NAME" &>/dev/null; then
    echo -e "${RED}⚠️  Warning: Resource group still exists${NC}"
    echo ""
    echo "Remaining resources:"
    az resource list --resource-group "$RG_NAME" --query "[].{Name:name, Type:type, Location:location}" -o table 2>/dev/null || echo "Could not list resources"
    
    echo ""
    read -p "Force delete resource group? (yes/no): " FORCE_DELETE
    if [ "$FORCE_DELETE" == "yes" ]; then
        echo -e "${YELLOW}Force deleting resource group...${NC}"
        az group delete --name "$RG_NAME" --yes --no-wait
        echo -e "${GREEN}✅ Resource group deletion initiated${NC}"
    fi
else
    echo -e "${GREEN}✅ Resource group successfully deleted${NC}"
fi

# Step 8: Check for soft-deleted Key Vaults
echo ""
echo -e "${YELLOW}Step 8: Checking for soft-deleted Key Vaults...${NC}"
DELETED_KVS=$(az keyvault list-deleted \
    --query "[?tags.EnvironmentTag=='$ENVIRONMENT_TAG'].name" \
    -o tsv)

if [ ! -z "$DELETED_KVS" ]; then
    echo -e "${YELLOW}Found soft-deleted Key Vaults:${NC}"
    echo "$DELETED_KVS"
    echo ""
    read -p "Purge soft-deleted Key Vaults? (yes/no): " PURGE_KV
    if [ "$PURGE_KV" == "yes" ]; then
        for kv in $DELETED_KVS; do
            echo -e "${YELLOW}Purging Key Vault: $kv${NC}"
            az keyvault purge --name "$kv" --no-wait || true
        done
        echo -e "${GREEN}✅ Key Vault purge initiated${NC}"
    fi
else
    echo -e "${GREEN}✅ No soft-deleted Key Vaults found${NC}"
fi

# Cleanup local files
echo ""
echo -e "${YELLOW}Cleaning up local state files...${NC}"
rm -f terraform.tfstate terraform.tfstate.backup
rm -f backend.tf
rm -f terraform.tfvars
rm -f .terraform.lock.hcl
rm -rf .terraform/

# Restore original backend.tf if it was backed up
LATEST_BACKUP=$(ls -t backend.tf.backup.* 2>/dev/null | head -1)
if [ ! -z "$LATEST_BACKUP" ]; then
    echo -e "${YELLOW}Restoring original backend.tf...${NC}"
    mv "$LATEST_BACKUP" backend.tf
    echo -e "${GREEN}✅ Original backend.tf restored${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Emergency Cleanup Completed${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  - Infrastructure destroyed"
echo "  - Local state files cleaned up"
echo "  - Resource group: $RG_NAME"
echo "  - Environment Tag: $ENVIRONMENT_TAG"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Verify all resources are deleted in Azure Portal"
echo "  2. Check for any orphaned resources"
echo "  3. Future deployments will use the correct state file path"
echo ""
