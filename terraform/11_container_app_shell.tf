resource "azurerm_container_app" "dab" {
  name                         = local.container_app_name
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.aca.id
  }

  secret {
    name  = "dab-obo-client-secret"
    value = azuread_application_password.api_obo.value
  }

  ingress {
    external_enabled = true
    target_port      = 5000
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3

    container {
      name   = "dab"
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.aca.client_id
      }

      env {
        name  = "DAB_OBO_CLIENT_ID"
        value = azuread_application.api.client_id
      }

      env {
        name  = "DAB_OBO_TENANT_ID"
        value = var.tenant_id
      }

      env {
        name        = "DAB_OBO_CLIENT_SECRET"
        secret_name = "dab-obo-client-secret"
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_key_vault_access_policy.uami,
    azurerm_key_vault_secret.sql_connection_string_obo,
    azurerm_key_vault_secret.dab_obo_client_secret
  ]

  lifecycle {
    ignore_changes = [
      template,
      ingress[0].target_port
    ]
  }
}
