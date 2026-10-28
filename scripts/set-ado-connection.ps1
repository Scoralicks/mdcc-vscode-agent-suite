[CmdletBinding()]
param(
    [string]$OrgUrl,
    [switch]$UseAzureCli,
    [switch]$Remove
)

# Configura a conexão com o Azure DevOps usada pelo servidor MCP ado-mdcc (leitura e escrita restrita).
# - ADO_ORG_URL fica como variável de usuário do Windows.
# - Autenticação, em ordem de preferência:
#   -UseAzureCli: Entra ID via `az login` (sem PAT; recomendado quando a organização usa Entra ID).
#   PAT: protegido por DPAPI no perfil do usuário, fora do repositório. Escopos mínimos:
#        Work Items (Read) para leitura; Work Items (Read & write) somente se for atualizar cards.
#   Nunca cole o PAT no chat.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tokenDir = Join-Path $env:LOCALAPPDATA "mdcc-agent-suite"
$tokenFile = Join-Path $tokenDir "ado-token.dpapi"
$adoResource = "499b84ac-1321-427f-aa17-267ca6975798"

if ($Remove) {
    [Environment]::SetEnvironmentVariable("ADO_ORG_URL", $null, "User")
    if (Test-Path -LiteralPath $tokenFile) { Remove-Item -LiteralPath $tokenFile -Force }
    Write-Host "Conexão Azure DevOps removida. Revogue também o PAT em User settings > Personal access tokens."
    return
}

if (-not $OrgUrl) { $OrgUrl = Read-Host "URL da organização (ex.: https://dev.azure.com/empresa)" }
$uri = $null
if (-not [Uri]::TryCreate($OrgUrl.Trim(), [UriKind]::Absolute, [ref]$uri)) { throw "URL inválida." }
if ($uri.Scheme -ne "https" -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
    throw "Use HTTPS, sem credenciais, query ou fragmento."
}
$segments = @($uri.AbsolutePath.Split('/', [StringSplitOptions]::RemoveEmptyEntries))
if ($uri.Host -eq "dev.azure.com" -and $segments.Count -ne 1) { throw "Use https://dev.azure.com/<organização>." }
if ($uri.Host -like "*.visualstudio.com" -and $segments.Count -ne 0) { throw "Use https://<organização>.visualstudio.com, sem caminho." }
if ($segments.Count -gt 2) { throw "Informe a organização ou coleção, não um projeto." }
$org = $uri.GetLeftPart([UriPartial]::Authority) + ($(if ($segments.Count) { "/" + ($segments -join "/") } else { "" }))

if ($UseAzureCli) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI não encontrado. Instale-o e rode 'az login'." }
    $token = (& az account get-access-token --resource $adoResource --query accessToken -o tsv 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Sem sessão no Azure CLI. Rode 'az login' com a conta da organização." }
    $headers = @{ Authorization = "Bearer $token"; Accept = "application/json" }
}
else {
    $secure = Read-Host "PAT do Azure DevOps (entrada oculta)" -AsSecureString
    if ($secure.Length -eq 0) { throw "PAT vazio." }
    $plain = [Net.NetworkCredential]::new("", $secure).Password
    $headers = @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(":$plain")); Accept = "application/json" }
    $plain = $null
}

# Testa antes de gravar. PAT inválido costuma devolver 203/302 com a página de login.
try {
    $response = Invoke-WebRequest -Method Get -Uri "$org/_apis/connectionData" -Headers $headers -MaximumRedirection 0 -SkipHttpErrorCheck
}
finally { $headers = $null; $token = $null }
if ($response.StatusCode -ne 200 -or "$($response.Headers['Content-Type'])" -notmatch 'json') {
    throw "Falha ao autenticar no Azure DevOps (HTTP $($response.StatusCode)). Verifique a URL, o PAT e seus escopos."
}
$me = $response.Content | ConvertFrom-Json

if ($UseAzureCli) {
    if (Test-Path -LiteralPath $tokenFile) { Remove-Item -LiteralPath $tokenFile -Force }
}
else {
    New-Item -ItemType Directory -Force -Path $tokenDir | Out-Null
    $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $tokenFile -NoNewline
}
[Environment]::SetEnvironmentVariable("ADO_ORG_URL", $org, "User")

Write-Host "Conexão Azure DevOps validada como '$($me.authenticatedUser.providerDisplayName)' em $org."
if ($UseAzureCli) { Write-Host "Autenticação: Entra ID via Azure CLI (o servidor renova o token pelo 'az')." }
else { Write-Host "PAT protegido por DPAPI em $tokenFile (legível apenas por este usuário do Windows)." }
Write-Host "Reinicie a sessão do Claude Code / VS Code para carregar o servidor MCP ado-mdcc."
