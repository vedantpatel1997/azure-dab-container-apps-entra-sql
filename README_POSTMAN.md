# Postman guide

Use Postman to call the production DAB API with an Entra bearer token.

## Values to collect

From PowerShell:

```powershell
terraform -chdir=terraform output -raw container_app_url
terraform -chdir=terraform output -raw api_scope
terraform -chdir=terraform output -raw api_audience
terraform -chdir=terraform output -raw jwt_issuer
```

You need:

- Base URL: `container_app_url`
- Scope: `api_scope`
- Tenant ID: `be945e7a-2e17-4b44-926f-512e85873eec`

For the validated environment from this run:

```text
baseUrl = https://ca-dabsecure-0xp5me.grayflower-181e28a2.westus3.azurecontainerapps.io
scope = api://app-dabsecure-api-0xp5me/access_as_user
audience = cecb2dfe-978c-4f44-80d8-10ab42103edb
```

## Create environment

Create a Postman environment with:

```text
baseUrl = https://<container-app-fqdn>
tenantId = be945e7a-2e17-4b44-926f-512e85873eec
scope = api://<api-app-name>/access_as_user
```

## Configure Authorization

In a request or collection:

```text
Type: OAuth 2.0
Grant Type: Authorization Code
Auth URL: https://login.microsoftonline.com/{{tenantId}}/oauth2/v2.0/authorize
Access Token URL: https://login.microsoftonline.com/{{tenantId}}/oauth2/v2.0/token
Scope: {{scope}}
Client Authentication: Send client credentials in body
```

For an interactive user flow, register a Postman client app or use an approved client application. Add this redirect URI to that client app registration:

```text
https://oauth.pstmn.io/v1/callback
```

Then grant that client app delegated access to the DAB API scope:

```text
API permissions -> Add a permission -> My APIs -> DAB API app -> access_as_user
```

For local quick testing without a separate Postman app registration, you can also paste a token from Azure CLI into Postman:

```powershell
$SCOPE = terraform -chdir=terraform output -raw api_scope
az account get-access-token --scope $SCOPE --query accessToken -o tsv
```

In Postman, set `Authorization` type to `Bearer Token` and paste the token.

Then request a token and send it as:

```text
Authorization: Bearer <token>
```

## Requests

Health:

```text
GET {{baseUrl}}/
```

Products:

```text
GET {{baseUrl}}/api/dbo_Products
```

Customers:

```text
GET {{baseUrl}}/api/dbo_Customers
```

OpenAPI:

```text
GET {{baseUrl}}/api/openapi
```

GraphQL:

```text
POST {{baseUrl}}/graphql
Content-Type: application/json
```

Body:

```json
{
  "query": "{ dbo_Products { items { ProductId Sku Name Category UnitPrice } } }"
}
```

## Expected behavior

Without a token, data endpoints return `403` or `401`.

With a valid token, `dbo_Products` returns 4 rows and `dbo_Customers` returns 3 rows after the sample schema has been bootstrapped.
