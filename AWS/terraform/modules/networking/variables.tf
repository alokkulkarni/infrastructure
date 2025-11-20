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

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for private subnet"
  type        = string
}

variable "availability_zone_2" {
  description = "Second availability zone for public subnet (ALB requirement)"
  type        = string
  default     = ""
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for second public subnet (ALB requirement)"
  type        = string
  default     = ""
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
}
