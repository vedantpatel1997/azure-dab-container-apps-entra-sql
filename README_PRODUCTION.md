# Production deployment guide

Production deployment has two phases.

## Phase 1: infrastructure

Terraform creates the Azure resources only:

```powershell
cd terraform
terraform init
terraform validate
terraform apply
cd ..
```

Render the DAB config from Terraform outputs:

```powershell
.\scripts\Render-DabConfig.ps1
```

Bootstrap the database schema and grants after a new environment is created:

```powershell
.\scripts\Bootstrap-Sql.ps1
```

This uses your Azure CLI Entra token to connect to Azure SQL, runs `dab/dabdemo_sample_schema.sql`, creates a database user for the Terraform-created SQL access group, and grants read/write/execute permissions.

## Phase 2: DAB image deployment

Build and push the image:

```powershell
.\scripts\Deploy-Dab.ps1
```

The Container App template is ignored by Terraform on purpose. Terraform creates the shell app, identity, ingress, and ACR pull permissions. Image deployment is handled by `scripts/Deploy-Dab.ps1` or GitHub Actions.

## Test production

```powershell
.\scripts\Test-Dab.ps1
```

Expected result after the sample schema is loaded:

```text
/api/dbo_Products  = 200, 4 rows
/api/dbo_Customers = 200, 3 rows
/graphql           = 200, 4 products
```

Without a bearer token, table endpoints should return `403`.

Current production URL can be read with:

```powershell
terraform -chdir=terraform output -raw container_app_url
```
