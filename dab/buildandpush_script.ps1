param(
    [string]$SubscriptionId = "6a3bb170-5159-4bff-860b-aa74fb762697",
    [string]$AcrName = "acrvpdabdemo",
    [string]$Repository = "vkp-dab-api",
    [string]$ResourceGroup = "rg-vp-dabdemo",
    [string]$ContainerAppName = "ca-vp-dabdemo",
    [string]$DockerfilePath = "."
)

Write-Host "Setting Azure subscription..."
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set Azure subscription."
    exit 1
}

Write-Host "Getting ACR login server..."
$acrLoginServer = az acr show `
    --name $AcrName `
    --resource-group $ResourceGroup `
    --query "loginServer" `
    -o tsv

if (-not $acrLoginServer) {
    Write-Error "ACR not found."
    exit 1
}

Write-Host "ACR Login Server: $acrLoginServer"

Write-Host "Logging into ACR..."
# Keeping RG as requested
az acr login --name $AcrName --resource-group $ResourceGroup
if ($LASTEXITCODE -ne 0) {
    Write-Error "ACR login failed."
    exit 1
}

# UTC datetime tag
$Tag = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")

$ImageName = "${acrLoginServer}/${Repository}:${Tag}"
$LatestImage = "${acrLoginServer}/${Repository}:latest"

Write-Host "Using Tag: $Tag"
Write-Host "Image: $ImageName"

Write-Host "Building Docker image..."
docker build -t $ImageName $DockerfilePath
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed."
    exit 1
}

Write-Host "Pushing Docker image..."
docker push $ImageName
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker push failed."
    exit 1
}

Write-Host "Tagging image as latest..."
docker tag $ImageName $LatestImage
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker tag latest failed."
    exit 1
}

Write-Host "Pushing latest image..."
docker push $LatestImage
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker push latest failed."
    exit 1
}

Write-Host "Updating Container App image..."
az containerapp update `
    --name $ContainerAppName `
    --resource-group $ResourceGroup `
    --image $ImageName

if ($LASTEXITCODE -ne 0) {
    Write-Error "Container App update failed."
    exit 1
}

Write-Host "Container App updated successfully."
Write-Host "Container App: $ContainerAppName"
Write-Host "Deployed Image: $ImageName"
Write-Host "Latest Image: $LatestImage"