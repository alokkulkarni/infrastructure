#!/bin/bash
# Script to fix Terraform state checksum mismatch
# This happens when state file in S3 is corrupted or out of sync with DynamoDB

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-testcontainers}"

echo "======================================"
echo "Terraform State Checksum Fix"
echo "======================================"
echo "Environment: $ENVIRONMENT"
echo "Region: $AWS_REGION"
echo ""

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
STATE_KEY="aws/ec2-runner/${ENVIRONMENT}/terraform.tfstate"
DYNAMODB_TABLE="${PROJECT_NAME}-terraform-locks"

echo "Bucket: $BUCKET_NAME"
echo "State Key: $STATE_KEY"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo ""

# Check if state file exists in S3
echo "Checking state file in S3..."
if aws s3api head-object --bucket "$BUCKET_NAME" --key "$STATE_KEY" --region "$AWS_REGION" &>/dev/null; then
    # Get the size of the state file
    STATE_SIZE=$(aws s3api head-object --bucket "$BUCKET_NAME" --key "$STATE_KEY" --region "$AWS_REGION" --query ContentLength --output text)
    echo "✓ State file exists (Size: $STATE_SIZE bytes)"
    
    if [ "$STATE_SIZE" -eq 0 ]; then
        echo "⚠ WARNING: State file is empty (0 bytes)"
        echo ""
        echo "This usually happens when:"
        echo "  1. Terraform backend was configured but no resources were created yet"
        echo "  2. A previous operation was interrupted"
        echo "  3. State file was accidentally deleted/corrupted"
        echo ""
        
        # Check DynamoDB for the digest entry
        echo "Checking DynamoDB for stale digest entry..."
        DIGEST_KEY="${BUCKET_NAME}/${STATE_KEY}-md5"
        
        if aws dynamodb get-item \
            --table-name "$DYNAMODB_TABLE" \
            --key "{\"LockID\": {\"S\": \"$DIGEST_KEY\"}}" \
            --region "$AWS_REGION" \
            --query "Item" \
            --output text &>/dev/null; then
            
            echo "⚠ Found stale digest entry in DynamoDB"
            echo ""
            echo "Options to fix this:"
            echo "  1. Delete the empty state file and start fresh"
            echo "  2. Delete the digest entry from DynamoDB"
            echo ""
            echo "Attempting to delete the digest entry from DynamoDB..."
            
            aws dynamodb delete-item \
                --table-name "$DYNAMODB_TABLE" \
                --key "{\"LockID\": {\"S\": \"$DIGEST_KEY\"}}" \
                --region "$AWS_REGION"
            
            echo "✓ Deleted stale digest entry from DynamoDB"
            echo ""
            echo "Now deleting the empty state file from S3..."
            aws s3 rm "s3://${BUCKET_NAME}/${STATE_KEY}" --region "$AWS_REGION"
            echo "✓ Deleted empty state file from S3"
            echo ""
            echo "State has been cleaned up. Terraform will create a fresh state file."
        else
            echo "✓ No digest entry found in DynamoDB"
            echo "Deleting the empty state file from S3..."
            aws s3 rm "s3://${BUCKET_NAME}/${STATE_KEY}" --region "$AWS_REGION"
            echo "✓ Deleted empty state file from S3"
        fi
    else
        echo "✓ State file has content, checking digest entry..."
        
        # Check if there's a digest mismatch
        DIGEST_KEY="${BUCKET_NAME}/${STATE_KEY}-md5"
        
        if DIGEST_ITEM=$(aws dynamodb get-item \
            --table-name "$DYNAMODB_TABLE" \
            --key "{\"LockID\": {\"S\": \"$DIGEST_KEY\"}}" \
            --region "$AWS_REGION" \
            --query "Item.Digest.S" \
            --output text 2>/dev/null); then
            
            if [ "$DIGEST_ITEM" != "None" ] && [ -n "$DIGEST_ITEM" ]; then
                echo "Found digest in DynamoDB: $DIGEST_ITEM"
                
                # Calculate actual checksum of S3 file
                ACTUAL_MD5=$(aws s3api head-object \
                    --bucket "$BUCKET_NAME" \
                    --key "$STATE_KEY" \
                    --region "$AWS_REGION" \
                    --query ETag \
                    --output text | tr -d '"')
                
                echo "Actual S3 ETag: $ACTUAL_MD5"
                
                if [ "$DIGEST_ITEM" != "$ACTUAL_MD5" ]; then
                    echo "⚠ Checksum mismatch detected!"
                    echo "Stored in DynamoDB: $DIGEST_ITEM"
                    echo "Actual in S3: $ACTUAL_MD5"
                    echo ""
                    echo "Deleting stale digest entry..."
                    
                    aws dynamodb delete-item \
                        --table-name "$DYNAMODB_TABLE" \
                        --key "{\"LockID\": {\"S\": \"$DIGEST_KEY\"}}" \
                        --region "$AWS_REGION"
                    
                    echo "✓ Deleted stale digest entry"
                    echo "Terraform will recalculate the checksum on next run"
                else
                    echo "✓ Checksums match, state is healthy"
                fi
            else
                echo "✓ No digest entry found (this is normal)"
            fi
        fi
    fi
else
    echo "✓ No state file exists yet (fresh deployment)"
    
    # Clean up any stale digest entries
    DIGEST_KEY="${BUCKET_NAME}/${STATE_KEY}-md5"
    echo "Checking for stale digest entries..."
    
    if aws dynamodb get-item \
        --table-name "$DYNAMODB_TABLE" \
        --key "{\"LockID\": {\"S\": \"$DIGEST_KEY\"}}" \
        --region "$AWS_REGION" \
        --query "Item" \
        --output text &>/dev/null; then
        
        echo "⚠ Found stale digest entry (no state file exists)"
        echo "Deleting stale digest entry..."
        
        aws dynamodb delete-item \
            --table-name "$DYNAMODB_TABLE" \
            --key "{\"LockID\": {\"S\": \"$DIGEST_KEY\"}}" \
            --region "$AWS_REGION"
        
        echo "✓ Deleted stale digest entry"
    else
        echo "✓ No stale digest entries found"
    fi
fi

echo ""
echo "======================================"
echo "State checksum check completed"
echo "======================================"
echo ""
echo "You can now run terraform init/plan/apply"
