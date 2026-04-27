data "azuread_service_principal" "azure_cli" {
  client_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
}

resource "azuread_application" "api" {
  display_name     = local.api_app_name
  sign_in_audience = "AzureADMyOrg"
  identifier_uris  = [local.api_identifier_uri]

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Access the DAB API as the signed-in user."
      admin_consent_display_name = "Access DAB API"
      enabled                    = true
      id                         = random_uuid.api_scope.result
      type                       = "User"
      user_consent_description   = "Access the DAB API as you."
      user_consent_display_name  = "Access DAB API"
      value                      = "access_as_user"
    }
  }
}

resource "azuread_service_principal" "api" {
  client_id = azuread_application.api.client_id
}

resource "azuread_service_principal_delegated_permission_grant" "azure_cli_to_api" {
  service_principal_object_id          = data.azuread_service_principal.azure_cli.object_id
  resource_service_principal_object_id = azuread_service_principal.api.object_id
  claim_values                         = ["access_as_user"]
}

resource "null_resource" "azure_cli_pre_authorize" {
  triggers = {
    application_object_id = azuread_application.api.object_id
    azure_cli_app_id      = data.azuread_service_principal.azure_cli.client_id
    scope_id              = random_uuid.api_scope.result
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = "Stop"
      $bodyPath = Join-Path $env:TEMP "dab-preauth-${random_uuid.api_scope.result}.json"
      $payload = @{
        api = @{
          preAuthorizedApplications = @(
            @{
              appId = "${data.azuread_service_principal.azure_cli.client_id}"
              delegatedPermissionIds = @("${random_uuid.api_scope.result}")
            }
          )
        }
      } | ConvertTo-Json -Depth 10 -Compress
      Set-Content -Path $bodyPath -Value $payload -Encoding ascii
      az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/${azuread_application.api.object_id}" --headers "Content-Type=application/json" --body "@$bodyPath"
    EOT
  }
}
