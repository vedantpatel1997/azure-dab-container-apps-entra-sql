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

output "api_client_id" {
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

output "sql_group" {
  value = azuread_group.sql.display_name
}

output "key_vault_secret_local_connection_string" {
  value = azurerm_key_vault_secret.sql_connection_string_local.name
}

output "key_vault_secret_cloud_connection_string" {
  value = azurerm_key_vault_secret.sql_connection_string_cloud.name
}

output "key_vault_secret_obo_connection_string" {
  value = azurerm_key_vault_secret.sql_connection_string_obo.name
}

output "key_vault_secret_dab_obo_client_secret" {
  value = azurerm_key_vault_secret.dab_obo_client_secret.name
}

output "key_vault_secret_sql_auth_connection_string" {
  value = azurerm_key_vault_secret.sql_connection_string_sql_auth.name
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
