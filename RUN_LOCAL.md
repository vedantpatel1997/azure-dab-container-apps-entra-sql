# Run Locally

Local DAB uses the same Azure SQL database as production. With OBO enabled, DAB validates your API token and then connects to Azure SQL as the signed-in user.

## 1. Sign In

```powershell
az login --tenant be945e7a-2e17-4b44-926f-512e85873eec
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
az account show --query "{tenantId:tenantId,subscriptionId:id,user:user.name}" -o json
```

The `tenantId` must be `be945e7a-2e17-4b44-926f-512e85873eec`.

Your Entra user object id must be in the Terraform variable `developer_object_ids`.

The default value is in:

```text
terraform/01_variables.tf
```

Terraform adds that user to:

```text
grp-vp-sql-dabdemo
```

The Container App managed identity is added to the same group automatically for setup and Key Vault access.

## 2. Confirm Terraform Has Been Applied

Terraform creates:

```text
SQL server: sql-vp-dabdemo.database.windows.net
SQL database: vkp-dabdemo
Key Vault: kv-vp-dabdemo
Secret: sql-connection-string
Secret: dab-obo-client-secret
```

If the SQL Server or group was just created, wait a few minutes before testing. Entra group membership can take a short time to work in Azure SQL.

The local DAB config reads:

```text
dab/dab-config.local.json
```

Terraform keeps Key Vault and SQL public network access enabled so the public Container App and local developer machines can reach them. Access is still controlled by Key Vault access policies, SQL firewall rules, Entra authentication, and SQL permissions.

If your organization disables public access and moves this to private networking, local testing from your workstation will only work from an approved private network. For a temporary smoke test in that model, enable public access, test, then disable it again:

```powershell
az keyvault update --name kv-vp-dabdemo --resource-group rg-vp-dabdemo --public-network-access Enabled
az sql server update --name sql-vp-dabdemo --resource-group rg-vp-dabdemo --set publicNetworkAccess=Enabled

# Run local DAB tests.

az keyvault update --name kv-vp-dabdemo --resource-group rg-vp-dabdemo --public-network-access Disabled
az sql server update --name sql-vp-dabdemo --resource-group rg-vp-dabdemo --set publicNetworkAccess=Disabled
```

## 3. Check The API Audience

The current API audience in both DAB config files is:

```text
911707a6-46f5-432b-86d1-9e645a3b6e4b
```

The token request scope is `api://app-vp-api-dabdemo/access_as_user`; the resulting token `aud` claim is the API client id above.

If you delete and recreate the Terraform infrastructure, get the new API audience:

```powershell
terraform -chdir=terraform output -raw api_audience
```

Then update the `runtime.host.authentication.jwt.audience` value in both files:

```text
dab/dab-config.json
dab/dab-config.local.json
```

## 4. Create Tables In SSMS

Connect in SSMS:

```text
Server: sql-vp-dabdemo.database.windows.net
Database: vkp-dabdemo
Authentication: Microsoft Entra MFA or Microsoft Entra interactive
```

Run your migration script. For the sample schema, run:

```text
dab/dabdemo_sample_schema.sql
```

## 5. Start DAB Locally

From the repo root, in the same PowerShell terminal where you start DAB:

```powershell
$env:AZURE_TENANT_ID = "be945e7a-2e17-4b44-926f-512e85873eec"
$env:AZURE_TOKEN_CREDENTIALS = "AzureCliCredential"
$env:DAB_OBO_CLIENT_ID = terraform -chdir=terraform output -raw api_client_id
$env:DAB_OBO_TENANT_ID = terraform -chdir=terraform output -raw tenant_id
$env:DAB_OBO_CLIENT_SECRET = az keyvault secret show --vault-name kv-vp-dabdemo --name dab-obo-client-secret --query value -o tsv

dotnet tool restore
dotnet tool run dab -- start --config .\dab\dab-config.local.json --no-https-redirect
```

Leave that terminal running.

Before starting DAB, you can verify that the same Azure CLI login can read the OBO connection string secret without printing the secret value:

```powershell
az account get-access-token --resource https://vault.azure.net --query "{tenant:tenant,subscription:subscription}" -o json
az keyvault secret show --vault-name kv-vp-dabdemo --name sql-connection-string --query "{name:name,id:id}" -o json
az keyvault secret show --vault-name kv-vp-dabdemo --name dab-obo-client-secret --query "{name:name,id:id}" -o json
```

