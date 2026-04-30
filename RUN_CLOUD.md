# Run In Cloud

Cloud deployment has three simple parts:

1. Terraform creates Azure resources.
2. You create tables in SSMS.
3. GitHub Actions builds the image and updates Container Apps.

## 1. Create Azure Infrastructure

From the repo root:

```powershell
az login --tenant be945e7a-2e17-4b44-926f-512e85873eec
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697

$ip = (Invoke-RestMethod "https://api.ipify.org").Trim()
@{
  allowed_ip_addresses = @{
    Local = $ip
  }
} | ConvertTo-Json -Depth 10 | Set-Content terraform\local.auto.tfvars.json -Encoding ascii

terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform apply
```

Terraform uses local state only.

The command above writes your current public IP into `terraform/local.auto.tfvars.json` so SSMS can connect to Azure SQL from your machine.

## 2. Resource Names

Terraform creates fixed names:

```text
Resource group: rg-vp-dabdemo
ACR: acrvpdabdemo.azurecr.io
SQL server: sql-vp-dabdemo.database.windows.net
SQL database: vkp-dabdemo
Key Vault: kv-vp-dabdemo
Container App: ca-vp-dabdemo
Managed identity: id-vp-aca-dabdemo
SQL Entra group: grp-vp-sql-dabdemo
API scope: api://app-vp-api-dabdemo/access_as_user
```

The Container App URL is created by Azure. Get it after apply:

```powershell
terraform -chdir=terraform output -raw container_app_url
```

This sample keeps Key Vault and SQL public network access enabled because the Container App uses their public endpoints. Access is still controlled by Key Vault access policies, SQL firewall rules, Entra authentication, and SQL permissions. For a private production topology, add private endpoints/VNet integration before disabling public access.

## 3. Check The DAB Audience

The current API audience in both DAB config files is:

```text
911707a6-46f5-432b-86d1-9e645a3b6e4b
```

The token request scope is `api://app-vp-api-dabdemo/access_as_user`; the resulting token `aud` claim is the API client id above.

If you delete and recreate the Terraform infrastructure, get the new API audience:

```powershell
terraform -chdir=terraform output -raw api_audience
```

Then update the `runtime.host.authentication.jwt.audience` value in:

```text
dab/dab-config.json
dab/dab-config.local.json
```

Also update the fixed `DAB_OBO_CLIENT_ID` value in:

```text
.github/workflows/deploy-dab.yml
dab/buildandpush_script.ps1
```

Commit and push that change before running the GitHub Action.

## 4. Run Your SQL Migration In SSMS

Connect in SSMS:

```text
Server: sql-vp-dabdemo.database.windows.net
Database: vkp-dabdemo
Authentication: Microsoft Entra MFA or Microsoft Entra interactive
```

Run your migration script.

For this sample, you can run:

```text
dab/dabdemo_sample_schema.sql
```

Terraform sets `grp-vp-sql-dabdemo` as the SQL Entra administrator group and adds your user plus the Container App managed identity as members.

With OBO enabled, Azure SQL sees the actual calling user, not the Container App managed identity. For production, create database users or groups for the real callers and grant the minimum table/view permissions they need.

If SSMS login fails immediately after Terraform finishes, wait a few minutes and try again. Entra group membership can take a short time to work in Azure SQL.

## 5. Key Vault Connection Strings

Terraform stores the OBO connection string, legacy/testing connection strings, and the DAB OBO client secret:

```text
sql-connection-string          Bare SQL connection string used by OBO
dab-obo-client-secret          Client secret DAB uses for the OBO token exchange
sql-connection-string-local    Legacy local Active Directory Default connection string
sql-connection-string-cloud    Legacy Container App managed identity connection string
sql-connection-string-sql-auth SQL username/password testing connection string
```

Production and local OBO configs use `sql-connection-string`. It intentionally has no `Authentication=` keyword.

The Container App stores `dab-obo-client-secret` as a Container Apps secret and exposes it to DAB as:

```text
DAB_OBO_CLIENT_SECRET=secretref:dab-obo-client-secret
```

## 6. Configure GitHub Actions

Only one GitHub repository variable is needed:

```text
AZURE_CLIENT_ID
```

This is the client id of the Entra app that GitHub Actions uses for OIDC login.

That Entra app needs:

```text
Reader on the subscription
Contributor on rg-vp-dabdemo
```

The federated credential subject should match this repo and branch:

```text
repo:vedantpatel1997/azure-dab-container-apps-entra-sql:ref:refs/heads/main
```

The workflow uses fixed resource names and looks up the Container App managed identity client id and DAB API app client id during deployment.

No GitHub secrets are required.

## 7. Run The GitHub Action

In GitHub:

```text
Actions -> deploy-dab -> Run workflow
```

The workflow:

1. Logs in to Azure.
2. Builds `vkp-dab-api:${GITHUB_SHA}` in ACR.
3. Updates `ca-vp-dabdemo` to use that image.
4. Sets `DAB_OBO_CLIENT_ID`, `DAB_OBO_TENANT_ID`, and `DAB_OBO_CLIENT_SECRET` for the container.

## 8. Test Cloud Endpoints

If the Container App was manually stopped, start it before testing:

```powershell
$subscription = terraform -chdir=terraform output -raw subscription_id
$uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/rg-vp-dabdemo/providers/Microsoft.App/containerApps/ca-vp-dabdemo/start?api-version=2025-07-01"
az rest --method post --url $uri
```

```powershell
$baseUrl = terraform -chdir=terraform output -raw container_app_url
$scope = "api://app-vp-api-dabdemo/access_as_user"
$token = az account get-access-token --scope $scope --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

$tokenPayload = $token.Split(".")[1].Replace("-", "+").Replace("_", "/")
switch ($tokenPayload.Length % 4) { 2 { $tokenPayload += "==" } 3 { $tokenPayload += "=" } }
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json | Select-Object aud,iss,scp

Invoke-WebRequest "$baseUrl/" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/openapi" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/dbo_Products" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/dbo_Customers" -Headers $headers -UseBasicParsing
```

OpenAPI / Swagger:

```powershell
Invoke-WebRequest "$baseUrl/api/openapi" -Headers $headers -UseBasicParsing
```

DAB exposes the Swagger/OpenAPI document at `/api/openapi`. It does not serve a built-in Swagger UI page at `/swagger` or `/swagger/index.html`, so those routes can return `400 Bad Request` or `404 Not Found`.

To see the interactive Swagger UI, run a separate Swagger UI viewer and point it at the cloud OpenAPI document:

```powershell
docker run --rm -p 8080:8080 -e SWAGGER_JSON_URL="$baseUrl/api/openapi" swaggerapi/swagger-ui
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
  -Uri "$baseUrl/graphql" `
  -Method POST `
  -ContentType "application/json" `
  -Headers $headers `
  -Body $body
```

Optional health check:

```powershell
Invoke-WebRequest "$baseUrl/health" -Headers $headers -UseBasicParsing
```

Health is authenticated because OBO needs a user token before DAB can open the SQL connection as that user.

The `/mcp` path is enabled for MCP clients. A normal browser or `Invoke-WebRequest` GET can return `406 Not Acceptable`; that does not mean REST or GraphQL is broken.

Anonymous table access should fail after tables exist:

```powershell
Invoke-WebRequest "$baseUrl/api/dbo_Products" -UseBasicParsing
```

Expected status: `403`.
