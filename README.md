# Azure Data API Builder on Container Apps

This repo deploys a small Azure Data API Builder (DAB) service on Azure Container Apps.

The workflow is intentionally simple:

1. Run Terraform locally to create Azure infrastructure.
2. Open Azure SQL in SSMS and run your migration/schema manually.
3. Run the GitHub Actions `deploy-dab` workflow to build the DAB image in ACR and update Container Apps.
4. Test production and local DAB manually.

Terraform does not run database migrations. GitHub Actions does not create infrastructure.
Terraform state is local only and is written to `terraform/terraform.tfstate`, which is ignored by git.
Resource names use `vkp` as the default organization prefix.

## What Terraform Creates

Terraform creates:

- Resource group
- User-assigned managed identity for Container Apps
- Entra app registration for DAB JWT auth
- Azure SQL server and database
- Azure Container Registry
- Key Vault secret containing the DAB SQL connection string
- Container Apps environment
- Container App shell

The Container App starts with a placeholder image. The DAB image is deployed later by GitHub Actions.

## Repository Layout

```text
.github/workflows/deploy-dab.yml  Builds/pushes image and updates Container App
dab/                              Dockerfile, DAB config templates, sample SQL schema
scripts/Render-DabConfig.ps1      Renders DAB config from Terraform outputs
scripts/Deploy-Dab.ps1            Local build/update helper for Container Apps
scripts/Test-Dab.ps1              Manual production endpoint test
scripts/Test-DabLocal.ps1         Manual localhost endpoint test
terraform/                        Azure infrastructure
```

## Prerequisites

- Azure CLI signed in to the target tenant
- Terraform
- .NET SDK for the local DAB tool
- SSMS for manual SQL migration
- GitHub Actions variables configured for the deploy workflow

Use the Azure account that should administer the SQL database:

```powershell
az login --tenant be945e7a-2e17-4b44-926f-512e85873eec
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
```

## 1. Create Infrastructure Locally

From the repo root:

```powershell
$ip = (Invoke-RestMethod "https://api.ipify.org").Trim()
@{
  allowed_ip_addresses = @{
    Local = $ip
  }
} | ConvertTo-Json -Depth 10 | Set-Content terraform\local.auto.tfvars.json -Encoding ascii

terraform -chdir=terraform init

terraform -chdir=terraform validate
terraform -chdir=terraform apply
terraform -chdir=terraform output
```

Default resource names look like:

```text
rg-vkp-xxxxxx
acrvkpxxxxxx
kv-vkp-xxxxxx
sql-vkp-xxxxxx
vkp-dabdemo
cae-vkp-xxxxxx
ca-vkp-xxxxxx
id-vkp-aca-xxxxxx
app-vkp-api-xxxxxx
```

## 2. Run SQL Migration Manually in SSMS

After Terraform finishes, get these values:

```powershell
terraform -chdir=terraform output -raw sql_server_fqdn
terraform -chdir=terraform output -raw sql_database_name
terraform -chdir=terraform output -raw uami_name
```

Open SSMS:

- Server: value from `sql_server_fqdn`
- Authentication: Microsoft Entra MFA or Microsoft Entra interactive
- Database: value from `sql_database_name`

Run your migration script. For the sample schema in this repo, run:

```text
dab/dabdemo_sample_schema.sql
```

Then grant the Container App managed identity access to the database. Replace `<UAMI_NAME>` with `terraform output -raw uami_name`:

```sql
DECLARE @uami sysname = N'<UAMI_NAME>';
DECLARE @sql nvarchar(max);

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @uami)
BEGIN
  SET @sql = N'CREATE USER ' + QUOTENAME(@uami) + N' FROM EXTERNAL PROVIDER;';
  EXEC sys.sp_executesql @sql;
END;

SET @sql = N'ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@uami) + N';';
EXEC sys.sp_executesql @sql;

SET @sql = N'ALTER ROLE db_datawriter ADD MEMBER ' + QUOTENAME(@uami) + N';';
EXEC sys.sp_executesql @sql;

SET @sql = N'GRANT EXECUTE ON SCHEMA::dbo TO ' + QUOTENAME(@uami) + N';';
EXEC sys.sp_executesql @sql;
```

## 3. Configure GitHub Actions Variables

The repo uses GitHub Actions variables, not GitHub secrets, because Azure login uses OIDC.

Set these repository variables from Terraform outputs:

```powershell
$outputs = terraform -chdir=terraform output -json | ConvertFrom-Json
$acrLogin = $outputs.acr_login_server.value

gh variable set AZURE_CLIENT_ID --body "<OIDC app client id>"
gh variable set AZURE_TENANT_ID --body $outputs.tenant_id.value
gh variable set AZURE_SUBSCRIPTION_ID --body $outputs.subscription_id.value
gh variable set AZURE_RESOURCE_GROUP --body $outputs.resource_group_name.value
gh variable set AZURE_ACR_NAME --body $acrLogin.Split(".")[0]
gh variable set AZURE_ACR_LOGIN_SERVER --body $acrLogin
gh variable set AZURE_CONTAINER_APP_NAME --body $outputs.container_app_name.value
gh variable set AZURE_UAMI_CLIENT_ID --body $outputs.uami_client_id.value
gh variable set DAB_API_AUDIENCE --body $outputs.api_audience.value
gh variable set DAB_JWT_ISSUER --body $outputs.jwt_issuer.value
gh variable set DAB_KEY_VAULT_URI --body $outputs.key_vault_uri.value
```

`AZURE_CLIENT_ID` is the client id of the Entra app registration that GitHub Actions uses for OIDC login. It must have permission to build in ACR and update the Container App.

No repository secrets are required for this setup. If old secrets exist from earlier experiments, remove them:

```powershell
gh secret delete AZURE_CLIENT_SECRET --repo vedantpatel1997/azure-dab-container-apps-entra-sql
gh secret delete ARM_CLIENT_SECRET --repo vedantpatel1997/azure-dab-container-apps-entra-sql
```

## 4. Run Cloud Deployment

In GitHub, run:

```text
Actions -> deploy-dab -> Run workflow
```

The workflow:

1. Logs in to Azure using OIDC.
2. Renders `dab/dab-config.json`.
3. Builds `vkp-dab-api:${GITHUB_SHA}` in ACR.
4. Updates the Container App image and `AZURE_CLIENT_ID` environment variable.

You can do the same deployment locally:

```powershell
.\scripts\Deploy-Dab.ps1 -ImageTag local-test
```

## 5. Test Production

After the image is deployed and SQL migration is complete:

```powershell
.\scripts\Test-Dab.ps1
```

Expected sample result:

```text
/api/dbo_Products  = 200, 4 rows
/api/dbo_Customers = 200, 3 rows
/graphql           = 200, 4 products
anonymous products = 403
```

## 6. Test Locally

Render local config and run the local test script:

```powershell
.\scripts\Render-DabConfig.ps1
.\scripts\Test-DabLocal.ps1
```

The script starts the repo-local DAB CLI on `http://localhost:5000`, tests REST/OpenAPI/GraphQL, verifies anonymous access is denied, and stops the local process.

## Cleanup

Local files generated during normal use are ignored by git:

```text
terraform/local.auto.tfvars.json
dab/dab-config.json
dab/dab-config.local.json
```

To remove the deployed Azure infrastructure:

```powershell
terraform -chdir=terraform destroy
```

To clean GitHub configuration, keep only the repository variables listed above and delete old secrets that are no longer needed.
