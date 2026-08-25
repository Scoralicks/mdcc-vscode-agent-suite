[CmdletBinding()]
param(
    [string]$ReferenceRoot = (Join-Path $PSScriptRoot "..\.reference"),
    [switch]$SkipIndex
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoUrl = "https://github.com/MicrosoftDocs/azure-monitor-docs.git"
$repoDir = Join-Path $ReferenceRoot "azure-monitor-docs"
$documentationPath = "articles/azure-monitor"
$indexFile = Join-Path $ReferenceRoot "azure-doc-index.json"
$manifestFile = Join-Path $ReferenceRoot "azure-monitor-source-manifest.json"

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git failed: git $($Arguments -join ' ')" }
}

if (Test-Path (Join-Path $repoDir ".git")) {
    Write-Host "Updating targeted MicrosoftDocs/azure-monitor-docs corpus..."
    Invoke-Git -Arguments @("-C", $repoDir, "fetch", "origin", "main", "--depth", "1")
    Invoke-Git -Arguments @("-C", $repoDir, "sparse-checkout", "set", $documentationPath)
    Invoke-Git -Arguments @("-C", $repoDir, "reset", "--hard", "origin/main")
    Invoke-Git -Arguments @("-C", $repoDir, "clean", "-fd")
}
else {
    if (Test-Path $repoDir) { Remove-Item -LiteralPath $repoDir -Recurse -Force }
    Write-Host "Cloning targeted MicrosoftDocs/azure-monitor-docs corpus..."
    Invoke-Git -Arguments @("clone", "--depth", "1", "--filter=blob:none", "--sparse", "--branch", "main", $repoUrl, $repoDir)
    Invoke-Git -Arguments @("-C", $repoDir, "sparse-checkout", "set", $documentationPath)
}

$commit = (& git -C $repoDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not read the Azure Monitor documentation commit." }
$commitDate = (& git -C $repoDir show -s --format=%cI HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not read the Azure Monitor documentation commit date." }
$docsDir = Join-Path $repoDir $documentationPath
$files = @(Get-ChildItem -LiteralPath $docsDir -Recurse -File -Filter "*.md" | Sort-Object FullName)

[ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString("o")
    repository = "MicrosoftDocs/azure-monitor-docs"
    branch = "main"
    commit = $commit
    commitDate = $commitDate
    documentationPath = $documentationPath
    indexedMarkdownFileCount = $files.Count
    localPath = $docsDir
    learnRoot = "https://learn.microsoft.com/en-us/azure/azure-monitor/"
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestFile -Encoding UTF8

if (-not $SkipIndex) {
    $baseIndex = Get-Content -Raw -LiteralPath $indexFile -Encoding UTF8 | ConvertFrom-Json
    Write-Host "Indexing $($files.Count) Azure Monitor Markdown files..."
    $monitorItems = foreach ($file in $files) {
        $text = Get-Content -Raw -LiteralPath $file.FullName -Encoding UTF8
        $lines = $text -split "\r?\n"
        $title = $null
        $msDate = $null
        $msService = $null
        foreach ($line in $lines | Select-Object -First 100) {
            if (-not $title -and $line -match '^title:\s*["'']?(.*?)["'']?\s*$') { $title = $Matches[1].Trim() }
            if (-not $msDate -and $line -match '^ms\.date:\s*["'']?(.*?)["'']?\s*$') { $msDate = $Matches[1].Trim() }
            if (-not $msService -and $line -match '^ms\.service:\s*["'']?(.*?)["'']?\s*$') { $msService = $Matches[1].Trim() }
            if (-not $title -and $line -match '^#\s+(.+)$') { $title = $Matches[1].Trim() }
        }
        $outboundLinks = @(
            [regex]::Matches($text, 'https://learn\.microsoft\.com/[A-Za-z0-9_./?=&%#-]+') |
                ForEach-Object { $_.Value.TrimEnd('.', ',', ')') } |
                Sort-Object -Unique
        )
        [ordered]@{
            sourceRoot = "azure-monitor-docs"
            path = [IO.Path]::GetRelativePath($repoDir, $file.FullName).Replace('\', '/')
            title = $title
            msDate = $msDate
            msService = $msService
            sizeBytes = $file.Length
            officialOutboundLinks = $outboundLinks
        }
    }
    $allItems = @($baseIndex.files) + @($monitorItems)
    [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString("o")
        sourceCommits = [ordered]@{
            azureDocs = [string]$baseIndex.sourceCommit
            azureMonitorDocs = $commit
        }
        count = $allItems.Count
        files = $allItems
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $indexFile -Encoding UTF8
}

Write-Host "Azure Monitor documentation synchronized successfully."
Write-Host "Commit: $commit"
Write-Host "Azure Monitor Markdown files: $($files.Count)"
