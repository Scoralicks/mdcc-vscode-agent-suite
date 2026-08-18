[CmdletBinding()]
param(
    [string]$ReferenceRoot = (Join-Path $PSScriptRoot "..\.reference"),
    [switch]$SkipIndex
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoUrl = "https://github.com/MicrosoftDocs/dynamics-365-contact-center.git"
$repoDir = Join-Path $ReferenceRoot "dynamics-365-contact-center"
$docsDir = Join-Path $repoDir "contact-center"
$sharedDir = Join-Path $repoDir "shared"
$indexFile = Join-Path $ReferenceRoot "mdcc-doc-index.json"
$manifestFile = Join-Path $ReferenceRoot "source-manifest.json"

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git failed: git $($Arguments -join ' ')"
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git was not found. Install Git and reopen the terminal."
}

New-Item -ItemType Directory -Path $ReferenceRoot -Force | Out-Null

if (Test-Path (Join-Path $repoDir ".git")) {
    Write-Host "Updating MicrosoftDocs/dynamics-365-contact-center..."
    Invoke-Git -Arguments @("-C", $repoDir, "fetch", "origin", "main", "--depth", "1")
    Invoke-Git -Arguments @("-C", $repoDir, "reset", "--hard", "origin/main")
    Invoke-Git -Arguments @("-C", $repoDir, "clean", "-fd")
}
else {
    if (Test-Path $repoDir) {
        Remove-Item -Path $repoDir -Recurse -Force
    }

    Write-Host "Cloning MicrosoftDocs/dynamics-365-contact-center..."
    Invoke-Git -Arguments @(
        "clone", "--depth", "1", "--single-branch", "--branch", "main",
        $repoUrl, $repoDir
    )
}

if (-not (Test-Path $docsDir)) {
    throw "Expected documentation directory was not found: $docsDir"
}

$commit = (& git -C $repoDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not read the repository commit." }

$commitDate = (& git -C $repoDir show -s --format=%cI HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not read the repository commit date." }

$markdownFiles = @(Get-ChildItem -Path $docsDir -Recurse -File -Filter "*.md")
$sharedMarkdownFiles = if (Test-Path $sharedDir) { @(Get-ChildItem -Path $sharedDir -Recurse -File -Filter "*.md") } else { @() }
$knowledgeFiles = @($markdownFiles) + @($sharedMarkdownFiles)

$manifest = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString("o")
    repository = "MicrosoftDocs/dynamics-365-contact-center"
    branch = "main"
    commit = $commit
    commitDate = $commitDate
    documentationPath = "contact-center"
    markdownFileCount = $markdownFiles.Count
    sharedDocumentationPath = "shared"
    sharedMarkdownFileCount = $sharedMarkdownFiles.Count
    indexedMarkdownFileCount = $knowledgeFiles.Count
    localPath = $docsDir
    learnRoot = "https://learn.microsoft.com/en-us/dynamics365/contact-center/"
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestFile -Encoding UTF8

if (-not $SkipIndex) {
    Write-Host "Indexing $($knowledgeFiles.Count) Markdown files, including local shared content..."

    $items = foreach ($file in $knowledgeFiles) {
        $lines = @(Get-Content -Path $file.FullName -Encoding UTF8)
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

        $relativePath = [IO.Path]::GetRelativePath($repoDir, $file.FullName).Replace('\', '/')
        $includePaths = @()
        foreach ($line in $lines) {
            if ($line -match '\[!INCLUDE[^\]]*\]\(([^)]+\.md)\)') {
                $includeTarget = $Matches[1].Trim()
                if (-not $includeTarget.StartsWith("~")) {
                    $resolvedInclude = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $includeTarget))
                    if (Test-Path -LiteralPath $resolvedInclude) {
                        $includePaths += [IO.Path]::GetRelativePath($repoDir, $resolvedInclude).Replace('\', '/')
                    }
                }
            }
        }

        [ordered]@{
            path = $relativePath
            title = $title
            msDate = $msDate
            msTopic = $msTopic
            sizeBytes = $file.Length
            lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
            localIncludes = @($includePaths | Sort-Object -Unique)
        }
    }

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
Write-Host "Docs: $docsDir"
Write-Host "Manifest: $manifestFile"
if (-not $SkipIndex) { Write-Host "Index: $indexFile" }
