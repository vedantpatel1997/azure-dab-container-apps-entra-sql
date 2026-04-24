# End-to-end setup guide: Data API builder on Azure Container Apps

This guide is written for your Azure SQL Database:

- Subscription: `6a3bb170-5159-4bff-860b-aa74fb762697`
- Resource group: `rg-dab-aca-mcp-auth-demo`
- SQL server: `sql-dabmcp-kwcm0e`
- Database: `dabdemo`
- SQL server FQDN: `sql-dabmcp-kwcm0e.database.windows.net`
- Target host: existing Azure Container App `temp-test`

Data API builder, or `DAB`, creates REST, GraphQL, and optional MCP endpoints from a JSON configuration file. You normally do **not** need to clone and build `https://github.com/Azure/data-api-builder` unless you plan to change the DAB product source code. For normal use, install the DAB CLI locally, create `dab-config.json`, test it against your Azure SQL database, then build a small container image that extends the official DAB runtime image.

Fresh-start assumptions for this guide:

- Ignore any old `dab-config.json` from earlier attempts.
- Use only the config in `dab-aca/dab-config.json`.
- Assume Azure SQL database `dabdemo` currently has no tables.
- Run `dab-aca/dabdemo_sample_schema.sql` first to create the sample database objects.
- Local testing uses your Azure/Entra developer sign-in.
- Production deployment to ACA `temp-test` uses a user-assigned managed identity.

Validation notes from this repo:

- `dab-aca/dab-config.json` parses as valid JSON.
- `docker build -t dab-aca:validation .` succeeds from inside `dab-aca`.
- `dab validate --config .\dab-config.json` satisfies the DAB schema and reports these REST paths: `/api/Customer`, `/api/Product`, `/api/SalesOrder`, `/api/OrderItem`, `/api/CustomerOrderSummary`, and `/api/SearchProducts`.
- On this machine, database connectivity validation fails with `Login failed for user '<token-identified principal>'. The server is not currently configured to accept this token.` Fix that by configuring Microsoft Entra admin/user access for Azure SQL, or use SQL username/password for local testing.

Official references used for this runbook:

- DAB overview: https://learn.microsoft.com/en-us/azure/data-api-builder/overview
- DAB CLI install: https://learn.microsoft.com/en-us/azure/data-api-builder/command-line/install
- DAB SQL quickstart: https://learn.microsoft.com/en-us/azure/data-api-builder/quickstart/basic-sql
- DAB validate command: https://learn.microsoft.com/en-us/azure/data-api-builder/command-line/dab-validate
- DAB start command: https://learn.microsoft.com/en-us/azure/data-api-builder/command-line/dab-start
- DAB configuration schema: https://learn.microsoft.com/en-us/azure/data-api-builder/configuration/
- DAB deploy to Azure Container Apps: https://learn.microsoft.com/en-us/azure/data-api-builder/deployment/azure-container-apps
- DAB container image usage: https://hub.docker.com/r/microsoft/azure-databases-data-api-builder
- SQL troubleshooting and managed identity notes: https://learn.microsoft.com/en-us/azure/data-api-builder/troubleshooting/mssql

## 1. What you will build

You will create this small project:

```text
dab-aca/
  dabdemo_sample_schema.sql
  dab-config.json
  Dockerfile
  .dockerignore
```

Then you will:

1. Install local tools.
2. Connect to your Azure subscription.
3. Confirm your SQL database is reachable.
4. Create sample database objects because `dabdemo` currently has no tables.
5. Configure local database authentication.
6. Use the included DAB config.
7. Confirm the included sample entities.
8. Run DAB locally with the CLI.
9. Run DAB locally with Docker.
10. Build and push the DAB image to Azure Container Registry.
11. Deploy the image to your existing Azure Container App `temp-test`.
12. Configure database connectivity and test `/`, `/api/swagger`, `/api/<entity>`, and `/graphql`.

## 2. Prerequisites on your machine

Install these first:

1. Azure CLI  
   https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

2. Docker Desktop  
   https://www.docker.com/products/docker-desktop/

3. .NET 8 SDK or newer  
   https://dotnet.microsoft.com/download

