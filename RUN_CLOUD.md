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

## 3. Check The DAB Audience

The current API audience in both DAB config files is:

```text
911707a6-46f5-432b-86d1-9e645a3b6e4b
```

If you delete and recreate the Terraform infrastructure, get the new API audience:

```powershell
terraform -chdir=terraform output -raw api_audience
```

Then update the `runtime.host.authentication.jwt.audience` value in:

```text
dab/dab-config.json
dab/dab-config.local.json
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

If SSMS login fails immediately after Terraform finishes, wait a few minutes and try again. Entra group membership can take a short time to work in Azure SQL.

## 5. Key Vault Connection Strings

Terraform stores three connection strings:

```text
sql-connection-string-local      Local DAB, uses your Azure CLI credential
sql-connection-string-cloud      Cloud DAB, uses the Container App UAMI
sql-connection-string-sql-auth   SQL username/password testing connection
```

Production DAB uses `sql-connection-string-cloud`.

Local DAB uses `sql-connection-string-local`.

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

The workflow uses fixed resource names and looks up the Container App managed identity client id during deployment.

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

## 8. Test Cloud Endpoints

```powershell
$baseUrl = terraform -chdir=terraform output -raw container_app_url
$scope = "api://app-vp-api-dabdemo/access_as_user"
$token = az account get-access-token --scope $scope --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

Invoke-WebRequest "$baseUrl/" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/openapi" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/dbo_Products" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/dbo_Customers" -Headers $headers -UseBasicParsing
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
Invoke-WebRequest "$baseUrl/health" -UseBasicParsing
```

In production mode, `/health` can return `403` or show REST checks as forbidden when your entities only allow the `authenticated` role. Use the authenticated REST and GraphQL calls above as the real API test.

The `/mcp` path is enabled for MCP clients. A normal browser or `Invoke-WebRequest` GET can return `406 Not Acceptable`; that does not mean REST or GraphQL is broken.

Anonymous table access should fail after tables exist:

```powershell
Invoke-WebRequest "$baseUrl/api/dbo_Products" -UseBasicParsing
```

Expected status: `403`.
