// Inicia o proxy oficial @microsoft/dataverse (stdio) para o servidor dataverse-mdcc do Claude Code
// em Windows, Linux ou macOS. O ambiente vem de MDCC_DATAVERSE_URL ou, se ausente, do ambiente ativo
// do catálogo local (config/dataverse-mcp.local.json). A URL é validada pela política de conexão.
// stdout pertence ao protocolo MCP: mensagens do launcher vão somente para stderr.
import { spawn } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { normalizeDataverseEndpoint } from '../mcp-configurator/endpoint.mjs';
import { loadCatalog, workspaceRoot } from '../mcp-configurator/presets.mjs';
import { findInstalledProxy } from '../dataverse-diagnostics/diagnostics.mjs';

export async function resolveEnvironment(env = process.env, root = workspaceRoot) {
  if (env.MDCC_DATAVERSE_URL?.trim()) {
    const endpoint = normalizeDataverseEndpoint(env.MDCC_DATAVERSE_URL);
    return { endpoint, source: 'MDCC_DATAVERSE_URL', classification: 'unconfirmed', label: null };
  }
  let catalog;
  try { catalog = await loadCatalog(root); } catch {
    throw new Error('Defina MDCC_DATAVERSE_URL (URL base do ambiente) ou crie config/dataverse-mcp.local.json a partir de config/dataverse-mcp.example.json.');
  }
  const active = catalog.environments.find((item) => item.id === catalog.activeEnvironment);
  return { endpoint: active.endpoint, source: `catálogo local (${active.id})`, classification: active.classification, label: active.label };
}

// Prefixo global do npm fora do Windows (lá, %APPDATA%\npm já é coberto por findInstalledProxy).
function globalNodeModules(env) {
  if (process.platform === 'win32') return [];
  const prefixes = [env.npm_config_prefix, env.NPM_CONFIG_PREFIX, dirname(dirname(process.execPath))].filter(Boolean);
  return prefixes.map((prefix) => join(prefix, 'lib', 'node_modules'));
}

export async function locateProxy(env = process.env, root = workspaceRoot) {
  const extra = [env.MDCC_DATAVERSE_PROXY_ROOT, ...globalNodeModules(env)].filter(Boolean);
  return findInstalledProxy(root, env.APPDATA, extra);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try {
    const target = await resolveEnvironment();
    const proxy = await locateProxy();
    if (!proxy) throw new Error('Proxy @microsoft/dataverse não encontrado. Instale com: npm install -g @microsoft/dataverse');
    const baseUrl = target.endpoint.replace(/\/api\/mcp$/, '');
    process.stderr.write(`[dataverse-mdcc] ${new URL(baseUrl).hostname} (${target.classification}) via ${target.source}; proxy ${proxy.version}; perfil diagnosis.\n`);
    if (target.classification === 'production') {
      process.stderr.write('[dataverse-mdcc] Ambiente classificado como produção: somente leitura, com consultas mínimas e aprovadas.\n');
    }
    const child = spawn(process.execPath, [proxy.bin, 'mcp', baseUrl], {
      stdio: 'inherit',
      env: { ...process.env, DATAVERSE_OPERATION_CONTEXT: process.env.DATAVERSE_OPERATION_CONTEXT ?? 'app=mdcc-vscode-agent-suite;agent=claude-code;profile=diagnosis' },
    });
    for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
    child.on('exit', (code, signal) => { process.exitCode = code ?? (signal ? 1 : 0); });
  } catch (error) {
    process.stderr.write(`[dataverse-mdcc] ${error.message}\n`);
    process.exitCode = 1;
  }
}
