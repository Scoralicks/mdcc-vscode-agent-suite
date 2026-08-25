[CmdletBinding()]
param(
    [string]$ReferenceRoot = (Join-Path $PSScriptRoot "..\.reference"),
    [switch]$SkipIndex
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoUrl = "https://github.com/MicrosoftDocs/azure-docs.git"
$repoDir = Join-Path $ReferenceRoot "azure-docs"
$indexFile = Join-Path $ReferenceRoot "azure-doc-index.json"
$manifestFile = Join-Path $ReferenceRoot "azure-source-manifest.json"
$sparsePaths = @(
    "articles/communication-services",
    "articles/event-grid",
    "articles/azure-functions",
    "articles/role-based-access-control",
    "articles/service-health",
    "articles/service-bus-messaging"
)

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git failed: git $($Arguments -join ' ')" }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git was not found. Install Git and reopen the terminal."
}

New-Item -ItemType Directory -Path $ReferenceRoot -Force | Out-Null

if (Test-Path (Join-Path $repoDir ".git")) {
    Write-Host "Updating targeted MicrosoftDocs/azure-docs corpus..."
    Invoke-Git -Arguments @("-C", $repoDir, "fetch", "origin", "main", "--depth", "1")
    Invoke-Git -Arguments (@("-C", $repoDir, "sparse-checkout", "set") + $sparsePaths)
    Invoke-Git -Arguments @("-C", $repoDir, "reset", "--hard", "origin/main")
    Invoke-Git -Arguments @("-C", $repoDir, "clean", "-fd")
}
else {
    if (Test-Path $repoDir) { Remove-Item -LiteralPath $repoDir -Recurse -Force }
    Write-Host "Cloning targeted MicrosoftDocs/azure-docs corpus..."
    Invoke-Git -Arguments @("clone", "--depth", "1", "--filter=blob:none", "--sparse", "--branch", "main", $repoUrl, $repoDir)
    Invoke-Git -Arguments (@("-C", $repoDir, "sparse-checkout", "set") + $sparsePaths)
}

$commit = (& git -C $repoDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not read the Azure documentation commit." }
$commitDate = (& git -C $repoDir show -s --format=%cI HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not read the Azure documentation commit date." }

$knowledgeFiles = foreach ($relativePath in $sparsePaths) {
    $area = Join-Path $repoDir $relativePath
    if (Test-Path $area) { Get-ChildItem -LiteralPath $area -Recurse -File -Filter "*.md" }
}
$knowledgeFiles = @($knowledgeFiles | Sort-Object FullName -Unique)

[ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString("o")
    repository = "MicrosoftDocs/azure-docs"
    branch = "main"
    commit = $commit
    commitDate = $commitDate
    sparsePaths = $sparsePaths
    indexedMarkdownFileCount = $knowledgeFiles.Count
    localPath = $repoDir
    learnRoot = "https://learn.microsoft.com/en-us/azure/"
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestFile -Encoding UTF8

if (-not $SkipIndex) {
    Write-Host "Indexing $($knowledgeFiles.Count) targeted Azure Markdown files..."
    $items = foreach ($file in $knowledgeFiles) {
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
            sourceRoot = "azure-docs"
            path = [IO.Path]::GetRelativePath($repoDir, $file.FullName).Replace('\', '/')
            title = $title
            msDate = $msDate
            msService = $msService
            sizeBytes = $file.Length
            officialOutboundLinks = $outboundLinks
        }
    }
    [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString("o")
        sourceCommit = $commit
        count = $items.Count
        files = $items
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $indexFile -Encoding UTF8
}

& (Join-Path $PSScriptRoot "sync-azure-monitor-docs.ps1") -ReferenceRoot $ReferenceRoot -SkipIndex:$SkipIndex

Write-Host "Targeted Azure documentation synchronized successfully."
Write-Host "Commit: $commit"
Write-Host "Azure core Markdown files: $($knowledgeFiles.Count)"
Write-Host "Manifest: $manifestFile"
if (-not $SkipIndex) { Write-Host "Index: $indexFile" }
