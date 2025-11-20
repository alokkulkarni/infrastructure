#!/bin/bash
# Quick Start: Build and Deploy Custom AMI
# This script guides you through the entire process

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                            ║${NC}"
echo -e "${BLUE}║  GitHub Actions Runner - Custom AMI Quick Start           ║${NC}"
echo -e "${BLUE}║                                                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${GREEN}Step 1: Checking Prerequisites${NC}"
echo "=================================================="
echo ""

# Check Packer
if ! command -v packer &> /dev/null; then
    echo -e "${YELLOW}⚠️  Packer not found${NC}"
    echo ""
    echo "Install Packer:"
    echo "  macOS:  brew tap hashicorp/tap && brew install hashicorp/tap/packer"
    echo "  Linux:  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -"
    echo "          sudo apt-add-repository \"deb [arch=amd64] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\""
    echo "          sudo apt-get update && sudo apt-get install packer"
    echo ""
    read -p "Install Packer now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew tap hashicorp/tap && brew install hashicorp/tap/packer
        else
            echo "Please install Packer manually for your system"
            exit 1
        fi
    else
        exit 1
    fi
fi
echo "✅ Packer: $(packer version | head -n1)"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found"
    echo "Install: https://aws.amazon.com/cli/"
    exit 1
fi
echo "✅ AWS CLI: $(aws --version)"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured"
    echo "Run: aws configure"
    exit 1
fi
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
echo "✅ AWS Account: $AWS_ACCOUNT"
echo "✅ AWS Identity: $AWS_USER"
echo ""

# Step 2: Build AMI
echo -e "${GREEN}Step 2: Build Custom AMI${NC}"
echo "=================================================="
echo "This will:"
echo "  - Launch a temporary EC2 instance (t3.medium)"
echo "  - Install all required packages"
echo "  - Create an AMI snapshot"
echo "  - Clean up temporary resources"
echo ""
echo "Estimated time: 15-20 minutes"
echo "Estimated cost: ~\$0.10 for build + \$0.25/month for AMI storage"
echo ""
read -p "Proceed with AMI build? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

cd "$(dirname "$0")"
echo ""
echo "Starting build..."
./build-ami.sh

if [ $? -ne 0 ]; then
    echo "❌ Build failed. Check logs above."
    exit 1
fi

echo ""
echo -e "${GREEN}✅ AMI Build Complete!${NC}"
echo ""

# Read AMI ID
if [ -f "latest-ami-id.txt" ]; then
    AMI_ID=$(cat latest-ami-id.txt)
    echo "Your new AMI ID: ${BLUE}$AMI_ID${NC}"
else
    echo "⚠️  AMI ID file not found. Check manifest.json"
    exit 1
fi

# Step 3: Update Configuration
echo ""
echo -e "${GREEN}Step 3: Update Terraform Configuration${NC}"
echo "=================================================="
echo ""
echo "Choose how to configure the custom AMI:"
echo ""
echo "Option A: Update terraform.tfvars (Recommended)"
echo "  Edit: AWS/terraform/terraform.tfvars"
echo "  Add:"
echo "    ami_id         = \"$AMI_ID\""
echo "    use_custom_ami = true"
echo ""
echo "Option B: Use GitHub Actions Workflow"
echo "  When running the deployment workflow, set:"
echo "    - Custom AMI ID: $AMI_ID"
echo "    - Use Custom AMI: true"
echo ""
echo "Option C: Command Line"
echo "  terraform apply -var=\"ami_id=$AMI_ID\" -var=\"use_custom_ami=true\""
echo ""
read -p "Update terraform.tfvars now? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    TFVARS_FILE="../../terraform/terraform.tfvars"
    
    if [ ! -f "$TFVARS_FILE" ]; then
        echo "Creating terraform.tfvars..."
        touch "$TFVARS_FILE"
    fi
    
    # Check if ami_id already exists
    if grep -q "^ami_id" "$TFVARS_FILE"; then
        # Update existing
        sed -i.bak "s|^ami_id.*|ami_id         = \"$AMI_ID\"|" "$TFVARS_FILE"
        echo "✅ Updated ami_id in terraform.tfvars"
    else
        # Add new
        echo "" >> "$TFVARS_FILE"
        echo "# Custom AMI Configuration" >> "$TFVARS_FILE"
        echo "ami_id         = \"$AMI_ID\"" >> "$TFVARS_FILE"
        echo "✅ Added ami_id to terraform.tfvars"
    fi
    
    # Check if use_custom_ami already exists
    if grep -q "^use_custom_ami" "$TFVARS_FILE"; then
        sed -i.bak "s|^use_custom_ami.*|use_custom_ami = true|" "$TFVARS_FILE"
        echo "✅ Updated use_custom_ami in terraform.tfvars"
    else
        echo "use_custom_ami = true" >> "$TFVARS_FILE"
        echo "✅ Added use_custom_ami to terraform.tfvars"
    fi
    
    echo ""
    echo "Configuration updated!"
fi

# Step 4: Next Steps
echo ""
echo -e "${GREEN}Step 4: Deploy Infrastructure${NC}"
echo "=================================================="
echo ""
echo "Now you can deploy your infrastructure:"
echo ""
echo "Via GitHub Actions:"
echo "  1. Go to: Actions → Deploy AWS Infrastructure (OIDC)"
echo "  2. Click 'Run workflow'"
echo "  3. Enter environment tag (e.g., SIT-Alok-TeamA-$(date +%Y%m%d-%H%M))"
echo "  4. Wait 5-10 minutes"
echo ""
echo "Via Terraform CLI:"
echo "  cd ../../terraform"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
echo ""
echo -e "${GREEN}Expected Results:${NC}"
echo "  ✅ EC2 instance starts in 2-3 minutes (vs 15-20 min)"
echo "  ✅ No package installation failures"
echo "  ✅ GitHub runner registers immediately"
echo "  ✅ Ready to run workflows"
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                            ║${NC}"
echo -e "${BLUE}║  ✅ Quick Start Complete!                                  ║${NC}"
echo -e "${BLUE}║                                                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Documentation: AWS/packer/README.md"
echo "AMI ID saved to: latest-ami-id.txt"
echo ""
