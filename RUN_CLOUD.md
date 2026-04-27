# Run In Cloud

Cloud deployment has three simple parts:

1. Terraform creates Azure resources.
2. You create tables/grants in SSMS.
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

Current resource names:

```text
Resource group: rg-vkp-vmerdr
ACR: acrvkpvmerdr.azurecr.io
SQL server: sql-vkp-vmerdr.database.windows.net
SQL database: vkp-dabdemo
Key Vault: kv-vkp-vmerdr
Container App: ca-vkp-vmerdr
Container App URL: https://ca-vkp-vmerdr.politesand-c76afc10.westus3.azurecontainerapps.io
Managed identity: id-vkp-aca-vmerdr
```

If Terraform outputs different values after a rebuild, update:

```text
dab/dab-config.json
dab/dab-config.local.json
.github/workflows/deploy-dab.yml
```

## 2. Run Your SQL Migration In SSMS

Connect in SSMS:

```text
Server: sql-vkp-vmerdr.database.windows.net
Database: vkp-dabdemo
Authentication: Microsoft Entra MFA or Microsoft Entra interactive
```

Run your migration script.

For this sample, you can run:

```text
dab/dabdemo_sample_schema.sql
```

## 3. SQL Connection String

Terraform stores the SQL connection string in Key Vault:

```text
Key Vault: kv-vkp-vmerdr
Secret: sql-connection-string
```

Do not put the SQL connection string in GitHub.

The Container App managed identity only needs Key Vault access. It does not need a SQL database user.

## 4. Configure GitHub Actions

Only one GitHub repository variable is needed:

```text
AZURE_CLIENT_ID
```

This is the client id of the Entra app that GitHub Actions uses for OIDC login.

The workflow already contains the tenant id, subscription id, ACR name, resource group, Container App name, image name, and managed identity client id.

No GitHub secrets are required.

## 5. Run The GitHub Action

In GitHub:

```text
Actions -> deploy-dab -> Run workflow
```

The workflow:

1. Logs in to Azure.
2. Builds `vkp-dab-api:${GITHUB_SHA}` in ACR.
3. Updates `ca-vkp-vmerdr` to use that image.

## 6. Test Cloud Endpoints

```powershell
$baseUrl = "https://ca-vkp-vmerdr.politesand-c76afc10.westus3.azurecontainerapps.io"
$scope = "api://app-vkp-api-vmerdr/access_as_user"
$token = az account get-access-token --scope $scope --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

Invoke-WebRequest "$baseUrl/" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/openapi" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/dbo_Products" -Headers $headers -UseBasicParsing
Invoke-WebRequest "$baseUrl/api/dbo_Customers" -Headers $headers -UseBasicParsing
```

GraphQL:

```powershell
$body = @{ query = "{ dbo_Products { items { ProductId Sku Name Category UnitPrice } } }" } | ConvertTo-Json -Compress

Invoke-RestMethod `
  -Uri "$baseUrl/graphql" `
  -Method POST `
  -ContentType "application/json" `
  -Headers $headers `
  -Body $body
```

Anonymous table access should fail:

```powershell
Invoke-WebRequest "$baseUrl/api/dbo_Products" -UseBasicParsing
```

Expected status: `403`.
