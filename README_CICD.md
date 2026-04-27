# CI/CD guide

Terraform is run locally only. GitHub Actions deploys DAB only.

## DAB deployment workflow

`.github/workflows/deploy-dab.yml`:

- Renders DAB config from GitHub variables.
- Builds the DAB image in ACR.
- Updates the Container App image.
- Sets `AZURE_CLIENT_ID` so DAB can resolve Key Vault using the UAMI.

Required GitHub secrets:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

Required GitHub variables:

```text
AZURE_ACR_NAME
AZURE_ACR_LOGIN_SERVER
AZURE_CONTAINER_APP_NAME
AZURE_RESOURCE_GROUP
AZURE_UAMI_CLIENT_ID
DAB_API_AUDIENCE
DAB_JWT_ISSUER
DAB_KEY_VAULT_URI
```

You can get the values from:

```powershell
terraform -chdir=terraform output
```
