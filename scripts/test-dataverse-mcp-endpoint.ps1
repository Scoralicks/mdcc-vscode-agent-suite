[CmdletBinding()]
param(
    [string]$Endpoint,
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    $Endpoint = Read-Host "Informe o endpoint completo do Dataverse MCP"
}

$policyPath = Join-Path $WorkspaceRoot "config/dataverse-mcp-policy.json"
$policy = Get-Content -Raw -LiteralPath $policyPath -Encoding UTF8 | ConvertFrom-Json

$uri = $null
if (-not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri)) {
    throw "O endpoint não é uma URL absoluta válida."
}

if ($uri.Scheme -ne $policy.connection.requiredScheme) {
    throw "Esquema rejeitado. Use somente $($policy.connection.requiredScheme)."
}

if (-not $uri.IsDefaultPort -and $uri.Port -ne 443) {
    throw "Porta rejeitada. Use a porta HTTPS padrão."
}

if (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
    throw "Credenciais embutidas na URL são proibidas."
}

if (-not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "Query string e fragmento não são permitidos no endpoint MCP."
}

if ($uri.AbsolutePath -ne $policy.connection.allowedPath) {
    throw "Caminho rejeitado. O caminho permitido é $($policy.connection.allowedPath)."
}

$hostAllowed = $false
foreach ($pattern in @($policy.connection.allowedHostPatterns)) {
    if ($uri.DnsSafeHost -cmatch $pattern) {
        $hostAllowed = $true
        break
    }
}

if (-not $hostAllowed) {
    throw "Host rejeitado pela allowlist em config/dataverse-mcp-policy.json."
}

Write-Host "Endpoint Dataverse MCP validado: $($uri.Scheme)://$($uri.DnsSafeHost)$($uri.AbsolutePath)"
