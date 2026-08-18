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
$includePaths = @(".github", ".vscode", "config", "docs", "scripts", "tests", "AGENTS.md", "CHANGELOG.md", "README.md", ".gitignore")

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    foreach ($relativePath in $includePaths) {
        $source = Join-Path $WorkspaceRoot $relativePath
        if (-not (Test-Path -LiteralPath $source)) { throw "Package source is missing: $relativePath" }
        Copy-Item -LiteralPath $source -Destination $packageRoot -Recurse -Force
    }

    $files = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Sort-Object FullName)
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

    Compress-Archive -LiteralPath $packageRoot -DestinationPath $OutputPath -CompressionLevel Optimal -Force
    & (Join-Path $WorkspaceRoot "scripts/test-mdcc-package.ps1") -WorkspaceRoot $WorkspaceRoot -PackagePath $OutputPath
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}

Write-Host "Package built and verified: $OutputPath"
