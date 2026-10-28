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
        ".github/agents/mdcc-browser-diagnostician.agent.md",
        ".github/agents/mdcc-delivery-planner.agent.md",
        ".github/instructions/mdcc-common.instructions.md",
        ".github/instructions/dataverse-mcp.instructions.md",
        ".github/instructions/playwright-mdcc.instructions.md",
        ".github/instructions/jira-mcp.instructions.md",
        ".github/instructions/ado-mcp.instructions.md",
        ".github/instructions/work-items.instructions.md",
        "tools/jira-mcp/server.mjs",
        "tools/ado-mcp/server.mjs",
        "tools/shared/secrets.mjs",
        "tools/shared/mcp-stdio.mjs",
        "tools/doctor/doctor.mjs",
        "tests/jira-mcp.test.mjs",
        "tests/ado-mcp.test.mjs",
        "tests/doctor.test.mjs",
        "tools/dataverse-mcp/launch.mjs",
        "scripts/set-jira-connection.ps1",
        "scripts/set-ado-connection.ps1",
        "scripts/install-visual-studio.ps1",
        "docs/jira-mcp.md",
        "docs/ado-mcp.md",
        ".vscode/mcp.json",
        ".vscode/settings.json",
        ".vscode/tasks.json",
        "config/mdcc-sources.json",
        "config/dataverse-mcp-policy.json",
        "config/dataverse-mcp-policy.schema.json",
        "config/mcp.template.json",
        "config/dataverse-mcp.example.json",
        "config/dataverse-mcp.local.schema.json",
        "docs/predefined-environments.md",
        "docs/vs-code-integration-review.md",
        "tests/mcp-presets.test.mjs",
        "tools/mcp-configurator/presets.mjs",
        "config/playwright-mcp.config.json",
        "docs/dataverse-mcp.md",
        "docs/dataverse-environment-validation.md",
        "docs/playwright-mdcc.md",
        "docs/mcp-environment-configurator.md",
        "scripts/build-mdcc-package.ps1",
        "scripts/test-agent-context.ps1",
        "scripts/test-dataverse-mcp-guardrails.ps1",
        "scripts/test-dataverse-mcp-endpoint.ps1",
        "scripts/prepare-dataverse-mcp-connection.ps1",
        "scripts/prepare-playwright-session.ps1",
        "scripts/install-playwright.ps1",
        "scripts/test-playwright-guardrails.ps1",
        "scripts/test-mdcc-package.ps1",
        "scripts/sync-mdcc-docs.ps1",
        "scripts/sync-mdcc-docs.sh",
        "tests/acceptance-scenarios.md",
        "tests/dataverse-mcp-acceptance.md",
        "tests/e2e/mdcc-readonly.smoke.spec.js",
        "tests/mcp-configurator.test.mjs",
        "tests/dataverse-diagnostics.test.mjs",
        "tests/dataverse-package.test.mjs",
        "tools/mcp-configurator/endpoint.mjs",
        "tools/mcp-configurator/index.html",
        "tools/mcp-configurator/server.mjs",
        "AGENTS.md",
        "CHANGELOG.md",
        "README.md",
        "package.json",
        "package-lock.json",
        "playwright.config.js",
        "package-manifest.json"
    )
    foreach ($relativePath in $required) {
        Assert-True ($entryByPath.ContainsKey($root + $relativePath)) "Package entry is missing: $relativePath"
    }

    $diagnosticsPath = Join-Path $WorkspaceRoot 'tools/dataverse-diagnostics'
    Assert-True (Test-Path -LiteralPath $diagnosticsPath -PathType Container) 'Dataverse diagnostics tools are missing from the workspace.'
    $diagnosticsFiles = @(Get-ChildItem -LiteralPath $diagnosticsPath -Recurse -File -Filter '*.mjs' -Force | ForEach-Object { [IO.Path]::GetRelativePath($WorkspaceRoot, $_.FullName).Replace('\', '/') } | Sort-Object)
    Assert-True ($diagnosticsFiles.Count -gt 0) 'At least one Dataverse diagnostics module is required.'
    $packagedDiagnostics = @($entries | Where-Object { $_.FullName -like "${root}tools/dataverse-diagnostics/*.mjs" } | ForEach-Object { $_.FullName.Substring($root.Length).Replace('\', '/') } | Sort-Object)
    Assert-True (@(Compare-Object -ReferenceObject $diagnosticsFiles -DifferenceObject $packagedDiagnostics).Count -eq 0) 'Dataverse diagnostics modules in the ZIP differ from the workspace.'

    $blockedPathPattern = '(?i)(^|/)(node_modules|playwright-report|test-results|\.playwright-output|\.auth|\.secrets|\.dataverse|\.mcp|\.cache)(/|$)|(^|/)\.env[^/]*(/|$)|(^|/)(\.?token[_-]?cache[^/]*|msal[_-]?cache[^/]*|\.msal[^/]*|auth\.json|credentials(?:\.json)?|oauth(?:[_-]?(?:cache|tokens?))?\.(?:json|bin)|tokens?\.(?:json|bin))$|\.har$|\.trace\.zip$|storage(state)?\.json$|\.mcp\.log$'
    foreach ($entry in $zip.Entries) {
        $entryPath = $entry.FullName.Replace('\', '/')
        Assert-True ($entryPath -notlike '*.local.json') "Local customer configuration is present in package: $entryPath"
        Assert-True ($entryPath -notmatch $blockedPathPattern) "Sensitive/generated artifact is present in package: $entryPath"
        if (-not $entry.Name) { continue }
        if ($entry.Length -le 5MB) {
            $scanReader = [IO.StreamReader]::new($entry.Open())
            try { $entryText = $scanReader.ReadToEnd() } finally { $scanReader.Dispose() }
            Assert-True ($entryText -notmatch '(?i)github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9]{20,}|authorization\s*:\s*bearer\s+[A-Za-z0-9._-]+') "Token-like content is present in package: $entryPath"
            $customerUrls = @([regex]::Matches($entryText, '(?i)https://([a-z0-9-]+)\.crm(?:[0-9]+)?\.dynamics\.com(?:/api/mcp)?'))
            foreach ($match in $customerUrls) {
                Assert-True ($match.Groups[1].Value -in @('contoso', 'xn--contoso')) "Customer-specific Dynamics URL is present in package: $entryPath"
            }
        }
    }

    $mcpEntry = $entryByPath[$root + ".vscode/mcp.json"]
    $mcpReader = [IO.StreamReader]::new($mcpEntry.Open())
    try { $packagedMcpText = $mcpReader.ReadToEnd() } finally { $mcpReader.Dispose() }
    $packagedMcp = $packagedMcpText | ConvertFrom-Json
    $packagedServerNames = @($packagedMcp.servers.PSObject.Properties.Name)
    Assert-True ($packagedServerNames -contains "dataverse-mdcc" -and $packagedServerNames -contains "playwright-mdcc") "Package is missing a required MCP server."
    foreach ($name in $packagedServerNames) {
        Assert-True ($name -in @("dataverse-mdcc", "playwright-mdcc", "jira-mdcc", "ado-mdcc")) "Package contains an unexpected MCP server: $name"
    }
    Assert-True ($packagedMcp.servers.'dataverse-mdcc'.url -eq '${input:dataverse-mcp-endpoint}') "Package contains a static Dataverse endpoint."
    Assert-True ($packagedMcpText -notmatch '(?i)https://[^"\s]+\.dynamics\.com') "Package contains a customer-specific Dataverse URL."
    Assert-True ($packagedMcpText -notmatch '(?i)arte') "Package contains a customer-specific MCP identifier."
    Assert-True ($packagedMcpText -notmatch '(?i)"auth"\s*:|github_pat_|ghp_|bearer\s+') "Package contains an inline MCP credential or token-like value."

    $agentEntries = @($entries | Where-Object { $_.FullName -like "$root.github/agents/*.agent.md" })
    Assert-True ($agentEntries.Count -eq 9) "The package must contain exactly nine agents; found $($agentEntries.Count)."

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
            $workspaceRelative = if ($item.path -eq '.vscode/mcp.json') { 'config/mcp.template.json' } else { [string]$item.path }
            $workspaceFile = Join-Path $WorkspaceRoot $workspaceRelative
            Assert-True (Test-Path -LiteralPath $workspaceFile) "Manifest file is missing from workspace: $($item.path)"
            $workspaceHash = (Get-FileHash -LiteralPath $workspaceFile -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-True ($workspaceHash -eq [string]$item.sha256) "Package is stale relative to workspace: $($item.path)"
        }
    }
    finally { $sha256.Dispose() }
}
finally { $zip.Dispose() }

Write-Host "Package content and hashes validated successfully."
