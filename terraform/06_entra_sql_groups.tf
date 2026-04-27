resource "azuread_group" "sql" {
  display_name     = local.sql_group_name
  security_enabled = true
  owners           = [local.terraform_principal_object_id]
  members          = local.sql_group_member_object_ids
}