The token tenant must be `be945e7a-2e17-4b44-926f-512e85873eec`.

### Troubleshooting: Key Vault Invalid Issuer

If DAB fails with an error like this:

```text
AKV10032: Invalid issuer. Expected one of https://sts.windows.net/be945e7a-2e17-4b44-926f-512e85873eec/, found https://sts.windows.net/<different-tenant-id>/.
```

DAB is reading Key Vault with a token from the wrong Entra tenant. This usually means the terminal running DAB did not inherit the tenant-scoped Azure CLI credential settings, or `DefaultAzureCredential` found another cached login first.

Run these commands again in the same terminal that will run DAB:

```powershell
az login --tenant be945e7a-2e17-4b44-926f-512e85873eec
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697

$env:AZURE_TENANT_ID = "be945e7a-2e17-4b44-926f-512e85873eec"
$env:AZURE_TOKEN_CREDENTIALS = "AzureCliCredential"
$env:DAB_OBO_CLIENT_ID = terraform -chdir=terraform output -raw api_client_id
$env:DAB_OBO_TENANT_ID = terraform -chdir=terraform output -raw tenant_id
$env:DAB_OBO_CLIENT_SECRET = az keyvault secret show --vault-name kv-vp-dabdemo --name dab-obo-client-secret --query value -o tsv

az account get-access-token --resource https://vault.azure.net --query "{tenant:tenant,subscription:subscription}" -o json
dotnet tool run dab -- start --config .\dab\dab-config.local.json --no-https-redirect
```

If the token tenant is still different, clear the wrong cached login and sign in again:

```powershell
az logout
az login --tenant be945e7a-2e17-4b44-926f-512e85873eec
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
```

## 6. Test Local Endpoints

Open a second PowerShell terminal:

```powershell
$scope = "api://app-vp-api-dabdemo/access_as_user"
$token = az account get-access-token --scope $scope --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

$tokenPayload = $token.Split(".")[1].Replace("-", "+").Replace("_", "/")
switch ($tokenPayload.Length % 4) { 2 { $tokenPayload += "==" } 3 { $tokenPayload += "=" } }
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json | Select-Object aud,iss,scp

Invoke-WebRequest "http://localhost:5000/" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/openapi" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/dbo_Products" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/dbo_Customers" -Headers $headers -UseBasicParsing
```

OpenAPI / Swagger:

```powershell
Invoke-WebRequest "http://localhost:5000/api/openapi" -Headers $headers -UseBasicParsing
```

DAB exposes the Swagger/OpenAPI document at `/api/openapi`. It does not serve a built-in Swagger UI page at `/swagger` or `/swagger/index.html`, so those routes can return `400 Bad Request` or `404 Not Found`.

To see the interactive Swagger UI, keep DAB running and start Swagger UI in another terminal:

```powershell
docker run --rm -p 8080:8080 -e SWAGGER_JSON_URL=http://host.docker.internal:5000/api/openapi swaggerapi/swagger-ui
```

Then open:

```text
http://localhost:8080
```

To call secured endpoints from Swagger UI, click `Authorize` and paste a bearer token from:

```powershell
$scope = "api://app-vp-api-dabdemo/access_as_user"
$token = az account get-access-token --scope $scope --query accessToken -o tsv
$token
```

GraphQL:

```powershell
$body = @{ query = "{ dbo_Products { items { ProductId Name } } }" } | ConvertTo-Json -Compress

Invoke-RestMethod `
  -Uri "http://localhost:5000/graphql" `
  -Method POST `
  -ContentType "application/json" `
  -Headers $headers `
  -Body $body
```

Optional health check:

```powershell
Invoke-WebRequest "http://localhost:5000/health" -Headers $headers -UseBasicParsing
```

Health is authenticated because OBO needs a user token before DAB can open the SQL connection as that user.

The `/mcp` path is enabled for MCP clients. A normal browser or `Invoke-WebRequest` GET can return `406 Not Acceptable`; that does not mean REST or GraphQL is broken.

Anonymous table access should fail after tables exist:

```powershell
Invoke-WebRequest "http://localhost:5000/api/dbo_Products" -UseBasicParsing
```

Expected status: `403`.
