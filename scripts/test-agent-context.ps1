[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$sources = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot "config/mdcc-sources.json") -Encoding UTF8 | ConvertFrom-Json
$sourceIds = @($sources.sourceCatalog.id)
foreach ($requiredSource in @("azure-communication-services", "azure-event-grid", "azure-observability", "azure-platform-integration")) {
    Assert-True ($sourceIds -contains $requiredSource) "Official Azure source group is missing: $requiredSource"
}

$agentsDir = Join-Path $WorkspaceRoot ".github/agents"
$commonPath = Join-Path $WorkspaceRoot ".github/instructions/mdcc-common.instructions.md"
$researcherPath = Join-Path $agentsDir "mdcc-researcher.agent.md"
$validatorPath = Join-Path $agentsDir "mdcc-validator.agent.md"
$masterPath = Join-Path $agentsDir "mdcc-master.agent.md"
$azureSpecialistPath = Join-Path $agentsDir "mdcc-azure-specialist.agent.md"

$agents = @(Get-ChildItem -LiteralPath $agentsDir -File -Filter "*.agent.md")
Assert-True ($agents.Count -gt 0) "No agents were found."
Assert-True ($agents.Count -eq 8) "Expected exactly eight MDCC agents; found $($agents.Count)."

foreach ($agent in $agents) {
    $content = Get-Content -Raw -LiteralPath $agent.FullName -Encoding UTF8
    Assert-True ($content -match "mdcc-common\.instructions\.md") "$($agent.Name) does not reference the common policy."
    Assert-True ($content -notmatch "(?i)(think out loud|reveal.{0,30}chain.of.thought|exponha.{0,30}cadeia de pensamento)") "$($agent.Name) requests private chain-of-thought."
    if ($content -match "dataverse-mdcc/") {
        Assert-True ($content -match "dataverse-mcp\.instructions\.md") "$($agent.Name) uses Dataverse without its instructions."
        Assert-True ($content -match "config/dataverse-mcp-policy\.json") "$($agent.Name) uses Dataverse without its policy."
    }
}

$common = Get-Content -Raw -LiteralPath $commonPath -Encoding UTF8
foreach ($marker in @("Responsabilidade Extrema", "Anti-Sycophancy", "Profundidade verificável", "Input raso para output profundo", "Obsessão pelo objetivo")) {
    Assert-True ($common -match [regex]::Escape($marker)) "Universal principle missing from common policy: $marker"
}
Assert-True ($common -match "Não exponha cadeia de pensamento privada") "The common policy must protect private chain-of-thought."
Assert-True ($common -match "matriz afirmação → fonte") "The common policy must require claim-to-source traceability."
Assert-True ($common -match "contact-center/\*\*/\*\.md" -and $common -match "shared/\*\*/\*\.md") "The common policy must declare both versioned knowledge directories."

$researcher = Get-Content -Raw -LiteralPath $researcherPath -Encoding UTF8
foreach ($marker in @("termos exatos", "sinônimos, traduções e nomes históricos", "entidades, sintomas e componentes relacionados", "matriz **afirmação → fonte**", "não confirmado")) {
    Assert-True ($researcher -match [regex]::Escape($marker)) "Research protocol marker missing: $marker"
}
Assert-True ($researcher -match "contact-center" -and $researcher -match "shared" -and $researcher -match "mdcc-doc-index\.json") "The Researcher must preflight contact-center, shared, and the index."

$validator = Get-Content -Raw -LiteralPath $validatorPath -Encoding UTF8
foreach ($marker in @("premissa do usuário aceita sem contestação", "resposta superficial", "exposição de cadeia de pensamento privada", "matriz afirmação → fonte")) {
    Assert-True ($validator -match [regex]::Escape($marker)) "Validator blocker missing: $marker"
}

$master = Get-Content -Raw -LiteralPath $masterPath -Encoding UTF8
$masterAgentLine = [regex]::Match($master, "(?m)^agents:\s*(.+)$").Groups[1].Value
Assert-True ($masterAgentLine -notmatch "MDCC Dataverse Remediator") "The Master must not delegate remediation in the diagnosis context."
Assert-True ($masterAgentLine -match "MDCC Azure Specialist") "The Master must route Azure work to MDCC Azure Specialist."

$azureSpecialist = Get-Content -Raw -LiteralPath $azureSpecialistPath -Encoding UTF8
foreach ($marker in @("azure-mcp.instructions.md", "config/azure-mcp-policy.json", "Event Grid", "Diagnostic Settings", "Nunca execute remediação Azure")) {
    Assert-True ($azureSpecialist -match [regex]::Escape($marker)) "Azure Specialist marker missing: $marker"
}

$referenceRepoPath = Join-Path $WorkspaceRoot ".reference/dynamics-365-contact-center"
$contactCenterPath = Join-Path $referenceRepoPath "contact-center"
$sharedPath = Join-Path $referenceRepoPath "shared"
$indexPath = Join-Path $WorkspaceRoot ".reference/mdcc-doc-index.json"
foreach ($requiredPath in @($contactCenterPath, $sharedPath, $indexPath)) {
    Assert-True (Test-Path -LiteralPath $requiredPath) "Required synchronized knowledge artifact is missing: $requiredPath"
}

$index = Get-Content -Raw -LiteralPath $indexPath -Encoding UTF8 | ConvertFrom-Json
Assert-True (@($index.files | Where-Object { $_.path -like "shared/*.md" }).Count -gt 0) "The knowledge index omits the shared documentation directory."
Assert-True (@($index.files | Where-Object { @($_.localIncludes).Count -gt 0 }).Count -gt 0) "The knowledge index does not trace local includes."
foreach ($item in $index.files) {
    $indexedPath = Join-Path $referenceRepoPath ([string]$item.path)
    Assert-True (Test-Path -LiteralPath $indexedPath -PathType Leaf) "Indexed knowledge file is missing: $($item.path)"
}

$azureReferenceRepoPath = Join-Path $WorkspaceRoot ".reference/azure-docs"
$azureIndexPath = Join-Path $WorkspaceRoot ".reference/azure-doc-index.json"
Assert-True (Test-Path -LiteralPath $azureIndexPath -PathType Leaf) "Targeted Azure knowledge index is missing. Run scripts/sync-azure-docs.ps1."
$azureIndex = Get-Content -Raw -LiteralPath $azureIndexPath -Encoding UTF8 | ConvertFrom-Json
Assert-True (@($azureIndex.files).Count -gt 0) "The targeted Azure knowledge index is empty."
foreach ($area in @("articles/communication-services/*", "articles/event-grid/*", "articles/azure-monitor/*")) {
    Assert-True (@($azureIndex.files | Where-Object { $_.path -like $area }).Count -gt 0) "Azure knowledge index omits required area: $area"
}
foreach ($item in $azureIndex.files) {
    $sourceRoot = if ([string]$item.sourceRoot -eq "azure-monitor-docs") {
        Join-Path $WorkspaceRoot ".reference/azure-monitor-docs"
    }
    else {
        $azureReferenceRepoPath
    }
    $indexedPath = Join-Path $sourceRoot ([string]$item.path)
    Assert-True (Test-Path -LiteralPath $indexedPath -PathType Leaf) "Indexed Azure knowledge file is missing: $($item.path)"
}

Write-Host "Agent context and knowledge-retrieval policy validated successfully."
