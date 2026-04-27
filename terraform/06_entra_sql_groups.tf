resource "azuread_group" "sql_admins" {
  display_name     = local.sql_admin_group_name
  security_enabled = true
  owners           = [local.terraform_principal_object_id]
  members          = local.sql_admin_member_object_ids
}

resource "azuread_group" "sql_access" {
  display_name     = local.sql_access_group_name
  security_enabled = true
  owners           = [local.terraform_principal_object_id]
  members          = local.sql_access_member_object_ids
}
