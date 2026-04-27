# Azure Data API Builder on Container Apps

This repo is an end-to-end sample for running Azure Data API Builder, or DAB, on Azure Container Apps with secure Microsoft Entra authentication and Azure SQL.

The project creates Azure infrastructure with Terraform, keeps DAB as a separate containerized app project, and uses Entra ID instead of SQL username/password for runtime database access.

## Architecture

```text
Client or Postman
  -> Entra ID access token for DAB API app
  -> Azure Container Apps running DAB
  -> DAB validates JWT issuer and audience
  -> DAB resolves SQL connection string from Key Vault
  -> DAB connects to Azure SQL with the Container App UAMI
  -> Azure SQL grants access through an Entra SQL access group
```

Local development uses the same DAB config shape and the same Entra token validation, but SQL access uses your signed-in Azure CLI identity with `Authentication=Active Directory Default`.

## Why DAB

DAB exposes database objects as REST and GraphQL APIs without writing a custom CRUD service. In this repo, DAB:

- Exposes `dbo` SQL objects under `/api` and `/graphql`.
- Generates OpenAPI at `/api/openapi`.
- Uses Entra JWT validation for API callers.
- Blocks anonymous data access because entities only grant the `authenticated` role.
- Uses Key Vault and managed identity in production.
- Uses the DAB 2.0 RC track because this project uses `autoentities` and MCP configuration.

Version note: NuGet currently lists `Microsoft.DataApiBuilder` stable `1.7.93` and prerelease `2.0.0-rc`. Microsoft Learn documents DAB 2.0 as public preview and calls out `autoentities`, OBO, and MCP features. This repo pins `2.0.0-rc` for both the Docker image and local .NET tool manifest.

Sources:

- https://www.nuget.org/packages/Microsoft.DataApiBuilder
- https://learn.microsoft.com/en-us/azure/data-api-builder/whats-new/version-2-0
- https://learn.microsoft.com/en-us/azure/data-api-builder/

## Repo layout

```text
terraform/                 Azure infrastructure only, numbered by creation flow
dab/                       DAB Dockerfile, config templates, sample SQL schema
scripts/                   Render, bootstrap, deploy, and test scripts
.github/workflows/         Infra and DAB deployment workflows
dotnet-tools.json          Local DAB 2.0 RC tool pin
README_*.md                Topic-specific guides
```

## Create from zero

Run these commands from the repo root.

1. Sign in to Azure.

```powershell
az login --tenant MngEnvMCAP797847.onmicrosoft.com
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
```

2. Create Terraform variables.

```powershell
Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars
```

If your workstation cannot connect to Azure SQL, add your public IP to `allowed_ip_addresses` in `terraform/terraform.tfvars`.

3. Create Azure infrastructure.

```powershell
cd terraform
terraform init
terraform validate
terraform apply
cd ..
```

For GitHub automation, run the bootstrap first:

```powershell
.\scripts\Bootstrap-GitHubActions.ps1
```

Then push to `main` or run the `infra` workflow with `apply` or `recreate`.

4. Render DAB configs from Terraform outputs.

```powershell
.\scripts\Render-DabConfig.ps1
```

This creates ignored local files:

```text
dab/dab-config.json
dab/dab-config.local.json
```

5. Bootstrap SQL schema and permissions.

```powershell
.\scripts\Bootstrap-Sql.ps1
```

This loads `dab/dabdemo_sample_schema.sql`, creates a database user for the Terraform-created Entra SQL access group, and grants read/write/execute permissions.

6. Deploy DAB to Azure Container Apps.

```powershell
.\scripts\Deploy-Dab.ps1
```

This builds the DAB image in ACR and updates only the Container App image and `AZURE_CLIENT_ID`.

7. Test production.

```powershell
.\scripts\Test-Dab.ps1
```

Expected results:

```text
/api/openapi             200
/api/dbo_Products        200, 4 rows
/api/dbo_Customers       200, 3 rows
/graphql dbo_Products    200, 4 rows
Unauthenticated data     403
```

8. Test locally.

```powershell
dotnet tool restore
.\scripts\Test-DabLocal.ps1
```

The local test starts DAB with `dab/dab-config.local.json`, uses your Azure CLI Entra login for SQL, tests endpoints, and stops the process.

## Detailed guides

- [Terraform guide](README_TERRAFORM.md)
- [DAB config guide](README_DAB_CONFIG.md)
- [Authentication guide](README_AUTH.md)
- [Local testing guide](README_LOCAL.md)
- [Production guide](README_PRODUCTION.md)
- [Postman guide](README_POSTMAN.md)
- [CI/CD guide](README_CICD.md)
- [Validation results](README_VALIDATION_RESULTS.md)