4. Azure Data Studio or SQL Server Management Studio  
   Azure Data Studio: https://learn.microsoft.com/en-us/azure-data-studio/download-azure-data-studio

5. PowerShell 7 is recommended, but Windows PowerShell also works for this guide.

Verify tools:

```powershell
az version
docker --version
dotnet --version
```

Install or update the DAB CLI:

```powershell
dotnet tool install --global Microsoft.DataApiBuilder
```

If it is already installed:

```powershell
dotnet tool update --global Microsoft.DataApiBuilder
```

Verify:

```powershell
dab --version
```

## 3. Sign in to Azure and set your subscription

```powershell
az login --tenant MngEnvMCAP797847.onmicrosoft.com
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
az account show --query "{name:name, subscriptionId:id, tenantId:tenantId}" -o table
```

Optional but useful: store names in PowerShell variables:

```powershell
$SUBSCRIPTION_ID = "6a3bb170-5159-4bff-860b-aa74fb762697"
$RESOURCE_GROUP = "rg-dab-aca-mcp-auth-demo"
$SQL_SERVER = "sql-dabmcp-kwcm0e"
$SQL_DB = "dabdemo"
$SQL_FQDN = "$SQL_SERVER.database.windows.net"

az account set --subscription $SUBSCRIPTION_ID
```

Confirm the database exists:

```powershell
az sql db show `
  --resource-group $RESOURCE_GROUP `
  --server $SQL_SERVER `
  --name $SQL_DB `
  --query "{name:name, status:status, sku:sku.name, location:location}" `
  -o table
```

## 4. Make sure your local machine can reach Azure SQL

For local development, Azure SQL firewall must allow your current public IP.

Get your public IP:

```powershell
$MY_IP = (Invoke-RestMethod -Uri "https://api.ipify.org")
$MY_IP
```

Create a firewall rule:

```powershell
az sql server firewall-rule create `
  --resource-group $RESOURCE_GROUP `
  --server $SQL_SERVER `
  --name "Allow-Local-DAB-Dev" `
  --start-ip-address $MY_IP `
  --end-ip-address $MY_IP
```

If your IP changes later, update it:

```powershell
$MY_IP = (Invoke-RestMethod -Uri "https://api.ipify.org")
az sql server firewall-rule update `
  --resource-group $RESOURCE_GROUP `
  --server $SQL_SERVER `
  --name "Allow-Local-DAB-Dev" `
  --start-ip-address $MY_IP `
  --end-ip-address $MY_IP
```

## 5. Decide how DAB will authenticate to SQL

This guide uses this path:

- Local testing: Microsoft Entra local developer auth with `Authentication=Active Directory Default`.
- ACA production: user-assigned managed identity with `Authentication=Active Directory Managed Identity`.

You can use SQL username/password for a quick test, but it is not the recommended production path.

### Option A: Microsoft Entra auth, recommended for this guide

Local connection string:

```text
Server=tcp:sql-dabmcp-kwcm0e.database.windows.net,1433;Database=dabdemo;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

ACA production managed identity connection string pattern:

```text
Server=tcp:sql-dabmcp-kwcm0e.database.windows.net,1433;Database=dabdemo;Authentication=Active Directory Managed Identity;User Id=<managed-identity-client-id>;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

Important: your Azure SQL server must have a Microsoft Entra admin configured before you can run `CREATE USER ... FROM EXTERNAL PROVIDER`.

To check or set the Entra admin in Azure Portal:

1. Open SQL server `sql-dabmcp-kwcm0e`.
2. Open `Microsoft Entra ID`.
3. Set an admin user or admin group.
4. Save.

### Option B: SQL username/password, optional for local debugging

Use this only if your Entra login is not ready yet. The connection string format is:

```text
Server=tcp:sql-dabmcp-kwcm0e.database.windows.net,1433;Initial Catalog=dabdemo;Persist Security Info=False;User ID=<sql-user>;Password=<sql-password>;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

For a safer app-specific login, connect to the database as an admin in Azure Data Studio/SSMS and run:

```sql
CREATE USER [dab_app_user] WITH PASSWORD = '<create-a-strong-password-here>';
ALTER ROLE db_datareader ADD MEMBER [dab_app_user];
-- Add this only if DAB should write data:
-- ALTER ROLE db_datawriter ADD MEMBER [dab_app_user];
```

