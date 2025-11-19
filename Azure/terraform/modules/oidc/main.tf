/**
 * Azure AD OIDC Module for GitHub Actions
 * 
 * Creates Azure AD Application and Service Principal with federated credentials
 * Eliminates the need for client secrets
 */

data "azuread_client_config" "current" {}

# Azure AD Application for GitHub Actions
resource "azuread_application" "github_actions" {
  display_name = "${var.project_name}-${var.environment}-github-actions"
  owners       = [data.azuread_client_config.current.object_id]

  tags = [
    "Environment:${var.environment}",
    "Project:${var.project_name}",
    "ManagedBy:Terraform"
  ]
}

# Federated Identity Credential for GitHub Actions (Main branch)
resource "azuread_application_federated_identity_credential" "github_main" {
  application_id = azuread_application.github_actions.id
  display_name   = "${var.project_name}-${var.environment}-github-main"
  description    = "GitHub Actions OIDC for main branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
}

# Federated Identity Credential for GitHub Actions (Pull Requests)
resource "azuread_application_federated_identity_credential" "github_pr" {
  application_id = azuread_application.github_actions.id
  display_name   = "${var.project_name}-${var.environment}-github-pr"
  description    = "GitHub Actions OIDC for pull requests"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:pull_request"
}

# Federated Identity Credential for GitHub Actions (Environment)
resource "azuread_application_federated_identity_credential" "github_environment" {
  application_id = azuread_application.github_actions.id
  display_name   = "${var.project_name}-${var.environment}-github-env"
  description    = "GitHub Actions OIDC for environment deployments"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:environment:${var.environment}"
}

# Service Principal for the Application
resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
  owners    = [data.azuread_client_config.current.object_id]

  tags = [
    "Environment:${var.environment}",
    "Project:${var.project_name}",
    "ManagedBy:Terraform"
  ]
}

# Role Assignment - Contributor access to subscription
resource "azurerm_role_assignment" "github_actions_contributor" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# Role Assignment - User Access Administrator (for managing role assignments)
resource "azurerm_role_assignment" "github_actions_user_access_admin" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.github_actions.object_id
}
