#!/bin/bash

###############################################################################
# Manual OIDC Setup Script for GitHub Actions
#
# This script creates the initial Azure AD Application and Federated Identity
# Credentials required for GitHub Actions OIDC authentication.
#
# Run this ONCE before the first Terraform deployment. After that, Terraform
# will manage these resources.
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - Permissions to create Azure AD applications
#   - Permissions to assign roles on subscription
#
# Usage:
#   ./setup-oidc-manually.sh <github-org> <github-repo> <environment>
#
# Example:
#   ./setup-oidc-manually.sh alokkulkarni infrastructure dev
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo
}

# Check arguments
if [ $# -lt 3 ]; then
    print_error "Usage: $0 <github-org> <github-repo> <environment>"
    print_info "Example: $0 alokkulkarni infrastructure dev"
    exit 1
fi

GITHUB_ORG="$1"
GITHUB_REPO="$2"
ENVIRONMENT="$3"
PROJECT_NAME="testcontainers"

print_header "Manual OIDC Setup for GitHub Actions"

print_info "Configuration:"
echo "  GitHub Org:   $GITHUB_ORG"
echo "  GitHub Repo:  $GITHUB_REPO"
echo "  Environment:  $ENVIRONMENT"
echo "  Project Name: $PROJECT_NAME"
echo

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    print_info "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

print_success "Azure CLI is installed"

# Check authentication
if ! az account show &> /dev/null; then
    print_error "Not authenticated with Azure CLI"
    print_info "Run: az login"
    exit 1
fi

print_success "Authenticated with Azure CLI"

# Get Azure IDs
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

print_info "Azure Subscription:"
echo "  Name: $SUBSCRIPTION_NAME"
echo "  ID:   $SUBSCRIPTION_ID"
echo "  Tenant: $TENANT_ID"
echo

# Confirm before proceeding
print_warning "This will create:"
echo "  1. Azure AD Application: ${PROJECT_NAME}-${ENVIRONMENT}-github-actions"
echo "  2. Service Principal"
echo "  3. Three Federated Identity Credentials:"
echo "     - Main branch: repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"
echo "     - Pull requests: repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request"
echo "     - Environment: repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${ENVIRONMENT}"
echo "  4. Role assignments: Contributor + User Access Administrator"
echo

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Aborted"
    exit 0
fi

APP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-github-actions"

print_header "Creating Azure AD Application"

# Check if app already exists
EXISTING_APP_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP_ID" ]; then
    print_warning "Application already exists: $APP_NAME"
    print_info "Using existing application ID: $EXISTING_APP_ID"
    APP_ID="$EXISTING_APP_ID"
    OBJECT_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].id' -o tsv)
else
    # Create app registration
    print_info "Creating app registration: $APP_NAME"
    az ad app create --display-name "$APP_NAME" > /dev/null
    
    APP_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)
    OBJECT_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].id' -o tsv)
    
    print_success "Created application"
    echo "  Application ID: $APP_ID"
    echo "  Object ID: $OBJECT_ID"
fi

print_header "Creating Service Principal"

# Check if service principal exists
EXISTING_SP=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_SP" ]; then
    print_warning "Service Principal already exists"
    SP_OBJECT_ID="$EXISTING_SP"
else
    # Create service principal
    print_info "Creating service principal"
    az ad sp create --id "$APP_ID" > /dev/null
    
    SP_OBJECT_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)
    
    print_success "Created service principal"
    echo "  Service Principal Object ID: $SP_OBJECT_ID"
fi

print_header "Creating Federated Identity Credentials"

# Function to create or update federated credential with validation
create_federated_credential() {
    local name="$1"
    local subject="$2"
    local description="$3"
    
    print_info "Validating credential: $name"
    
    # Check if credential already exists and get its subject
    EXISTING_SUBJECT=$(az ad app federated-credential list \
        --id "$OBJECT_ID" \
        --query "[?name=='$name'].subject" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_SUBJECT" ]; then
        # Credential exists - validate subject matches
        if [ "$EXISTING_SUBJECT" = "$subject" ]; then
            print_success "  Credential is valid: $name"
            echo "    Subject: $subject"
            return 0
        else
            print_warning "  Credential exists but subject mismatch"
            echo "    Expected: $subject"
            echo "    Found:    $EXISTING_SUBJECT"
            print_info "  Deleting invalid credential"
            
            az ad app federated-credential delete \
                --id "$OBJECT_ID" \
                --federated-credential-id "$name" \
                --yes 2>/dev/null || true
            
            sleep 2  # Wait for deletion to propagate
        fi
    fi
    
    # Create credential (either new or replacement)
    print_info "  Creating credential: $name"
    az ad app federated-credential create \
        --id "$OBJECT_ID" \
        --parameters "{
            \"name\": \"$name\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"$subject\",
            \"audiences\": [\"api://AzureADTokenExchange\"],
            \"description\": \"$description\"
        }" > /dev/null
    print_success "  Created: $name"
    echo "    Subject: $subject"
}

