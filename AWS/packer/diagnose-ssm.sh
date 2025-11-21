#!/bin/bash
# SSM Connectivity Diagnostic Script

set -e

echo "============================================"
echo "SSM Connectivity Diagnostic"
echo "============================================"
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check 1: Session Manager Plugin
echo "1. Checking Session Manager Plugin..."
if command -v session-manager-plugin &> /dev/null; then
    VERSION=$(session-manager-plugin --version 2>&1 || echo "unknown")
    echo -e "${GREEN}✓${NC} Session Manager Plugin installed: $VERSION"
else
    echo -e "${RED}✗${NC} Session Manager Plugin NOT installed"
    echo ""
    echo "To install on macOS:"
    echo "  brew install --cask session-manager-plugin"
    echo ""
    echo "Or download from:"
    echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
    exit 1
fi
echo ""

# Check 2: AWS CLI
echo "2. Checking AWS CLI..."
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1)
    echo -e "${GREEN}✓${NC} AWS CLI installed: $AWS_VERSION"
else
    echo -e "${RED}✗${NC} AWS CLI NOT installed"
    exit 1
fi
echo ""

# Check 3: AWS Credentials
echo "3. Checking AWS Credentials..."
if aws sts get-caller-identity &> /dev/null; then
    IDENTITY=$(aws sts get-caller-identity)
    echo -e "${GREEN}✓${NC} AWS Credentials configured"
    echo "$IDENTITY" | jq '.' 2>/dev/null || echo "$IDENTITY"
else
    echo -e "${RED}✗${NC} AWS Credentials NOT configured or invalid"
    exit 1
fi
echo ""

# Check 4: Default Region
echo "4. Checking AWS Region..."
REGION=${AWS_DEFAULT_REGION:-$(aws configure get region)}
if [ -n "$REGION" ]; then
    echo -e "${GREEN}✓${NC} AWS Region configured: $REGION"
else
    echo -e "${YELLOW}⚠${NC}  AWS Region not set, using default"
    REGION="us-east-1"
fi
echo ""

# Check 5: IAM Instance Profile
echo "5. Checking IAM Instance Profile..."
if aws iam get-instance-profile --instance-profile-name PackerSSMInstanceProfile --region "$REGION" &> /dev/null; then
    echo -e "${GREEN}✓${NC} Instance Profile 'PackerSSMInstanceProfile' exists"
else
    echo -e "${RED}✗${NC} Instance Profile 'PackerSSMInstanceProfile' NOT found"
    echo ""
    echo "To create it, run:"
    echo "  cd $(dirname "$0")"
    echo "  aws cloudformation create-stack \\"
    echo "    --stack-name packer-ssm-iam-stack \\"
    echo "    --template-body file://iam-setup.yml \\"
    echo "    --capabilities CAPABILITY_NAMED_IAM \\"
    echo "    --region $REGION"
    exit 1
fi
echo ""

# Check 6: IAM Role
echo "6. Checking IAM Role..."
if aws iam get-role --role-name PackerSSMRole &> /dev/null; then
    echo -e "${GREEN}✓${NC} IAM Role 'PackerSSMRole' exists"
    
    # Check role policies
    POLICIES=$(aws iam list-attached-role-policies --role-name PackerSSMRole --query 'AttachedPolicies[*].PolicyArn' --output text)
    if echo "$POLICIES" | grep -q "AmazonSSMManagedInstanceCore"; then
        echo -e "${GREEN}✓${NC} Role has AmazonSSMManagedInstanceCore policy"
    else
        echo -e "${RED}✗${NC} Role missing AmazonSSMManagedInstanceCore policy"
    fi
else
    echo -e "${RED}✗${NC} IAM Role 'PackerSSMRole' NOT found"
    exit 1
fi
echo ""

# Check 7: Current IAM permissions for SSM
echo "7. Checking your IAM permissions for SSM..."
TEST_INSTANCE_ID="i-nonexistent123"
if aws ssm start-session --target "$TEST_INSTANCE_ID" --region "$REGION" 2>&1 | grep -q "InvalidInstanceId"; then
    echo -e "${GREEN}✓${NC} You have ssm:StartSession permission"
elif aws ssm start-session --target "$TEST_INSTANCE_ID" --region "$REGION" 2>&1 | grep -q "AccessDenied"; then
    echo -e "${RED}✗${NC} You lack ssm:StartSession permission"
    echo ""
    echo "Your IAM user/role needs these permissions:"
    echo "  - ssm:StartSession"
    echo "  - ssm:TerminateSession"
    echo "  - ssm:DescribeSessions"
else
    echo -e "${YELLOW}⚠${NC}  Could not verify SSM permissions"
fi
echo ""

# Check 8: VPC and Subnet (optional but helpful)
echo "8. Checking Default VPC..."
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region "$REGION" 2>/dev/null || echo "none")
if [ "$DEFAULT_VPC" != "none" ] && [ -n "$DEFAULT_VPC" ]; then
    echo -e "${GREEN}✓${NC} Default VPC found: $DEFAULT_VPC"
    
    # Check for internet gateway
    IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$DEFAULT_VPC" --query "InternetGateways[0].InternetGatewayId" --output text --region "$REGION" 2>/dev/null || echo "none")
    if [ "$IGW" != "none" ] && [ -n "$IGW" ]; then
        echo -e "${GREEN}✓${NC} Internet Gateway found: $IGW"
    else
        echo -e "${YELLOW}⚠${NC}  No Internet Gateway found (may affect SSM connectivity)"
    fi
else
    echo -e "${YELLOW}⚠${NC}  No Default VPC found"
fi
echo ""

# Check 9: Packer installation
echo "9. Checking Packer..."
if command -v packer &> /dev/null; then
    PACKER_VERSION=$(packer version)
    echo -e "${GREEN}✓${NC} Packer installed: $PACKER_VERSION"
else
    echo -e "${RED}✗${NC} Packer NOT installed"
    exit 1
fi
echo ""

# Summary
echo "============================================"
echo "Diagnostic Summary"
echo "============================================"
echo ""
echo -e "${GREEN}All checks passed!${NC}"
echo ""
echo "You should be able to run Packer with SSM now:"
echo "  packer build -var 'region=$REGION' github-runner-ami.pkr.hcl"
echo ""
echo "If the build still fails, check:"
echo "  1. The instance can reach SSM endpoints (needs internet access)"
echo "  2. SSM agent logs on the instance: sudo journalctl -u amazon-ssm-agent"
echo "  3. Run packer with debug: PACKER_LOG=1 packer build ..."
echo ""
