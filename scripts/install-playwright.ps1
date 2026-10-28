[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Push-Location $WorkspaceRoot
try {
    & npm ci --ignore-scripts
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed." }
    & npx playwright install chromium
    if ($LASTEXITCODE -ne 0) { throw "Playwright Chromium installation failed." }
    & (Join-Path $WorkspaceRoot "scripts/test-playwright-guardrails.ps1") -WorkspaceRoot $WorkspaceRoot
}
finally {
    Pop-Location
}

Write-Host "Playwright dependencies and Chromium installed successfully."
