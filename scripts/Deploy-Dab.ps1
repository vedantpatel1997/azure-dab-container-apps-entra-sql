param(
    [string]$TerraformDirectory = (Join-Path (Join-Path $PSScriptRoot "..") "terraform"),
    [string]$DabDirectory = (Join-Path (Join-Path $PSScriptRoot "..") "dab"),
    [string]$ImageTag = "latest"
)

$ErrorActionPreference = "Stop"

& "$PSScriptRoot\Render-DabConfig.ps1" -TerraformDirectory $TerraformDirectory -DabDirectory $DabDirectory

$outputs = terraform "-chdir=$TerraformDirectory" output -json | ConvertFrom-Json
$acrLogin = $outputs.acr_login_server.value
$acrName = $acrLogin.Split(".")[0]
$resourceGroup = $outputs.resource_group_name.value
$containerApp = $outputs.container_app_name.value
$uamiClientId = $outputs.uami_client_id.value

az acr build `
    --registry $acrName `
    --resource-group $resourceGroup `
    --image "vkp-dab-api:$ImageTag" `
    $DabDirectory
if ($LASTEXITCODE -ne 0) {
    throw "ACR build failed with exit code $LASTEXITCODE"
}

az containerapp update `
    --name $containerApp `
    --resource-group $resourceGroup `
    --image "$acrLogin/vkp-dab-api:$ImageTag" `
    --set-env-vars "AZURE_CLIENT_ID=$uamiClientId"
if ($LASTEXITCODE -ne 0) {
    throw "Container App update failed with exit code $LASTEXITCODE"
}

Write-Host "Deployed $acrLogin/vkp-dab-api:$ImageTag to $containerApp"
