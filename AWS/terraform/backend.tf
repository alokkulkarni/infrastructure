# Backend configuration for storing Terraform state in S3
# Note: S3 bucket and DynamoDB table must be created before initializing
# Run the setup script: scripts/setup-terraform-backend.sh

# Temporarily using local backend for dry run validation
# Uncomment and configure for production use
# terraform {
#   backend "s3" {
#     bucket         = "testcontainers-terraform-state"
#     key            = "aws/ec2-runner/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "testcontainers-terraform-locks"
#
#     # Uncomment these for additional security
#     # kms_key_id = "alias/terraform-state"
#     # acl        = "private"
#   }
# }

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
