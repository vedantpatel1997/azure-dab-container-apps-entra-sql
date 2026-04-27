param(
    [string]$TerraformDirectory = "$PSScriptRoot\..\terraform",
    [string]$DabDirectory = "$PSScriptRoot\..\dab",
    [string]$ApiAudience,
    [string]$JwtIssuer,
    [string]$KeyVaultUri
)

$ErrorActionPreference = "Stop"

function Get-OutputValue {
    param([object]$Outputs, [string]$Name)
    if ($Outputs.PSObject.Properties.Name -contains $Name) {
        return $Outputs.$Name.value
    }
    return $null
}

if (-not $ApiAudience -or -not $JwtIssuer -or -not $KeyVaultUri) {
    $outputsJson = terraform "-chdir=$TerraformDirectory" output -json
    $outputs = $outputsJson | ConvertFrom-Json

    if (-not $ApiAudience) { $ApiAudience = Get-OutputValue $outputs "api_audience" }
    if (-not $JwtIssuer) { $JwtIssuer = Get-OutputValue $outputs "jwt_issuer" }
    if (-not $KeyVaultUri) { $KeyVaultUri = Get-OutputValue $outputs "key_vault_uri" }
}

if (-not $ApiAudience -or -not $JwtIssuer -or -not $KeyVaultUri) {
    throw "Missing ApiAudience, JwtIssuer, or KeyVaultUri. Run Terraform first or pass all three parameters."
}

$replacements = @{
    '${api_audience}' = $ApiAudience
    '${jwt_issuer}' = $JwtIssuer
    '${key_vault_uri}' = $KeyVaultUri
}

foreach ($item in @(
    @{ Template = "dab-config.json.tftpl"; Output = "dab-config.json" },
    @{ Template = "dab-config.local.json.tftpl"; Output = "dab-config.local.json" }
)) {
    $content = Get-Content -Raw -Path (Join-Path $DabDirectory $item.Template)
    foreach ($key in $replacements.Keys) {
        $content = $content.Replace($key, $replacements[$key])
    }
    Set-Content -Path (Join-Path $DabDirectory $item.Output) -Value $content -Encoding ascii
}

Write-Host "Rendered DAB configs in $DabDirectory"
