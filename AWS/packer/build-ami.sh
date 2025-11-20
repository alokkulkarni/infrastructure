#!/bin/bash
# Build custom GitHub Runner AMI using Packer
# This script builds an AMI in eu-west-2 region with all required packages pre-installed

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Change to packer directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

log "GitHub Runner AMI Builder"
log "=========================="

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
    error "Packer is not installed. Please install Packer first."
    echo ""
    echo "Install Packer:"
    echo "  macOS:  brew tap hashicorp/tap && brew install hashicorp/tap/packer"
    echo "  Linux:  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -"
    echo "          sudo apt-add-repository \"deb [arch=amd64] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\""
    echo "          sudo apt-get update && sudo apt-get install packer"
    exit 1
fi

PACKER_VERSION=$(packer version | head -n1)
log "Packer version: $PACKER_VERSION"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured or invalid"
    echo ""
    echo "Configure AWS credentials:"
    echo "  aws configure"
    echo "  OR set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    exit 1
fi

AWS_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
log "AWS Identity: $AWS_IDENTITY"

# Get AWS region
REGION="${AWS_DEFAULT_REGION:-eu-west-2}"
log "Target Region: $REGION"

# Initialize Packer
log "Initializing Packer plugins..."
packer init github-runner-ami.pkr.hcl

# Validate Packer configuration
log "Validating Packer configuration..."
packer validate github-runner-ami.pkr.hcl

if [ $? -ne 0 ]; then
    error "Packer configuration validation failed"
    exit 1
fi

log "Validation successful!"
echo ""

# Build the AMI
log "Starting AMI build..."
log "This will take approximately 15-20 minutes..."
echo ""

packer build \
    -var "region=$REGION" \
    github-runner-ami.pkr.hcl

if [ $? -eq 0 ]; then
    echo ""
    log "✅ AMI build completed successfully!"
    echo ""
    
    # Extract AMI ID from manifest
    if [ -f "manifest.json" ]; then
        AMI_ID=$(jq -r '.builds[0].artifact_id' manifest.json | cut -d':' -f2)
        AMI_NAME=$(jq -r '.builds[0].custom_data.build_time' manifest.json)
        
        log "AMI Details:"
        log "  AMI ID:     $AMI_ID"
        log "  Region:     $REGION"
        log "  Build Time: $AMI_NAME"
        echo ""
        
        log "Next steps:"
        echo "  1. Update terraform.tfvars with the new AMI ID:"
        echo "     custom_ami_id = \"$AMI_ID\""
        echo ""
        echo "  2. Or set as Terraform variable:"
        echo "     terraform apply -var=\"custom_ami_id=$AMI_ID\""
        echo ""
        echo "  3. Update AWS/terraform/modules/ec2/main.tf to use the custom AMI"
        echo ""
        
        # Save AMI ID to file
        echo "$AMI_ID" > latest-ami-id.txt
        log "AMI ID saved to: latest-ami-id.txt"
        
        # Optionally tag the AMI
        warning "Remember to add Cost Allocation Tags to the AMI in AWS Console if needed"
    else
        warning "manifest.json not found. Check Packer output for AMI ID."
    fi
else
    error "AMI build failed!"
    exit 1
fi

echo ""
log "Build process completed at $(date)"
