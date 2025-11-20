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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}
