#!/bin/bash

# Register Azure Resource Providers
# These providers must be registered before Terraform can create resources

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
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
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════"
    echo ""
}

# Required providers for TestContainers infrastructure
PROVIDERS=(
    "Microsoft.Network"
    "Microsoft.Compute"
    "Microsoft.Storage"
    "Microsoft.ContainerRegistry"
    "Microsoft.KeyVault"
)

print_header "Azure Provider Registration"

# Check Azure CLI authentication
if ! az account show > /dev/null 2>&1; then
    print_error "Not authenticated with Azure CLI"
    echo "Run: az login"
    exit 1
fi

# Show current subscription
SUB_NAME=$(az account show --query name -o tsv)
SUB_ID=$(az account show --query id -o tsv)
print_info "Azure Subscription:"
echo "  Name: $SUB_NAME"
echo "  ID:   $SUB_ID"
echo ""

print_info "Providers to register:"
for provider in "${PROVIDERS[@]}"; do
    echo "  - $provider"
done
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Registration cancelled"
    exit 0
fi

print_header "Checking and Registering Providers"

for provider in "${PROVIDERS[@]}"; do
    print_info "Checking: $provider"
    
    # Get current state
    state=$(az provider show -n "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
    
    if [ "$state" = "Registered" ]; then
        print_success "  Already registered: $provider"
    else
        print_info "  Current state: $state"
        print_info "  Registering: $provider"
        
        az provider register --namespace "$provider" > /dev/null 2>&1
        
        # Wait for registration (max 2 minutes)
        print_info "  Waiting for registration to complete..."
        max_attempts=24  # 24 * 5 seconds = 2 minutes
        attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            state=$(az provider show -n "$provider" --query "registrationState" -o tsv)
            
            if [ "$state" = "Registered" ]; then
                print_success "  Registered: $provider"
                break
            fi
            
            echo -n "."
            sleep 5
            ((attempt++))
        done
        echo ""
        
        if [ "$state" != "Registered" ]; then
            print_warning "  Registration in progress: $provider (state: $state)"
            print_info "    You can monitor with: az provider show -n $provider"
        fi
    fi
    echo ""
done

print_header "Registration Summary"

print_info "Final provider states:"
for provider in "${PROVIDERS[@]}"; do
    state=$(az provider show -n "$provider" --query "registrationState" -o tsv)
    if [ "$state" = "Registered" ]; then
        print_success "  $provider: $state"
    else
        print_warning "  $provider: $state"
    fi
done

echo ""
print_info "Note: Providers in 'Registering' state will complete in the background."
print_info "Terraform operations will work once registration completes."
echo ""

# Check if all are registered
all_registered=true
for provider in "${PROVIDERS[@]}"; do
    state=$(az provider show -n "$provider" --query "registrationState" -o tsv)
    if [ "$state" != "Registered" ]; then
        all_registered=false
        break
    fi
done

if [ "$all_registered" = true ]; then
    print_success "All providers registered successfully!"
    echo ""
    print_info "You can now run Terraform commands:"
    echo "  terraform plan"
    echo "  terraform apply"
else
    print_warning "Some providers are still registering."
    print_info "Monitor registration status with:"
    echo "  az provider list --query \"[?registrationState=='Registering']\" -o table"
    echo ""
    print_info "You can proceed with Terraform, but some resources may fail until registration completes."
fi

echo ""
