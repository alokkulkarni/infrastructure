#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up Terraform Backend for Azure...${NC}"

# Verify Azure CLI authentication first
echo -e "${YELLOW}Verifying Azure CLI authentication...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}ERROR: Not authenticated with Azure CLI${NC}"
    echo -e "${RED}Please ensure 'az login' has been run successfully${NC}"
    exit 1
fi

CURRENT_ACCOUNT=$(az account show --query "{name:name, id:id}" -o json 2>/dev/null || echo "Could not retrieve account details")
echo -e "${GREEN}✓ Authenticated${NC}"
if [ "$CURRENT_ACCOUNT" != "Could not retrieve account details" ]; then
    echo "$CURRENT_ACCOUNT"
fi

# Check required environment variables
if [ -z "$AZURE_LOCATION" ]; then
    echo -e "${RED}Error: AZURE_LOCATION environment variable is not set${NC}"
    exit 1
fi

if [ -z "$ENVIRONMENT_TAG" ]; then
    echo -e "${RED}Error: ENVIRONMENT_TAG environment variable is not set${NC}"
    exit 1
fi

# Get Azure Subscription ID from environment (passed from GitHub Actions)
if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
    echo -e "${RED}Error: AZURE_SUBSCRIPTION_ID environment variable is not set${NC}"
    exit 1
fi
echo -e "${GREEN}Using subscription ID from environment${NC}"

# Derive resource names dynamically
PROJECT_NAME="${PROJECT_NAME:-testcontainers}"
# Storage account names must be 3-24 characters, lowercase letters and numbers only
# Using first 8 chars of subscription ID to ensure uniqueness across Azure
SUBSCRIPTION_SHORT=$(echo "$AZURE_SUBSCRIPTION_ID" | tr -d '-' | cut -c1-8)
RESOURCE_GROUP_NAME="${PROJECT_NAME}-tfstate-rg"
STORAGE_ACCOUNT_NAME="${PROJECT_NAME}tfstate${SUBSCRIPTION_SHORT}"

# Container name based on environment tag for isolation
# Convert environment tag to lowercase and replace invalid chars
CONTAINER_NAME=$(echo "$ENVIRONMENT_TAG" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME (shared)"
echo "  Container: $CONTAINER_NAME (unique per environment tag)"
echo "  Environment Tag: $ENVIRONMENT_TAG"
echo "  Location: $AZURE_LOCATION"
echo ""

# Check if resource group exists
echo -e "${YELLOW}Checking if resource group exists...${NC}"

if az group show --name $RESOURCE_GROUP_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Resource group already exists, reusing existing resource group${NC}"
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

# First check if storage account name is available globally
echo "Checking storage account name availability..."
NAME_CHECK=$(az storage account check-name --name $STORAGE_ACCOUNT_NAME --query "{available:nameAvailable, reason:reason, message:message}" -o json)
echo "Name check result: $NAME_CHECK"

# Check if it exists in our resource group
if az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Storage account already exists in our resource group, reusing it${NC}"
else
    # Check if name is taken globally
    IS_AVAILABLE=$(echo "$NAME_CHECK" | grep -o '"available":\s*true' || echo "false")
    
    if [[ "$NAME_CHECK" == *'"available": true'* ]]; then
        echo -e "${YELLOW}Creating storage account...${NC}"
        if az storage account create \
            --name $STORAGE_ACCOUNT_NAME \
            --resource-group $RESOURCE_GROUP_NAME \
            --location $AZURE_LOCATION \
            --sku Standard_LRS \
            --encryption-services blob \
            --min-tls-version TLS1_2 \
            --allow-blob-public-access false \
            --https-only true \
            --tags Environment=shared ManagedBy=Terraform Purpose=TerraformState; then
            echo -e "${GREEN}✓ Storage account created${NC}"
        else
            echo -e "${RED}ERROR: Failed to create storage account${NC}"
            echo "This could be due to:"
            echo "  1. Insufficient permissions"
            echo "  2. Subscription quota exceeded"
            echo "  3. Location not supported"
            exit 1
        fi
    else
        echo -e "${RED}ERROR: Storage account name '$STORAGE_ACCOUNT_NAME' is not available${NC}"
        echo "Name check details: $NAME_CHECK"
        echo ""
        echo "This usually means:"
        echo "  1. The name is already taken by another subscription"
        echo "  2. The name was recently deleted (soft-delete period)"
        echo ""
        echo "Attempting to check if it exists elsewhere..."
        az storage account show --name $STORAGE_ACCOUNT_NAME 2>&1 || echo "Not accessible in current subscription"
        exit 1
    fi
fi

# Enable versioning
echo -e "${YELLOW}Enabling blob versioning...${NC}"
az storage account blob-service-properties update \
    --account-name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --enable-versioning true
echo -e "${GREEN}✓ Blob versioning enabled${NC}"

# Configure RBAC for OIDC authentication
if [ -n "$ARM_CLIENT_ID" ]; then
    echo -e "${YELLOW}Configuring RBAC permissions for OIDC authentication...${NC}"
    
    # Get storage account resource ID
    STORAGE_ACCOUNT_ID=$(az storage account show \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --query id -o tsv)
    
    # Assign Storage Blob Data Contributor role to the service principal
    echo -e "${YELLOW}Assigning Storage Blob Data Contributor role...${NC}"
    az role assignment create \
        --assignee $ARM_CLIENT_ID \
        --role "Storage Blob Data Contributor" \
        --scope $STORAGE_ACCOUNT_ID \
        2>/dev/null || echo -e "${YELLOW}Note: Role assignment may already exist${NC}"
    
    # Assign Storage Account Contributor role for backend operations
    echo -e "${YELLOW}Assigning Storage Account Contributor role...${NC}"
    az role assignment create \
        --assignee $ARM_CLIENT_ID \
        --role "Storage Account Contributor" \
        --scope $STORAGE_ACCOUNT_ID \
        2>/dev/null || echo -e "${YELLOW}Note: Role assignment may already exist${NC}"
    
    echo -e "${GREEN}✓ RBAC permissions configured${NC}"
    echo -e "${YELLOW}Note: Role assignments may take a few seconds to propagate${NC}"
    sleep 5
else
    echo -e "${YELLOW}Skipping RBAC configuration (ARM_CLIENT_ID not set)${NC}"
    echo -e "${YELLOW}For OIDC, you'll need to manually assign Storage Blob Data Contributor role${NC}"
fi

# Check if container exists
echo -e "${YELLOW}Checking if container exists...${NC}"
ACCOUNT_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv)

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
echo "- Shared resource group: $RESOURCE_GROUP_NAME"
echo "- Shared storage account: $STORAGE_ACCOUNT_NAME"
echo "- Environment-specific container: $CONTAINER_NAME"
echo "- Each environment tag gets its own container for complete isolation"
echo "- No resources are recreated if they already exist"
echo ""
echo -e "${YELLOW}Backend Configuration:${NC}"
echo "  resource_group_name  = \"$RESOURCE_GROUP_NAME\""
echo "  storage_account_name = \"$STORAGE_ACCOUNT_NAME\""
echo "  container_name       = \"$CONTAINER_NAME\""
echo "  key                  = \"terraform.tfstate\""
echo ""

# Export for GitHub Actions workflow consumption
echo "export TF_BACKEND_RESOURCE_GROUP=\"$RESOURCE_GROUP_NAME\""
echo "export TF_BACKEND_STORAGE_ACCOUNT=\"$STORAGE_ACCOUNT_NAME\""
echo "export TF_BACKEND_CONTAINER=\"$CONTAINER_NAME\""