If you expose only read endpoints, keep this user read-only.

For production, continue with managed identity instead of SQL username/password.

## 6. Open the ready-to-run local DAB project folder

This workspace already includes a ready-to-run project folder:

```text
dab-aca/
  dabdemo_sample_schema.sql
  dab-config.json
  Dockerfile
  .dockerignore
```

Move into it:

```powershell
cd dab-aca
```

If you ever need to recreate this folder from scratch, create the four files shown above using the contents in this repo.

## 7. Create sample tables in `dabdemo`

Because your database currently has no tables, run the sample schema script first.

Open Azure Data Studio or SSMS and connect with these exact database values:

```text
Server: sql-dabmcp-kwcm0e.database.windows.net
Database: dabdemo
Authentication: Microsoft Entra ID, SQL Login, or whichever admin method you already use
```

Open `dabdemo_sample_schema.sql` and run it against `dabdemo`.

The script is safe to rerun for this demo. It drops the demo procedure, view, and tables first, then recreates and reseeds them.

The script creates:

- `dbo.Customers`
- `dbo.Products`
- `dbo.SalesOrders`
- `dbo.OrderItems`
- `dbo.CustomerOrderSummary`
- `dbo.SearchProducts`

Verify the objects were created:

```sql
SELECT
    s.name AS schema_name,
    o.name AS object_name,
    o.type_desc
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE
    s.name = N'dbo'
    AND o.name IN
    (
        N'Customers',
        N'Products',
        N'SalesOrders',
        N'OrderItems',
        N'CustomerOrderSummary',
        N'SearchProducts'
    )
ORDER BY o.type_desc, o.name;
```

Quick data check:

```sql
SELECT TOP 10 * FROM dbo.Customers;
SELECT TOP 10 * FROM dbo.Products;
SELECT TOP 10 * FROM dbo.CustomerOrderSummary;
EXEC dbo.SearchProducts @search = N'DAB';
```

## 8. Set the local DAB connection string

This guide uses your actual Azure SQL server and database values:

```text
Server=tcp:sql-dabmcp-kwcm0e.database.windows.net,1433;Database=dabdemo;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

Run this in the same PowerShell window where you will run DAB:

```powershell
$env:DATABASE_CONNECTION_STRING = "Server=tcp:sql-dabmcp-kwcm0e.database.windows.net,1433;Database=dabdemo;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

This is ready to run if your local Azure login has access to `dabdemo`. If it fails with a login error, sign in locally and retry:

```powershell
az login --tenant MngEnvMCAP797847.onmicrosoft.com
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697
```

If your local Entra user is not allowed inside the database, connect as the Azure SQL Entra admin and run this, replacing the email with your signed-in Azure user:

```sql
CREATE USER [your.name@your-domain.com] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [your.name@your-domain.com];
ALTER ROLE db_datawriter ADD MEMBER [your.name@your-domain.com];
GRANT EXECUTE ON dbo.SearchProducts TO [your.name@your-domain.com];
```

Optional SQL username/password connection string, only if you prefer SQL auth:

```powershell
$env:DATABASE_CONNECTION_STRING = "Server=tcp:sql-dabmcp-kwcm0e.database.windows.net,1433;Initial Catalog=dabdemo;Persist Security Info=False;User ID=<sql-user>;Password=<sql-password>;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

## 9. Use the included DAB config

The ready-to-run file `dab-aca/dab-config.json` is already configured for your sample objects and this connection-string pattern:

```json
"connection-string": "@env('DATABASE_CONNECTION_STRING')"
```

Open it and confirm these values:

- `data-source.database-type` is `mssql`
- `data-source.connection-string` is `@env('DATABASE_CONNECTION_STRING')`
- `runtime.rest.enabled` is `true`
- `runtime.graphql.enabled` is `true`
- `runtime.mcp.enabled` is `true`
- `runtime.host.authentication.provider` is `AppService`
- host mode is `development` for local testing

You do not need to run `dab init` for the ready-to-run path.

If you delete `dab-config.json` and want to regenerate it manually, use:

```powershell
dab init `
  --database-type "mssql" `
  --host-mode "Development" `
  --connection-string "@env('DATABASE_CONNECTION_STRING')"
```

