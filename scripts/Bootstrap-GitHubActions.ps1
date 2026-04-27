param(
    [string]$Repository = "vedantpatel1997/azure-dab-container-apps-entra-sql",
    [string]$SubscriptionId = "6a3bb170-5159-4bff-860b-aa74fb762697",
    [string]$TenantId = "be945e7a-2e17-4b44-926f-512e85873eec",
    [string]$Location = "westus3",
    [string]$StateResourceGroup = "rg-dabsecure-tfstate",
    [string]$StateStorageAccount = "stdabsecuretf797847",
    [string]$StateContainer = "tfstate",
    [string]$StateKey = "dabsecure.tfstate",
    [string]$OidcAppName = "github-dabsecure-oidc"
)

$ErrorActionPreference = "Stop"

function Invoke-GitHubApi {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body,
        [string]$Token
    )

    $headers = @{
        Authorization          = "Bearer $Token"
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
    }

    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body ($Body | ConvertTo-Json -Depth 20 -Compress) -ContentType "application/json"
}

function Get-GitHubToken {
    $credential = @"
protocol=https
host=github.com

"@ | git credential fill

    $passwordLine = $credential | Where-Object { $_ -like "password=*" } | Select-Object -First 1
    if (-not $passwordLine) {
        return $null
    }

    return $passwordLine.Substring("password=".Length)
}

$owner, $repoName = $Repository.Split("/", 2)
if (-not $owner -or -not $repoName) {
    throw "Repository must be in owner/name format."
}

az account set --subscription $SubscriptionId

az group create --name $StateResourceGroup --location $Location | Out-Null

$storageExists = az storage account check-name --name $StateStorageAccount | ConvertFrom-Json
if ($storageExists.nameAvailable) {
    az storage account create `
        --name $StateStorageAccount `
        --resource-group $StateResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --allow-blob-public-access false `
        --min-tls-version TLS1_2 | Out-Null
}

$accountId = az storage account show --name $StateStorageAccount --resource-group $StateResourceGroup --query id -o tsv

az storage container create `
    --account-name $StateStorageAccount `
    --name $StateContainer `
    --auth-mode login | Out-Null

$app = az ad app list --display-name $OidcAppName --query "[0]" -o json | ConvertFrom-Json
if (-not $app) {
    $app = az ad app create --display-name $OidcAppName -o json | ConvertFrom-Json
}

$clientId = $app.appId
$appObjectId = $app.id

$sp = az ad sp list --filter "appId eq '$clientId'" --query "[0]" -o json | ConvertFrom-Json
if (-not $sp) {
    $sp = az ad sp create --id $clientId -o json | ConvertFrom-Json
}

$spObjectId = $sp.id
$subscriptionScope = "/subscriptions/$SubscriptionId"

foreach ($role in @("Contributor", "User Access Administrator")) {
    $existing = az role assignment list --assignee $clientId --role $role --scope $subscriptionScope --query "[0].id" -o tsv
    if (-not $existing) {
        az role assignment create --assignee $clientId --role $role --scope $subscriptionScope | Out-Null
    }
}

$existingBlobRole = az role assignment list --assignee $clientId --role "Storage Blob Data Contributor" --scope $accountId --query "[0].id" -o tsv
if (-not $existingBlobRole) {
    az role assignment create --assignee $clientId --role "Storage Blob Data Contributor" --scope $accountId | Out-Null
}

$graphSp = az ad sp show --id "00000003-0000-0000-c000-000000000000" -o json | ConvertFrom-Json
$graphRoles = @("Application.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All")

foreach ($roleValue in $graphRoles) {
    $role = $graphSp.appRoles | Where-Object { $_.value -eq $roleValue -and $_.allowedMemberTypes -contains "Application" } | Select-Object -First 1
    if (-not $role) {
        throw "Could not find Microsoft Graph app role $roleValue."
    }

    $assignmentBody = @{
        principalId = $spObjectId
        resourceId  = $graphSp.id
        appRoleId   = $role.id
    }
    $assignmentPath = Join-Path $env:TEMP "github-dabsecure-$roleValue.json"
    Set-Content -Path $assignmentPath -Value ($assignmentBody | ConvertTo-Json -Compress) -Encoding ascii

    try {
        az rest `
            --method POST `
            --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spObjectId/appRoleAssignments" `
            --headers "Content-Type=application/json" `
            --body "@$assignmentPath" | Out-Null
    }
    catch {
        if ($_.Exception.Message -notmatch "Permission being assigned already exists|already exists") {
            throw
        }
    }
}

$federatedName = "github-main"
$subject = "repo:${Repository}:ref:refs/heads/main"
$federatedCredentials = az ad app federated-credential list --id $appObjectId -o json | ConvertFrom-Json
$existingFederatedCredential = $federatedCredentials | Where-Object { $_.name -eq $federatedName } | Select-Object -First 1
$federatedCredentialPath = Join-Path $env:TEMP "github-dabsecure-federated.json"

$federatedCredential = @{
    name        = $federatedName
    issuer      = "https://token.actions.githubusercontent.com"
    subject     = $subject
    audiences   = @("api://AzureADTokenExchange")
    description = "GitHub Actions main branch for $Repository"
}

Set-Content -Path $federatedCredentialPath -Value ($federatedCredential | ConvertTo-Json -Depth 10) -Encoding ascii

if ($existingFederatedCredential) {
    az ad app federated-credential update --id $appObjectId --federated-credential-id $existingFederatedCredential.id --parameters "@$federatedCredentialPath" | Out-Null
}
else {
    az ad app federated-credential create --id $appObjectId --parameters "@$federatedCredentialPath" | Out-Null
}

$githubToken = Get-GitHubToken
if ($githubToken) {
    $variables = @{
        AZURE_CLIENT_ID             = $clientId
        AZURE_TENANT_ID             = $TenantId
        AZURE_SUBSCRIPTION_ID       = $SubscriptionId
        TF_STATE_RESOURCE_GROUP     = $StateResourceGroup
        TF_STATE_STORAGE_ACCOUNT    = $StateStorageAccount
        TF_STATE_CONTAINER          = $StateContainer
        TF_STATE_KEY                = $StateKey
    }

    foreach ($name in $variables.Keys) {
        $uri = "https://api.github.com/repos/$Repository/actions/variables/$name"
        try {
            Invoke-GitHubApi -Method PATCH -Uri $uri -Token $githubToken -Body @{ name = $name; value = $variables[$name] } | Out-Null
        }
        catch {
            Invoke-GitHubApi -Method POST -Uri "https://api.github.com/repos/$Repository/actions/variables" -Token $githubToken -Body @{ name = $name; value = $variables[$name] } | Out-Null
        }
    }

    Write-Host "Updated GitHub Actions variables for $Repository."
}
else {
    Write-Host "GitHub token was not available from git credential manager. Set these repository variables manually:"
}

Write-Host "AZURE_CLIENT_ID=$clientId"
Write-Host "AZURE_TENANT_ID=$TenantId"
Write-Host "AZURE_SUBSCRIPTION_ID=$SubscriptionId"
Write-Host "TF_STATE_RESOURCE_GROUP=$StateResourceGroup"
Write-Host "TF_STATE_STORAGE_ACCOUNT=$StateStorageAccount"
Write-Host "TF_STATE_CONTAINER=$StateContainer"
Write-Host "TF_STATE_KEY=$StateKey"
