# Run Locally

Local DAB uses the same Azure SQL database as production, but it connects with your signed-in Azure CLI user.

## 1. Sign In

```powershell
az login --tenant be945e7a-2e17-4b44-926f-512e85873eec
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
```

Your Entra user object id must be in `terraform/developer_object_ids`. Terraform adds that user to:

```text
grp-vkp-sql-dabdemo
```

## 2. Confirm Terraform Has Been Applied

Terraform creates:

```text
SQL server: sql-vkp-dabdemo.database.windows.net
SQL database: vkp-dabdemo
Key Vault: kv-vkp-dabdemo
Secret: sql-connection-string-local
```

The local DAB config reads:

```text
dab/dab-config.local.json
```

## 3. Update The API Audience

After `terraform apply`, get the API audience:

```powershell
terraform -chdir=terraform output -raw api_audience
```

Replace `REPLACE_WITH_TERRAFORM_OUTPUT_API_AUDIENCE` in both files:

```text
dab/dab-config.json
dab/dab-config.local.json
```

## 4. Create Tables In SSMS

Connect in SSMS:

```text
Server: sql-vkp-dabdemo.database.windows.net
Database: vkp-dabdemo
Authentication: Microsoft Entra MFA or Microsoft Entra interactive
```

Run your migration script. For the sample schema, run:

```text
dab/dabdemo_sample_schema.sql
```

## 5. Start DAB Locally

From the repo root:

```powershell
$env:AZURE_TENANT_ID = "be945e7a-2e17-4b44-926f-512e85873eec"
$env:AZURE_TOKEN_CREDENTIALS = "AzureCliCredential"

dotnet tool restore
dotnet tool run dab -- start --config .\dab\dab-config.local.json --no-https-redirect
```

Leave that terminal running.

## 6. Test Local Endpoints

Open a second PowerShell terminal:

```powershell
$scope = "api://app-vkp-api-dabdemo/access_as_user"
$token = az account get-access-token --scope $scope --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

Invoke-WebRequest "http://localhost:5000/" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/openapi" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/dbo_Products" -Headers $headers -UseBasicParsing
Invoke-WebRequest "http://localhost:5000/api/dbo_Customers" -Headers $headers -UseBasicParsing
```

Anonymous table access should fail after tables exist:

```powershell
Invoke-WebRequest "http://localhost:5000/api/dbo_Products" -UseBasicParsing
```

Expected status: `403`.
