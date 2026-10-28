[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    # Origem HTTPS aprovada para o Playwright. Padrão: variável MDCC_PLAYWRIGHT_ORIGIN.
    [string]$PlaywrightOrigin,
    [switch]$SkipHandshake
)

# Prepara a suíte MDCC para o GitHub Copilot do Visual Studio 2026 (18.4+).
# - Agentes: o Visual Studio lê .github/agents/*.agent.md da raiz do repositório; nada a copiar.
# - MCP: gera <pasta>\.vs\mcp.json (por usuário, fora do Git), que o Visual Studio lê antes de
#   .mcp.json e .vscode\mcp.json. Usa caminhos absolutos e somente servidores stdio locais:
#   dataverse-mdcc (proxy oficial, perfil diagnosis), jira-mdcc, ado-mdcc e playwright-mdcc.
# Nenhuma URL de cliente, credencial ou token é gravada: o Dataverse vem de MDCC_DATAVERSE_URL
# ou do catálogo local, resolvido a cada início pelo launcher.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw "Node.js não encontrado. Instale Node.js 22, 24 ou 26." }

function Join-Workspace([string]$relative) { (Join-Path $root $relative).Replace('\', '/') }

$servers = [ordered]@{
    "dataverse-mdcc" = [ordered]@{
        type = "stdio"; command = "node"; args = @(Join-Workspace "tools/dataverse-mcp/launch.mjs")
        env = [ordered]@{ DATAVERSE_OPERATION_CONTEXT = "app=mdcc-vscode-agent-suite;agent=visual-studio;profile=diagnosis" }
    }
    "jira-mdcc" = [ordered]@{ type = "stdio"; command = "node"; args = @(Join-Workspace "tools/jira-mcp/server.mjs") }
    "ado-mdcc" = [ordered]@{ type = "stdio"; command = "node"; args = @(Join-Workspace "tools/ado-mcp/server.mjs") }
}

if (-not $PlaywrightOrigin) {
    $PlaywrightOrigin = if ($env:MDCC_PLAYWRIGHT_ORIGIN) { $env:MDCC_PLAYWRIGHT_ORIGIN } else { [Environment]::GetEnvironmentVariable("MDCC_PLAYWRIGHT_ORIGIN", "User") }
}
$playwrightCli = Join-Path $root "node_modules/@playwright/mcp/cli.js"
if ($PlaywrightOrigin -and (Test-Path -LiteralPath $playwrightCli)) {
    $uri = $null
    if (-not [Uri]::TryCreate($PlaywrightOrigin.Trim(), [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne "https" -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -notin @("", "/")) {
        throw "MDCC_PLAYWRIGHT_ORIGIN deve ser uma origem HTTPS sem caminho, credenciais, query ou fragmento."
    }
    $servers["playwright-mdcc"] = [ordered]@{
        type = "stdio"; command = "node"
        args = @(
            $playwrightCli.Replace('\', '/'),
            "--config", (Join-Workspace "config/playwright-mcp.config.json"),
            "--allowed-origins", $uri.GetLeftPart([UriPartial]::Authority),
            "--output-dir", (Join-Workspace ".playwright-output")
        )
    }
}
else {
    Write-Host "playwright-mdcc omitido: defina MDCC_PLAYWRIGHT_ORIGIN e rode npm ci para incluí-lo."
}

$vsDir = Join-Path $root ".vs"
New-Item -ItemType Directory -Force -Path $vsDir | Out-Null
$target = Join-Path $vsDir "mcp.json"
[ordered]@{ servers = $servers } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $target -Encoding UTF8
Write-Host "MCP do Visual Studio gerado: $target ($($servers.Keys -join ', '))."

if (-not $SkipHandshake) {
    # Handshake MCP local (initialize + tools/list), sem chamar ferramentas nem autenticar.
    $requests = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' + "`n" + '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    foreach ($name in @("jira-mdcc", "ado-mdcc")) {
        $output = $requests | & $node $servers[$name].args[0]
        $list = @($output | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.id -eq 2 })
        if ($list.Count -ne 1 -or @($list[0].result.tools).Count -lt 1) { throw "Handshake MCP falhou para $name." }
        Write-Host "Handshake $name OK ($(@($list[0].result.tools).Count) ferramentas)."
    }
    $checks = & $node (Join-Path $root "tools/doctor/doctor.mjs") --json | ConvertFrom-Json
    foreach ($check in @($checks | Where-Object { $_.area -like "Dataverse*" })) {
        if ($check.status -eq "ok") { Write-Host "$($check.area) OK: $($check.detail)." }
        else { Write-Warning "$($check.area): $($check.detail). $($check.fix)" }
    }
}

Write-Host ""
Write-Host "Próximos passos no Visual Studio:"
Write-Host "1. File > Open > Folder... e abra $root (feche e reabra se já estiver aberto)."
Write-Host "2. Copilot Chat > seletor de agentes: escolha MDCC Master (ou @MDCC Master)."
Write-Host "3. Tools (ícone de ferramentas): habilite os servidores mdcc e confirme o trust dialog na primeira execução."
