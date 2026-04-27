# Authentication guide

This setup uses Entra ID end to end, but local and production connect to SQL differently.

There are two separate auth flows:

```text
Client -> DAB       Entra JWT bearer token
DAB -> Azure SQL    Entra database identity
```

## Client to DAB

Clients call DAB with a bearer token:

```text
Authorization: Bearer <access-token>
```

The token must come from the same Entra tenant and must target the DAB API app registration created by Terraform.

Get a token locally:

```powershell
$SCOPE = terraform -chdir=terraform output -raw api_scope
$TOKEN = az account get-access-token --scope $SCOPE --query accessToken -o tsv
```

DAB validates:

- `iss`: must match the configured tenant issuer.
- `aud`: must match the DAB API app client ID.
- Token must represent an authenticated caller.

The DAB config maps any valid token to the built-in `authenticated` role. Because the `autoentities` permissions grant only `authenticated`, anonymous callers cannot query table data.

## DAB to SQL

Local DAB uses your signed-in Entra user:

```text
Authentication=Active Directory Default
```

Production DAB uses the Container App user-assigned managed identity:

```text
Authentication=Active Directory Managed Identity
```

Both identities are members of the Entra SQL access group created by Terraform. The database grants that group permissions.

Terraform creates the Entra group, and `scripts/Bootstrap-Sql.ps1` creates the matching contained database user:

```sql
CREATE USER [grp-...-sql-access-...] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [grp-...-sql-access-...];
ALTER ROLE db_datawriter ADD MEMBER [grp-...-sql-access-...];
```

## Who gets access

Access is granted to:

- Your current Entra user, because Terraform adds it to the SQL admin/access groups.
- The UAMI service principal, because Terraform adds it to the SQL access group.
- Any future users you add to the SQL access group, assuming they can also get a DAB API token.

For a future user to access the API, both of these must be true:

- The user can get a token for the DAB API app registration.
- The user is allowed by DAB permissions. In this repo, that means any valid authenticated token.

For a future user to run DAB locally against SQL, the user must also be added to the SQL access group or another SQL database role.

## How to make endpoints stricter

The current sample grants all actions to any authenticated caller:

```json
{
  "role": "authenticated",
  "actions": [
    { "action": "*" }
  ]
}
```

For stricter production APIs, replace `*` with explicit actions such as `read`, or define named roles and map Entra claims to those roles. You can also expose only selected entities instead of `dbo.%`.

## What is OBO?

OBO means "on-behalf-of." In OBO, an API receives a user token, exchanges it for another token to a downstream service, and the downstream service sees the user identity.

This final setup does not use OBO for SQL. It uses:

- User identity locally.
- Managed identity in production.

That matches the target you asked for: local login as your account, cloud login as UAMI.

Use OBO only if Azure SQL must see the original end user on every production request. DAB 2.0 supports OBO for Microsoft SQL, but it requires extra app registration permissions and OBO client secret environment variables. This repo intentionally keeps production runtime simpler: DAB validates the user token at the API layer, then uses the UAMI for database access.
