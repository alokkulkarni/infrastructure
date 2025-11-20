#!/bin/bash
# Script to check for existing GitHub OIDC provider and IAM role
# These resources are managed manually and NOT by Terraform
# This script only verifies they exist, it does NOT import them

set -e

OIDC_URL="token.actions.githubusercontent.com"

echo "=========================================="
echo "Verifying OIDC resources (read-only check)"
echo "=========================================="
echo ""
echo "NOTE: OIDC provider and GitHub Actions role are managed manually."
echo "      Terraform will NOT create, modify, or import these resources."
echo "      This script only verifies they exist for the workflows to use."
echo ""

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_URL}"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "Expected OIDC ARN: $OIDC_ARN"
echo ""

# Check if OIDC provider exists in AWS
echo "Checking if OIDC provider exists in AWS..."
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &>/dev/null; then
    echo "✓ OIDC provider exists in AWS (managed manually)"
else
    echo "❌ ERROR: OIDC provider does not exist in AWS!"
    echo "   Please create it manually using the OIDC_GUIDE.md"
    exit 1
fi

echo ""
echo "====================================="
echo "Checking for existing IAM role"
echo "====================================="

# Get environment from environment variable or use dev as default
ENVIRONMENT="${ENVIRONMENT:-dev}"
ROLE_NAME="testcontainers-${ENVIRONMENT}-github-actions-role"

echo "Environment: $ENVIRONMENT"
echo "Expected IAM Role: $ROLE_NAME"
echo ""

# Check if IAM role exists in AWS
echo "Checking if IAM role exists in AWS..."
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo "✓ IAM role exists in AWS (managed manually)"
    
    # Check trust policy
    echo ""
    echo "Verifying trust policy allows GitHub Actions..."
    TRUST_POLICY=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json)
    if echo "$TRUST_POLICY" | grep -q "token.actions.githubusercontent.com"; then
        echo "✓ Trust policy includes GitHub OIDC provider"
    else
        echo "⚠️  WARNING: Trust policy may not be configured for GitHub OIDC"
    fi
else
    echo "❌ ERROR: IAM role does not exist in AWS!"
    echo "   Please create it manually using the OIDC_GUIDE.md"
    exit 1
fi

echo ""
echo "=========================================="
echo "✓ All OIDC resources verified successfully"
echo "=========================================="
echo ""
echo "Terraform will use data sources to reference these resources."
echo "No imports or modifications will be performed."
echo ""

