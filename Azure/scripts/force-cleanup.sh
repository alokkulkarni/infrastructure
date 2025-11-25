#!/bin/bash

# Force Cleanup Script - Uses Azure CLI directly
# Use this when Terraform cleanup fails due to permission or state issues

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Force Infrastructure Cleanup (Azure CLI)${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Configuration
RG_NAME="testcontainers-dev-rg"
ENVIRONMENT_TAG="SIT-Alok-TeamA-20251125-0921"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RG_NAME"
echo "  Environment Tag: $ENVIRONMENT_TAG"
echo ""

# Confirmation
echo -e "${RED}⚠️  WARNING: This will DESTROY all infrastructure using Azure CLI!${NC}"
echo -e "${RED}This action cannot be undone.${NC}"
echo ""
read -p "Are you sure you want to proceed? Type 'DESTROY' to confirm: " CONFIRMATION

if [ "$CONFIRMATION" != "DESTROY" ]; then
    echo -e "${RED}Cleanup cancelled.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 1: Checking if resource group exists...${NC}"
if ! az group show --name "$RG_NAME" &>/dev/null; then
    echo -e "${GREEN}✅ Resource group does not exist - nothing to clean up${NC}"
    exit 0
fi

echo -e "${YELLOW}Resource group exists. Listing resources...${NC}"
az resource list --resource-group "$RG_NAME" --query "[].{Name:name, Type:type}" -o table

RESOURCE_COUNT=$(az resource list --resource-group "$RG_NAME" --query "length([])" -o tsv)
echo ""
echo -e "${YELLOW}Found $RESOURCE_COUNT resources${NC}"
echo ""

echo -e "${YELLOW}Step 2: Deleting Key Vaults (if any)...${NC}"
KV_LIST=$(az keyvault list --resource-group "$RG_NAME" --query "[].name" -o tsv 2>/dev/null)
if [ ! -z "$KV_LIST" ]; then
    for kv in $KV_LIST; do
        echo -e "${YELLOW}Deleting Key Vault: $kv${NC}"
        az keyvault delete --name "$kv" --resource-group "$RG_NAME" 2>/dev/null || echo "Already deleted or inaccessible"
    done
    echo -e "${GREEN}✅ Key Vaults processed${NC}"
else
    echo -e "${GREEN}✅ No Key Vaults found${NC}"
fi

echo ""
echo -e "${YELLOW}Step 3: Deleting VMs (if any)...${NC}"
VM_LIST=$(az vm list --resource-group "$RG_NAME" --query "[].name" -o tsv 2>/dev/null)
if [ ! -z "$VM_LIST" ]; then
    for vm in $VM_LIST; do
        echo -e "${YELLOW}Deleting VM: $vm${NC}"
        az vm delete --resource-group "$RG_NAME" --name "$vm" --yes --no-wait 2>/dev/null || echo "Already deleted"
    done
    echo -e "${YELLOW}Waiting for VMs to be deleted...${NC}"
    sleep 10
    echo -e "${GREEN}✅ VMs deletion initiated${NC}"
else
    echo -e "${GREEN}✅ No VMs found${NC}"
fi

echo ""
echo -e "${YELLOW}Step 4: Force deleting entire resource group...${NC}"
echo -e "${RED}This will delete ALL remaining resources in the resource group${NC}"
echo ""
read -p "Proceed with resource group deletion? Type 'yes' to continue: " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "yes" ]; then
    echo -e "${RED}Resource group deletion cancelled.${NC}"
    echo -e "${YELLOW}Individual resources have been deleted, but resource group remains.${NC}"
    exit 0
fi

echo -e "${YELLOW}Deleting resource group: $RG_NAME${NC}"
az group delete --name "$RG_NAME" --yes --no-wait

echo ""
echo -e "${GREEN}✅ Resource group deletion initiated${NC}"
echo ""
echo -e "${YELLOW}Note: Deletion is running in the background. Check status with:${NC}"
echo -e "  az group show --name $RG_NAME"
echo ""

echo -e "${YELLOW}Step 5: Checking for soft-deleted Key Vaults...${NC}"
sleep 5  # Give it a moment for soft-delete to register

DELETED_KVS=$(az keyvault list-deleted --query "[?tags.EnvironmentTag=='$ENVIRONMENT_TAG'].name" -o tsv 2>/dev/null)
if [ -z "$DELETED_KVS" ]; then
    # Try without tag filter
    DELETED_KVS=$(az keyvault list-deleted --query "[?properties.vaultId && contains(properties.vaultId, '$RG_NAME')].name" -o tsv 2>/dev/null)
fi

if [ ! -z "$DELETED_KVS" ]; then
    echo -e "${YELLOW}Found soft-deleted Key Vaults:${NC}"
    echo "$DELETED_KVS"
    echo ""
    read -p "Purge soft-deleted Key Vaults? (yes/no): " PURGE_KV
    if [ "$PURGE_KV" == "yes" ]; then
        for kv in $DELETED_KVS; do
            echo -e "${YELLOW}Purging Key Vault: $kv${NC}"
            az keyvault purge --name "$kv" --no-wait 2>/dev/null || echo "Could not purge $kv"
        done
        echo -e "${GREEN}✅ Key Vault purge initiated${NC}"
    fi
else
    echo -e "${GREEN}✅ No soft-deleted Key Vaults found${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Force Cleanup Completed${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  - Resource group deletion initiated: $RG_NAME"
echo "  - Key Vaults processed"
echo "  - VMs deleted"
echo ""
echo -e "${YELLOW}Verification (run after a few minutes):${NC}"
echo "  az group show --name $RG_NAME"
echo "  (Should return 'ResourceGroupNotFound' when complete)"
echo ""
echo -e "${YELLOW}If using Terraform, clean up the local state:${NC}"
echo "  cd ../terraform"
echo "  rm -f terraform.tfstate terraform.tfstate.backup"
echo "  rm -f backend.tf.backup.*"
echo "  rm -rf .terraform/"
echo ""
