output "vnet_id" {
  description = "Virtual network ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual network name"
  value       = azurerm_virtual_network.main.name
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = azurerm_subnet.public.id
}

output "public_subnet_name" {
  description = "Public subnet name"
  value       = azurerm_subnet.public.name
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = azurerm_subnet.private.id
}

output "private_subnet_name" {
  description = "Private subnet name"
  value       = azurerm_subnet.private.name
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = azurerm_nat_gateway.main.id
}

output "nat_public_ip" {
  description = "NAT Gateway public IP address"
  value       = azurerm_public_ip.nat.ip_address
}
