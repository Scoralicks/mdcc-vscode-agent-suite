import { readFile, realpath, stat } from 'node:fs/promises';
import { spawn, execFile } from 'node:child_process';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { loadCatalog, checkRuntime, workspaceRoot } from '../mcp-configurator/presets.mjs';
import { normalizeDataverseEndpoint } from '../mcp-configurator/endpoint.mjs';

const READ_TOOLS = ['search', 'search_data', 'read_query', 'describe'];
const MAX_PAGES = 6;
const MAX_TOOLS = 1000;
const MAX_BYTES = 8 * 1024 * 1024;
const PROTOCOLS = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'];
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

// All externally visible errors are fixed identifiers: upstream text is never logged.
class DiagnosticError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const fail = code => { throw new DiagnosticError(code); };
const safeCode = error => error instanceof DiagnosticError ? error.code : 'unexpected-failure';

export function validatePolicyEndpoint(endpoint, policy) {
  const connection = policy?.connection;
  const profile = policy?.profiles?.diagnosis;
  const proxy = policy?.codexConnection;
  if (policy?.schemaVersion !== 1 || policy.serverName !== 'dataverse-mdcc' ||
      connection?.requiredScheme !== 'https' || connection.allowedPath !== '/api/mcp' ||
      connection.previewAllowed !== false || !Array.isArray(connection.allowedHostPatterns) ||
      !connection.allowedHostPatterns.length || connection.allowedHostPatterns.length > 10 ||
      !connection.allowedHostPatterns.every(pattern => typeof pattern === 'string' && pattern.length < 256 && pattern.startsWith('^') && pattern.endsWith('$')) ||
      profile?.mutating !== false || !Array.isArray(profile.allowedTools) ||
      !profile.allowedTools.length || profile.allowedTools.some(name => !READ_TOOLS.includes(name)) ||
      new Set(profile.allowedTools).size !== profile.allowedTools.length ||
      !Array.isArray(policy.deniedTools) || profile.allowedTools.some(name => policy.deniedTools.includes(name)) ||
      proxy?.profile !== 'diagnosis' || proxy.transport !== 'stdio-microsoft-dataverse-proxy' ||
      proxy.authentication !== 'interactive-oauth-via-windows-protected-cache' ||
      policy.localPresetConnection?.profile !== 'diagnosis' ||
      policy.credentialPolicy?.allowSecretsInRepository !== false ||
      policy.credentialPolicy?.allowSecretsInChat !== false ||
      policy.credentialPolicy?.allowPlaintextEnvironmentFiles !== false) fail('policy-incompatible');
  let normalized;
  try {
    normalized = normalizeDataverseEndpoint(endpoint, connection);
    const parsed = new URL(normalized);
    if (!connection.allowedHostPatterns.some(pattern => new RegExp(pattern).test(parsed.hostname)) || parsed.pathname !== connection.allowedPath) fail('endpoint-policy-mismatch');
  } catch { fail('endpoint-policy-mismatch'); }
  return normalized;
}

async function readPolicy(root) {
  try { return JSON.parse((await readFile(join(root, 'config/dataverse-mcp-policy.json'), 'utf8')).replace(/^\uFEFF/, '')); }
  catch { fail('policy-unavailable'); }
}

function within(directory, target) {
  const path = relative(directory, target);
  return path !== '..' && !path.startsWith(`..${sep}`) && !isAbsolute(path);
}

export async function findInstalledProxy(root = workspaceRoot, appdata = process.env.APPDATA, extraBases = []) {
  const bases = [join(root, 'node_modules')];
  if (appdata) bases.push(join(appdata, 'npm/node_modules'), join(appdata, 'node_modules'));
  bases.push(...extraBases);
  for (const base of bases) {
    const directory = join(base, '@microsoft/dataverse');
    try {
      const info = JSON.parse(await readFile(join(directory, 'package.json'), 'utf8'));
      const bin = typeof info.bin === 'string' ? info.bin : info.bin?.dataverse;
      if (info.name !== '@microsoft/dataverse' || typeof bin !== 'string' || !/^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][a-zA-Z0-9.-]+)?$/.test(info.version)) continue;
      const path = resolve(directory, bin);
      if (!within(directory, path) || !within(await realpath(directory), await realpath(path)) || !(await stat(path)).isFile()) continue;
      return { bin: path, version: info.version };
    } catch { /* Missing or malformed packages never disclose their contents. */ }
  }
  return null;
}

