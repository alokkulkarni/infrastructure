output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "vnet_id" {
  description = "Virtual network ID"
  value       = module.networking.vnet_id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = module.networking.public_subnet_id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = module.networking.private_subnet_id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway public IP address"
  value       = module.networking.nat_public_ip
}

output "vm_id" {
  description = "Virtual machine ID"
  value       = module.vm.vm_id
}

output "vm_private_ip" {
  description = "Private IP address of the VM"
  value       = module.vm.vm_private_ip
}

output "vm_public_ip" {
  description = "Public IP address of the VM (for accessing applications)"
  value       = module.vm.vm_public_ip
}

output "nginx_url" {
  description = "URL to access the Nginx reverse proxy server"
  value       = "http://${module.vm.vm_public_ip}"
}

output "nginx_health_check" {
  description = "URL for Nginx health check endpoint"
  value       = "http://${module.vm.vm_public_ip}/health"
}

output "nsg_id" {
  description = "ID of the Network Security Group"
  value       = module.security.nsg_id
}

output "github_actions_app_id" {
  description = "Application (client) ID for GitHub Actions (use this in workflow)"
  value       = module.oidc.application_id
}

output "github_actions_service_principal_id" {
  description = "Service Principal Object ID"
  value       = module.oidc.service_principal_id
}

output "subscription_id" {
  description = "Azure Subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Azure Tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}