## 10. Confirm the sample database objects in DAB

The included `dab-config.json` already exposes:

- `Customer` -> `dbo.Customers`
- `Product` -> `dbo.Products`
- `SalesOrder` -> `dbo.SalesOrders`
- `OrderItem` -> `dbo.OrderItems`
- `CustomerOrderSummary` -> `dbo.CustomerOrderSummary`
- `SearchProducts` -> `dbo.SearchProducts` through REST only

You do not need to run `dab add` for the ready-to-run path.

For demo simplicity, these entities allow anonymous access. In production, you will tighten this later.

## 11. Validate the config

```powershell
dab validate --config .\dab-config.json
```

If validation fails:

- Confirm `$env:DATABASE_CONNECTION_STRING` is set in the same PowerShell window.
- Confirm the SQL firewall allows your current IP.
- Confirm you ran `dabdemo_sample_schema.sql` in the `dabdemo` database.
- Confirm your local Entra user or SQL user can read/write the sample tables and execute `dbo.SearchProducts`.
- If you see `Login failed for user '<token-identified principal>'. The server is not currently configured to accept this token.`, your local Entra auth is not ready for Azure SQL yet. Set a Microsoft Entra admin on SQL server `sql-dabmcp-kwcm0e`, connect as that admin, then create a contained database user for your signed-in account. If you do not want to do that yet, use the optional SQL username/password connection string for local testing.

## 12. Run DAB locally with the CLI

```powershell
dab start --config .\dab-config.json
```

By default, DAB listens on port `5000`.

Open:

```text
http://localhost:5000/
http://localhost:5000/api/swagger
http://localhost:5000/graphql
```

Test REST endpoints:

```powershell
Invoke-RestMethod "http://localhost:5000/api/Customer"
Invoke-RestMethod "http://localhost:5000/api/Product"
Invoke-RestMethod "http://localhost:5000/api/SalesOrder"
Invoke-RestMethod "http://localhost:5000/api/OrderItem"
Invoke-RestMethod "http://localhost:5000/api/CustomerOrderSummary"
Invoke-RestMethod "http://localhost:5000/api/SearchProducts"
Invoke-RestMethod "http://localhost:5000/api/SearchProducts?search=Mug"
```

Test REST filtering:

```powershell
Invoke-RestMethod "http://localhost:5000/api/Product?`$filter=Category eq 'Merch'"
```

Test GraphQL with PowerShell:

```powershell
$body = @{
  query = "{ Products { items { ProductId Sku Name Category UnitPrice } } }"
} | ConvertTo-Json

Invoke-RestMethod `
  -Uri "http://localhost:5000/graphql" `
  -Method POST `
  -ContentType "application/json" `
  -Body $body
```

The included config explicitly sets the GraphQL plural type for `Product` to `Products`, so the query uses `Products` with a capital `P`. If GraphQL still fails, open `http://localhost:5000/graphql` and inspect the generated schema. REST paths above should work from the DAB entity names.

Stop local DAB with `Ctrl+C`.

## 13. Run DAB locally with Docker

This confirms your config works inside a container before ACA.

Pull the DAB image:

```powershell
docker pull mcr.microsoft.com/azure-databases/data-api-builder:latest
```

Run with your local `dab-config.json` mounted into the container:

```powershell
docker run --rm -it `
  -p 5000:5000 `
  -v "${PWD}:/App/config" `
  -e DATABASE_CONNECTION_STRING="$env:DATABASE_CONNECTION_STRING" `
  mcr.microsoft.com/azure-databases/data-api-builder:latest `
  --ConfigFileName "/App/config/dab-config.json"
```

Open:

```text
http://localhost:5000/
http://localhost:5000/api/swagger
```

Stop with `Ctrl+C`.

## 14. Prepare config for production

Before building the container image, make these production changes to `dab-config.json`.

Change host mode from `Development` to `Production`:

```powershell
dab configure `
  --config .\dab-config.json `
  --runtime.host.mode Production
