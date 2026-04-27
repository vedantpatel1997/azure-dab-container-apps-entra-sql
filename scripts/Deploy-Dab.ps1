param(
    [string]$TerraformDirectory = "$PSScriptRoot\..\terraform",
    [string]$DabDirectory = "$PSScriptRoot\..\dab",
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

az acr build --registry $acrName --image "dab-api:$ImageTag" $DabDirectory

az containerapp update `
    --name $containerApp `
    --resource-group $resourceGroup `
    --image "$acrLogin/dab-api:$ImageTag" `
    --set-env-vars "AZURE_CLIENT_ID=$uamiClientId"

Write-Host "Deployed $acrLogin/dab-api:$ImageTag to $containerApp"
