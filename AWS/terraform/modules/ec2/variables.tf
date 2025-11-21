variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "environment_tag" {
  description = "Environment tag for resource isolation"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for EC2 instance (if empty, uses latest Ubuntu 22.04)"
  type        = string
  default     = ""
}

variable "use_custom_ami" {
  description = "Whether to use pre-built custom AMI (true) or standard Ubuntu AMI (false)"
  type        = bool
  default     = false
}

variable "subnet_id" {
  description = "Subnet ID for EC2 instance"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "github_runner_token" {
  description = "GitHub runner registration token"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repository URL"
  type        = string
}

variable "github_runner_name" {
  description = "Name for the GitHub Actions runner"
  type        = string
}

variable "github_runner_labels" {
  description = "Labels for the GitHub Actions runner"
  type        = list(string)
}

variable "github_pat" {
  description = "GitHub Personal Access Token for runner token generation via gh CLI"
  type        = string
  sensitive   = true
  default     = ""
}
