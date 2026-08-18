[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$PackagePath = (Join-Path (Split-Path -Parent $PSScriptRoot) "mdcc-vscode-agent-suite.zip")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath))
try {
    $root = "mdcc-vscode-agent-suite/"
    $entries = @($zip.Entries | Where-Object { $_.Name })
    $entryByPath = @{}
    foreach ($entry in $entries) { $entryByPath[$entry.FullName.Replace('\', '/')] = $entry }

    $required = @(
        ".github/agents/mdcc-master.agent.md",
        ".github/agents/mdcc-researcher.agent.md",
        ".github/agents/mdcc-architect.agent.md",
        ".github/agents/mdcc-troubleshooter.agent.md",
        ".github/agents/mdcc-dataverse-diagnostician.agent.md",
        ".github/agents/mdcc-dataverse-remediator.agent.md",
        ".github/agents/mdcc-validator.agent.md",
        ".github/instructions/mdcc-common.instructions.md",
        ".github/instructions/dataverse-mcp.instructions.md",
        ".vscode/mcp.json",
        ".vscode/settings.json",
        ".vscode/tasks.json",
        "config/mdcc-sources.json",
        "config/dataverse-mcp-policy.json",
        "config/dataverse-mcp-policy.schema.json",
        "docs/dataverse-mcp.md",
        "scripts/build-mdcc-package.ps1",
        "scripts/test-agent-context.ps1",
        "scripts/test-dataverse-mcp-guardrails.ps1",
        "scripts/test-dataverse-mcp-endpoint.ps1",
        "scripts/test-mdcc-package.ps1",
        "scripts/sync-mdcc-docs.ps1",
        "scripts/sync-mdcc-docs.sh",
        "tests/acceptance-scenarios.md",
        "tests/dataverse-mcp-acceptance.md",
        "AGENTS.md",
        "CHANGELOG.md",
        "README.md",
        "package-manifest.json"
    )
    foreach ($relativePath in $required) {
        Assert-True ($entryByPath.ContainsKey($root + $relativePath)) "Package entry is missing: $relativePath"
    }

    $agentEntries = @($entries | Where-Object { $_.FullName -like "$root.github/agents/*.agent.md" })
    Assert-True ($agentEntries.Count -eq 7) "The package must contain exactly seven agents; found $($agentEntries.Count)."

    $manifestEntry = $entryByPath[$root + "package-manifest.json"]
    $reader = [IO.StreamReader]::new($manifestEntry.Open())
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    Assert-True (@($manifest.files).Count -gt 0) "The package manifest is empty."

    $manifestPaths = @($manifest.files | ForEach-Object { $root + [string]$_.path } | Sort-Object)
    $zipContentPaths = @($entries | Where-Object { $_.FullName -ne ($root + "package-manifest.json") } | ForEach-Object { $_.FullName.Replace('\', '/') } | Sort-Object)
    Assert-True (@(Compare-Object -ReferenceObject $manifestPaths -DifferenceObject $zipContentPaths).Count -eq 0) "ZIP content and manifest file lists differ."

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($item in $manifest.files) {
            $path = $root + [string]$item.path
            Assert-True ($entryByPath.ContainsKey($path)) "Manifest entry is missing from ZIP: $($item.path)"
            $stream = $entryByPath[$path].Open()
            try {
                $actualHash = [Convert]::ToHexString($sha256.ComputeHash($stream)).ToLowerInvariant()
            }
            finally { $stream.Dispose() }
            Assert-True ($actualHash -eq [string]$item.sha256) "Hash mismatch in package: $($item.path)"
            $workspaceFile = Join-Path $WorkspaceRoot ([string]$item.path)
            Assert-True (Test-Path -LiteralPath $workspaceFile) "Manifest file is missing from workspace: $($item.path)"
            $workspaceHash = (Get-FileHash -LiteralPath $workspaceFile -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-True ($workspaceHash -eq [string]$item.sha256) "Package is stale relative to workspace: $($item.path)"
        }
    }
    finally { $sha256.Dispose() }
}
finally { $zip.Dispose() }

Write-Host "Package content and hashes validated successfully."
