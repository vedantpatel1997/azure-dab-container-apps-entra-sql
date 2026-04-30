resource "azurerm_key_vault" "kv" {
  name                          = local.key_vault_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  public_network_access_enabled = true
}

resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = var.tenant_id
  object_id    = local.terraform_principal_object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Purge"]
}

resource "azurerm_key_vault_access_policy" "developers" {
  for_each = local.key_vault_developer_object_ids

  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = var.tenant_id
  object_id    = each.value

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_access_policy" "uami" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.aca.principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_secret" "sql_connection_string_local" {
  name         = "sql-connection-string-local"
  value        = local.sql_connection_string_local
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

resource "azurerm_key_vault_secret" "sql_connection_string_obo" {
  name         = "sql-connection-string"
  value        = local.sql_connection_string_obo
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

resource "azurerm_key_vault_secret" "sql_connection_string_cloud" {
  name         = "sql-connection-string-cloud"
  value        = local.sql_connection_string_cloud
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

resource "azurerm_key_vault_secret" "dab_obo_client_secret" {
  name         = "dab-obo-client-secret"
  value        = azuread_application_password.api_obo.value
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

resource "azurerm_key_vault_secret" "sql_connection_string_sql_auth" {
  name         = "sql-connection-string-sql-auth"
  value        = local.sql_connection_string_sql_auth
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.current_user]
}
