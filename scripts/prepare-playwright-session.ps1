[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentUrl,
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$uri = $null
if (-not [Uri]::TryCreate($EnvironmentUrl, [UriKind]::Absolute, [ref]$uri)) {
    throw "EnvironmentUrl must be an absolute URL."
}
if ($uri.Scheme -ne "https" -or -not $uri.Host -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
    throw "Use an HTTPS origin without credentials, query string, or fragment."
}

$packagePath = Join-Path $WorkspaceRoot "package.json"
$lockPath = Join-Path $WorkspaceRoot "package-lock.json"
if (-not (Test-Path -LiteralPath $packagePath) -or -not (Test-Path -LiteralPath $lockPath)) {
    throw "Playwright manifests are missing. Extract the complete package first."
}

$nodeVersion = (& node --version 2>$null)
if ($LASTEXITCODE -ne 0) { throw "Node.js was not found. Install a supported Node.js version." }

$mcpCli = Join-Path $WorkspaceRoot "node_modules/@playwright/mcp/cli.js"
if (-not (Test-Path -LiteralPath $mcpCli)) {
    throw "Dependencies are not installed. Run the task 'MDCC: Install Playwright dependencies'."
}

Write-Host "Playwright session preflight passed."
Write-Host "Node: $nodeVersion"
Write-Host "Approved origin: $($uri.GetLeftPart([UriPartial]::Authority))"
Write-Host "Start playwright-mdcc and enter this exact origin when VS Code prompts for the allowed origin."
Write-Warning "Authenticate only in the isolated browser window. Do not paste credentials into chat."
