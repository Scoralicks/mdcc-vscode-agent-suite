[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "mdcc-vscode-agent-suite.zip")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageName = "mdcc-vscode-agent-suite"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("mdcc-package-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $stagingRoot $packageName
$includePaths = @(".github", ".vscode", "config", "docs", "scripts", "tests", "tools", "AGENTS.md", "CHANGELOG.md", "README.md", ".gitignore", "package.json", "package-lock.json", "playwright.config.js")
$blockedPathPattern = '(?i)(^|/)(node_modules|playwright-report|test-results|\.playwright-output|\.auth|\.secrets|\.dataverse|\.mcp|\.cache)(/|$)|(^|/)\.env[^/]*(/|$)|(^|/)(\.?token[_-]?cache[^/]*|msal[_-]?cache[^/]*|\.msal[^/]*|auth\.json|credentials(?:\.json)?|oauth(?:[_-]?(?:cache|tokens?))?\.(?:json|bin)|tokens?\.(?:json|bin))$|\.har$|\.trace\.zip$|storage(state)?\.json$|\.mcp\.log$'

# Inspect paths before running tools or copying files. Git ignore rules do not
# protect distribution archives, and hidden authentication caches count too.
foreach ($relativePath in $includePaths) {
    $source = Join-Path $WorkspaceRoot $relativePath
    if (-not (Test-Path -LiteralPath $source)) { throw "Package source is missing: $relativePath" }
    $items = if (Test-Path -LiteralPath $source -PathType Container) { Get-ChildItem -LiteralPath $source -Recurse -Force } else { Get-Item -LiteralPath $source -Force }
    foreach ($item in $items) {
        $relative = [IO.Path]::GetRelativePath($WorkspaceRoot, $item.FullName).Replace('\', '/')
        if ($relative -match $blockedPathPattern) { throw "Sensitive/generated package input found: $relative" }
    }
}

& (Join-Path $WorkspaceRoot "scripts/test-agent-context.ps1") -WorkspaceRoot $WorkspaceRoot
& (Join-Path $WorkspaceRoot "scripts/test-dataverse-mcp-guardrails.ps1") -WorkspaceRoot $WorkspaceRoot
& (Join-Path $WorkspaceRoot "scripts/test-playwright-guardrails.ps1") -WorkspaceRoot $WorkspaceRoot
& node --test --test-isolation=none (Join-Path $WorkspaceRoot "tests/mcp-configurator.test.mjs") (Join-Path $WorkspaceRoot "tests/mcp-presets.test.mjs") (Join-Path $WorkspaceRoot "tests/dataverse-diagnostics.test.mjs") (Join-Path $WorkspaceRoot "tests/dataverse-package.test.mjs") (Join-Path $WorkspaceRoot "tests/jira-mcp.test.mjs") (Join-Path $WorkspaceRoot "tests/ado-mcp.test.mjs") (Join-Path $WorkspaceRoot "tests/doctor.test.mjs")
if ($LASTEXITCODE -ne 0) { throw "MCP configuration, work-tracking, diagnostics or package tests failed." }

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    foreach ($relativePath in $includePaths) {
        $source = Join-Path $WorkspaceRoot $relativePath
        if (-not (Test-Path -LiteralPath $source)) { throw "Package source is missing: $relativePath" }
        if (Test-Path -LiteralPath $source -PathType Container) {
            foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File -Force) {
                $relative = [IO.Path]::GetRelativePath($WorkspaceRoot, $file.FullName).Replace('\', '/')
                if ($relative -match $blockedPathPattern) { throw "Sensitive/generated package input found: $relative" }
                if ($file.Name -like '*.local.json' -or $relative -eq '.vscode/mcp.json') { continue }
                $destination = Join-Path $packageRoot $relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Copy-Item -LiteralPath $file.FullName -Destination $destination
            }
        }
        else { Copy-Item -LiteralPath $source -Destination $packageRoot -Force }
    }
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'config/mcp.template.json') -Destination (Join-Path $packageRoot '.vscode/mcp.json')

    $files = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Force | Sort-Object FullName)
    $manifestFiles = foreach ($file in $files) {
        [ordered]@{
            path = [IO.Path]::GetRelativePath($packageRoot, $file.FullName).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            sizeBytes = $file.Length
        }
    }
    [ordered]@{
        schemaVersion = 1
        generatedAtUtc = [DateTime]::UtcNow.ToString("o")
        files = @($manifestFiles)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $packageRoot "package-manifest.json") -Encoding UTF8

    $temporaryZip = Join-Path $stagingRoot 'verified-package.zip'
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $temporaryZip -CompressionLevel Optimal -Force
    & (Join-Path $WorkspaceRoot "scripts/test-mdcc-package.ps1") -WorkspaceRoot $WorkspaceRoot -PackagePath $temporaryZip
    Copy-Item -LiteralPath $temporaryZip -Destination $OutputPath -Force
}
finally {
    $resolvedStaging = [IO.Path]::GetFullPath($stagingRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedStaging.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedStaging) -notmatch '^mdcc-package-[a-f0-9]{32}$') { throw 'Unsafe staging cleanup path.' }
    if (Test-Path -LiteralPath $resolvedStaging) { Remove-Item -LiteralPath $resolvedStaging -Recurse -Force }
}

Write-Host "Package built and verified: $OutputPath"
