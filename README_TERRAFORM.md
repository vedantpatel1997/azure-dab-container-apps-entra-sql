# Terraform guide

Terraform in this repo creates infrastructure only. It does not build the DAB image or deploy app code. SQL bootstrap and DAB deployment run after Terraform in scripts or GitHub Actions.

## File order

The Terraform files are numbered so the dependency story is easy to follow:

```text
00_versions.tf
01_variables.tf
02_names_and_random.tf
03_resource_group.tf
04_managed_identity.tf
05_entra_api_app.tf
06_entra_sql_groups.tf
07_container_registry.tf
08_key_vault.tf
09_sql_server_database.tf
10_container_apps_environment.tf
11_container_app_shell.tf
12_outputs.tf
```

Terraform still builds a dependency graph internally, but this file order shows the human reading order.

## What it creates

Terraform creates:

- A new resource group.
- A user-assigned managed identity, or UAMI.
- An Entra API app registration for DAB JWT validation.
- A delegated `access_as_user` scope for clients.
- Azure CLI preauthorization so local tests can request a token without extra portal clicks.
- Entra SQL admin and SQL access groups.
- ACR with `AcrPull` granted to the UAMI.
- Key Vault with a `sql-connection-string` secret.
- Azure SQL server and database.
- Azure Container Apps environment and a placeholder Container App shell.

The Container App has `lifecycle.ignore_changes` for the app template because image deployment is handled by CI/CD or local deployment commands.

## Important files

```text
05_entra_api_app.tf       Creates the API app registration and token scope.
06_entra_sql_groups.tf    Creates SQL admin/access groups and adds your user plus the UAMI.
08_key_vault.tf           Stores the managed identity SQL connection string.
09_sql_server_database.tf Creates Azure SQL and firewall rules.
11_container_app_shell.tf Creates the Container App shell and ignores image drift.
```

## Run

```powershell
cd terraform
terraform init
terraform validate
terraform apply
```

For GitHub Actions, Terraform uses an Azure Storage remote backend. Bootstrap it with:

```powershell
.\scripts\Bootstrap-GitHubActions.ps1
```

For local use against that same backend:

```powershell
cd terraform
terraform init `
  -backend-config="use_azuread_auth=true" `
  -backend-config="tenant_id=be945e7a-2e17-4b44-926f-512e85873eec" `
  -backend-config="subscription_id=6a3bb170-5159-4bff-860b-aa74fb762697" `
  -backend-config="resource_group_name=rg-dabsecure-tfstate" `
  -backend-config="storage_account_name=stdabsecuretf797847" `
  -backend-config="container_name=tfstate" `
  -backend-config="key=dabsecure.tfstate"
```

Useful outputs:

```powershell
terraform output
terraform output -raw api_scope
terraform output -raw acr_login_server
terraform output -raw container_app_name
terraform output -raw key_vault_uri
```

## Destroy and recreate

```powershell
cd terraform
terraform destroy
terraform apply
```

After a fresh apply, render the DAB config again because the random suffix and generated app registration values may change:

```powershell
cd ..
.\scripts\Render-DabConfig.ps1
```