```

If you already know your front-end URL, configure CORS now. Replace `https://your-frontend-domain.com` with your real site. If you do not have a front end yet, skip this command for now.

```powershell
dab configure `
  --config .\dab-config.json `
  --runtime.host.cors.origins "https://your-frontend-domain.com" `
  --runtime.host.cors.allow-credentials false
```

For this demo, the sample entities still allow anonymous access so you can test quickly. Before exposing this to real users, change the DAB auth provider and entity permissions. The production deployment steps below still use managed identity for the database connection, so there is no SQL password in ACA.

Validate again:

```powershell
dab validate --config .\dab-config.json
```

These are the specific things you changed for production:

- `runtime.host.mode`: `Development` -> `Production`
- `runtime.host.authentication.provider`: keep `AppService` for DAB `1.7.93`
- Database connection: still `@env('DATABASE_CONNECTION_STRING')`, no secret inside `dab-config.json`
- ACA secret value: will use managed identity connection string
- Container target port: `5000`
- Ingress target app: existing ACA `temp-test`
- Optional CORS: your real front-end origin

## 15. Confirm Dockerfile and .dockerignore

The `dab-aca` folder already includes this `Dockerfile`:

```dockerfile
FROM mcr.microsoft.com/azure-databases/data-api-builder:latest
COPY dab-config.json /App/dab-config.json
CMD ["--ConfigFileName", "/App/dab-config.json"]
```

It also includes this `.dockerignore`:

```text
.git
.env
*.user
*.log
```

Build locally:

```powershell
docker build -t dab-aca:local .
```

Run your custom image locally:

```powershell
docker run --rm -it `
  -p 5000:5000 `
  -e DATABASE_CONNECTION_STRING="$env:DATABASE_CONNECTION_STRING" `
  dab-aca:local
```

Test:

```powershell
Invoke-RestMethod "http://localhost:5000/"
```

Stop with `Ctrl+C`.

## 16. Create Azure Container Registry

Choose a globally unique ACR name. ACR names can contain only letters and numbers.

```powershell
$LOCATION = (az group show --name $RESOURCE_GROUP --query location -o tsv)
$ACR_NAME = "acrdabaca$((Get-Random -Maximum 99999))"
$IMAGE_NAME = "dab-aca"
$IMAGE_TAG = "v1"

az acr create `
  --resource-group $RESOURCE_GROUP `
  --name $ACR_NAME `
  --sku Basic `
  --admin-enabled true

$ACR_LOGIN_SERVER = az acr show `
  --resource-group $RESOURCE_GROUP `
  --name $ACR_NAME `
  --query loginServer `
  -o tsv

$ACR_LOGIN_SERVER
```

Build and push image with ACR build:

```powershell
az acr build `
  --registry $ACR_NAME `
  --image "$IMAGE_NAME`:$IMAGE_TAG" `
  .
```

Your final image will be:

```powershell
$IMAGE = "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"
$IMAGE
```

## 17. Confirm the existing ACA target

Set names:

```powershell
$CONTAINER_APP_NAME = "temp-test"
```

Install/update the Container Apps extension:

```powershell
az extension add --name containerapp --upgrade
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```

Confirm the existing app:

```powershell
az containerapp show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --query "{name:name, location:location, environment:properties.environmentId, fqdn:properties.configuration.ingress.fqdn, image:properties.template.containers[0].image}" `
  -o table
```

Get the current app URL, if ingress is already enabled:

```powershell
$APP_FQDN = az containerapp show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --query properties.configuration.ingress.fqdn `
  -o tsv

$APP_URL = "https://$APP_FQDN"
$APP_URL
```

If `$APP_URL` is empty, ingress is not enabled yet. You will enable it in the deployment step.

## 18. Create production managed identity for Azure SQL

Create a user-assigned managed identity:

```powershell
$IDENTITY_NAME = "id-dab-aca-sql"

