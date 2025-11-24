#!/bin/bash

# Azure OIDC Configuration Verification Script
# This script checks if your Azure environment is properly configured for OIDC with Terraform backend

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Azure OIDC Configuration Verification                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if required environment variables are set
echo -e "${YELLOW}[1/7] Checking environment variables...${NC}"

REQUIRED_VARS=("AZURE_CLIENT_ID" "AZURE_TENANT_ID" "AZURE_SUBSCRIPTION_ID")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
        echo -e "${RED}  ✗ $var not set${NC}"
    else
        echo -e "${GREEN}  ✓ $var set${NC}"
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}Error: Missing environment variables. Please set:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo -e "${RED}  export $var=<value>${NC}"
    done
    exit 1
fi

# Check Azure CLI authentication
echo ""
echo -e "${YELLOW}[2/7] Checking Azure CLI authentication...${NC}"
if az account show &> /dev/null; then
    CURRENT_SUB=$(az account show --query id -o tsv)
    echo -e "${GREEN}  ✓ Authenticated to Azure${NC}"
    echo -e "    Current subscription: $CURRENT_SUB"
    
    if [ "$CURRENT_SUB" != "$AZURE_SUBSCRIPTION_ID" ]; then
        echo -e "${YELLOW}  ⚠ Current subscription differs from AZURE_SUBSCRIPTION_ID${NC}"
        echo -e "${YELLOW}    Setting to correct subscription...${NC}"
        az account set --subscription $AZURE_SUBSCRIPTION_ID
    fi
else
    echo -e "${RED}  ✗ Not authenticated to Azure CLI${NC}"
    echo -e "${RED}    Please run: az login${NC}"
    exit 1
fi

# Check if service principal/app exists
echo ""
echo -e "${YELLOW}[3/7] Checking app registration...${NC}"
APP_INFO=$(az ad app show --id $AZURE_CLIENT_ID 2>/dev/null || echo "")

if [ -z "$APP_INFO" ]; then
    echo -e "${RED}  ✗ App registration not found${NC}"
    echo -e "${RED}    App ID: $AZURE_CLIENT_ID${NC}"
    exit 1
else
    APP_NAME=$(echo $APP_INFO | jq -r '.displayName')
    echo -e "${GREEN}  ✓ App registration found${NC}"
    echo -e "    Name: $APP_NAME"
    echo -e "    App ID: $AZURE_CLIENT_ID"
fi

# Check federated credentials
echo ""
echo -e "${YELLOW}[4/7] Checking federated credentials...${NC}"
APP_OBJECT_ID=$(az ad app show --id $AZURE_CLIENT_ID --query id -o tsv)
FED_CREDS=$(az ad app federated-credential list --id $APP_OBJECT_ID 2>/dev/null || echo "[]")
FED_COUNT=$(echo $FED_CREDS | jq '. | length')

if [ "$FED_COUNT" -eq 0 ]; then
    echo -e "${RED}  ✗ No federated credentials found${NC}"
    echo -e "${RED}    You need to create federated credentials for GitHub Actions${NC}"
    exit 1
else
    echo -e "${GREEN}  ✓ Found $FED_COUNT federated credential(s)${NC}"
    echo $FED_CREDS | jq -r '.[] | "    - " + .name + " (subject: " + .subject + ")"'
fi

# Check service principal role assignments
echo ""
echo -e "${YELLOW}[5/7] Checking subscription-level role assignments...${NC}"
ROLE_ASSIGNMENTS=$(az role assignment list --assignee $AZURE_CLIENT_ID --subscription $AZURE_SUBSCRIPTION_ID 2>/dev/null || echo "[]")

REQUIRED_ROLES=("Contributor" "User Access Administrator")
FOUND_ROLES=()

for role in "${REQUIRED_ROLES[@]}"; do
    if echo $ROLE_ASSIGNMENTS | jq -e ".[] | select(.roleDefinitionName == \"$role\")" > /dev/null; then
        echo -e "${GREEN}  ✓ $role role assigned${NC}"
        FOUND_ROLES+=("$role")
    else
        echo -e "${RED}  ✗ $role role NOT assigned${NC}"
    fi
done

