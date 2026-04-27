# Auth guide

This setup uses Entra ID end to end, but local and production connect to SQL differently.

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

## Who gets access

Access is granted to:

- Your current Entra user, because Terraform adds it to the SQL admin/access groups.
- The UAMI service principal, because Terraform adds it to the SQL access group.
- Any future users you add to the SQL access group, assuming they can also get a DAB API token.

## What is OBO?

OBO means "on-behalf-of." In OBO, an API receives a user token, exchanges it for another token to a downstream service, and the downstream service sees the user identity.

This final setup does not use OBO for SQL. It uses:

- User identity locally.
- Managed identity in production.

That matches the target you asked for: local login as your account, cloud login as UAMI.

