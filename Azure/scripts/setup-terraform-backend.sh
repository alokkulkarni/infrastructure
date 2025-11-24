#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up Terraform Backend for Azure...${NC}"

# Check required environment variables
if [ -z "$AZURE_LOCATION" ]; then
    echo -e "${RED}Error: AZURE_LOCATION environment variable is not set${NC}"
    exit 1
fi

# Get Azure Subscription ID for unique naming
# Try to get from environment first (set by GitHub Actions), then from az account
if [ -n "$ARM_SUBSCRIPTION_ID" ]; then
    AZURE_SUBSCRIPTION_ID="$ARM_SUBSCRIPTION_ID"
    echo -e "${GREEN}Using subscription from ARM_SUBSCRIPTION_ID environment variable${NC}"
else
    AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null)
    if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
        echo -e "${RED}Error: Unable to retrieve Azure Subscription ID${NC}"
        echo -e "${RED}Please ensure you are logged in with 'az login' or set ARM_SUBSCRIPTION_ID${NC}"
        exit 1
    fi
fi
echo "Subscription ID: $AZURE_SUBSCRIPTION_ID"

# Derive resource names dynamically
PROJECT_NAME="${PROJECT_NAME:-testcontainers}"
# Storage account names must be 3-24 characters, lowercase letters and numbers only
# Using first 8 chars of subscription ID to ensure uniqueness
SUBSCRIPTION_SHORT=$(echo "$AZURE_SUBSCRIPTION_ID" | tr -d '-' | cut -c1-8)
RESOURCE_GROUP_NAME="${PROJECT_NAME}-tfstate-rg"
STORAGE_ACCOUNT_NAME="${PROJECT_NAME}tfstate${SUBSCRIPTION_SHORT}"
CONTAINER_NAME="tfstate"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  Location: $AZURE_LOCATION"
echo ""

# Check if resource group exists
echo -e "${YELLOW}Checking if resource group exists...${NC}"
if az group show --name $RESOURCE_GROUP_NAME --subscription $AZURE_SUBSCRIPTION_ID &> /dev/null; then
    echo -e "${GREEN}✓ Resource group already exists, reusing existing resource group${NC}"
else
    echo -e "${YELLOW}Creating resource group...${NC}"
    az group create \
        --name $RESOURCE_GROUP_NAME \
        --location $AZURE_LOCATION \
        --subscription $AZURE_SUBSCRIPTION_ID \
        --tags Environment=shared ManagedBy=Terraform Purpose=TerraformState
    echo -e "${GREEN}✓ Resource group created${NC}"
fi

# Check if storage account exists
echo -e "${YELLOW}Checking if storage account exists...${NC}"
if az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --subscription $AZURE_SUBSCRIPTION_ID &> /dev/null; then
    echo -e "${GREEN}✓ Storage account already exists, reusing existing storage account${NC}"
else
    echo -e "${YELLOW}Creating storage account...${NC}"
    az storage account create \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --location $AZURE_LOCATION \
        --subscription $AZURE_SUBSCRIPTION_ID \
        --sku Standard_LRS \
        --encryption-services blob \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --https-only true \
        --tags Environment=shared ManagedBy=Terraform Purpose=TerraformState
    echo -e "${GREEN}✓ Storage account created${NC}"
fi

# Enable versioning
echo -e "${YELLOW}Enabling blob versioning...${NC}"
az storage account blob-service-properties update \
    --account-name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --subscription $AZURE_SUBSCRIPTION_ID \
    --enable-versioning true
echo -e "${GREEN}✓ Blob versioning enabled${NC}"

# Check if container exists
echo -e "${YELLOW}Checking if container exists...${NC}"
ACCOUNT_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --subscription $AZURE_SUBSCRIPTION_ID --query '[0].value' -o tsv)

if az storage container show \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $ACCOUNT_KEY &> /dev/null; then
    echo -e "${GREEN}✓ Container already exists, reusing existing container${NC}"
else
    echo -e "${YELLOW}Creating container...${NC}"
    az storage container create \
        --name $CONTAINER_NAME \
        --account-name $STORAGE_ACCOUNT_NAME \
        --account-key $ACCOUNT_KEY \
        --auth-mode key
    echo -e "${GREEN}✓ Container created${NC}"
fi

echo ""
echo -e "${GREEN}✓ Terraform backend setup complete!${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: This script is idempotent and reuses existing resources.${NC}"
echo "- Resource group, storage account, and container are shared across all environments"
echo "- Each environment uses a different state file blob (key)"
echo "- No resources are recreated if they already exist"
echo ""
echo -e "${YELLOW}Backend Configuration:${NC}"
echo "  resource_group_name  = \"$RESOURCE_GROUP_NAME\""
echo "  storage_account_name = \"$STORAGE_ACCOUNT_NAME\""
echo "  container_name       = \"$CONTAINER_NAME\""
echo "  key                  = \"azure/ENV/terraform.tfstate\""
echo ""

# Export for GitHub Actions workflow consumption
echo "export TF_BACKEND_RESOURCE_GROUP=\"$RESOURCE_GROUP_NAME\""
echo "export TF_BACKEND_STORAGE_ACCOUNT=\"$STORAGE_ACCOUNT_NAME\""
