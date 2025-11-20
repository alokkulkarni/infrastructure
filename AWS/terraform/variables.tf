variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
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

variable "environment_tag" {
  description = "Environment tag for resource isolation (Format: SIT-USERID-TEAMID-YYYYMMDD-HHMM). Used to isolate resources for different teams/testers and manage separate state files."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
  description = "Availability zone for private subnet"
  type        = string
  default     = "eu-west-2a"
}

variable "availability_zone_2" {
  description = "Second availability zone for public subnet (ALB requires 2 AZs)"
  type        = string
  default     = "eu-west-2b"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet 1"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for public subnet 2 (for ALB)"
  type        = string
  default     = "10.0.3.0/24"
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
  description = "Custom AMI ID for EC2 instance (leave empty to use latest Ubuntu 22.04 LTS). Use this when you have a pre-built AMI with all packages installed."
  type        = string
  default     = "" # Will be looked up dynamically in ec2 module if empty
}

variable "use_custom_ami" {
  description = "Whether to use pre-built custom AMI with packages pre-installed (true) or standard Ubuntu AMI (false). When true, uses lightweight user-data script."
  type        = bool
  default     = false
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
