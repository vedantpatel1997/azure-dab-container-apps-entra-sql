# Azure Data API Builder on Container Apps

This repo is intentionally simple.

Terraform creates the Azure infrastructure. You create the SQL tables yourself in SSMS. GitHub Actions builds the DAB image and updates Azure Container Apps.

The SQL connection string is the only secret-like value. Terraform stores it in Azure Key Vault as `sql-connection-string`. It is not stored in GitHub.

## Files To Know

```text
terraform/                         Azure infrastructure
dab/dab-config.json                Production DAB config
dab/dab-config.local.json          Local DAB config, same database as production
dab/Dockerfile                     Container image
dab/dabdemo_sample_schema.sql      Optional sample schema
.github/workflows/deploy-dab.yml   Build image in ACR and update Container App
RUN_LOCAL.md                       Local run instructions
RUN_CLOUD.md                       Cloud run instructions
```

## Current Azure Values

```text
Tenant: be945e7a-2e17-4b44-926f-512e85873eec
Subscription: 6a3bb170-5159-4bff-860b-aa74fb762697
Resource group: rg-vkp-vmerdr
ACR: acrvkpvmerdr.azurecr.io
SQL server: sql-vkp-vmerdr.database.windows.net
SQL database: vkp-dabdemo
Key Vault: kv-vkp-vmerdr
Container App: ca-vkp-vmerdr
Container App URL: https://ca-vkp-vmerdr.politesand-c76afc10.westus3.azurecontainerapps.io
Managed identity: id-vkp-aca-vmerdr
API scope: api://app-vkp-api-vmerdr/access_as_user
```

## Run

For local development, follow [RUN_LOCAL.md](RUN_LOCAL.md).

For Azure deployment, follow [RUN_CLOUD.md](RUN_CLOUD.md).

## Important

If you delete and recreate the Terraform infrastructure, some generated values may change. After recreating, run:

```powershell
terraform -chdir=terraform output
```

Then update the plain text values in:

```text
dab/dab-config.json
dab/dab-config.local.json
.github/workflows/deploy-dab.yml
RUN_LOCAL.md
RUN_CLOUD.md
```
