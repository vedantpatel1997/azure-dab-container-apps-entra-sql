resource "azurerm_user_assigned_identity" "aca" {
  name                = local.uami_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}
