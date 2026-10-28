[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$package = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot "package.json") | ConvertFrom-Json
Assert-True ($package.devDependencies.'@playwright/test' -match '^\d+\.\d+\.\d+$') "@playwright/test must use an exact version."
Assert-True ($package.devDependencies.'@playwright/mcp' -match '^\d+\.\d+\.\d+$') "@playwright/mcp must use an exact version."
Assert-True (Test-Path -LiteralPath (Join-Path $WorkspaceRoot "package-lock.json")) "package-lock.json is required."

$configText = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot "config/playwright-mcp.config.json")
$config = $configText | ConvertFrom-Json
Assert-True ($config.browser.isolated -eq $true) "Playwright MCP must use an isolated browser context."
Assert-True ($config.browser.contextOptions.acceptDownloads -eq $false) "Downloads must be disabled."
Assert-True ($config.browser.contextOptions.ignoreHTTPSErrors -eq $false) "TLS validation must remain enabled."
Assert-True ($config.saveSession -eq $false) "MCP sessions must not be persisted."
Assert-True ($config.allowUnrestrictedFileAccess -eq $false) "Unrestricted file access must remain disabled."

$mcpText = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot ".vscode/mcp.json")
Assert-True ($mcpText -match 'playwright-mdcc') "The Playwright MCP server is missing."
foreach ($unsafe in @('--no-sandbox', '--ignore-https-errors', '--allow-unrestricted-file-access', '--extension', '0\.0\.0\.0')) {
    Assert-True ($mcpText -notmatch $unsafe) "Unsafe Playwright MCP option found: $unsafe"
}

$gitignore = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot ".gitignore")
foreach ($ignored in @('node_modules/', 'playwright/.auth/', 'playwright-report/', 'test-results/', '.playwright-output/', '*.har')) {
    Assert-True ($gitignore.Contains($ignored)) "Sensitive/generated path is not ignored: $ignored"
}

Write-Host "Playwright guardrails validated successfully."
