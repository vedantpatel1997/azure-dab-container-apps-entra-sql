resource "random_password" "sql_admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_uuid" "api_scope" {}

data "azuread_client_config" "current" {}

locals {
  app_name = "${var.name_prefix}-dabdemo"

  resource_group_name = "rg-${local.app_name}"
  acr_name            = replace("acr-${local.app_name}", "-", "")
  key_vault_name      = substr("kv-${local.app_name}", 0, 24)
  sql_server_name     = "sql-${local.app_name}"
  log_analytics_name  = "log-${local.app_name}"
  aca_env_name        = "cae-${local.app_name}"
  container_app_name  = "ca-${local.app_name}"
  uami_name           = "id-${var.name_prefix}-aca-dabdemo"
  api_app_name        = "app-${var.name_prefix}-api-dabdemo"
  sql_group_name      = "grp-${var.name_prefix}-sql-dabdemo"
  api_identifier_uri  = "api://${local.api_app_name}"
  sql_admin_password  = coalesce(var.sql_admin_password, random_password.sql_admin.result)

  sql_connection_string_obo      = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.db.name};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sql_connection_string_local    = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.db.name};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sql_connection_string_cloud    = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.db.name};Authentication=Active Directory Managed Identity;User Id=${azurerm_user_assigned_identity.aca.client_id};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sql_connection_string_sql_auth = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.db.name};User ID=${var.sql_admin_login};Password=${local.sql_admin_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

  terraform_principal_object_id = data.azuread_client_config.current.object_id
  sql_group_member_object_ids   = toset(concat(tolist(var.developer_object_ids), [azurerm_user_assigned_identity.aca.principal_id]))
  key_vault_developer_object_ids = setsubtract(
    var.developer_object_ids,
    toset([local.terraform_principal_object_id])
  )
}
