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

if [ -z "$RESOURCE_GROUP_NAME" ]; then
    echo -e "${RED}Error: RESOURCE_GROUP_NAME environment variable is not set${NC}"
    exit 1
fi

if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo -e "${RED}Error: STORAGE_ACCOUNT_NAME environment variable is not set${NC}"
    exit 1
fi

CONTAINER_NAME="tfstate"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  Location: $AZURE_LOCATION"
echo ""

# Check if resource group exists
echo -e "${YELLOW}Checking if resource group exists...${NC}"
if az group show --name $RESOURCE_GROUP_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Resource group already exists${NC}"
else
    echo -e "${YELLOW}Creating resource group...${NC}"
    az group create \
        --name $RESOURCE_GROUP_NAME \
        --location $AZURE_LOCATION \
        --tags Environment=shared ManagedBy=Terraform Purpose=TerraformState
    echo -e "${GREEN}✓ Resource group created${NC}"
fi

# Check if storage account exists
echo -e "${YELLOW}Checking if storage account exists...${NC}"
if az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Storage account already exists${NC}"
else
    echo -e "${YELLOW}Creating storage account...${NC}"
    az storage account create \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --location $AZURE_LOCATION \
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
    --enable-versioning true
echo -e "${GREEN}✓ Blob versioning enabled${NC}"

# Check if container exists
echo -e "${YELLOW}Checking if container exists...${NC}"
ACCOUNT_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv)

if az storage container show \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $ACCOUNT_KEY &> /dev/null; then
    echo -e "${GREEN}✓ Container already exists${NC}"
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
echo -e "${YELLOW}Backend Configuration:${NC}"
echo "  resource_group_name  = \"$RESOURCE_GROUP_NAME\""
echo "  storage_account_name = \"$STORAGE_ACCOUNT_NAME\""
echo "  container_name       = \"$CONTAINER_NAME\""
echo "  key                  = \"azure/ENV/terraform.tfstate\""
