output "lb_id" {
  description = "ID of the Load Balancer"
  value       = azurerm_lb.main.id
}

output "lb_public_ip" {
  description = "Public IP address of the Load Balancer"
  value       = azurerm_public_ip.lb.ip_address
}

output "lb_public_ip_fqdn" {
  description = "FQDN of the Load Balancer public IP (if configured)"
  value       = azurerm_public_ip.lb.fqdn
}

output "backend_pool_id" {
  description = "ID of the backend address pool"
  value       = azurerm_lb_backend_address_pool.main.id
}

output "frontend_ip_configuration_name" {
  description = "Name of the frontend IP configuration"
  value       = "PublicIPAddress"
}