# Create federated credentials
create_federated_credential \
    "${PROJECT_NAME}-${ENVIRONMENT}-github-main" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main" \
    "GitHub Actions OIDC for main branch"

create_federated_credential \
    "${PROJECT_NAME}-${ENVIRONMENT}-github-pr" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request" \
    "GitHub Actions OIDC for pull requests"

create_federated_credential \
    "${PROJECT_NAME}-${ENVIRONMENT}-github-env" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${ENVIRONMENT}" \
    "GitHub Actions OIDC for environment deployments"

print_header "Assigning Azure Roles"

# Function to validate and assign role
assign_role() {
    local role="$1"
    
    print_info "Validating role: $role"
    
    # Check if role assignment exists at correct scope
    EXISTING_SCOPE=$(az role assignment list \
        --assignee "$SP_OBJECT_ID" \
        --role "$role" \
        --query "[0].scope" -o tsv 2>/dev/null || echo "")
    
    EXPECTED_SCOPE="/subscriptions/$SUBSCRIPTION_ID"
    
    if [ "$EXISTING_SCOPE" = "$EXPECTED_SCOPE" ]; then
        print_success "  Role is valid: $role"
        return 0
    fi
    
    if [ -n "$EXISTING_SCOPE" ] && [ "$EXISTING_SCOPE" != "$EXPECTED_SCOPE" ]; then
        print_warning "  Role exists at wrong scope: $EXISTING_SCOPE"
        print_info "  Cleaning up incorrect assignments"
        
        # Get all assignments for this role and clean up incorrect ones
        az role assignment list \
            --assignee "$SP_OBJECT_ID" \
            --role "$role" \
            --query "[].id" -o tsv | while read assignment_id; do
            local scope=$(az role assignment list --query "[?id=='$assignment_id'].scope" -o tsv)
            if [ "$scope" != "$EXPECTED_SCOPE" ]; then
                print_info "    Removing: $scope"
                az role assignment delete --ids "$assignment_id" 2>/dev/null || true
            fi
        done
    fi
    
    # Assign role at correct scope
    print_info "  Assigning role: $role"
    az role assignment create \
        --assignee "$SP_OBJECT_ID" \
        --role "$role" \
        --scope "$EXPECTED_SCOPE" > /dev/null 2>&1 || true
    
    sleep 3  # Wait for propagation
    
    # Verify assignment
    VERIFY_SCOPE=$(az role assignment list \
        --assignee "$SP_OBJECT_ID" \
        --role "$role" \
        --query "[0].scope" -o tsv 2>/dev/null || echo "")
    
    if [ "$VERIFY_SCOPE" = "$EXPECTED_SCOPE" ]; then
        print_success "  Assigned: $role"
    else
        print_warning "  Assignment may not have propagated yet: $role"
    fi
}

assign_role "Contributor"
assign_role "User Access Administrator"

print_header "✓ OIDC Setup Complete!"

print_info "GitHub Secrets to configure:"
echo
echo "  AZURE_CLIENT_ID:      $APP_ID"
echo "  AZURE_TENANT_ID:      $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo

print_info "Add these to GitHub:"
echo "  1. Go to: https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/settings/secrets/actions"
echo "  2. Click 'New repository secret'"
echo "  3. Add each secret above"
echo

print_warning "Important:"
echo "  - Do NOT include trailing newlines when adding secrets to GitHub"
echo "  - Paste the values exactly as shown above"
echo "  - The workflow will sanitize any whitespace automatically"
echo

print_success "You can now run GitHub Actions workflows with OIDC authentication!"
echo

print_info "Next steps:"
echo "  1. Add the secrets to GitHub (see above)"
echo "  2. Run the 'Deploy Azure Infrastructure' workflow"
echo "  3. Terraform will manage these resources going forward"
echo
