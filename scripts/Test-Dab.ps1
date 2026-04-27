param(
    [string]$TerraformDirectory = (Join-Path (Join-Path $PSScriptRoot "..") "terraform"),
    [string]$BaseUrl,
    [string]$ApiScope
)

$ErrorActionPreference = "Stop"

if (-not $BaseUrl -or -not $ApiScope) {
    $outputs = terraform "-chdir=$TerraformDirectory" output -json | ConvertFrom-Json
    $resourceGroup = $outputs.resource_group_name.value
    $containerApp = $outputs.container_app_name.value
    $ApiScope = $outputs.api_scope.value
    $fqdn = az containerapp show --name $containerApp --resource-group $resourceGroup --query properties.configuration.ingress.fqdn -o tsv
    $BaseUrl = "https://$fqdn"
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$token = az account get-access-token --scope $ApiScope --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

$results = @()
foreach ($path in @("/", "/api/openapi", "/api/dbo_Products", "/api/dbo_Customers")) {
    $response = Invoke-WebRequest "$BaseUrl$path" -Headers $headers -UseBasicParsing -TimeoutSec 60
    $count = ""
    try {
        $json = $response.Content | ConvertFrom-Json
        if ($json.value) {
            $count = @($json.value).Count
        }
    } catch {
        $count = ""
    }
    $results += [pscustomobject]@{
        Path = $path
        Status = $response.StatusCode
        Count = $count
        Length = $response.Content.Length
    }
}

$body = @{ query = "{ dbo_Products { items { ProductId Sku Name Category UnitPrice } } }" } | ConvertTo-Json -Compress
$graphql = Invoke-RestMethod -Uri "$BaseUrl/graphql" -Method POST -ContentType "application/json" -Headers $headers -Body $body -TimeoutSec 60
$results += [pscustomobject]@{
    Path = "/graphql dbo_Products"
    Status = 200
    Count = @($graphql.data.dbo_Products.items).Count
    Length = ""
}

$results | Format-Table -AutoSize

try {
    Invoke-WebRequest "$BaseUrl/api/dbo_Products" -UseBasicParsing -TimeoutSec 30 | Out-Null
    $unauthenticatedStatus = "Unexpected success"
}
catch {
    $unauthenticatedStatus = $_.Exception.Response.StatusCode.value__
}

Write-Host "Unauthenticated /api/dbo_Products status: $unauthenticatedStatus"
