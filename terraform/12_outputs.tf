output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "subscription_id" {
  value = var.subscription_id
}

output "tenant_id" {
  value = var.tenant_id
}

output "container_app_url" {
  value = "https://${azurerm_container_app.dab.ingress[0].fqdn}"
}

output "container_app_name" {
  value = azurerm_container_app.dab.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "api_audience" {
  value = azuread_application.api.client_id
}

output "api_scope" {
  value = "${local.api_identifier_uri}/access_as_user"
}

output "jwt_issuer" {
  value = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.kv.vault_uri
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "sql_database_name" {
  value = azurerm_mssql_database.db.name
}

output "sql_access_group" {
  value = azuread_group.sql_access.display_name
}

output "uami_client_id" {
  value = azurerm_user_assigned_identity.aca.client_id
}

output "uami_name" {
  value = azurerm_user_assigned_identity.aca.name
}

output "uami_resource_id" {
  value = azurerm_user_assigned_identity.aca.id
}
