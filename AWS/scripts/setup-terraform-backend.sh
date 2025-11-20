#!/bin/bash
# Script to set up S3 backend for Terraform state management
# This creates the S3 bucket and DynamoDB table for state locking
# The naming convention uses the project name and AWS account ID for uniqueness

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-testcontainers}"

echo "======================================"
echo "Terraform Backend Setup"
echo "======================================"
echo "Project: $PROJECT_NAME"
echo "Region: $AWS_REGION"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured. Please configure AWS CLI."
    exit 1
fi

# Get AWS Account ID for unique bucket naming
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Derive resource names from project and account
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
DYNAMODB_TABLE="${PROJECT_NAME}-terraform-locks"

echo "S3 Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo ""

echo "AWS credentials verified."
echo ""

# Create S3 bucket
echo "Checking S3 bucket: $BUCKET_NAME"
if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
    echo "✓ S3 bucket already exists, reusing existing bucket."
else
    echo "Creating S3 bucket: $BUCKET_NAME"
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        $([ "$AWS_REGION" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=$AWS_REGION")
    
    echo "S3 bucket created successfully."
    
    # Enable versioning
    echo "Enabling versioning on S3 bucket..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION"
    
    # Enable encryption
    echo "Enabling default encryption on S3 bucket..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }' \
        --region "$AWS_REGION"
    
    # Block public access
    echo "Blocking public access to S3 bucket..."
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --region "$AWS_REGION"
    
    # Add bucket policy
    echo "Adding bucket policy..."
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Deny\",
                    \"Principal\": \"*\",
                    \"Action\": \"s3:*\",
                    \"Resource\": [
                        \"arn:aws:s3:::$BUCKET_NAME/*\",
                        \"arn:aws:s3:::$BUCKET_NAME\"
                    ],
                    \"Condition\": {
                        \"Bool\": {
                            \"aws:SecureTransport\": \"false\"
                        }
                    }
                }
            ]
        }" \
        --region "$AWS_REGION"
    
    echo "S3 bucket configuration completed."
fi

echo ""

# Create DynamoDB table for state locking
echo "Checking DynamoDB table: $DYNAMODB_TABLE"
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &> /dev/null; then
    echo "✓ DynamoDB table already exists, reusing existing table."
else
    echo "Creating DynamoDB table: $DYNAMODB_TABLE"
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --tags Key=Purpose,Value=TerraformStateLocking Key=Project,Value=$PROJECT_NAME \
        --region "$AWS_REGION"
    
    echo "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION"
    
    echo "DynamoDB table created successfully."
fi

echo ""
echo "======================================"
echo "Backend setup completed successfully!"
echo "======================================"
echo ""
echo "IMPORTANT: This script is idempotent and reuses existing resources."
echo "- S3 bucket and DynamoDB table are shared across all environments"
echo "- Each environment uses a different state file path (key)"
echo "- No resources are recreated if they already exist"
echo ""
echo "Your backend configuration:"
echo ""
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"$BUCKET_NAME\""
echo "    key            = \"aws/ec2-runner/{environment}/terraform.tfstate\""
echo "    region         = \"$AWS_REGION\""
echo "    encrypt        = true"
echo "    dynamodb_table = \"$DYNAMODB_TABLE\""
echo "  }"
echo "}"
echo ""
echo "Environment variables exported:"
echo "export TF_BACKEND_BUCKET=\"$BUCKET_NAME\""
echo "export TF_BACKEND_DYNAMODB_TABLE=\"$DYNAMODB_TABLE\""
echo ""
echo "You can now initialize Terraform with: terraform init"
