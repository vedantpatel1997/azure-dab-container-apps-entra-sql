resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "random_password" "sql_admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_uuid" "api_scope" {}

data "azuread_client_config" "current" {}

locals {
  suffix = random_string.suffix.result

  resource_group_name   = "rg-${var.name_prefix}-${local.suffix}"
  acr_name              = replace("acr${var.name_prefix}${local.suffix}", "-", "")
  key_vault_name        = substr("kv-${var.name_prefix}-${local.suffix}", 0, 24)
  sql_server_name       = "sql-${var.name_prefix}-${local.suffix}"
  log_analytics_name    = "log-${var.name_prefix}-${local.suffix}"
  aca_env_name          = "cae-${var.name_prefix}-${local.suffix}"
  container_app_name    = "ca-${var.name_prefix}-${local.suffix}"
  uami_name             = "id-${var.name_prefix}-aca-${local.suffix}"
  api_app_name          = "app-${var.name_prefix}-api-${local.suffix}"
  sql_admin_group_name  = "grp-${var.name_prefix}-sql-admins-${local.suffix}"
  sql_access_group_name = "grp-${var.name_prefix}-sql-access-${local.suffix}"
  api_identifier_uri    = "api://${local.api_app_name}"
  sql_admin_password    = coalesce(var.sql_admin_password, random_password.sql_admin.result)

  sql_connection_string = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.db.name};User ID=${var.sql_admin_login};Password=${local.sql_admin_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

  terraform_principal_object_id = data.azuread_client_config.current.object_id
  sql_admin_member_object_ids   = toset(concat([local.terraform_principal_object_id], tolist(var.developer_object_ids)))
  sql_access_member_object_ids  = toset(concat([local.terraform_principal_object_id, azurerm_user_assigned_identity.aca.principal_id], tolist(var.developer_object_ids)))
  key_vault_developer_object_ids = setsubtract(
    var.developer_object_ids,
    toset([local.terraform_principal_object_id])
  )
}
