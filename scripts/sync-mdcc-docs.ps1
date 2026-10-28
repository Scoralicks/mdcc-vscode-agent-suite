[CmdletBinding()]
param(
    [string]$ReferenceRoot = (Join-Path $PSScriptRoot "..\.reference"),
    [switch]$SkipIndex,
    # Sincroniza apenas a base de Contact Center (mais rápido; sem a documentação de Customer Service).
    [switch]$SkipCustomerService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoUrl = "https://github.com/MicrosoftDocs/dynamics-365-contact-center.git"
$repoDir = Join-Path $ReferenceRoot "dynamics-365-contact-center"
$docsDir = Join-Path $repoDir "contact-center"
$sharedDir = Join-Path $repoDir "shared"
$indexFile = Join-Path $ReferenceRoot "mdcc-doc-index.json"
$manifestFile = Join-Path $ReferenceRoot "source-manifest.json"

# Customer Service e Channel Integration Framework vivem no repositório de Customer Engagement;
# o sparse checkout baixa somente estas pastas.
$ceRepoName = "dynamics-365-customer-engagement"
$ceRepoUrl = "https://github.com/MicrosoftDocs/dynamics-365-customer-engagement.git"
$ceRepoDir = Join-Path $ReferenceRoot $ceRepoName
$cePaths = @("ce/customer-service", "ce/channel-integration-framework")

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git failed: git $($Arguments -join ' ')"
    }
}

function Sync-Repository {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Directory,
        [string[]]$SparsePaths = @()
    )

    $name = Split-Path -Leaf $Directory
    if (Test-Path (Join-Path $Directory ".git")) {
        Write-Host "Updating MicrosoftDocs/$name..."
        if ($SparsePaths.Count) { Invoke-Git -Arguments (@("-C", $Directory, "sparse-checkout", "set") + $SparsePaths) }
        Invoke-Git -Arguments @("-C", $Directory, "fetch", "origin", "main", "--depth", "1")
        Invoke-Git -Arguments @("-C", $Directory, "reset", "--hard", "origin/main")
        Invoke-Git -Arguments @("-C", $Directory, "clean", "-fd")
        return
    }

    if (Test-Path $Directory) {
        Remove-Item -Path $Directory -Recurse -Force
    }

    Write-Host "Cloning MicrosoftDocs/$name..."
    if ($SparsePaths.Count) {
        Invoke-Git -Arguments @("clone", "--depth", "1", "--single-branch", "--branch", "main", "--filter=blob:none", "--sparse", $Url, $Directory)
        Invoke-Git -Arguments (@("-C", $Directory, "sparse-checkout", "set") + $SparsePaths)
    }
    else {
        Invoke-Git -Arguments @("clone", "--depth", "1", "--single-branch", "--branch", "main", $Url, $Directory)
    }
}

