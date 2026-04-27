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

## Why production config looks this way

Production uses:

```json
"connection-string": "@akv('sql-connection-string')"
```

DAB resolves that value from Key Vault at startup. The secret contains a managed identity SQL connection string:

```text
Authentication=Active Directory Managed Identity;User Id=<uami-client-id>
```

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

