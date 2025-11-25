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

# Parse command line arguments
RESOURCE_GROUP=""
ENVIRONMENT_TAG=""
STORAGE_ACCOUNT=""
CONTAINER=""
STATE_BLOB=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group NAME  Azure Resource Group to delete (required)"
    echo "  -t, --tag TAG              Environment tag (optional, for Key Vault cleanup)"
    echo "  -a, --account NAME         Storage Account name (optional, for state cleanup)"
    echo "  -c, --container NAME       Storage Container name (optional, for state cleanup)"
    echo "  -s, --state-file PATH      State file blob path (optional, for state cleanup)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Basic cleanup - just delete resource group"
    echo "  $0 -g testcontainers-dev-rg"
    echo ""
    echo "  # Full cleanup - delete resources and state file"
    echo "  $0 -g testcontainers-dev-rg -t SIT-Team-20251125 -a tctfstate2745ace7 -c dev-container -s terraform.tfstate"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -t|--tag)
            ENVIRONMENT_TAG="$2"
            shift 2
            ;;
        -a|--account)
            STORAGE_ACCOUNT="$2"
            shift 2
            ;;
        -c|--container)
            CONTAINER="$2"
            shift 2
            ;;
        -s|--state-file)
            STATE_BLOB="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$RESOURCE_GROUP" ]; then
    echo -e "${RED}ERROR: Resource group is required${NC}"
    echo ""
    usage
fi

echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
if [ ! -z "$ENVIRONMENT_TAG" ]; then
    echo "  Environment Tag: $ENVIRONMENT_TAG"
fi
if [ ! -z "$STORAGE_ACCOUNT" ]; then
    echo "  Storage Account: $STORAGE_ACCOUNT"
    echo "  Container: $CONTAINER"
    echo "  State File: $STATE_BLOB"
fi
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
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo -e "${GREEN}✅ Resource group does not exist - nothing to clean up${NC}"
    
    # Still check for soft-deleted Key Vaults
    if [ ! -z "$ENVIRONMENT_TAG" ]; then
        echo ""
        echo -e "${YELLOW}Checking for soft-deleted Key Vaults with tag: $ENVIRONMENT_TAG${NC}"
        DELETED_KVS=$(az keyvault list-deleted --query "[?tags.EnvironmentTag=='$ENVIRONMENT_TAG'].name" -o tsv 2>/dev/null)
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
        fi
    fi
    exit 0
fi

echo -e "${YELLOW}Resource group exists. Listing resources...${NC}"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" -o table

RESOURCE_COUNT=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" -o tsv)
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

echo -e "${YELLOW}Deleting resource group: $RESOURCE_GROUP${NC}"
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo ""
echo -e "${GREEN}✅ Resource group deletion initiated${NC}"
echo ""
echo -e "${YELLOW}Note: Deletion is running in the background. Check status with:${NC}"
echo -e "  az group show --name $RESOURCE_GROUP"
echo ""

echo -e "${YELLOW}Step 5: Checking for soft-deleted Key Vaults...${NC}"
sleep 5  # Give it a moment for soft-delete to register

if [ ! -z "$ENVIRONMENT_TAG" ]; then
    DELETED_KVS=$(az keyvault list-deleted --query "[?tags.EnvironmentTag=='$ENVIRONMENT_TAG'].name" -o tsv 2>/dev/null)
    if [ -z "$DELETED_KVS" ]; then
        # Try without tag filter, using resource group
        DELETED_KVS=$(az keyvault list-deleted --query "[?properties.vaultId && contains(properties.vaultId, '$RESOURCE_GROUP')].name" -o tsv 2>/dev/null)
    fi
else
    # No tag specified, try to find by resource group only
    DELETED_KVS=$(az keyvault list-deleted --query "[?properties.vaultId && contains(properties.vaultId, '$RESOURCE_GROUP')].name" -o tsv 2>/dev/null)
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
echo "  - Resource group deletion initiated: $RESOURCE_GROUP"
echo "  - Key Vaults processed"
echo "  - VMs deleted"
echo ""
echo -e "${YELLOW}Verification (run after a few minutes):${NC}"
echo "  az group show --name $RESOURCE_GROUP"
echo "  (Should return 'ResourceGroupNotFound' when complete)"
echo ""

# Cleanup state file if storage info provided
if [ ! -z "$STORAGE_ACCOUNT" ] && [ ! -z "$CONTAINER" ] && [ ! -z "$STATE_BLOB" ]; then
    echo -e "${YELLOW}Step 6: Cleaning up state file...${NC}"
    echo ""
    read -p "Delete state file from storage? (yes/no): " DELETE_STATE
    if [ "$DELETE_STATE" == "yes" ]; then
        echo -e "${YELLOW}Deleting state file: $STATE_BLOB${NC}"
        ACCOUNT_KEY=$(az storage account keys list \
            --account-name "$STORAGE_ACCOUNT" \
            --resource-group "testcontainers-tfstate-rg" \
            --query "[0].value" \
            -o tsv 2>/dev/null)
        
        if [ ! -z "$ACCOUNT_KEY" ]; then
            az storage blob delete \
                --account-name "$STORAGE_ACCOUNT" \
                --container-name "$CONTAINER" \
                --name "$STATE_BLOB" \
                --account-key "$ACCOUNT_KEY" 2>/dev/null && \
                echo -e "${GREEN}✅ State file deleted${NC}" || \
                echo -e "${YELLOW}Could not delete state file${NC}"
        else
            echo -e "${YELLOW}Could not retrieve storage account key${NC}"
        fi
    fi
    echo ""
fi

echo -e "${YELLOW}Local cleanup (if you used Terraform):${NC}"
echo "  cd ../terraform"
echo "  rm -f terraform.tfstate terraform.tfstate.backup"
echo "  rm -f backend.tf.backup.*"
echo "  rm -rf .terraform/"
echo ""