if [ ${#FOUND_ROLES[@]} -lt 2 ]; then
    echo -e "${YELLOW}  ⚠ Missing required roles. Please assign:${NC}"
    for role in "${REQUIRED_ROLES[@]}"; do
        if [[ ! " ${FOUND_ROLES[@]} " =~ " ${role} " ]]; then
            echo -e "${YELLOW}    az role assignment create --assignee $AZURE_CLIENT_ID --role \"$role\" --scope /subscriptions/$AZURE_SUBSCRIPTION_ID${NC}"
        fi
    done
fi

# Check storage account and RBAC
echo ""
echo -e "${YELLOW}[6/7] Checking Terraform backend storage...${NC}"

PROJECT_NAME="testcontainers"
SUBSCRIPTION_SHORT=$(echo "$AZURE_SUBSCRIPTION_ID" | tr -d '-' | cut -c1-8)
RESOURCE_GROUP_NAME="${PROJECT_NAME}-tfstate-rg"
STORAGE_ACCOUNT_NAME="${PROJECT_NAME}tfstate${SUBSCRIPTION_SHORT}"

# Check if resource group exists
if az group show --name $RESOURCE_GROUP_NAME --subscription $AZURE_SUBSCRIPTION_ID &> /dev/null; then
    echo -e "${GREEN}  ✓ Resource group exists: $RESOURCE_GROUP_NAME${NC}"
else
    echo -e "${RED}  ✗ Resource group not found: $RESOURCE_GROUP_NAME${NC}"
    echo -e "${YELLOW}    Run the backend setup script to create it${NC}"
    exit 1
fi

# Check if storage account exists
if az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --subscription $AZURE_SUBSCRIPTION_ID &> /dev/null; then
    echo -e "${GREEN}  ✓ Storage account exists: $STORAGE_ACCOUNT_NAME${NC}"
    
    # Get storage account resource ID
    STORAGE_ACCOUNT_ID=$(az storage account show \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --subscription $AZURE_SUBSCRIPTION_ID \
        --query id -o tsv)
    
    # Check RBAC on storage account
    echo ""
    echo -e "${YELLOW}[7/7] Checking storage account RBAC...${NC}"
    STORAGE_ROLES=$(az role assignment list --scope $STORAGE_ACCOUNT_ID --assignee $AZURE_CLIENT_ID 2>/dev/null || echo "[]")
    
    STORAGE_REQUIRED_ROLES=("Storage Blob Data Contributor" "Storage Account Contributor")
    STORAGE_FOUND_ROLES=()
    
    for role in "${STORAGE_REQUIRED_ROLES[@]}"; do
        if echo $STORAGE_ROLES | jq -e ".[] | select(.roleDefinitionName == \"$role\")" > /dev/null; then
            echo -e "${GREEN}  ✓ $role role assigned on storage${NC}"
            STORAGE_FOUND_ROLES+=("$role")
        else
            echo -e "${RED}  ✗ $role role NOT assigned on storage${NC}"
        fi
    done
    
    if [ ${#STORAGE_FOUND_ROLES[@]} -lt 2 ]; then
        echo -e "${YELLOW}  ⚠ Missing storage RBAC roles. Please assign:${NC}"
        for role in "${STORAGE_REQUIRED_ROLES[@]}"; do
            if [[ ! " ${STORAGE_FOUND_ROLES[@]} " =~ " ${role} " ]]; then
                echo -e "${YELLOW}    az role assignment create --assignee $AZURE_CLIENT_ID --role \"$role\" --scope $STORAGE_ACCOUNT_ID${NC}"
            fi
        done
    fi
else
    echo -e "${RED}  ✗ Storage account not found: $STORAGE_ACCOUNT_NAME${NC}"
    echo -e "${YELLOW}    Run the backend setup script to create it${NC}"
    exit 1
fi

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Verification Summary                                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

ALL_GOOD=true

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}✗ Environment variables: Missing variables${NC}"
    ALL_GOOD=false
else
    echo -e "${GREEN}✓ Environment variables: All set${NC}"
fi

if [ -z "$APP_INFO" ]; then
    echo -e "${RED}✗ App registration: Not found${NC}"
    ALL_GOOD=false
else
    echo -e "${GREEN}✓ App registration: Found${NC}"
fi

if [ "$FED_COUNT" -eq 0 ]; then
    echo -e "${RED}✗ Federated credentials: None configured${NC}"
    ALL_GOOD=false
else
    echo -e "${GREEN}✓ Federated credentials: $FED_COUNT configured${NC}"
fi

if [ ${#FOUND_ROLES[@]} -lt 2 ]; then
    echo -e "${YELLOW}⚠ Subscription roles: Missing roles${NC}"
    ALL_GOOD=false
else
    echo -e "${GREEN}✓ Subscription roles: All assigned${NC}"
fi

if ! az group show --name $RESOURCE_GROUP_NAME --subscription $AZURE_SUBSCRIPTION_ID &> /dev/null; then
    echo -e "${RED}✗ Backend storage: Resource group missing${NC}"
    ALL_GOOD=false
elif ! az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --subscription $AZURE_SUBSCRIPTION_ID &> /dev/null; then
    echo -e "${RED}✗ Backend storage: Storage account missing${NC}"
    ALL_GOOD=false
else
    echo -e "${GREEN}✓ Backend storage: Configured${NC}"
fi

if [ ${#STORAGE_FOUND_ROLES[@]} -lt 2 ]; then
    echo -e "${YELLOW}⚠ Storage RBAC: Missing roles${NC}"
    ALL_GOOD=false
else
    echo -e "${GREEN}✓ Storage RBAC: All assigned${NC}"
fi

echo ""
if [ "$ALL_GOOD" = true ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ All checks passed! OIDC is properly configured         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}You can now run Terraform with OIDC authentication!${NC}"
    echo ""
    echo -e "${BLUE}Required environment variables for Terraform:${NC}"
    echo -e "  export ARM_CLIENT_ID=$AZURE_CLIENT_ID"
    echo -e "  export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID"
    echo -e "  export ARM_TENANT_ID=$AZURE_TENANT_ID"
    echo -e "  export ARM_USE_OIDC=true"
    echo -e "  export ARM_USE_AZUREAD=true"
    exit 0
else
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠ Some checks failed. Please review above                ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Review the failed checks above"
    echo -e "  2. Run suggested commands to fix issues"
    echo -e "  3. Re-run this script to verify"
    exit 1
fi
