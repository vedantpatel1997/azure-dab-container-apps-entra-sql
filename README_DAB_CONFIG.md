# DAB config guide

The DAB project is in:

```text
dab/
```

Tracked source files:

```text
dab/Dockerfile
dab/dab-config.json.tftpl
dab/dab-config.local.json.tftpl
dab/dabdemo_sample_schema.sql
```

Generated files:

```text
dab/dab-config.json
dab/dab-config.local.json
```

The generated config files are ignored by git because they contain environment-specific values from Terraform outputs.

## Version

This repo pins DAB `2.0.0-rc` in:

```text
dab/Dockerfile
dotnet-tools.json
dab/dab-config*.json.tftpl schema URLs
```

Reason: DAB 2.0 adds the `autoentities` configuration used here. The latest stable NuGet package is `1.7.93`, but the latest prerelease package is `2.0.0-rc`.

## Why production config looks this way

Production uses:

```json
"connection-string": "@akv('sql-connection-string')"
```

DAB resolves that value from Key Vault at startup. The secret contains a managed identity SQL connection string:

```text
Authentication=Active Directory Managed Identity;User Id=<uami-client-id>
```

This keeps SQL credentials out of the image and out of git. The Container App UAMI has `Get/List` access to Key Vault and is also a member of the SQL access group.

The API auth section tells DAB to accept only Entra JWTs from this tenant and API app:

```json
"authentication": {
  "provider": "EntraId",
  "jwt": {
    "audience": "<api-app-client-id>",
    "issuer": "https://login.microsoftonline.com/<tenant-id>/v2.0"
  }
}
```

The `autoentities` section exposes all `dbo` objects and grants access only to the DAB role named `authenticated`:

```json
"role": "authenticated"
```

That means anonymous callers cannot read table data.

## Config anatomy

`data-source` says DAB connects to Azure SQL.

`runtime.rest.path` exposes REST under `/api`.

`runtime.graphql.path` exposes GraphQL under `/graphql`.

`runtime.mcp.path` enables MCP under `/mcp`.

`runtime.host.authentication` tells DAB to validate Entra JWTs.

`autoentities` tells DAB to discover all matching `dbo` objects at startup and expose them with the entity name pattern `dbo_<object>`.

`azure-key-vault` tells DAB where to resolve `@akv(...)` secrets in production.

## Local config differences

Local config uses:

```json
"connection-string": "@env('DATABASE_CONNECTION_STRING')"
```

The local connection string uses:

```text
Authentication=Active Directory Default
```

So local SQL access follows your current Azure CLI or developer credential.

## Generate configs

After Terraform apply:

```powershell
.\scripts\Render-DabConfig.ps1
```

This reads Terraform outputs and writes:

```text
dab/dab-config.json
dab/dab-config.local.json
```
