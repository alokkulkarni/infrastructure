#!/bin/bash
# Script to import existing GitHub OIDC provider and IAM role into Terraform state
# This prevents "EntityAlreadyExists" errors when resources were created manually

set -e

OIDC_URL="token.actions.githubusercontent.com"

echo "=========================================="
echo "Checking for existing OIDC resources"
echo "=========================================="

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
echo "====================================="
echo "Checking for existing IAM role"
echo "====================================="

# Get environment from terraform.tfvars or use dev as default
if [ -f "terraform.tfvars" ]; then
    ENVIRONMENT=$(grep -E '^environment[[:space:]]*=' terraform.tfvars | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' || echo "dev")
else
    ENVIRONMENT="dev"
fi

ROLE_NAME="testcontainers-${ENVIRONMENT}-github-actions-role"

echo "Environment: $ENVIRONMENT"
echo "Expected IAM Role: $ROLE_NAME"
echo ""

# Check if IAM role exists in AWS
echo "Checking if IAM role exists in AWS..."
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo "✓ IAM role exists in AWS"
    
    # Check if it's already in Terraform state
    echo "Checking Terraform state..."
    if terraform state list 2>/dev/null | grep -q "module.iam_oidc.aws_iam_role.github_actions"; then
        echo "✓ IAM role already in Terraform state"
    else
        echo "⚠ IAM role exists in AWS but not in Terraform state"
        echo "Importing IAM role into Terraform state..."
        
        # Import the existing IAM role
        terraform import "module.iam_oidc.aws_iam_role.github_actions" "$ROLE_NAME"
        
        echo "✓ IAM role imported successfully"
    fi
else
    echo "✓ IAM role does not exist in AWS (will be created by Terraform)"
fi

echo ""
echo "=========================================="
echo "OIDC resources check completed"
echo "=========================================="
