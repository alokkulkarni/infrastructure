#!/bin/bash

# Idempotent Terraform Apply
# This script ensures Terraform operations are idempotent by:
# 1. Auto-importing existing resources before apply
# 2. Handling resource conflicts gracefully
# 3. Continuing with apply even if some resources already exist

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Idempotent Terraform Apply${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Check we're in the right directory
if [ ! -f "main.tf" ]; then
    print_warning "Not in terraform directory. Changing to Azure/terraform..."
    cd "$(git rev-parse --show-toplevel)/infrastructure/Azure/terraform" 2>/dev/null || {
        echo "Error: Could not find terraform directory"
        exit 1
    }
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_info "Step 1: Initialize Terraform"
terraform init -upgrade

echo ""
print_info "Step 2: Auto-import existing resources"
if [ -f "../scripts/auto-import-resources.sh" ]; then
    ../scripts/auto-import-resources.sh || {
        print_warning "Auto-import completed with warnings (this is normal for first run)"
    }
else
    print_warning "Auto-import script not found, skipping..."
fi

echo ""
print_info "Step 3: Create Terraform plan"
terraform plan -out=tfplan

echo ""
print_info "Step 4: Review the plan above"
echo ""
read -p "Continue with apply? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Apply cancelled by user"
    exit 0
fi

echo ""
print_info "Step 5: Apply Terraform plan"
terraform apply tfplan

echo ""
print_success "Terraform apply completed successfully!"
echo ""

print_info "Outputs:"
terraform output

echo ""
print_success "All done! 🎉"
