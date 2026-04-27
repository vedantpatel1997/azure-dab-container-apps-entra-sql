resource "azuread_group" "sql_admins" {
  display_name     = local.sql_admin_group_name
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
  members          = [data.azuread_client_config.current.object_id]
}

resource "azuread_group" "sql_access" {
  display_name     = local.sql_access_group_name
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
  members = [
    data.azuread_client_config.current.object_id,
    azurerm_user_assigned_identity.aca.principal_id
  ]
}
