[CmdletBinding()]
param(
    [string]$BaseUrl,
    [string]$Email,
    [switch]$Remove
)

# Configura a conexão com o Jira Cloud usada pelo servidor MCP jira-mdcc (leitura e escrita restrita).
# - JIRA_BASE_URL e JIRA_EMAIL ficam como variáveis de usuário do Windows.
# - O token de API (https://id.atlassian.com/manage-profile/security/api-tokens) é
#   protegido por DPAPI no perfil do usuário, fora do repositório. Nunca cole o token no chat.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tokenDir = Join-Path $env:LOCALAPPDATA "mdcc-agent-suite"
$tokenFile = Join-Path $tokenDir "jira-token.dpapi"

if ($Remove) {
    [Environment]::SetEnvironmentVariable("JIRA_BASE_URL", $null, "User")
    [Environment]::SetEnvironmentVariable("JIRA_EMAIL", $null, "User")
    if (Test-Path -LiteralPath $tokenFile) { Remove-Item -LiteralPath $tokenFile -Force }
    Write-Host "Conexão Jira removida. Revogue também o token em https://id.atlassian.com/manage-profile/security/api-tokens."
    return
}

if (-not $BaseUrl) { $BaseUrl = Read-Host "URL do Jira (ex.: https://empresa.atlassian.net)" }
$uri = $null
if (-not [Uri]::TryCreate($BaseUrl.Trim(), [UriKind]::Absolute, [ref]$uri)) { throw "URL inválida." }
if ($uri.Scheme -ne "https" -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -notin @("", "/")) {
    throw "Use uma origem HTTPS sem caminho, credenciais, query ou fragmento (ex.: https://empresa.atlassian.net)."
}
$origin = $uri.GetLeftPart([UriPartial]::Authority)

if (-not $Email) { $Email = Read-Host "E-mail da conta Atlassian" }
if ($Email -notmatch '^[^@\s]+@[^@\s]+$') { throw "E-mail inválido." }

$secure = Read-Host "Token de API do Jira (entrada oculta)" -AsSecureString
if ($secure.Length -eq 0) { throw "Token vazio." }

# Testa antes de gravar.
$plain = [Net.NetworkCredential]::new("", $secure).Password
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Email}:$plain"))
$plain = $null
try {
    $me = Invoke-RestMethod -Method Get -Uri "$origin/rest/api/3/myself" -Headers @{ Authorization = "Basic $basic"; Accept = "application/json" }
}
catch {
    throw "Falha ao autenticar no Jira: $($_.Exception.Message)"
}
finally { $basic = $null }

New-Item -ItemType Directory -Force -Path $tokenDir | Out-Null
$secure | ConvertFrom-SecureString | Set-Content -LiteralPath $tokenFile -NoNewline
[Environment]::SetEnvironmentVariable("JIRA_BASE_URL", $origin, "User")
[Environment]::SetEnvironmentVariable("JIRA_EMAIL", $Email, "User")

Write-Host "Conexão Jira validada como '$($me.displayName)' em $origin."
Write-Host "Token protegido por DPAPI em $tokenFile (legível apenas por este usuário do Windows)."
Write-Host "Reinicie a sessão do Claude Code / VS Code para carregar o servidor MCP jira-mdcc."
