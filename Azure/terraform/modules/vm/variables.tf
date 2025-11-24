variable "project_name" {
  description = "Name of the project"
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

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID for the VM"
  type        = string
}

variable "nsg_id" {
  description = "ID of the Network Security Group"
  type        = string
}

variable "vm_size" {
  description = "Size of the VM"
  type        = string
}

variable "admin_username" {
  description = "Admin username for VM"
  type        = string
}

variable "github_pat" {
  description = "GitHub Personal Access Token for runner registration"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repository URL"
  type        = string
}

variable "github_runner_name" {
  description = "Name for the GitHub runner"
  type        = string
}

variable "github_runner_labels" {
  description = "Labels for the GitHub runner"
  type        = list(string)
}
