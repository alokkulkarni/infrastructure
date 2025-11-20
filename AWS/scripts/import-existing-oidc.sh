#!/bin/bash
# Script to import existing GitHub OIDC provider into Terraform state
# This prevents "EntityAlreadyExists" errors when the OIDC provider was created manually

set -e

OIDC_URL="token.actions.githubusercontent.com"

echo "======================================"
echo "Checking for existing OIDC provider"
echo "======================================"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_URL}"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "Expected OIDC ARN: $OIDC_ARN"
echo ""

# Check if OIDC provider exists in AWS
echo "Checking if OIDC provider exists in AWS..."
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &>/dev/null; then
    echo "✓ OIDC provider exists in AWS"
    
    # Check if it's already in Terraform state
    echo "Checking Terraform state..."
    if terraform state list 2>/dev/null | grep -q "module.iam_oidc.aws_iam_openid_connect_provider.github"; then
        echo "✓ OIDC provider already in Terraform state"
    else
        echo "⚠ OIDC provider exists in AWS but not in Terraform state"
        echo "Importing OIDC provider into Terraform state..."
        
        # Import the existing OIDC provider
        terraform import "module.iam_oidc.aws_iam_openid_connect_provider.github" "$OIDC_ARN"
        
        echo "✓ OIDC provider imported successfully"
    fi
else
    echo "✓ OIDC provider does not exist in AWS (will be created by Terraform)"
fi

echo ""
echo "======================================"
echo "OIDC provider check completed"
echo "======================================"
