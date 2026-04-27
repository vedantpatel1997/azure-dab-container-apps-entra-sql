# Local testing

Local testing uses your Entra account for both the API token and SQL database connection.

## Prerequisites

```powershell
az login --tenant MngEnvMCAP797847.onmicrosoft.com
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
```

Render config after Terraform apply:

```powershell
.\scripts\Render-DabConfig.ps1
```

Set the local SQL connection string:

```powershell
$SQL_SERVER = terraform -chdir=terraform output -raw sql_server_fqdn
$SQL_DB = terraform -chdir=terraform output -raw sql_database_name
$env:DATABASE_CONNECTION_STRING = "Server=tcp:$SQL_SERVER,1433;Database=$SQL_DB;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

## Run DAB locally

DAB 2.0 RC is required because this project uses `autoentities`.

If your global `dab` CLI is older, install the 2.0 RC tool into a temporary folder:

```powershell
$tool = Join-Path $env:TEMP "dab-tool-2rc"
dotnet tool install Microsoft.DataApiBuilder --tool-path $tool --version 2.0.0-rc
& "$tool\dab.exe" --version
```

Then run:

```powershell
& "$tool\dab.exe" start --config .\dab\dab-config.local.json --no-https-redirect
```

If local CLI is still DAB 1.7, run the 2.0 RC container after Docker Desktop is started:

```powershell
docker run --rm -it `
  -p 5000:5000 `
  -v "${PWD}\dab:/App/config" `
  -e DATABASE_CONNECTION_STRING="$env:DATABASE_CONNECTION_STRING" `
  mcr.microsoft.com/azure-databases/data-api-builder:2.0.0-rc `
  --ConfigFileName "/App/config/dab-config.local.json"
```

## Test

```powershell
$SCOPE = terraform -chdir=terraform output -raw api_scope
$TOKEN = az account get-access-token --scope $SCOPE --query accessToken -o tsv
$HEADERS = @{ Authorization = "Bearer $TOKEN" }

Invoke-RestMethod "http://localhost:5000/" -Headers $HEADERS
Invoke-RestMethod "http://localhost:5000/api/dbo_Products" -Headers $HEADERS
Invoke-RestMethod "http://localhost:5000/api/dbo_Customers" -Headers $HEADERS
Invoke-RestMethod "http://localhost:5000/api/openapi" -Headers $HEADERS
```

GraphQL:

```powershell
$body = @{ query = "{ dbo_Products { items { ProductId Sku Name Category UnitPrice } } }" } | ConvertTo-Json

Invoke-RestMethod `
  -Uri "http://localhost:5000/graphql" `
  -Method POST `
  -ContentType "application/json" `
  -Headers $HEADERS `
  -Body $body
```