az identity create `
  --name $IDENTITY_NAME `
  --resource-group $RESOURCE_GROUP `
  --location $LOCATION

$IDENTITY_ID = az identity show `
  --name $IDENTITY_NAME `
  --resource-group $RESOURCE_GROUP `
  --query id `
  -o tsv

$IDENTITY_CLIENT_ID = az identity show `
  --name $IDENTITY_NAME `
  --resource-group $RESOURCE_GROUP `
  --query clientId `
  -o tsv

$IDENTITY_PRINCIPAL_ID = az identity show `
  --name $IDENTITY_NAME `
  --resource-group $RESOURCE_GROUP `
  --query principalId `
  -o tsv

$IDENTITY_CLIENT_ID
```

Assign it to the Container App:

```powershell
az containerapp identity assign `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --user-assigned $IDENTITY_ID
```

Now connect to `dabdemo` as the Azure SQL Microsoft Entra admin and run this SQL. It grants the managed identity access to the sample tables and stored procedure.

```sql
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_principals
    WHERE name = N'id-dab-aca-sql'
)
BEGIN
    CREATE USER [id-dab-aca-sql] FROM EXTERNAL PROVIDER;
END;

IF IS_ROLEMEMBER(N'db_datareader', N'id-dab-aca-sql') = 0
BEGIN
    ALTER ROLE db_datareader ADD MEMBER [id-dab-aca-sql];
END;

IF IS_ROLEMEMBER(N'db_datawriter', N'id-dab-aca-sql') = 0
BEGIN
    ALTER ROLE db_datawriter ADD MEMBER [id-dab-aca-sql];
END;

GRANT EXECUTE ON dbo.SearchProducts TO [id-dab-aca-sql];
```

If you make the sample API read-only later, remove `db_datawriter` and use only `db_datareader` plus `EXECUTE` on stored procedures you expose.

## 19. Deploy production image to existing ACA `temp-test`

Get ACR credentials:

```powershell
$ACR_USERNAME = az acr credential show --name $ACR_NAME --query username -o tsv
$ACR_PASSWORD = az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv
```

Configure the existing `temp-test` app so it can pull from your ACR:

```powershell
az containerapp registry set `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --server $ACR_LOGIN_SERVER `
  --username $ACR_USERNAME `
  --password $ACR_PASSWORD
```

Create the production managed identity connection string:

```powershell
$MI_CONNECTION_STRING = "Server=tcp:sql-dabmcp-kwcm0e.database.windows.net,1433;Database=dabdemo;Authentication=Active Directory Managed Identity;User Id=$IDENTITY_CLIENT_ID;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

Store the connection string as an ACA secret named `database-connection-string`:

```powershell
az containerapp secret set `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --secrets "database-connection-string=$MI_CONNECTION_STRING"
```

Update `temp-test` to run your DAB image and use the secret as `DATABASE_CONNECTION_STRING`:

```powershell
az containerapp update `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --image $IMAGE `
  --env-vars "DATABASE_CONNECTION_STRING=secretref:database-connection-string" `
  --min-replicas 0 `
  --max-replicas 3 `
  --cpu 0.5 `
  --memory 1Gi
```

Enable or update HTTP ingress for DAB port `5000`:

```powershell
az containerapp ingress enable `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --type external `
  --target-port 5000 `
  --transport auto
```

Allow Azure-hosted services to reach Azure SQL for the first production smoke test:

```powershell
az sql server firewall-rule create `
  --resource-group $RESOURCE_GROUP `
  --server $SQL_SERVER `
  --name "Allow-Azure-Services" `
  --start-ip-address 0.0.0.0 `
  --end-ip-address 0.0.0.0
```

For stricter production networking, replace this broad Azure-services rule with ACA VNet integration plus an Azure SQL private endpoint or another controlled outbound path.

Get the app URL:

```powershell
$APP_FQDN = az containerapp show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --query properties.configuration.ingress.fqdn `
  -o tsv

$APP_URL = "https://$APP_FQDN"
$APP_URL
```

Test production:

```powershell
Invoke-RestMethod "$APP_URL/"
Invoke-RestMethod "$APP_URL/api/Customer"
Invoke-RestMethod "$APP_URL/api/Product"
Invoke-RestMethod "$APP_URL/api/CustomerOrderSummary"
Invoke-RestMethod "$APP_URL/api/SearchProducts"
```

Open:

```text
https://<your-container-app-fqdn>/api/swagger
https://<your-container-app-fqdn>/graphql
```

## 20. Logs and troubleshooting

Stream logs:

```powershell
az containerapp logs show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --follow
```

Check app details:

```powershell
az containerapp show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --query "{fqdn:properties.configuration.ingress.fqdn, latestRevision:properties.latestRevisionName, provisioningState:properties.provisioningState}" `
  -o table
```