function Get-RepositoryCommit {
    param([Parameter(Mandatory)][string]$Directory)

    $commit = (& git -C $Directory rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not read the repository commit: $Directory" }
    $commitDate = (& git -C $Directory show -s --format=%cI HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not read the repository commit date: $Directory" }
    return @{ commit = $commit; commitDate = $commitDate }
}

function Get-IndexItem {
    param(
        [Parameter(Mandatory)][IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$RepositoryDirectory,
        [string]$Repository
    )

    $lines = @(Get-Content -Path $File.FullName -Encoding UTF8)
    $title = $null
    $msDate = $null
    $msTopic = $null
    $inFrontMatter = $false
    $frontMatterClosed = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($i -eq 0 -and $line.Trim() -eq "---") {
            $inFrontMatter = $true
            continue
        }

        if ($inFrontMatter -and $line.Trim() -eq "---") {
            $inFrontMatter = $false
            $frontMatterClosed = $true
            continue
        }

        if ($inFrontMatter) {
            if (-not $title -and $line -match '^title:\s*["'']?(.*?)["'']?\s*$') { $title = $Matches[1].Trim() }
            if (-not $msDate -and $line -match '^ms\.date:\s*["'']?(.*?)["'']?\s*$') { $msDate = $Matches[1].Trim() }
            if (-not $msTopic -and $line -match '^ms\.topic:\s*["'']?(.*?)["'']?\s*$') { $msTopic = $Matches[1].Trim() }
            continue
        }

        if (-not $title -and $line -match '^#\s+(.+)$') {
            $title = $Matches[1].Trim()
            break
        }

        if ($frontMatterClosed -and $i -gt 80) { break }
    }

    $relativePath = [IO.Path]::GetRelativePath($RepositoryDirectory, $File.FullName).Replace('\', '/')
    $includePaths = @()
    foreach ($line in $lines) {
        if ($line -match '\[!INCLUDE[^\]]*\]\(([^)]+\.md)\)') {
            $includeTarget = $Matches[1].Trim()
            if (-not $includeTarget.StartsWith("~")) {
                $resolvedInclude = [IO.Path]::GetFullPath((Join-Path $File.DirectoryName $includeTarget))
                if (Test-Path -LiteralPath $resolvedInclude) {
                    $includePaths += [IO.Path]::GetRelativePath($RepositoryDirectory, $resolvedInclude).Replace('\', '/')
                }
            }
        }
    }

    $item = [ordered]@{}
    # Itens sem "repository" pertencem à base primária (compatível com índices anteriores).
    if ($Repository) { $item.repository = $Repository }
    $item.path = $relativePath
    $item.title = $title
    $item.msDate = $msDate
    $item.msTopic = $msTopic
    $item.sizeBytes = $File.Length
    $item.lastWriteTimeUtc = $File.LastWriteTimeUtc.ToString("o")
    $item.localIncludes = @($includePaths | Sort-Object -Unique)
    return $item
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git was not found. Install Git and reopen the terminal."
}

New-Item -ItemType Directory -Path $ReferenceRoot -Force | Out-Null

Sync-Repository -Url $repoUrl -Directory $repoDir

if (-not (Test-Path $docsDir)) {
    throw "Expected documentation directory was not found: $docsDir"
}

$primary = Get-RepositoryCommit -Directory $repoDir
$commit = $primary.commit

$markdownFiles = @(Get-ChildItem -Path $docsDir -Recurse -File -Filter "*.md")
$sharedMarkdownFiles = if (Test-Path $sharedDir) { @(Get-ChildItem -Path $sharedDir -Recurse -File -Filter "*.md") } else { @() }
$knowledgeFiles = @($markdownFiles) + @($sharedMarkdownFiles)

$additionalSources = @()
$ceFiles = @()
if (-not $SkipCustomerService) {
    Sync-Repository -Url $ceRepoUrl -Directory $ceRepoDir -SparsePaths $cePaths
    $ce = Get-RepositoryCommit -Directory $ceRepoDir
    foreach ($path in $cePaths) {
        $directory = Join-Path $ceRepoDir $path
        if (-not (Test-Path $directory)) { throw "Expected documentation directory was not found: $directory" }
        $files = @(Get-ChildItem -Path $directory -Recurse -File -Filter "*.md")
        $ceFiles += $files
        $additionalSources += [ordered]@{
            repository = "MicrosoftDocs/$ceRepoName"
            localRepository = $ceRepoName
            branch = "main"
            commit = $ce.commit
            commitDate = $ce.commitDate
            documentationPath = $path
            markdownFileCount = $files.Count
        }
    }
}
elseif (Test-Path (Join-Path $ReferenceRoot "source-manifest.json")) {
    Write-Host "Customer Service documentation skipped; previous copy (if any) is not indexed."
}

$manifest = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString("o")
    repository = "MicrosoftDocs/dynamics-365-contact-center"
    branch = "main"
    commit = $commit
    commitDate = $primary.commitDate
    documentationPath = "contact-center"
    markdownFileCount = $markdownFiles.Count
    sharedDocumentationPath = "shared"
    sharedMarkdownFileCount = $sharedMarkdownFiles.Count
    indexedMarkdownFileCount = $knowledgeFiles.Count + $ceFiles.Count
    localPath = $docsDir
    learnRoot = "https://learn.microsoft.com/en-us/dynamics365/contact-center/"
    additionalSources = @($additionalSources)
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestFile -Encoding UTF8

if (-not $SkipIndex) {
    Write-Host "Indexing $($knowledgeFiles.Count + $ceFiles.Count) Markdown files, including local shared content..."

    $items = @(foreach ($file in $knowledgeFiles) { Get-IndexItem -File $file -RepositoryDirectory $repoDir })
    $items += @(foreach ($file in $ceFiles) { Get-IndexItem -File $file -RepositoryDirectory $ceRepoDir -Repository $ceRepoName })

    $index = [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString("o")
        sourceCommit = $commit
        count = $items.Count
        files = $items
    }

    $index | ConvertTo-Json -Depth 8 | Set-Content -Path $indexFile -Encoding UTF8
}

Write-Host "Documentation synchronized successfully."
Write-Host "Commit: $commit"
Write-Host "Markdown files: $($markdownFiles.Count)"
Write-Host "Shared Markdown files: $($sharedMarkdownFiles.Count)"
foreach ($source in $additionalSources) { Write-Host "$($source.documentationPath) Markdown files: $($source.markdownFileCount)" }
Write-Host "Docs: $docsDir"
Write-Host "Manifest: $manifestFile"
if (-not $SkipIndex) { Write-Host "Index: $indexFile" }
