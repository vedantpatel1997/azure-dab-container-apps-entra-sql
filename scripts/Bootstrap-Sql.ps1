param(
    [string]$TerraformDirectory = (Join-Path (Join-Path $PSScriptRoot "..") "terraform"),
    [string]$SchemaFile = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "dab") "dabdemo_sample_schema.sql")
)

$ErrorActionPreference = "Stop"

$outputs = terraform "-chdir=$TerraformDirectory" output -json | ConvertFrom-Json
$server = $outputs.sql_server_fqdn.value
$database = $outputs.sql_database_name.value
$groupName = $outputs.sql_access_group.value
$schemaPath = (Resolve-Path $SchemaFile).Path

$work = Join-Path $env:TEMP "dab-sql-bootstrap"
if (Test-Path $work) {
    Remove-Item $work -Recurse -Force
}

dotnet new console --output $work | Out-Null
dotnet add $work package Microsoft.Data.SqlClient --version 6.1.3 | Out-Null

$program = @'
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

if (args.Length < 4)
{
    Console.Error.WriteLine("Usage: <server> <database> <schemaFile> <groupName>");
    return 2;
}

var server = args[0];
var database = args[1];
var schemaFile = args[2];
var groupName = args[3];
var token = Environment.GetEnvironmentVariable("SQL_ACCESS_TOKEN");

if (string.IsNullOrWhiteSpace(token))
{
    Console.Error.WriteLine("SQL_ACCESS_TOKEN was not set.");
    return 2;
}

var cs = $"Server=tcp:{server},1433;Database={database};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;";
await using var conn = new SqlConnection(cs) { AccessToken = token };
await conn.OpenAsync();

async Task ExecuteBatch(string sql)
{
    if (string.IsNullOrWhiteSpace(sql)) return;
    await using var cmd = conn.CreateCommand();
    cmd.CommandTimeout = 180;
    cmd.CommandText = sql;
    await cmd.ExecuteNonQueryAsync();
}

var script = await File.ReadAllTextAsync(schemaFile);
var batches = Regex.Split(script, @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);
foreach (var batch in batches)
{
    await ExecuteBatch(batch);
}

var escapedGroup = groupName.Replace("]", "]]", StringComparison.Ordinal);
var escapedLiteral = groupName.Replace("'", "''", StringComparison.Ordinal);
var grantSql = $@"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'{escapedLiteral}')
BEGIN
  CREATE USER [{escapedGroup}] FROM EXTERNAL PROVIDER;
END;
ALTER ROLE db_datareader ADD MEMBER [{escapedGroup}];
ALTER ROLE db_datawriter ADD MEMBER [{escapedGroup}];
GRANT EXECUTE ON dbo.SearchProducts TO [{escapedGroup}];
";
await ExecuteBatch(grantSql);

await using var verify = conn.CreateCommand();
verify.CommandText = "SELECT 'Customers', COUNT(*) FROM dbo.Customers UNION ALL SELECT 'Products', COUNT(*) FROM dbo.Products UNION ALL SELECT 'SalesOrders', COUNT(*) FROM dbo.SalesOrders UNION ALL SELECT 'OrderItems', COUNT(*) FROM dbo.OrderItems";
await using var reader = await verify.ExecuteReaderAsync();
while (await reader.ReadAsync())
{
    Console.WriteLine($"{reader.GetString(0)}={reader.GetInt32(1)}");
}

return 0;
'@

Set-Content -Path (Join-Path $work "Program.cs") -Value $program -Encoding UTF8

$env:SQL_ACCESS_TOKEN = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv

$lastError = $null
for ($attempt = 1; $attempt -le 6; $attempt++) {
    try {
        dotnet run --project $work -- $server $database $schemaPath $groupName
        $lastError = $null
        break
    }
    catch {
        $lastError = $_
        if ($attempt -eq 6) {
            break
        }

        Write-Host "SQL bootstrap attempt $attempt failed. Waiting for Entra/SQL permission propagation..."
        Start-Sleep -Seconds 30
        $env:SQL_ACCESS_TOKEN = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
    }
}

if ($lastError) {
    throw $lastError
}
