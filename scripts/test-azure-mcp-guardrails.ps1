[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$mcp = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot ".vscode/mcp.json") -Encoding UTF8 | ConvertFrom-Json
$policy = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot "config/azure-mcp-policy.json") -Encoding UTF8 | ConvertFrom-Json
$settings = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot ".vscode/settings.json") -Encoding UTF8 | ConvertFrom-Json
$agent = Get-Content -Raw -LiteralPath (Join-Path $WorkspaceRoot ".github/agents/mdcc-azure-specialist.agent.md") -Encoding UTF8

$learn = $mcp.servers.'microsoft-learn'
Assert-True ($learn.type -eq "http") "Microsoft Learn MCP must use HTTP."
Assert-True ($learn.url -eq "https://learn.microsoft.com/api/mcp") "Unexpected Microsoft Learn MCP endpoint."

$azure = $mcp.servers.'azure-mdcc-diagnostics'
Assert-True ($azure.type -eq "stdio" -and $azure.command -eq "npx") "Azure MCP must use the reviewed local STDIO launcher."
$args = @($azure.args)
Assert-True ($args -contains "@azure/mcp@2.0.5") "Azure MCP package must remain pinned to the reviewed version."
Assert-True ($args -contains "--read-only") "Azure MCP must run in read-only mode."
Assert-True (-not ($args -contains "--disable-user-confirmation")) "User confirmation must not be disabled."
Assert-True (-not ($args -contains "--enable-insecure-transport")) "Insecure transport must not be enabled."
foreach ($forbiddenOption in @($policy.server.forbiddenOptions)) {
    Assert-True (-not ($args -contains $forbiddenOption)) "Forbidden Azure MCP option is configured: $forbiddenOption"
}
Assert-True (@($args | Where-Object { $_ -like "--dangerously-*" }).Count -eq 0) "No dangerously-* Azure MCP option is allowed."

$actualNamespaces = for ($i = 0; $i -lt $args.Count - 1; $i++) {
    if ($args[$i] -eq "--namespace") { [string]$args[$i + 1] }
}
$expectedNamespaces = @($policy.server.allowedNamespaces)
Assert-True (@(Compare-Object ($actualNamespaces | Sort-Object) ($expectedNamespaces | Sort-Object)).Count -eq 0) "Azure MCP namespaces differ from policy."
Assert-True (-not ($actualNamespaces -contains "communication")) "The ACS communication namespace exposes send operations and must not be in diagnosis."

foreach ($namespace in $expectedNamespaces) {
    $key = "azure-mdcc-diagnostics/$namespace"
    $property = $settings.'chat.tools.eligibleForAutoApproval'.PSObject.Properties[$key]
    Assert-True ($null -ne $property -and $property.Value -eq $false) "Azure tool must be ineligible for auto-approval: $key"
}

Assert-True ($agent -match "mdcc-common\.instructions\.md") "Azure Specialist must reference the common policy."
Assert-True ($agent -match "azure-mcp\.instructions\.md") "Azure Specialist must reference Azure MCP instructions."
Assert-True ($agent -match "config/azure-mcp-policy\.json") "Azure Specialist must reference Azure MCP policy."
Assert-True ($agent -match "azure-mdcc-diagnostics/\*") "Azure Specialist must be the Azure diagnostic tool owner."
Assert-True ($agent -match "Nunca execute remediação Azure") "Azure Specialist must prohibit remediation."

Write-Host "Azure MCP read-only guardrails validated successfully."
