#!/bin/bash

set -e
set -o pipefail

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

# Get current account without displaying subscription ID (to avoid masking issues)
CURRENT_ACCOUNT_NAME=$(az account show --query "name" -o tsv 2>/dev/null || echo "Unknown")
echo -e "${GREEN}✓ Authenticated${NC}"
echo "Subscription: $CURRENT_ACCOUNT_NAME"

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

# CRITICAL: Set subscription context once at the start
# After this, all subsequent az commands will use this subscription context
# We do NOT pass --subscription to individual commands to avoid GitHub masking issues
echo -e "${YELLOW}Setting subscription context...${NC}"
if ! az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null; then
    echo -e "${RED}ERROR: Failed to set subscription context${NC}"
    exit 1
fi

# Verify the subscription is set correctly (without logging the actual ID)
CURRENT_SUB_NAME=$(az account show --query "name" -o tsv)
echo -e "${GREEN}✓ Subscription context set to: $CURRENT_SUB_NAME${NC}"

# Check if Microsoft.Storage provider is registered
echo -e "${YELLOW}Checking Microsoft.Storage provider registration...${NC}"
STORAGE_PROVIDER_STATE=$(az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")

if [ "$STORAGE_PROVIDER_STATE" != "Registered" ]; then
    echo -e "${YELLOW}Microsoft.Storage provider not registered. Registering now...${NC}"
    az provider register --namespace Microsoft.Storage
    
    # Wait for registration to complete (with timeout)
    echo -e "${YELLOW}Waiting for provider registration to complete...${NC}"
    TIMEOUT=120
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        STATE=$(az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
        if [ "$STATE" = "Registered" ]; then
            echo -e "${GREEN}✓ Microsoft.Storage provider registered${NC}"
            break
        fi
        echo -e "${YELLOW}  Status: $STATE (waiting...)${NC}"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo -e "${RED}WARNING: Provider registration timed out after ${TIMEOUT}s${NC}"
        echo -e "${YELLOW}Registration may still be in progress. Storage operations might fail.${NC}"
    fi
else
    echo -e "${GREEN}✓ Microsoft.Storage provider already registered${NC}"
fi

# Derive resource names dynamically
PROJECT_NAME="${PROJECT_NAME:-testcontainers}"
# Storage account names must be 3-24 characters, lowercase letters and numbers only
# Using first 8 chars of subscription ID to ensure uniqueness across Azure
SUBSCRIPTION_SHORT=$(echo "$AZURE_SUBSCRIPTION_ID" | tr -d '-' | cut -c1-8)
RESOURCE_GROUP_NAME="${PROJECT_NAME}-tfstate-rg"
# Shorten to "tctfstate" (9 chars) + 8 char subscription = 17 chars total (within 24 limit)
STORAGE_ACCOUNT_NAME="tctfstate${SUBSCRIPTION_SHORT}"

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

# Try to get storage account from our resource group
if az storage account show \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Storage account already exists in our resource group, reusing it${NC}"
else
    echo -e "${YELLOW}Storage account not found in resource group, attempting to create...${NC}"
    
    # Try to create storage account (subscription context already set)
    if az storage account create \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --location $AZURE_LOCATION \
        --sku Standard_LRS \
        --encryption-services blob \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --https-only true \
        --tags Environment=shared ManagedBy=Terraform Purpose=TerraformState 2>&1 | tee /tmp/storage_create.log; then
        echo -e "${GREEN}✓ Storage account created${NC}"
    else
        # Check if it failed because name is taken
        if grep -q "StorageAccountAlreadyTaken\|AlreadyExists" /tmp/storage_create.log; then
            echo -e "${RED}ERROR: Storage account name '$STORAGE_ACCOUNT_NAME' is globally taken${NC}"
            echo ""
            echo "The storage account name is already in use by another Azure subscription."
            echo "Storage account names must be globally unique across all of Azure."
            echo ""
            echo "Solutions:"
            echo "  1. Use a different PROJECT_NAME environment variable"
            echo "  2. Manually specify a unique storage account name"
            echo "  3. If this storage account was yours, it may be soft-deleted (wait 24h)"
            echo ""
            echo "Current naming: ${PROJECT_NAME}tfstate${SUBSCRIPTION_SHORT}"
            exit 1
        else
            echo -e "${RED}ERROR: Failed to create storage account${NC}"
            echo "Error details:"
            cat /tmp/storage_create.log
            echo ""
            echo "This could be due to:"
            echo "  1. Insufficient permissions (need Storage Account Contributor)"
            echo "  2. Subscription quota exceeded"
            echo "  3. Location not supported for storage accounts"
            echo "  4. Network restrictions"
            exit 1
        fi
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
ACCOUNT_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --query '[0].value' -o tsv)

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
