import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { normalizeDataverseEndpoint } from '../tools/mcp-configurator/endpoint.mjs';
import { startConfigurator } from '../tools/mcp-configurator/server.mjs';

test('normaliza URL base e endpoint GA', () => {
  assert.equal(normalizeDataverseEndpoint(' https://Contoso.crm4.dynamics.com '), 'https://contoso.crm4.dynamics.com/api/mcp');
  assert.equal(normalizeDataverseEndpoint('https://contoso.crm.dynamics.com/api/mcp/'), 'https://contoso.crm.dynamics.com/api/mcp');
});

for (const invalid of [
  'http://contoso.crm4.dynamics.com',
  'https://user:secret@contoso.crm4.dynamics.com',
  'https://contoso.crm4.dynamics.com:444',
  'https://contoso.crm4.dynamics.com/api/mcp_preview',
  'https://contoso.crm4.dynamics.com/api/mcp?x=1',
  'https://contoso.crm4.dynamics.com/#fragment',
  'https://contoso.crm4.dynamics.com.evil.example',
  'https://127.0.0.1/api/mcp',
  'https://contoso.crm4.dynamics.com./api/mcp',
  'https://xn--contoso.crm4.dynamics.com/api/mcp'
]) test(`rejeita endpoint inseguro: ${invalid}`, () => assert.throws(() => normalizeDataverseEndpoint(invalid)));

test('serviço local aplica Host, Origin, CSRF, rotação, limite e não persiste endpoint', async t => {
  const { server, origin } = await startConfigurator({ idleTimeoutMs: 30_000 });
  t.after(() => new Promise(resolveClose => server.listening ? server.close(resolveClose) : resolveClose()));

  const page = await fetch(`${origin}/`);
  assert.equal(page.status, 200);
  assert.equal(page.headers.get('cache-control'), 'no-store');
  const html = await page.text();
  const firstToken = html.match(/let csrf = '([a-f0-9]+)'/)?.[1];
  assert.ok(firstToken);

  const canaryHost = `canary-${Date.now()}.crm4.dynamics.com`;
  const accepted = await post(origin, '/api/validate', firstToken, { environmentUrl: `https://${canaryHost}` });
  assert.equal(accepted.response.status, 200);
  assert.equal(accepted.data.persisted, false);
  assert.equal(accepted.data.endpoint, `https://${canaryHost}/api/mcp`);
  assert.notEqual(accepted.data.csrfToken, firstToken);

  const replay = await post(origin, '/api/validate', firstToken, { environmentUrl: `https://${canaryHost}` });
  assert.equal(replay.response.status, 403);

  const missingOrigin = await fetch(`${origin}/api/validate`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-mdcc-csrf': accepted.data.csrfToken },
    body: JSON.stringify({ environmentUrl: `https://${canaryHost}` })
  });
  assert.equal(missingOrigin.status, 403);

  const oversized = await fetch(`${origin}/api/validate`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'origin': origin, 'x-mdcc-csrf': accepted.data.csrfToken },
    body: JSON.stringify({ environmentUrl: `https://${canaryHost}`, padding: 'x'.repeat(17_000) })
  });
  assert.equal(oversized.status, 413);

  const badHost = await rawRequest(origin, { method: 'GET', path: '/', host: 'evil.example' });
  assert.equal(badHost.statusCode, 403);

  const workspaceRoot = resolve(import.meta.dirname, '..');
  const searchable = ['.vscode', 'config', 'docs', 'scripts', 'tools', 'README.md', 'package.json'];
  for (const relative of searchable) {
    for (const file of await listFiles(join(workspaceRoot, relative))) {
      assert.equal((await readFile(file, 'utf8')).includes(canaryHost), false, `Canary persisted in ${file}`);
    }
  }

  const closing = await post(origin, '/api/close', accepted.data.csrfToken, {});
  assert.equal(closing.response.status, 200);
});

async function post(origin, path, token, body) {
  const response = await fetch(`${origin}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'origin': origin, 'x-mdcc-csrf': token },
    body: JSON.stringify(body)
  });
  return { response, data: await response.json() };
}

async function rawRequest(origin, options) {
  const { request } = await import('node:http');
  const target = new URL(origin);
  return new Promise((resolveRequest, reject) => {
    const req = request({ hostname: target.hostname, port: target.port, method: options.method, path: options.path, headers: { Host: options.host } }, response => {
      response.resume();
      response.on('end', () => resolveRequest(response));
    });
    req.on('error', reject);
    req.end();
  });
}

async function listFiles(path) {
  const stat = await import('node:fs/promises').then(fs => fs.stat(path));
  if (stat.isFile()) return [path];
  const files = [];
  for (const entry of await readdir(path, { withFileTypes: true })) {
    if (entry.name === 'node_modules') continue;
    files.push(...await listFiles(join(path, entry.name)));
  }
  return files;
}
