import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough, Writable } from 'node:stream';
import { mkdtemp, mkdir, readFile, writeFile, rm, copyFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runDiagnostics, planMetadataRead, confirmsQueueMetadata, validatePolicyEndpoint, findInstalledProxy } from '../tools/dataverse-diagnostics/diagnostics.mjs';
import { parseArguments } from '../tools/dataverse-diagnostics/cli.mjs';
import { workspaceRoot, renderPreset } from '../tools/mcp-configurator/presets.mjs';

const describe = { name: 'describe', inputSchema: { type: 'object', properties: { tableName: { type: 'string' } }, required: ['tableName'] } };
const metadata = { content: [{ type: 'text', text: JSON.stringify({ LogicalName: 'queue', SchemaName: 'Queue', Attributes: [{ LogicalName: 'queueid' }] }) }] };
const handshake = { protocolVersion: '2025-06-18', capabilities: { tools: {} } };
const canary = 'PRIVATE-CANARY-token-https://contoso.crm9.dynamics.com';

async function fixture(t, classification = 'development') {
  const root = await mkdtemp(join(tmpdir(), 'mdcc-diagnostics-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'config'));
  await mkdir(join(root, '.vscode'));
  await copyFile(join(workspaceRoot, 'config/dataverse-mcp-policy.json'), join(root, 'config/dataverse-mcp-policy.json'));
  await copyFile(join(workspaceRoot, 'config/mcp.template.json'), join(root, 'config/mcp.template.json'));
  const active = { id: 'dev', label: 'Development', environmentUrl: 'https://contoso.crm4.dynamics.com', classification };
  await writeFile(join(root, 'config/dataverse-mcp.local.json'), JSON.stringify({ schemaVersion: 1, activeEnvironment: 'dev', environments: [active] }));
  const template = JSON.parse(await readFile(join(root, 'config/mcp.template.json'), 'utf8'));
  await writeFile(join(root, '.vscode/mcp.json'), JSON.stringify(renderPreset(template, active)));
  return root;
}

function simulated(respond = request => request.method === 'initialize' ? handshake : request.method === 'tools/list' ? { tools: [describe] } : metadata) {
  const child = new EventEmitter();
  child.stdout = new PassThrough(); child.stderr = new PassThrough(); child.pid = 12345;
  const requests = [], launches = [];
  let stopped = 0;
  child.stdin = new Writable({ write(data, encoding, callback) {
    const request = JSON.parse(data.toString()); requests.push(request);
    callback();
    if (!Object.hasOwn(request, 'id')) return;
    queueMicrotask(() => {
      const response = respond(request, child);
      if (response === undefined) return;
      const envelope = response?.rpcError ? { error: response.rpcError } : { result: response };
      child.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id: request.id, ...envelope })}\n`);
    });
  } });
  const dependencies = {
    platform: 'win32',
    findProxy: async () => ({ bin: 'C:\\safe\\dataverse.js', version: '1.0.18' }),
    spawnProxy: (...args) => { launches.push(args); return child; },
    stopProxy: async target => { if (target) { stopped++; child.stdout.destroy(); child.stderr.destroy(); child.stdin.destroy(); } },
  };
  return { child, dependencies, requests, launches, stopped: () => stopped };
}

test('offline preflight validates active preset and policy without spawning or authenticating', async t => {
  const root = await fixture(t), fake = simulated();
  const result = await runDiagnostics({ root }, fake.dependencies);
  assert.equal(result.ok, true);
  assert.equal(fake.launches.length, 0);
  assert.equal(result.authentication, 'not-verified');
  assert.equal(result.metadataRead.status, 'not-attempted');
  assert.equal(JSON.stringify(result).includes('contoso'), false);
});

test('metadata-only live read separates handshake, discovery, authentication and unverified identity', async t => {
  const root = await fixture(t), fake = simulated();
  const result = await runDiagnostics({ root, live: true }, fake.dependencies);
  assert.equal(result.ok, true);
  assert.equal(result.localHandshake, 'confirmed');
  assert.equal(result.toolDiscovery.status, 'listed-by-proxy');
  assert.equal(result.metadataRead.status, 'confirmed');
  assert.equal(result.authentication, 'confirmed-by-metadata-response');
  assert.equal(result.identity, 'not-verified');
  assert.equal(result.effectiveRoles, 'not-verified');
  assert.equal(result.recordsRead, false);
  assert.equal(result.writesPerformed, false);
  assert.deepEqual(fake.requests.map(item => item.method), ['initialize', 'notifications/initialized', 'tools/list', 'tools/call']);
  assert.deepEqual(fake.requests.at(-1).params, { name: 'describe', arguments: { tableName: 'queue' } });
  assert.deepEqual(fake.launches[0][1], ['C:\\safe\\dataverse.js', 'mcp', 'https://contoso.crm4.dynamics.com']);
  assert.equal(fake.launches[0][2].shell, false);
  assert.equal(fake.launches[0][2].windowsHide, true);
  assert.equal(fake.stopped(), 1);
});

test('tool isError and JSONRPC errors never count as authenticated or disclose upstream text', async t => {
  const root = await fixture(t);
  for (const failure of [{ ...metadata, isError: true, private: canary }, { rpcError: { code: 401, message: canary } }, {}]) {
    const fake = simulated(request => request.method === 'initialize' ? handshake : request.method === 'tools/list' ? { tools: [describe] } : failure);
    const result = await runDiagnostics({ root, live: true }, fake.dependencies);
    assert.equal(result.ok, false);
    assert.equal(result.localHandshake, 'confirmed');
    assert.equal(result.metadataRead.status, 'failed');
    assert.equal(result.authentication, 'not-verified');
    assert.equal(JSON.stringify(result).includes(canary), false);
    assert.equal(fake.stopped(), 1);
  }
});

test('a bounded timeout and explicit cancellation close the child and preserve partial evidence', async t => {
  const root = await fixture(t), fake = simulated(request => request.method === 'initialize' ? handshake : undefined);
  const result = await runDiagnostics({ root, live: true, timeoutSeconds: 1 }, fake.dependencies);
  assert.equal(result.reason, 'timeout-or-cancelled');
  assert.equal(result.localHandshake, 'confirmed');
  assert.equal(fake.stopped(), 1);
  const controller = new AbortController(); controller.abort();
  const cancelled = simulated();
  assert.equal((await runDiagnostics({ root, live: true, signal: controller.signal }, cancelled.dependencies)).reason, 'timeout-or-cancelled');
  assert.equal(cancelled.launches.length, 0);
});

test('paginated tools are discovered without selecting any mutating tool', async t => {
  const root = await fixture(t);
  const fake = simulated(request => {
    if (request.method === 'initialize') return handshake;
    if (request.method === 'tools/list') return request.params.cursor ? { tools: [describe] } : { tools: [{ name: 'update_record', inputSchema: describe.inputSchema }, { name: canary }], nextCursor: 'page2' };
    return metadata;
  });
  const result = await runDiagnostics({ root, live: true }, fake.dependencies);
  assert.equal(result.ok, true);
  assert.equal(result.toolDiscovery.pages, 2);
  assert.equal(result.toolDiscovery.allowedCount, 1);
  assert.equal(result.toolDiscovery.otherCount, 2);
  assert.equal(JSON.stringify(result).includes(canary), false);
  assert.deepEqual(fake.requests.filter(item => item.method === 'tools/call').map(item => item.params.name), ['describe']);
});

test('missing metadata tool, unsafe schema and duplicate cursors fail without any tool call', async t => {
  const root = await fixture(t);
  for (const tools of [[], [{ name: 'update_record', inputSchema: describe.inputSchema }], [{ ...describe, inputSchema: { ...describe.inputSchema, required: ['secret'] } }]]) {
    const fake = simulated(request => request.method === 'initialize' ? handshake : { tools });
    const result = await runDiagnostics({ root, live: true }, fake.dependencies);
    assert.equal(result.reason, 'safe-metadata-tool-unavailable');
    assert.equal(fake.requests.some(item => item.method === 'tools/call'), false);
  }
  const fake = simulated(request => request.method === 'initialize' ? handshake : { tools: [], nextCursor: 'same-cursor' });
  assert.equal((await runDiagnostics({ root, live: true }, fake.dependencies)).reason, 'tool-pagination-invalid');
  assert.equal(fake.requests.filter(item => item.method === 'tools/list').length, 2);
});

test('unbounded cursor sequence stops at six pages', async t => {
  const root = await fixture(t); let pages = 0;
  const fake = simulated(request => request.method === 'initialize' ? handshake : { tools: [], nextCursor: `page${++pages}` });
  assert.equal((await runDiagnostics({ root, live: true }, fake.dependencies)).reason, 'tool-pagination-limit');
  assert.equal(pages, 6);
});

test('malicious proxy logs, notifications and failures never escape the sanitized report', async t => {
  const root = await fixture(t);
  const fake = simulated((request, child) => {
    child.stdout.write(`${canary}\n${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/message', params: { data: canary } })}\n`);
    child.stderr.write(canary);
    if (request.method === 'initialize') return handshake;
    if (request.method === 'tools/list') return { tools: [describe] };
    return { content: [{ type: 'text', text: canary }], isError: true };
  });
  const result = await runDiagnostics({ root, live: true }, fake.dependencies);
  assert.equal(result.reason, 'metadata-tool-error');
  assert.equal(JSON.stringify(result).includes(canary), false);
  const failed = simulated(); failed.dependencies.spawnProxy = () => { throw new Error(canary); };
  assert.equal((await runDiagnostics({ root, live: true }, failed.dependencies)).reason, 'unexpected-failure');
});

test('policy restrictions, runtime divergence and production prevent process launch', async t => {
  const root = await fixture(t), policy = JSON.parse(await readFile(join(root, 'config/dataverse-mcp-policy.json'), 'utf8'));
  for (const mutate of [
    p => { p.connection.allowedHostPatterns = ['^different\\.crm4\\.dynamics\\.com$']; },
    p => { p.connection.allowedPath = '/api/mcp_preview'; },
    p => { p.profiles.diagnosis.allowedTools.push('update_record'); },
    p => { p.profiles.diagnosis.mutating = true; },
    p => { p.codexConnection.authentication = 'client-secret'; },
  ]) {
    const next = structuredClone(policy); mutate(next);
    await writeFile(join(root, 'config/dataverse-mcp-policy.json'), JSON.stringify(next));
    const fake = simulated(), result = await runDiagnostics({ root, live: true }, fake.dependencies);
    assert.equal(result.ok, false); assert.equal(fake.launches.length, 0);
  }
  await writeFile(join(root, 'config/dataverse-mcp-policy.json'), JSON.stringify(policy));
  const runtime = JSON.parse(await readFile(join(root, '.vscode/mcp.json'), 'utf8'));
  runtime.servers['dataverse-mdcc'].url = 'https://contoso.crm.dynamics.com/api/mcp';
  await writeFile(join(root, '.vscode/mcp.json'), JSON.stringify(runtime));
  const divergent = simulated();
  assert.equal((await runDiagnostics({ root, live: true }, divergent.dependencies)).reason, 'catalog-or-runtime-invalid');
  assert.equal(divergent.launches.length, 0);
  for (const classification of ['production', 'unconfirmed']) {
    const classified = await fixture(t, classification), fake = simulated();
    assert.equal((await runDiagnostics({ root: classified, live: true }, fake.dependencies)).reason, 'environment-classification-not-supported');
    assert.equal(fake.launches.length, 0);
  }
});

test('only Windows cache is supported for live and credentials/preview/custom tools have no CLI arguments', async t => {
  const root = await fixture(t), fake = simulated(); fake.dependencies.platform = 'linux';
  assert.equal((await runDiagnostics({ root, live: true }, fake.dependencies)).reason, 'windows-protected-cache-required');
  assert.equal(fake.launches.length, 0);
  assert.deepEqual(parseArguments([]), { live: false, timeoutSeconds: 90 });
  assert.deepEqual(parseArguments(['--live', '--timeout-seconds', '180']), { live: true, timeoutSeconds: 180 });
  for (const args of [['--live', '--preflight'], ['--preview'], ['--validate'], ['--tool', 'update_record'], ['--client-secret', canary], ['--timeout-seconds', '181'], ['--timeout-seconds', '0']]) assert.throws(() => parseArguments(args));
});

test('schema-derived metadata planning and evidence reject empty/error/foreign table results', () => {
  const search = { name: 'search', inputSchema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } };
  assert.equal(planMetadataRead([search]).name, 'search');
  assert.equal(planMetadataRead([describe, search]).name, 'describe');
  assert.equal(planMetadataRead([describe], ['read_query']), null);
  const unsafe = structuredClone(describe); unsafe.inputSchema.properties.tableName.enum = ['account'];
  assert.equal(planMetadataRead([unsafe]), null);
  assert.equal(confirmsQueueMetadata(metadata), true);
  for (const result of [{}, { content: [] }, { content: [{ type: 'text', text: 'OK' }] }, { structuredContent: { LogicalName: 'account', SchemaName: 'Account' } }, { structuredContent: { LogicalName: 'queue' } }, { ...metadata, isError: true }]) assert.equal(confirmsQueueMetadata(result), false);
});

test('package discovery uses installed official package and refuses escaping bin paths', async t => {
  const root = await fixture(t), directory = join(root, 'node_modules/@microsoft/dataverse');
  await mkdir(join(directory, 'bin'), { recursive: true });
  await writeFile(join(directory, 'bin/dataverse.js'), '// fixture');
  const info = { name: '@microsoft/dataverse', version: '1.0.18', bin: { dataverse: 'bin/dataverse.js' } };
  await writeFile(join(directory, 'package.json'), JSON.stringify(info));
  assert.equal((await findInstalledProxy(root, null)).version, '1.0.18');
  info.bin.dataverse = '../../../outside.js';
  await writeFile(join(directory, 'package.json'), JSON.stringify(info));
  assert.equal(await findInstalledProxy(root, null), null);
});

test('endpoint gate rejects credentials, queries, foreign hosts and preview before using policy', async t => {
  const root = await fixture(t), policy = JSON.parse(await readFile(join(root, 'config/dataverse-mcp-policy.json'), 'utf8'));
  for (const endpoint of ['https://user:password@contoso.crm4.dynamics.com/api/mcp', 'https://contoso.crm4.dynamics.com/api/mcp?token=private', 'https://example.com/api/mcp', 'https://contoso.crm4.dynamics.com/api/mcp_preview']) assert.throws(() => validatePolicyEndpoint(endpoint, policy));
});

