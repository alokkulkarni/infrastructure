/**
 * Azure Virtual Machine Module
 * 
 * Creates VM with Docker and GitHub Actions runner
 * No SSH access - managed via Azure Serial Console or Run Command
 */

# Public IP for VM (internet access)
resource "azurerm_public_ip" "vm" {
  name                = "${var.project_name}-${var.environment}-vm-pip"
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

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "${var.project_name}-${var.environment}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.private_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = {
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
    Project        = var.project_name
    ManagedBy      = "Terraform"
  }
}

# Associate NIC with NSG
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = var.nsg_id
}

# Get latest Ubuntu image
data "azurerm_platform_image" "ubuntu" {
  location  = var.location
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-jammy"
  sku       = "22_04-lts-gen2"
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  name                = "${var.project_name}-${var.environment}-vm"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username

  # Disable password authentication - no SSH access
  disable_password_authentication = true

  # Generate a key pair but it won't be used for access
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  os_disk {
    name                 = "${var.project_name}-${var.environment}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = data.azurerm_platform_image.ubuntu.publisher
    offer     = data.azurerm_platform_image.ubuntu.offer
    sku       = data.azurerm_platform_image.ubuntu.sku
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    github_runner_token  = var.github_runner_token
    github_repo_url      = var.github_repo_url
    github_runner_name   = var.github_runner_name
    github_runner_labels = join(",", var.github_runner_labels)
  }))

  tags = {
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
    Project        = var.project_name
    ManagedBy      = "Terraform"
  }
}

# Generate SSH key (not used for access, only for Azure requirement)
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in Key Vault (optional backup)
resource "azurerm_key_vault" "main" {
  name                       = "${var.project_name}${var.environment}kv"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = {
    Environment    = var.environment
    EnvironmentTag = var.environment_tag
    Project        = var.project_name
    ManagedBy      = "Terraform"
  }
}

# Key Vault access policy for Terraform
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge"
  ]
}

# Store SSH private key in Key Vault
resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "${var.project_name}-${var.environment}-ssh-key"
  value        = tls_private_key.ssh.private_key_pem
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

data "azurerm_client_config" "current" {}
