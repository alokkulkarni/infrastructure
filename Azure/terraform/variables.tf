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

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "public_subnet_address_prefix" {
  description = "Address prefix for the public subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_address_prefix" {
  description = "Address prefix for the private subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Admin username for VM (SSH disabled, only for Azure requirement)"
  type        = string
  default     = "azureuser"
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
  default     = "azure-vm-runner"
}

variable "github_runner_labels" {
  description = "Labels for the GitHub Actions runner"
  type        = list(string)
  default     = ["self-hosted", "azure", "linux"]
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org/username)"
  type        = string
}
