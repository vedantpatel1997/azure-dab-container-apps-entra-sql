# Validation results

Validation was completed after a full destroy and recreate.

## Terraform

Commands run:

```powershell
cd terraform
terraform destroy -auto-approve
terraform apply -auto-approve
terraform plan -detailed-exitcode
```

Result:

```text
Destroy complete.
Apply complete. Resources: 24 added, 0 changed, 0 destroyed.
No changes. Your infrastructure matches the configuration.
```

Current outputs:

```text
resource_group_name = rg-dabsecure-0xp5me
container_app_name  = ca-dabsecure-0xp5me
container_app_url   = https://ca-dabsecure-0xp5me.grayflower-181e28a2.westus3.azurecontainerapps.io
acr_login_server    = acrdabsecure0xp5me.azurecr.io
key_vault_name      = kv-dabsecure-0xp5me
sql_server_fqdn     = sql-dabsecure-0xp5me.database.windows.net
sql_database_name   = dabdemo
sql_access_group    = grp-dabsecure-sql-access-0xp5me
```

## SQL bootstrap

Command run:

```powershell
.\scripts\Bootstrap-Sql.ps1
```

Result:

```text
Customers=3
Products=4
SalesOrders=3
OrderItems=5
```

## Production DAB

Command run:

```powershell
.\scripts\Deploy-Dab.ps1
.\scripts\Test-Dab.ps1
```

Authenticated result:

```text
Path                  Status Count
/                        200
/api/openapi             200
/api/dbo_Products        200 4
/api/dbo_Customers       200 3
/graphql dbo_Products    200 4
```

Unauthenticated data endpoint result:

```text
/api/dbo_Products = 403
```

## Local DAB

Local DAB was tested with the temporary `Microsoft.DataApiBuilder` `2.0.0-rc` tool and the local config:

```powershell
dab start --config .\dab\dab-config.local.json --no-https-redirect
```

Authenticated local result:

```text
Path                  Status Count
/                        200
/api/openapi             200
/api/dbo_Products        200 4
/api/dbo_Customers       200 3
/graphql dbo_Products    200 4
```

