import { readFile, writeFile, rename, unlink, lstat, mkdir } from 'node:fs/promises';
import { join, resolve, dirname } from 'node:path';
import { existsSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { isDeepStrictEqual } from 'node:util';
import { pathToFileURL } from 'node:url';
import { normalizeDataverseEndpoint, loadConnectionPolicy } from './endpoint.mjs';

export const workspaceRoot = resolve(import.meta.dirname, '../..');
export const catalogPath = 'config/dataverse-mcp.local.json';
export const templatePath = 'config/mcp.template.json';
export const runtimePath = '.vscode/mcp.json';

function keys(value, allowed) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => !allowed.includes(key))) {
    throw new Error('Configuração inválida: use somente os campos documentados, sem credenciais.');
  }
}

export function validateCatalog(catalog, connection = loadConnectionPolicy()) {
  keys(catalog, ['$schema', 'schemaVersion', 'activeEnvironment', 'environments']);
  if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.environments) ||
      !catalog.environments.length || catalog.environments.length > 100) {
    throw new Error('O catálogo deve conter de 1 a 100 ambientes e schemaVersion 1.');
  }
  const ids = new Set();
  const endpoints = new Set();
  const environments = catalog.environments.map(item => {
    keys(item, ['id', 'label', 'environmentUrl', 'classification']);
    if (typeof item.id !== 'string' || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(item.id) || ids.has(item.id)) {
      throw new Error('Cada ambiente deve ter um id único em letras minúsculas, números e hífen.');
    }
    if (typeof item.label !== 'string' || !/^[\p{L}\p{N} ()_.-]{1,80}$/u.test(item.label) ||
        !['development', 'test', 'production', 'unconfirmed'].includes(item.classification)) {
      throw new Error('Rótulo ou classificação de ambiente inválido.');
    }
    const endpoint = normalizeDataverseEndpoint(item.environmentUrl, connection);
    if (endpoints.has(endpoint)) throw new Error('O catálogo contém endpoints duplicados.');
    ids.add(item.id);
    endpoints.add(endpoint);
    return { ...item, endpoint };
  });
  if (!ids.has(catalog.activeEnvironment)) throw new Error('activeEnvironment não corresponde a um ambiente cadastrado.');
  return { activeEnvironment: catalog.activeEnvironment, environments };
}

async function jsonFile(path) {
  let content;
  try { content = await readFile(path, 'utf8'); }
  catch (error) {
    if (error.code === 'ENOENT') throw new Error('Arquivo de configuração ausente. Consulte docs/predefined-environments.md.');
    throw error;
  }
  // Do not include JSON parser excerpts: malformed files may contain secrets.
  try { return JSON.parse(content.replace(/^\uFEFF/, '')); }
  catch { throw new Error('JSON inválido no arquivo de configuração.'); }
}

export async function loadCatalog(root = workspaceRoot) {
  return validateCatalog(await jsonFile(join(root, catalogPath)), loadConnectionPolicy(root));
}

// Servidores obrigatórios e opcionais do baseline. Os opcionais de work tracking só
// são aceitos com a definição exata, para que nenhum alias ou servidor extra entre.
export const requiredServers = ['dataverse-mdcc', 'playwright-mdcc'];
export const optionalServers = {
  'jira-mdcc': { type: 'stdio', command: 'node', args: ['${workspaceFolder}/tools/jira-mcp/server.mjs'] },
  'ado-mdcc': { type: 'stdio', command: 'node', args: ['${workspaceFolder}/tools/ado-mcp/server.mjs'] },
};

export async function readTemplate(root = workspaceRoot) {
  const template = await jsonFile(join(root, templatePath));
  keys(template, ['inputs', 'servers']);
  keys(template.servers, [...requiredServers, ...Object.keys(optionalServers)]);
  if (requiredServers.some(name => !template.servers[name]) ||
      Object.entries(optionalServers).some(([name, spec]) => name in template.servers && !isDeepStrictEqual(template.servers[name], spec)) ||
      !isDeepStrictEqual(template.servers['dataverse-mdcc'], { type: 'http', url: '${input:dataverse-mcp-endpoint}' }) ||
      !Array.isArray(template.inputs) || template.inputs.filter(input => input.id === 'dataverse-mcp-endpoint').length !== 1) {
    throw new Error('Template MCP incompatível com o baseline MDCC.');
  }
  return template;
}

