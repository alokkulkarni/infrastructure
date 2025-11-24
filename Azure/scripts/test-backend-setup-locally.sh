#!/bin/bash

# Local Testing Script for Terraform Backend Setup
# This script allows you to test the backend setup locally before running GitHub Actions
# 
# Usage:
#   ./test-backend-setup-locally.sh [ENVIRONMENT_TAG] [LOCATION]
#
# Example:
#   ./test-backend-setup-locally.sh SIT-alok-teama-$(date +%Y%m%d-%H%M) eastus
#
# Prerequisites:
#   1. Azure CLI installed (az)
#   2. Authenticated with Azure (az login)
#   3. Proper permissions (Contributor, Storage Account Contributor, etc.)

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Local Testing - Terraform Backend Setup${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Check if az CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}ERROR: Azure CLI (az) is not installed${NC}"
    echo "Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if authenticated
echo -e "${YELLOW}Checking Azure CLI authentication...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}ERROR: Not authenticated with Azure CLI${NC}"
    echo -e "${YELLOW}Please run: az login${NC}"
    exit 1
fi

CURRENT_ACCOUNT=$(az account show --query "{name:name, id:id, tenantId:tenantId}" -o json)
echo -e "${GREEN}✓ Authenticated${NC}"
echo "$CURRENT_ACCOUNT" | jq .
echo ""

# Get parameters
ENVIRONMENT_TAG="${1:-}"
LOCATION="${2:-eastus}"

if [ -z "$ENVIRONMENT_TAG" ]; then
    echo -e "${YELLOW}Environment tag not provided. Generating one...${NC}"
    ENVIRONMENT_TAG="SIT-local-test-$(date +%Y%m%d-%H%M%S)"
    echo -e "${GREEN}Using: $ENVIRONMENT_TAG${NC}"
fi

echo -e "${BLUE}Configuration:${NC}"
echo "  Environment Tag: $ENVIRONMENT_TAG"
echo "  Location: $LOCATION"
echo ""

# Get subscription ID from current context
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}Subscription ID: $AZURE_SUBSCRIPTION_ID${NC}"
echo ""

# Ask for confirmation
echo -e "${YELLOW}This will create/update the following resources:${NC}"
echo "  - Resource Group: testcontainers-tfstate-rg"
echo "  - Storage Account: testcontainerstfstate$(echo $AZURE_SUBSCRIPTION_ID | tr -d '-' | cut -c1-8)"
echo "  - Container: $(echo $ENVIRONMENT_TAG | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# Export environment variables
export AZURE_SUBSCRIPTION_ID
export AZURE_LOCATION="$LOCATION"
export ENVIRONMENT_TAG
export PROJECT_NAME="testcontainers"

# Get service principal client ID if available (for RBAC testing)
# In local testing, this is optional
export ARM_CLIENT_ID="${ARM_CLIENT_ID:-}"

if [ -n "$ARM_CLIENT_ID" ]; then
    echo -e "${GREEN}ARM_CLIENT_ID set, will configure RBAC${NC}"
else
    echo -e "${YELLOW}ARM_CLIENT_ID not set, skipping RBAC configuration${NC}"
    echo -e "${YELLOW}(This is normal for local testing with user credentials)${NC}"
fi
echo ""

# Run the setup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-terraform-backend.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
    echo -e "${RED}ERROR: Setup script not found at: $SETUP_SCRIPT${NC}"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Running setup-terraform-backend.sh${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

bash "$SETUP_SCRIPT"

EXIT_CODE=$?

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Local test completed successfully!${NC}"
    echo ""
    echo -e "${GREEN}Backend Configuration:${NC}"
    echo "  backend_resource_group=$(echo testcontainers-tfstate-rg)"
    echo "  backend_storage_account=testcontainerstfstate$(echo $AZURE_SUBSCRIPTION_ID | tr -d '-' | cut -c1-8)"
    echo "  backend_container=$(echo $ENVIRONMENT_TAG | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    echo "  backend_key=terraform.tfstate"
    echo ""
    echo -e "${YELLOW}You can now use these values in your Terraform backend config:${NC}"
    echo ""
    echo "terraform {"
    echo "  backend \"azurerm\" {"
    echo "    resource_group_name  = \"testcontainers-tfstate-rg\""
    echo "    storage_account_name = \"testcontainerstfstate$(echo $AZURE_SUBSCRIPTION_ID | tr -d '-' | cut -c1-8)\""
    echo "    container_name       = \"$(echo $ENVIRONMENT_TAG | tr '[:upper:]' '[:lower:]' | tr '_' '-')\""
    echo "    key                  = \"terraform.tfstate\""
    echo "  }"
    echo "}"
    echo ""
    echo -e "${GREEN}Ready to run GitHub Actions workflow!${NC}"
else
    echo -e "${RED}✗ Local test failed with exit code $EXIT_CODE${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo "  1. Check Azure CLI authentication: az account show"
    echo "  2. Verify permissions: az role assignment list --assignee \$(az account show --query user.name -o tsv)"
    echo "  3. Check subscription quota: az vm list-usage --location $LOCATION"
    echo "  4. Review error messages above"
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

exit $EXIT_CODE
