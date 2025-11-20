#!/bin/bash

# Import existing EC2 IAM role if it exists
# This prevents the "EntityAlreadyExists" error during terraform apply

set -e

echo "🔍 Checking for existing EC2 IAM role..."

# Get project name and environment from terraform variables
PROJECT_NAME="${PROJECT_NAME:-testcontainers}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-ec2-role"

echo "Looking for role: $ROLE_NAME"

# Check if role exists in AWS
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "✅ Role exists in AWS: $ROLE_NAME"
    
    # Check if role is in terraform state
    if terraform state list | grep -q "module.ec2.aws_iam_role.ec2"; then
        echo "✅ Role already in terraform state"
    else
        echo "⚠️  Role exists in AWS but not in terraform state - importing..."
        terraform import module.ec2.aws_iam_role.ec2 "$ROLE_NAME" || {
            echo "⚠️  Import failed, but continuing (may already be imported)"
        }
        echo "✅ Import completed"
    fi
    
    # Also check and import instance profile if needed
    PROFILE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-ec2-profile"
    if aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1; then
        echo "✅ Instance profile exists: $PROFILE_NAME"
        if ! terraform state list | grep -q "module.ec2.aws_iam_instance_profile.ec2"; then
            echo "⚠️  Instance profile exists but not in state - importing..."
            terraform import module.ec2.aws_iam_instance_profile.ec2 "$PROFILE_NAME" || {
                echo "⚠️  Import failed, but continuing"
            }
        fi
    fi
else
    echo "ℹ️  Role does not exist - will be created by terraform"
fi

echo "✅ EC2 IAM role check complete"