export function renderPreset(template, environment) {
  const config = structuredClone(template);
  config.servers['dataverse-mdcc'].url = normalizeDataverseEndpoint(environment.environmentUrl);
  config.inputs = config.inputs.filter(input => input.id !== 'dataverse-mcp-endpoint');
  return config;
}

export async function checkRuntime(root = workspaceRoot) {
  const runtime = await jsonFile(join(root, runtimePath));
  const template = await readTemplate(root);
  if (isDeepStrictEqual(runtime, template)) return 'runtime-input';
  const catalog = await loadCatalog(root);
  const active = catalog.environments.find(item => item.id === catalog.activeEnvironment);
  if (!isDeepStrictEqual(runtime, renderPreset(template, active))) {
    throw new Error('Conexão divergente do catálogo/template. Pare o MCP e execute npm run mcp:select.');
  }
  return active.id;
}

export function assertUntracked(root = workspaceRoot) {
  // Scope Git trust to this read-only index query; never alter global Git config.
  // This also handles workspaces extracted under a repository owned by another identity.
  let gitRoot = resolve(root);
  while (!existsSync(join(gitRoot, '.git')) && dirname(gitRoot) !== gitRoot) gitRoot = dirname(gitRoot);
  const gitOptions = existsSync(join(gitRoot, '.git')) ? ['-c', `safe.directory=${gitRoot.replaceAll('\\', '/')}`, '-c', 'core.fsmonitor=false'] : [];
  try {
    const result = execFileSync('git', [...gitOptions, 'ls-files', '--', runtimePath, catalogPath], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    if (result.trim()) throw new Error('Configuração local rastreada pelo Git. Remova somente do índice (git rm --cached) antes de selecionar um ambiente.');
  } catch (error) {
    if (String(error.stderr ?? '').includes('not a git repository')) return;
    if (!error.stderr) throw error;
    throw new Error('Não foi possível verificar o rastreamento Git. Resolva a propriedade/acesso ao repositório antes de aplicar ambientes locais.');
  }
}

export async function applyPreset(root = workspaceRoot, { reset = false } = {}) {
  const template = await readTemplate(root);
  let config = template;
  let active;
  if (!reset) {
    const catalog = await loadCatalog(root);
    active = catalog.environments.find(item => item.id === catalog.activeEnvironment);
    config = renderPreset(template, active);
    assertUntracked(root);
  }
  const directory = join(root, '.vscode');
  await mkdir(directory, { recursive: true });
  if ((await lstat(directory)).isSymbolicLink()) throw new Error('Diretório MCP não pode ser um link.');
  const target = join(root, runtimePath);
  const current = await lstat(target).catch(error => { if (error.code !== 'ENOENT') throw error; });
  if (current?.isSymbolicLink()) throw new Error('Configuração MCP não pode ser um link.');
  const temporary = join(directory, `mcp.${randomUUID()}.local.json`);
  try {
    await writeFile(temporary, `${JSON.stringify(config, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
    await rename(temporary, target);
  } finally {
    await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
  }
  return active;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try {
    const args = process.argv.slice(2);
    if (args.length > 1 || args.some(arg => !['--check', '--reset', '--list'].includes(arg))) throw new Error('Use npm run mcp:select [-- --list|--check|--reset].');
    if (args.includes('--check')) {
      await checkRuntime();
      console.log('Configuração MCP consistente com o template e o ambiente local selecionado.');
    } else if (args.includes('--list')) {
      const catalog = await loadCatalog();
      for (const item of catalog.environments) console.log(`${item.id === catalog.activeEnvironment ? '*' : ' '} ${item.id}: ${item.label} (${item.classification})`);
    } else {
      const active = await applyPreset(workspaceRoot, { reset: args.includes('--reset') });
      console.log(active ? `Conexão preparada: ${active.label} (${active.classification}), host ${new URL(active.endpoint).hostname}.` : 'Template com input restaurado.');
      console.log('Nenhum servidor foi iniciado e nenhuma autenticação foi executada.');
      console.log('Pare o MCP, encerre a conversa anterior e reinicie dataverse-mdcc; confirme host, tenant, identidade e roles de leitura antes de consultar.');
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
