output "application_id" {
  description = "Application (client) ID - add to GitHub secrets as AZURE_CLIENT_ID"
  value       = azuread_application.github_actions.client_id
}

output "service_principal_id" {
  description = "Service Principal Object ID"
  value       = azuread_service_principal.github_actions.object_id
}

output "application_object_id" {
  description = "Application Object ID"
  value       = azuread_application.github_actions.object_id
}
