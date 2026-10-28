[CmdletBinding()]
param(
    [string]$EnvironmentUrl,
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($EnvironmentUrl)) {
    $EnvironmentUrl = Read-Host "Informe a URL base do ambiente Dataverse do cliente ou o endpoint completo /api/mcp"
}

$uri = $null
if (-not [Uri]::TryCreate($EnvironmentUrl.Trim(), [UriKind]::Absolute, [ref]$uri)) {
    throw "A URL do ambiente não é uma URL absoluta válida."
}

$normalizedPath = $uri.AbsolutePath.TrimEnd('/')
if ($uri.UserInfo -or $uri.Query -or $uri.Fragment) {
    throw 'Credenciais, query string e fragmento são proibidos na URL original.'
}
if ([string]::IsNullOrEmpty($normalizedPath)) {
    $endpoint = "$($uri.GetLeftPart([UriPartial]::Authority))/api/mcp"
}
elseif ($normalizedPath -ceq "/api/mcp") {
    $endpoint = "$($uri.GetLeftPart([UriPartial]::Authority))/api/mcp"
}
else {
    throw "Informe somente a URL base do ambiente ou o endpoint GA terminado em /api/mcp."
}

$validatorPath = Join-Path $WorkspaceRoot "scripts/test-dataverse-mcp-endpoint.ps1"
& $validatorPath -Endpoint $endpoint -WorkspaceRoot $WorkspaceRoot | Out-Null

Write-Host "Conexão Dataverse MCP preparada para o host: $($uri.DnsSafeHost)"
Write-Host "1. Confirme no Power Platform admin center que o Dataverse MCP e o cliente Microsoft GitHub Copilot estão habilitados."
Write-Host "2. No VS Code, execute 'MCP: List Servers' e inicie 'dataverse-mdcc'."
Write-Host "3. Quando solicitado, informe exatamente o endpoint validado: $endpoint"
Write-Host "4. Revise o host no prompt de confiança e autentique interativamente com a identidade de diagnóstico de menor privilégio."
Write-Host "5. Execute primeiro uma operação de metadados somente leitura com o MDCC Dataverse Diagnostician."
Write-Host "Nenhum endpoint, token ou credencial foi persistido pelo script."

if ($PassThru) { $endpoint }
