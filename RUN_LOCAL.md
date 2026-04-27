# Run Locally

Local DAB uses the same Azure SQL database as production.

## 1. Sign In

```powershell
az login --tenant be945e7a-2e17-4b44-926f-512e85873eec
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
```

## 2. Confirm The Database Exists

Terraform creates:

```text
SQL server: sql-vkp-vmerdr.database.windows.net
SQL database: vkp-dabdemo
```

Before DAB can work, create your tables in SSMS and grant access as described in [RUN_CLOUD.md](RUN_CLOUD.md).

## 3. Check DAB Auth Values

The local config is committed at:

```text
dab/dab-config.local.json
```

It already contains:

```text
audience: 6d37871a-7694-47d2-9423-c1f2f77ac353
issuer: https://login.microsoftonline.com/be945e7a-2e17-4b44-926f-512e85873eec/v2.0
```

If you recreate Terraform and the API app changes, update the audience in both:

```text
dab/dab-config.json
dab/dab-config.local.json
```

Get the new value with:

```powershell
terraform -chdir=terraform output -raw api_audience
```

## 4. Start DAB Locally

From the repo root:

```powershell
$env:AZURE_TENANT_ID = "be945e7a-2e17-4b44-926f-512e85873eec"
$env:AZURE_TOKEN_CREDENTIALS = "AzureCliCredential"

dotnet tool restore
dotnet tool run dab -- start --config .\dab\dab-config.local.json --no-https-redirect
```

Leave that terminal running.

Local DAB reads the SQL connection string from the same Key Vault secret production uses:

```text
Key Vault: kv-vkp-vmerdr
Secret: sql-connection-string
```

## 5. Test Local Endpoints

Open a second PowerShell terminal:

```powershell
$scope = "api://app-vkp-api-vmerdr/access_as_user"
$token = az account get-access-token --scope $scope --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

Invoke-WebRequest "http://localhost:5000/" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/openapi" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/dbo_Products" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/dbo_Customers" -Headers $headers -UseBasicParsing
```

GraphQL:

```powershell
$body = @{ query = "{ dbo_Products { items { ProductId Sku Name Category UnitPrice } } }" } | ConvertTo-Json -Compress

Invoke-RestMethod `
  -Uri "http://localhost:5000/graphql" `
  -Method POST `
  -ContentType "application/json" `
  -Headers $headers `
  -Body $body
```

Anonymous table access should fail:

```powershell
Invoke-WebRequest "http://localhost:5000/api/dbo_Products" -UseBasicParsing
```

Expected status: `403`.
