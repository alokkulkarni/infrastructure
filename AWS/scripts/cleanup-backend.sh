#!/bin/bash
# Script to destroy the Terraform backend resources
# WARNING: This will delete the S3 bucket and DynamoDB table used for state management

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="${TERRAFORM_STATE_BUCKET:-testcontainers-terraform-state}"
DYNAMODB_TABLE="${TERRAFORM_LOCK_TABLE:-testcontainers-terraform-locks}"

echo "======================================"
echo "Terraform Backend Cleanup"
echo "======================================"
echo "WARNING: This will delete:"
echo "- S3 Bucket: $BUCKET_NAME"
echo "- DynamoDB Table: $DYNAMODB_TABLE"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Delete S3 bucket contents and bucket
echo "Deleting S3 bucket: $BUCKET_NAME"
if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
    echo "Removing all objects from bucket..."
    aws s3 rm "s3://$BUCKET_NAME" --recursive --region "$AWS_REGION"
    
    echo "Removing all versions from bucket..."
    aws s3api delete-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION"
    
    echo "S3 bucket deleted."
else
    echo "S3 bucket does not exist."
fi

# Delete DynamoDB table
echo "Deleting DynamoDB table: $DYNAMODB_TABLE"
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &> /dev/null; then
    aws dynamodb delete-table \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION"
    
    echo "DynamoDB table deleted."
else
    echo "DynamoDB table does not exist."
fi

echo ""
echo "Backend cleanup completed."
