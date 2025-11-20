variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "testcontainers"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
  description = "Availability zone for resources"
  type        = string
  default     = "us-east-1a"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance (Ubuntu 22.04 LTS)"
  type        = string
  default     = "" # Will be looked up dynamically in ec2 module
}

variable "github_runner_token" {
  description = "GitHub runner registration token (generated dynamically)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_repo_url" {
  description = "GitHub repository URL for runner registration"
  type        = string
}

variable "github_runner_name" {
  description = "Name for the GitHub Actions runner"
  type        = string
  default     = "aws-ec2-runner"
}

variable "github_runner_labels" {
  description = "Labels for the GitHub Actions runner"
  type        = list(string)
  default     = ["self-hosted", "aws", "linux"]
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org/username)"
  type        = string
}

variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state - used ONLY for OIDC IAM role permissions. Value is derived automatically in workflows using: {project_name}-terraform-state-{aws_account_id}"
  type        = string
}

variable "terraform_lock_table" {
  description = "DynamoDB table name for Terraform state locking - used ONLY for OIDC IAM role permissions. Value is derived automatically in workflows using: {project_name}-terraform-locks"
  type        = string
}
