/**
 * Azure Load Balancer Module
 * 
 * Creates a Standard Load Balancer with:
 * - Public IP in the public subnet
 * - Backend pool for VM NICs
 * - Health probe for HTTP on port 80
 * - Load balancing rules for HTTP (80) and HTTPS (443)
 * 
 * This allows VMs in private subnets to receive inbound internet traffic
 * while maintaining security through NAT Gateway for outbound connections.
 */

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb" {
  name                = "${var.project_name}-${var.environment}-lb-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
    Project        = var.project_name
    ManagedBy      = "Terraform"
  }
}

# Load Balancer
resource "azurerm_lb" "main" {
  name                = "${var.project_name}-${var.environment}-lb"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = {
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
    Project        = var.project_name
    ManagedBy      = "Terraform"
  }
}

# Backend Address Pool
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "BackendPool"
}

# Health Probe - HTTP on port 80
resource "azurerm_lb_probe" "http" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "http-probe"
  protocol        = "Http"
  port            = 80
  request_path    = "/"
  interval_in_seconds = 15
  number_of_probes    = 2
}

# Load Balancing Rule - HTTP (port 80)
resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "HTTP"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.http.id
  enable_floating_ip             = false
  idle_timeout_in_minutes        = 4
  disable_outbound_snat          = true  # NAT Gateway handles outbound
}

# Load Balancing Rule - HTTPS (port 443)
resource "azurerm_lb_rule" "https" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "HTTPS"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.http.id
  enable_floating_ip             = false
  idle_timeout_in_minutes        = 4
  disable_outbound_snat          = true  # NAT Gateway handles outbound
}