function initialReport(live) {
  return {
    schemaVersion: 1,
    mode: live ? 'live' : 'preflight',
    ok: false,
    configuration: 'not-checked',
    environmentClassification: 'not-checked',
    client: { package: '@microsoft/dataverse', version: null, installed: false },
    endpoint: 'not-checked',
    profile: 'diagnosis',
    localHandshake: 'not-attempted',
    toolDiscovery: { status: 'not-attempted', pages: 0, allowedCount: 0, otherCount: 0 },
    metadataRead: { status: 'not-attempted', tool: null, target: 'queue' },
    authentication: 'not-verified',
    identity: 'not-verified',
    effectiveRoles: 'not-verified',
    recordsRead: false,
    writesPerformed: false,
    reason: null,
  };
}

async function prepare(root, report, discover) {
  const policy = await readPolicy(root);
  let catalog, runtime;
  try { catalog = await loadCatalog(root); runtime = await checkRuntime(root); }
  catch { fail('catalog-or-runtime-invalid'); }
  if (runtime !== catalog.activeEnvironment) fail('active-preset-not-applied');
  const active = catalog.environments.find(item => item.id === catalog.activeEnvironment);
  const endpoint = validatePolicyEndpoint(active.endpoint, policy);
  report.configuration = 'verified';
  report.endpoint = 'ga-policy-verified';
  report.environmentClassification = active.classification;
  const proxy = await discover(root);
  if (!proxy) fail('proxy-not-installed');
  report.client.installed = true;
  report.client.version = /^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][a-zA-Z0-9.-]+)?$/.test(proxy.version) ? proxy.version : null;
  return { origin: new URL(endpoint).origin, policy, proxy, classification: active.classification };
}

function scalarAccepts(schema, value) {
  return object(schema) && (schema.type === 'string' || Array.isArray(schema.type) && schema.type.includes('string')) &&
    (!own(schema, 'const') || schema.const === value) && (!own(schema, 'enum') || Array.isArray(schema.enum) && schema.enum.includes(value)) &&
    !own(schema, '$ref') && !own(schema, 'oneOf') && !own(schema, 'anyOf') && !own(schema, 'allOf') &&
    (!own(schema, 'minLength') || value.length >= schema.minLength) && (!own(schema, 'maxLength') || value.length <= schema.maxLength) &&
    !own(schema, 'pattern');
}

// Only recognized metadata selectors are supported. Unknown required fields fail closed.
export function planMetadataRead(tools, allowed = READ_TOOLS) {
  for (const name of ['describe', 'search']) {
    const tool = tools.find(item => item?.name === name);
    if (!tool || !allowed.includes(name)) continue;
    const schema = tool.inputSchema;
    if (!object(schema) || schema.type !== 'object' || !object(schema.properties) ||
        ['oneOf', 'anyOf', 'allOf', '$ref', 'if', 'dependentRequired', 'dependencies'].some(key => own(schema, key)) ||
        (schema.required !== undefined && (!Array.isArray(schema.required) || schema.required.some(key => typeof key !== 'string')))) continue;
    const args = Object.create(null);
    let targets = 0;
    let invalid = false;
    for (const [key, field] of Object.entries(schema.properties)) {
      const selector = key.replaceAll('_', '').toLowerCase();
      const target = name === 'describe'
        ? ['table', 'tablename', 'tablelogicalname', 'entityname', 'entitylogicalname', 'logicalname'].includes(selector)
        : ['query', 'searchquery', 'searchterm', 'searchtext'].includes(selector);
      if (target && scalarAccepts(field, 'queue')) { args[key] = 'queue'; targets++; }
      else if (schema.required?.includes(key)) {
        // An explicit table/metadata enum can supply a required metadata scope.
        const scopes = ['table', 'tables', 'entity', 'entities', 'metadata'];
        const supported = ['type', 'kind', 'scope', 'objecttype', 'metadatatype'].includes(selector)
          ? scopes.find(value => field?.enum?.includes(value) && scalarAccepts(field, value)) : undefined;
        if (supported) args[key] = supported;
        else invalid = true;
      }
    }
    if (schema.required?.some(key => !own(args, key))) invalid = true;
    if (!invalid && targets === 1) return { name, arguments: args };
  }
  return null;
}

