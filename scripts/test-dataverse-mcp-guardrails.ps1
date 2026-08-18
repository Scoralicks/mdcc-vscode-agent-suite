[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Read-Json {
    param([Parameter(Mandatory)][string]$Path)
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
}

function Assert-SetEqual {
    param(
        [Parameter(Mandatory)][object[]]$Actual,
        [Parameter(Mandatory)][object[]]$Expected,
        [Parameter(Mandatory)][string]$Message
    )
    $difference = @(Compare-Object -ReferenceObject @($Expected | Sort-Object) -DifferenceObject @($Actual | Sort-Object))
    Assert-True ($difference.Count -eq 0) $Message
}

$mcpPath = Join-Path $WorkspaceRoot ".vscode/mcp.json"
$settingsPath = Join-Path $WorkspaceRoot ".vscode/settings.json"
$policyPath = Join-Path $WorkspaceRoot "config/dataverse-mcp-policy.json"
$diagnosticianPath = Join-Path $WorkspaceRoot ".github/agents/mdcc-dataverse-diagnostician.agent.md"
$remediatorPath = Join-Path $WorkspaceRoot ".github/agents/mdcc-dataverse-remediator.agent.md"
$endpointValidatorPath = Join-Path $WorkspaceRoot "scripts/test-dataverse-mcp-endpoint.ps1"

$mcp = Read-Json $mcpPath
$settings = Read-Json $settingsPath
$policy = Read-Json $policyPath
$policyJson = Get-Content -Raw -LiteralPath $policyPath -Encoding UTF8
$diagnostician = Get-Content -Raw -LiteralPath $diagnosticianPath -Encoding UTF8
$remediator = Get-Content -Raw -LiteralPath $remediatorPath -Encoding UTF8

Assert-True ($mcp.servers.'dataverse-mdcc'.type -eq "http") "Dataverse MCP must use the remote HTTP endpoint."
Assert-True ($mcp.servers.'dataverse-mdcc'.url -eq '${input:dataverse-mcp-endpoint}') "The endpoint must be supplied through the secure VS Code input."
Assert-True ($policyJson | Test-Json -SchemaFile (Join-Path $WorkspaceRoot "config/dataverse-mcp-policy.schema.json")) "The Dataverse MCP policy does not conform to its JSON Schema."
Assert-True ($policy.connection.client -eq "github-copilot-vscode") "The approved client must remain GitHub Copilot in VS Code."
Assert-True ($policy.connection.clientApplicationId -eq "aebc6443-996d-45c2-90f0-388ff96faa56") "The official GitHub Copilot client application ID changed unexpectedly."
Assert-True ($policy.connection.transport -eq "http") "VS Code must use the direct HTTP transport."
Assert-True ($policy.connection.requiresAllowedClientRegistration) "Allowed-client registration must remain mandatory."
Assert-True ($policy.connection.requiredScheme -eq "https") "Only HTTPS endpoints are allowed."
Assert-True (@($policy.connection.allowedHostPatterns).Count -ge 1) "At least one Dataverse host pattern is required."
Assert-True ($policy.connection.allowedPath -eq "/api/mcp") "The default endpoint must be the GA /api/mcp endpoint."
Assert-True (-not $policy.connection.previewAllowed) "Preview must remain disabled by default."
Assert-True (-not $policy.credentialPolicy.allowSecretsInRepository) "Repository secrets must remain forbidden."
Assert-True (-not $policy.credentialPolicy.allowSecretsInChat) "Chat secrets must remain forbidden."
Assert-True (-not $policy.credentialPolicy.allowPlaintextEnvironmentFiles) "Plaintext environment files must remain forbidden."
Assert-True ($policy.identityPolicy.diagnosisAndRemediationMustUseSeparateIdentities) "Diagnosis and remediation identities must remain separate."
Assert-True ($policy.identityPolicy.remediationSessionDisabledByDefault) "The remediation session must remain disabled by default."
Assert-True ($policy.identityPolicy.verifyEffectiveRolesIncludingTeams) "Effective roles, including team grants, must be verified."

$readTools = @("search", "search_data", "read_query", "describe")
$diagnosisTools = @($policy.profiles.diagnosis.allowedTools)
$remediationTools = @($policy.profiles.remediation.allowedTools)
$deniedTools = @($policy.deniedTools)
$expectedDeniedTools = @("create_record", "create_table", "update_table", "upsert_skill", "delete_record", "delete_table", "delete_skill", "init_file_upload", "commit_file_upload", "file_download")

Assert-True (-not $policy.profiles.diagnosis.mutating) "The diagnosis profile cannot be mutating."
Assert-SetEqual $diagnosisTools $readTools "The diagnosis tool set changed."
Assert-True ($policy.profiles.remediation.mutating) "The remediation profile must declare its mutating nature."
Assert-True ("update_record" -in $remediationTools) "The remediation profile must explicitly list update_record."
Assert-SetEqual $remediationTools @($readTools + "update_record") "The remediation tool set changed."
Assert-SetEqual $deniedTools $expectedDeniedTools "The denied tool set changed."
Assert-True ($policy.audit.recordPlan -and $policy.audit.recordApproval -and $policy.audit.recordToolAndTarget -and $policy.audit.recordBeforeAndAfterSummary) "Required audit records must remain enabled."

$approvalRules = $settings.'chat.tools.eligibleForAutoApproval'
foreach ($tool in @("create_record", "update_record", "create_table", "update_table", "delete_record", "delete_table", "upsert_skill", "delete_skill", "init_file_upload", "commit_file_upload", "file_download")) {
    $propertyName = "dataverse-mdcc/$tool"
    Assert-True ($approvalRules.PSObject.Properties.Name -contains $propertyName) "Missing manual-approval rule for $propertyName."
    Assert-True ($approvalRules.$propertyName -eq $false) "$propertyName must never be eligible for auto-approval."
}

Assert-True ($diagnostician -notmatch "dataverse-mdcc/(create|update|delete|upsert|init_file|commit_file|file_download)") "The diagnostician exposes a mutating or file tool."
Assert-True ($remediator -match "dataverse-mdcc/update_record") "The remediator does not expose update_record."
Assert-True ($remediator -match "vscode/askQuestions") "The remediator must expose the current VS Code interactive approval tool."
Assert-True ($remediator -notmatch "vscode/askQuestion'") "The obsolete singular approval tool name is present."
Assert-True ($remediator -notmatch "dataverse-mdcc/(create|delete|upsert|init_file|commit_file|file_download)") "The remediator exposes a default-denied tool."

& $endpointValidatorPath -Endpoint "https://contoso.crm4.dynamics.com/api/mcp" -WorkspaceRoot $WorkspaceRoot | Out-Null

$invalidEndpoints = @(
    "http://contoso.crm.dynamics.com/api/mcp",
    "https://evil.example/api/mcp",
    "https://contoso.crm.dynamics.com/api/mcp_preview",
    "https://user:secret@contoso.crm.dynamics.com/api/mcp",
    "https://contoso.crm.dynamics.com/api/mcp?unsafe=true"
)

foreach ($invalidEndpoint in $invalidEndpoints) {
    $rejected = $false
    try {
        & $endpointValidatorPath -Endpoint $invalidEndpoint -WorkspaceRoot $WorkspaceRoot | Out-Null
    }
    catch {
        $rejected = $true
    }
    Assert-True $rejected "Unsafe endpoint was accepted: $invalidEndpoint"
}

Write-Host "Dataverse MCP guardrails validated successfully."
