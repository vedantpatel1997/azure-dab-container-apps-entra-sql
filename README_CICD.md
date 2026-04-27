# CI/CD guide

GitHub Actions can run the full automation:

1. Terraform creates, destroys, or recreates infrastructure.
2. SQL bootstrap loads schema and grants database permissions.
3. DAB image deployment builds in ACR and updates Container Apps.
4. Production tests call REST, OpenAPI, GraphQL, and anonymous-deny checks.

## Bootstrap GitHub automation

Run this once from a machine where you are signed in to Azure and GitHub:

```powershell
.\scripts\Bootstrap-GitHubActions.ps1
```

It creates:

- Azure Storage remote Terraform state.
- GitHub OIDC Entra app registration and service principal.
- Federated credential for the `main` branch.
- Azure RBAC for subscription deployment and state access.
- Microsoft Graph app permissions needed by the Terraform AzureAD provider.
- GitHub Actions variables.

The workflow uses GitHub repository variables instead of secrets because OIDC does not need a client secret.

## Infra workflow

`.github/workflows/infra.yml` supports:

```text
plan
apply
destroy
recreate
```

`recreate` runs `terraform destroy -auto-approve` and then `terraform apply -auto-approve` from the same remote state.

On push to `main`, the infra workflow applies Terraform automatically.

## DAB deployment workflow

`.github/workflows/deploy-dab.yml`:

- Renders DAB config from GitHub variables.
- Builds the DAB image in ACR.
- Updates the Container App image.
- Sets `AZURE_CLIENT_ID` so DAB can resolve Key Vault using the UAMI.
- Runs production endpoint tests.

It runs automatically after a successful `infra` workflow.

Required GitHub variables created by the bootstrap script:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
TF_STATE_RESOURCE_GROUP
TF_STATE_STORAGE_ACCOUNT
TF_STATE_CONTAINER
TF_STATE_KEY
```

Variables updated by the infra workflow after apply:

```text
AZURE_ACR_NAME
AZURE_ACR_LOGIN_SERVER
AZURE_CONTAINER_APP_NAME
AZURE_CONTAINER_APP_URL
AZURE_RESOURCE_GROUP
AZURE_UAMI_CLIENT_ID
DAB_API_AUDIENCE
DAB_API_SCOPE
DAB_JWT_ISSUER
DAB_KEY_VAULT_URI
```

You can get the values from:

```powershell
terraform -chdir=terraform output
```

Typical variable mapping:

```text
AZURE_ACR_NAME            acrdabsecure0xp5me
AZURE_ACR_LOGIN_SERVER    acrdabsecure0xp5me.azurecr.io
AZURE_CONTAINER_APP_NAME  ca-dabsecure-0xp5me
AZURE_RESOURCE_GROUP      rg-dabsecure-0xp5me
AZURE_UAMI_CLIENT_ID      terraform output -raw uami_client_id
DAB_API_AUDIENCE          terraform output -raw api_audience
DAB_API_SCOPE             terraform output -raw api_scope
DAB_JWT_ISSUER            terraform output -raw jwt_issuer
DAB_KEY_VAULT_URI         terraform output -raw key_vault_uri
```