export function confirmsQueueMetadata(result) {
  if (!object(result) || result.isError === true) return false;
  let budget = 2000;
  const inspect = (value, depth = 0) => {
    if (--budget < 0 || depth > 12 || !value) return false;
    if (Array.isArray(value)) return value.some(item => inspect(item, depth + 1));
    if (!object(value)) return false;
    const entries = Object.entries(value);
    const target = entries.some(([key, item]) => /^(logicalname|tablename|table|entityname|entitylogicalname|tablelogicalname)$/i.test(key.replaceAll('_', '')) && item === 'queue');
    const metadata = entries.some(([key, item]) => /^(schemaname|entitysetname|primaryidattribute|primarynameattribute|attributes|columns)$/i.test(key.replaceAll('_', '')) &&
      (typeof item === 'string' && item.length > 0 || Array.isArray(item) && item.length > 0 || object(item) && Object.keys(item).length > 0));
    return target && metadata || entries.some(([, item]) => inspect(item, depth + 1));
  };
  if (inspect(result.structuredContent)) return true;
  if (!Array.isArray(result.content)) return false;
  return result.content.some(item => {
    if (item?.type !== 'text' || typeof item.text !== 'string' || item.text.length > MAX_BYTES) return false;
    try { if (inspect(JSON.parse(item.text))) return true; } catch { /* Text need not be JSON. */ }
    // Markdown/text output must identify the logical table and real metadata labels.
    return /(?:logical\s*name|table\s*(?:name)?|entity\s*(?:name)?)\s*[:=|]?\s*[`"'*]*queue\b/i.test(item.text) &&
      /\b(?:schema\s*name|entity\s*set\s*name|primary\s*id\s*attribute|attribute\s*type|column\s+name)\b/i.test(item.text) &&
      !/\b(?:unauthorized|forbidden|access denied|permission denied|authentication failed)\b/i.test(item.text);
  });
}

function openTransport(child, signal) {
  let buffer = '';
  let bytes = 0;
  let sequence = 0;
  let terminalError;
  const pending = new Map();
  const stop = code => {
    terminalError ??= new DiagnosticError(code);
    for (const { reject } of pending.values()) reject(terminalError);
    pending.clear();
  };
  const send = message => {
    if (terminalError) throw terminalError;
    try { child.stdin.write(`${JSON.stringify(message)}\n`); }
    catch { stop('transport-write-failed'); throw terminalError; }
  };
  const onData = data => {
    bytes += Buffer.byteLength(data);
    if (bytes > MAX_BYTES) { stop('transport-output-limit'); return; }
    buffer += data.toString('utf8');
    let boundary;
    while ((boundary = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, boundary); buffer = buffer.slice(boundary + 1);
      let message;
      try { message = JSON.parse(line); } catch { continue; }
      if (!object(message) || message.jsonrpc !== '2.0') continue;
      if (typeof message.method === 'string') {
        // No elicitation, sampling or filesystem access is permitted through this client.
        if (own(message, 'id') && (typeof message.id === 'string' || typeof message.id === 'number')) {
          try { send({ jsonrpc: '2.0', id: message.id, error: { code: -32601, message: 'Unsupported request' } }); } catch { /* Already rejected. */ }
        }
        continue;
      }
      const request = pending.get(message.id);
      if (!request) continue;
      pending.delete(message.id);
      if (own(message, 'error')) request.reject(new DiagnosticError('rpc-request-failed'));
      else if (!own(message, 'result')) request.reject(new DiagnosticError('rpc-response-invalid'));
      else request.resolve(message.result);
    }
  };
  const onError = () => stop('proxy-process-failed');
  const onClose = () => stop('proxy-process-closed');
  const onAbort = () => stop('timeout-or-cancelled');
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', onData);
  // Drain all diagnostics without storing or relaying a single byte.
  child.stderr.resume();
  child.on('error', onError);
  child.on('close', onClose);
  child.stdin.on('error', onError);
  signal.addEventListener('abort', onAbort, { once: true });
  if (signal.aborted) onAbort();
  return {
    request(method, params) {
      if (terminalError) return Promise.reject(terminalError);
      const id = ++sequence;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        try { send({ jsonrpc: '2.0', id, method, params }); }
        catch (error) { pending.delete(id); reject(error); }
      });
    },
    notify(method) { send({ jsonrpc: '2.0', method }); },
    dispose() { signal.removeEventListener('abort', onAbort); stop('transport-closed'); },
  };
}

async function stopProxy(child, platform) {
  if (!child) return;
  // The official JS wrapper does not forward signals. Kill its tree before the wrapper.
  if (platform === 'win32' && Number.isInteger(child.pid) && child.pid > 0) {
    const taskkill = join(process.env.SystemRoot || 'C:\\Windows', 'System32/taskkill.exe');
    await new Promise(resolve => {
      try { execFile(taskkill, ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, shell: false, timeout: 5000, maxBuffer: 1024 }, () => resolve()); }
      catch { resolve(); }
    });
  }
  try { child.stdin.destroy(); child.kill(); } catch { /* Never expose process errors. */ }
}

async function readTools(transport, report) {
  const tools = [];
  const cursors = new Set();
  let cursor;
  do {
    if (report.toolDiscovery.pages >= MAX_PAGES) fail('tool-pagination-limit');
    const page = await transport.request('tools/list', cursor ? { cursor } : {});
    report.toolDiscovery.pages++;
    if (!object(page) || !Array.isArray(page.tools) || page.tools.some(tool => !object(tool) || typeof tool.name !== 'string')) fail('tool-list-invalid');
    tools.push(...page.tools);
    if (tools.length > MAX_TOOLS || new Set(tools.map(tool => tool.name)).size !== tools.length) fail('tool-list-invalid');
    cursor = page.nextCursor;
    if (cursor !== undefined && (typeof cursor !== 'string' || !cursor.length || cursor.length > 4096 || cursors.has(cursor))) fail('tool-pagination-invalid');
    if (cursor) cursors.add(cursor);
  } while (cursor);
  return tools;
}

export async function runDiagnostics({ root = workspaceRoot, live = false, timeoutSeconds = 90, signal } = {}, dependencies = {}) {
  const report = initialReport(live);
  let child, transport, timer;
  const controller = new AbortController();
  const platform = dependencies.platform ?? process.platform;
  const cancel = () => controller.abort();
  try {
    if (!Number.isInteger(timeoutSeconds) || timeoutSeconds < 1 || timeoutSeconds > 180) fail('timeout-out-of-range');
    const context = await prepare(root, report, dependencies.findProxy ?? findInstalledProxy);
    if (!live) { report.ok = true; return report; }
    if (platform !== 'win32') fail('windows-protected-cache-required');
    if (!['development', 'test'].includes(context.classification)) fail('environment-classification-not-supported');
    signal?.addEventListener('abort', cancel, { once: true });
    if (signal?.aborted) fail('timeout-or-cancelled');
    timer = setTimeout(cancel, timeoutSeconds * 1000);
    child = (dependencies.spawnProxy ?? spawn)(process.execPath, [context.proxy.bin, 'mcp', context.origin], {
      shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], cwd: root,
    });
    transport = openTransport(child, controller.signal);
    const initialized = await transport.request('initialize', {
      protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'mdcc-readonly-diagnostics', version: '1.0.0' },
    });
    if (!object(initialized) || !PROTOCOLS.includes(initialized.protocolVersion) || !object(initialized.capabilities) || !object(initialized.capabilities.tools)) fail('handshake-invalid');
    report.localHandshake = 'confirmed';
    transport.notify('notifications/initialized');
    const tools = await readTools(transport, report);
    report.toolDiscovery.status = 'listed-by-proxy';
    report.toolDiscovery.allowedCount = tools.filter(tool => context.policy.profiles.diagnosis.allowedTools.includes(tool.name)).length;
    report.toolDiscovery.otherCount = tools.length - report.toolDiscovery.allowedCount;
    const plan = planMetadataRead(tools, context.policy.profiles.diagnosis.allowedTools);
    if (!plan) fail('safe-metadata-tool-unavailable');
    report.metadataRead.tool = plan.name;
    report.metadataRead.status = 'attempted';
    const result = await transport.request('tools/call', plan);
    if (result?.isError === true) fail('metadata-tool-error');
    if (!confirmsQueueMetadata(result)) fail('metadata-not-confirmed');
    report.metadataRead.status = 'confirmed';
    report.authentication = 'confirmed-by-metadata-response';
    report.ok = true;
  } catch (error) {
    report.reason = safeCode(error);
    if (report.configuration === 'not-checked') report.configuration = 'failed';
    if (report.metadataRead.status === 'attempted') report.metadataRead.status = 'failed';
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', cancel);
    transport?.dispose();
    try { await (dependencies.stopProxy ?? stopProxy)(child, platform); }
    catch { report.ok = false; report.reason = 'proxy-cleanup-failed'; }
  }
  return report;
}

export async function preflight(options, dependencies) {
  return runDiagnostics({ ...options, live: false }, dependencies);
}
