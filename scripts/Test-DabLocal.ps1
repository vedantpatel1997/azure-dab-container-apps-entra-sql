param(
    [string]$TerraformDirectory = (Join-Path (Join-Path $PSScriptRoot "..") "terraform"),
    [string]$ConfigFile = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "dab") "dab-config.local.json"),
    [int]$Port = 5000
)

$ErrorActionPreference = "Stop"

$outputs = terraform "-chdir=$TerraformDirectory" output -json | ConvertFrom-Json
$sqlServer = $outputs.sql_server_fqdn.value
$sqlDb = $outputs.sql_database_name.value
$scope = $outputs.api_scope.value
$configPath = (Resolve-Path $ConfigFile).Path

$env:DATABASE_CONNECTION_STRING = "Server=tcp:$sqlServer,1433;Database=$sqlDb;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

dotnet tool restore | Out-Null

$out = Join-Path $env:TEMP "dab-local-test.out.log"
$err = Join-Path $env:TEMP "dab-local-test.err.log"
Remove-Item $out, $err -ErrorAction SilentlyContinue

$arguments = @("tool", "run", "dab", "--", "start", "--config", $configPath, "--no-https-redirect")
$process = Start-Process -FilePath "dotnet" -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err

try {
    $base = "http://localhost:$Port"
    $ready = $false

    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 2

        if ($process.HasExited) {
            $stderr = Get-Content $err -Raw -ErrorAction SilentlyContinue
            throw "Local DAB exited with code $($process.ExitCode). $stderr"
        }

        try {
            $health = Invoke-WebRequest "$base/" -UseBasicParsing -TimeoutSec 5
            if ($health.StatusCode -eq 200) {
                $ready = $true
                break
            }
        }
        catch {
            # Keep waiting until DAB has opened the HTTP listener.
        }
    }

    if (-not $ready) {
        $stderr = Get-Content $err -Raw -ErrorAction SilentlyContinue
        throw "Local DAB did not become ready. $stderr"
    }

    $token = az account get-access-token --scope $scope --query accessToken -o tsv
    $headers = @{ Authorization = "Bearer $token" }
    $results = @()

    foreach ($path in @("/", "/api/openapi", "/api/dbo_Products", "/api/dbo_Customers")) {
        $response = Invoke-WebRequest "$base$path" -Headers $headers -UseBasicParsing -TimeoutSec 60
        $count = ""

        try {
            $json = $response.Content | ConvertFrom-Json
            if ($json.value) {
                $count = @($json.value).Count
            }
        }
        catch {
            $count = ""
        }

        $results += [pscustomobject]@{
            Path   = $path
            Status = $response.StatusCode
            Count  = $count
            Length = $response.Content.Length
        }
    }

    $body = @{ query = "{ dbo_Products { items { ProductId Sku Name Category UnitPrice } } }" } | ConvertTo-Json -Compress
    $graphql = Invoke-RestMethod -Uri "$base/graphql" -Method POST -ContentType "application/json" -Headers $headers -Body $body -TimeoutSec 60

    $results += [pscustomobject]@{
        Path   = "/graphql dbo_Products"
        Status = 200
        Count  = @($graphql.data.dbo_Products.items).Count
        Length = ""
    }

    try {
        Invoke-WebRequest "$base/api/dbo_Products" -UseBasicParsing -TimeoutSec 30 | Out-Null
        $unauthenticatedStatus = "Unexpected success"
    }
    catch {
        $unauthenticatedStatus = $_.Exception.Response.StatusCode.value__
    }

    $results | Format-Table -AutoSize
    Write-Host "Unauthenticated /api/dbo_Products status: $unauthenticatedStatus"
}
finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
}
