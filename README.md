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

There is one SQL Entra group: `grp-vp-sql-dabdemo`.

Terraform adds:

```text
Your user object id from developer_object_ids
The Container App user-assigned managed identity
```

Local DAB uses your Azure CLI credential. Cloud DAB uses the Container App managed identity.

## Key Vault Secrets

Terraform stores three connection strings:

```text
sql-connection-string-local      Uses Active Directory Default for local runs
sql-connection-string-cloud      Uses the Container App user-assigned managed identity
sql-connection-string-sql-auth   Uses SQL username and password for testing
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
