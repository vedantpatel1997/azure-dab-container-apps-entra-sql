# Azure Data API Builder on Container Apps

This repo is intentionally simple.

Terraform creates the Azure infrastructure. You create SQL tables yourself in SSMS. GitHub Actions builds the DAB image in ACR and updates Azure Container Apps.

## Files To Know

```text
terraform/                         Azure infrastructure with local state
dab/dab-config.json                Production DAB config
dab/dab-config.local.json          Local DAB config, same database as production
dab/Dockerfile                     Container image
dab/dabdemo_sample_schema.sql      Optional sample schema
.github/workflows/deploy-dab.yml   Build image in ACR and update Container App
RUN_LOCAL.md                       Local run instructions
RUN_CLOUD.md                       Cloud run instructions
```

## Fixed Resource Names

Terraform no longer adds a random suffix to resource names.

```text
Tenant: be945e7a-2e17-4b44-926f-512e85873eec
Subscription: 6a3bb170-5159-4bff-860b-aa74fb762697
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

## Authentication Model

DAB uses Entra ID authentication plus On-Behalf-Of (OBO) user-delegated SQL authentication.

The request flow is:

```text
User gets a token for api://app-vp-api-dabdemo/access_as_user
DAB validates that token
DAB exchanges it for a SQL token with audience https://database.windows.net
Azure SQL sees the actual calling user
```

For this app registration, the token `aud` claim is the API client id `911707a6-46f5-432b-86d1-9e645a3b6e4b`. The token request scope is still `api://app-vp-api-dabdemo/access_as_user`.

The Container App managed identity is still used by DAB to read Key Vault and pull from ACR. It is not the SQL caller for OBO requests.

There is one SQL Entra admin group: `grp-vp-sql-dabdemo`. Terraform adds the `developer_object_ids` users and the Container App managed identity to that group for setup and administration. For production data access, create database users or groups and grant only the SQL permissions each user group needs.

OBO requires three Container App environment variables:

```text
DAB_OBO_CLIENT_ID       API app registration client id
DAB_OBO_TENANT_ID       Entra tenant id
DAB_OBO_CLIENT_SECRET   Secret reference for dab-obo-client-secret
```

The SQL connection string used by OBO must be bare: server, database, encryption, and timeout only. Do not add `Authentication=Active Directory Managed Identity` or SQL credentials to `sql-connection-string`.

## Key Vault Secrets

Terraform stores the OBO connection string, legacy/testing connection strings, and the DAB OBO client secret:

```text
sql-connection-string          Bare SQL connection string used by OBO
dab-obo-client-secret          Client secret DAB uses for the OBO token exchange
sql-connection-string-local    Legacy local Active Directory Default connection string
sql-connection-string-cloud    Legacy Container App managed identity connection string
sql-connection-string-sql-auth SQL username and password testing connection string
```

If the Terraform app registration is recreated, update these values together:

```text
dab/dab-config.json runtime.host.authentication.jwt.audience
dab/dab-config.local.json runtime.host.authentication.jwt.audience
.github/workflows/deploy-dab.yml DAB_OBO_CLIENT_ID
dab/buildandpush_script.ps1 ApiClientId default
```

## OpenAPI And Swagger UI

DAB exposes the OpenAPI document at:

```text
Local: http://localhost:5000/api/openapi
Cloud: <container-app-url>/api/openapi
```

DAB does not host a built-in Swagger UI page at `/swagger` or `/swagger/index.html`. To see the interactive Swagger UI, run a separate Swagger UI viewer and point it at the DAB OpenAPI document.

Local example:

```powershell
docker run --rm -p 8080:8080 -e SWAGGER_JSON_URL=http://host.docker.internal:5000/api/openapi swaggerapi/swagger-ui
```

Then open:

```text
http://localhost:8080
```

For secured REST calls in Swagger UI, get a user token and use the `Authorize` button:

```powershell
$scope = "api://app-vp-api-dabdemo/access_as_user"
$token = az account get-access-token --scope $scope --query accessToken -o tsv
$token
```

## Run

For local development, follow [RUN_LOCAL.md](RUN_LOCAL.md).

For Azure deployment, follow [RUN_CLOUD.md](RUN_CLOUD.md).