Common problems:

1. `Login failed for user`
   - SQL username/password is wrong, or managed identity database user was not created.
   - Confirm the connection string in the ACA secret.

2. `Cannot open server requested by the login`
   - Azure SQL firewall is blocking ACA.
   - For quick testing, use the `Allow-Azure-Services` firewall rule.
   - For production, configure VNet/private endpoint networking.

3. `Invalid object name`
   - The entity source is wrong.
   - Use `schema.table`, for example `dbo.Customers`.

4. Entity returns 404
   - Check the entity name in `dab-config.json`.
   - REST path is usually `/api/<EntityName>` unless you configured a custom route.

5. GraphQL query fails
   - Open `/graphql` and inspect the generated schema.
   - GraphQL names may differ from your guessed plural/singular names.

6. Config validates locally but fails in ACA
   - Confirm `DATABASE_CONNECTION_STRING` exists in ACA.
   - Confirm the image contains the latest `dab-config.json`.
   - Rebuild/push image after config changes.

## 21. Updating DAB config after deployment

If you add another entity:

```powershell
dab add NewEntity `
  --source "dbo.NewTable" `
  --source.type table `
  --permissions "anonymous:read"

dab validate --config .\dab-config.json
docker build -t dab-aca:local .
```

Push a new image tag:

```powershell
$IMAGE_TAG = "v2"
az acr build `
  --registry $ACR_NAME `
  --image "$IMAGE_NAME`:$IMAGE_TAG" `
  .

$IMAGE = "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"

az containerapp update `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --image $IMAGE
```

## 22. Security checklist before real production

Do these before exposing this beyond a demo:

1. Use managed identity instead of SQL password.
2. Grant only required database roles. Prefer `db_datareader`; add write permissions only where needed.
3. Avoid `anonymous:*` for production.
4. Configure DAB authentication with Microsoft Entra ID or another JWT provider.
5. Restrict CORS to your real front-end origins.
6. Consider placing ACA and SQL behind private networking.
7. Enable logs and Application Insights/OpenTelemetry if this API becomes important.
8. Pin the DAB base image to a tested version instead of `latest`.
9. Keep `dab-config.json` free of secrets by using `@env('DATABASE_CONNECTION_STRING')`.
10. Rotate SQL passwords if you used them during early testing.

## 23. Cleanup commands for demo resources

Only run these if you want to remove demo resources. Because this guide targets existing app `temp-test`, do not delete the Container App unless you intentionally want to remove that app.

Remove the DAB secret from `temp-test` if you no longer need it:

```powershell
az containerapp secret remove `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP `
  --secret-names database-connection-string
```

Do not delete the ACA environment unless you are certain no other apps use it.

Delete ACR:

```powershell
az acr delete `
  --name $ACR_NAME `
  --resource-group $RESOURCE_GROUP `
  --yes
```

Delete the local firewall rule:

```powershell
az sql server firewall-rule delete `
  --resource-group $RESOURCE_GROUP `
  --server $SQL_SERVER `
  --name "Allow-Local-DAB-Dev"
```

## 24. Quick command summary

Use this after you understand the detailed steps above:

```powershell
az login --tenant MngEnvMCAP797847.onmicrosoft.com
az account set --subscription 6a3bb170-5159-4bff-860b-aa74fb762697

dotnet tool install --global Microsoft.DataApiBuilder

cd dab-aca

$env:DATABASE_CONNECTION_STRING = "Server=tcp:sql-dabmcp-kwcm0e.database.windows.net,1433;Database=dabdemo;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

dab validate --config .\dab-config.json
dab start --config .\dab-config.json
```

Before `dab validate`, run `dab-aca/dabdemo_sample_schema.sql` in Azure Data Studio or SSMS against database `dabdemo`.

The Dockerfile and `.dockerignore` already exist in `dab-aca`. Build and deploy using the detailed ACA sections above.
