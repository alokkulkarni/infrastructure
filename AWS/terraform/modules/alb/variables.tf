variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "environment_tag" {
  description = "Environment tag for resource identification"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALB will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB (requires at least 2 AZs)"
  type        = list(string)
}

variable "ec2_instance_id" {
  description = "EC2 instance ID to register with target group"
  type        = string
}
