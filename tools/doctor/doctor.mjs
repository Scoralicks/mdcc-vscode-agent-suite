// Verifica, sem rede e sem autenticar, se a estação está pronta para usar a suíte MDCC.
// Nunca imprime segredos: só indica se cada item está presente e qual script resolve a lacuna.
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { checkRuntime, workspaceRoot } from '../mcp-configurator/presets.mjs';
import { locateProxy, resolveEnvironment } from '../dataverse-mcp/launch.mjs';
import { readUserEnvironment } from '../shared/secrets.mjs';
import { tokenFilePath as jiraTokenFile } from '../jira-mcp/server.mjs';
import { tokenFilePath as adoTokenFile } from '../ado-mcp/server.mjs';

const DOCS_MAX_AGE_DAYS = 14;

export function commandExists(name) {
  const finder = process.platform === 'win32' ? 'where' : 'which';
  return spawnSync(finder, [name], { stdio: 'ignore', windowsHide: true }).status === 0;
}

function envValue(env, name, readUser) {
  return env[name] || readUser(name);
}

export async function runChecks({ root = workspaceRoot, env = process.env, exists = commandExists, now = Date.now(), nodeVersion = process.versions.node, readUser = readUserEnvironment } = {}) {
  const checks = [];
  const add = (area, status, detail, fix) => checks.push({ area, status, detail, ...(fix && { fix }) });

  const major = Number(nodeVersion.split('.')[0]);
  if (major >= 22 && major < 27) add('Node.js', 'ok', `v${nodeVersion}`);
  else add('Node.js', 'fail', `v${nodeVersion} fora de >=22 <27`, 'Instale Node.js 22, 24 ou 26.');

  if (exists('git')) add('Git', 'ok', 'disponível');
  else add('Git', 'fail', 'não encontrado', 'Instale o Git; ele é necessário para sincronizar a documentação.');

  if (exists('pwsh')) add('PowerShell 7', 'ok', 'disponível');
  else add('PowerShell 7', 'warn', 'pwsh não encontrado', 'Instale PowerShell 7 para validações, build e scripts de conexão.');

  const indexPath = join(root, '.reference/mdcc-doc-index.json');
  if (!existsSync(indexPath)) {
    add('Documentação oficial', 'warn', 'não sincronizada', 'pwsh -NoProfile -File scripts/sync-mdcc-docs.ps1');
  } else {
    try {
      const index = JSON.parse(readFileSync(indexPath, 'utf8').replace(/^﻿/, ''));
      const ageDays = Math.floor((now - Date.parse(index.generatedAtUtc)) / 86400000);
      const customerService = (index.files ?? []).filter((f) => f.repository === 'dynamics-365-customer-engagement').length;
      const detail = `${index.count} arquivos, sincronizada há ${ageDays} dia(s); Customer Service: ${customerService || 'não indexado'}`;
      if (!Number.isFinite(ageDays) || ageDays > DOCS_MAX_AGE_DAYS) add('Documentação oficial', 'warn', detail, 'Sincronize de novo: pwsh -NoProfile -File scripts/sync-mdcc-docs.ps1');
      else if (!customerService) add('Documentação oficial', 'warn', detail, 'Rode a sincronização sem -SkipCustomerService para incluir Customer Service.');
      else add('Documentação oficial', 'ok', detail);
    } catch {
      add('Documentação oficial', 'warn', 'índice ilegível', 'pwsh -NoProfile -File scripts/sync-mdcc-docs.ps1');
    }
  }

  try {
    const target = await resolveEnvironment(env, root);
    add('Dataverse (ambiente)', 'ok', `${new URL(target.endpoint).hostname} (${target.classification}) via ${target.source}`);
  } catch (error) {
    add('Dataverse (ambiente)', 'warn', error.message, 'Defina MDCC_DATAVERSE_URL ou copie config/dataverse-mcp.example.json para config/dataverse-mcp.local.json.');
  }

  const proxy = await locateProxy(env, root).catch(() => null);
  if (proxy) add('Dataverse (proxy Claude Code)', 'ok', `@microsoft/dataverse ${proxy.version}`);
  else add('Dataverse (proxy Claude Code)', 'warn', 'não instalado', 'npm install -g @microsoft/dataverse (necessário só no Claude Code).');

  try {
    const runtime = await checkRuntime(root);
    add('VS Code MCP', 'ok', runtime === 'runtime-input' ? 'template com URL solicitada em runtime' : `preset ativo: ${runtime}`);
  } catch (error) {
    add('VS Code MCP', 'warn', error.message, 'npm run mcp:select (ou -- --reset para o template genérico).');
  }

  if (existsSync(join(root, 'node_modules/@playwright/mcp/cli.js'))) add('Playwright MCP', 'ok', 'instalado');
  else add('Playwright MCP', 'warn', 'dependências ausentes', 'npm ci (ou a task MDCC: Install Playwright dependencies).');

  const jiraUrl = envValue(env, 'JIRA_BASE_URL', readUser);
  const jiraToken = env.JIRA_API_TOKEN || existsSync(jiraTokenFile(env));
  if (jiraUrl && envValue(env, 'JIRA_EMAIL', readUser) && jiraToken) add('Jira', 'ok', new URL(jiraUrl).hostname);
  else add('Jira', 'info', 'não configurado (opcional)', 'pwsh -NoProfile -File scripts/set-jira-connection.ps1');

  const adoUrl = envValue(env, 'ADO_ORG_URL', readUser);
  const adoAuth = env.ADO_PAT ? 'PAT (variável)' : existsSync(adoTokenFile(env)) ? 'PAT (DPAPI)' : exists('az') ? 'Entra ID (Azure CLI)' : null;
  if (adoUrl && adoAuth) add('Azure DevOps', 'ok', `${adoUrl} · ${adoAuth}`);
  else if (adoUrl) add('Azure DevOps', 'warn', `${adoUrl} sem credencial`, 'pwsh -NoProfile -File scripts/set-ado-connection.ps1 (ou -UseAzureCli após az login).');
  else add('Azure DevOps', 'info', 'não configurado (opcional)', 'pwsh -NoProfile -File scripts/set-ado-connection.ps1');

  return checks;
}

const ICON = { ok: '✔', warn: '!', fail: '✖', info: '·' };

export function formatReport(checks) {
  const width = Math.max(...checks.map((c) => c.area.length));
  const lines = checks.map((c) => `${ICON[c.status]} ${c.area.padEnd(width)}  ${c.detail}${c.fix ? `\n  ${' '.repeat(width)}  → ${c.fix}` : ''}`);
  const failed = checks.filter((c) => c.status === 'fail').length;
  const warned = checks.filter((c) => c.status === 'warn').length;
  lines.push('', failed ? `${failed} item(ns) bloqueante(s), ${warned} aviso(s).` : warned ? `Pronto, com ${warned} aviso(s).` : 'Tudo pronto.');
  return lines.join('\n');
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const checks = await runChecks();
  if (process.argv.includes('--json')) console.log(JSON.stringify(checks, null, 2));
  else console.log(formatReport(checks));
  if (checks.some((c) => c.status === 'fail')) process.exitCode = 1;
}
