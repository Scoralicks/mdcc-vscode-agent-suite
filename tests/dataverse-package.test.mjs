import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, cp, rm, readdir } from 'node:fs/promises';
import { join, resolve, relative, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const project = resolve(import.meta.dirname, '..');
const buildSource = await readFile(join(project, 'scripts/build-mdcc-package.ps1'), 'utf8');
const validationSource = await readFile(join(project, 'scripts/test-mdcc-package.ps1'), 'utf8');
const template = await readFile(join(project, 'config/mcp.template.json'), 'utf8');
// Reuse the package inventory only to provision fixtures. Assertions exercise
// the actual build and ZIP validator; no local customer files are read.
const required = [...validationSource.match(/\$required = @\(([\s\S]*?)\n\s{4}\)/)[1].matchAll(/"([^"\r\n]+)"/g)].map(match => match[1]);
const stubTest = "import test from 'node:test'; test('fixture prerequisite', () => {});\n";

function powershell(args, env = {}) {
  return spawnSync('pwsh', ['-NoProfile', '-NonInteractive', ...args], {
    encoding: 'utf8', timeout: 60_000, env: { ...process.env, ...env }, windowsHide: true,
  });
}

function output(result) { return `${result.error?.code ?? ''}\n${result.stdout ?? ''}\n${result.stderr ?? ''}`; }

async function put(root, path, content = 'synthetic fixture\n') {
  const target = join(root, path);
  await mkdir(join(target, '..'), { recursive: true });
  await writeFile(target, content);
}

async function fixture(t) {
  const temporary = await mkdtemp(join(tmpdir(), 'mdcc-package-test-'));
  t.after(async () => {
    const resolved = resolve(temporary);
    assert.ok(resolved.startsWith(`${resolve(tmpdir())}${sep}`));
    assert.match(relative(tmpdir(), resolved), /^mdcc-package-test-[^/\\]+$/);
    await rm(resolved, { recursive: true, force: true });
  });
  const workspace = join(temporary, 'workspace');
  for (const path of required.filter(path => path !== 'package-manifest.json')) await put(workspace, path);
  for (const path of ['.gitignore', 'tools/dataverse-diagnostics/probe.mjs', 'docs/authentication.md', 'scripts/test-authentication.ps1']) await put(workspace, path);
  await put(workspace, 'scripts/build-mdcc-package.ps1', buildSource);
  await put(workspace, 'scripts/test-mdcc-package.ps1', validationSource);
  for (const path of ['test-agent-context.ps1', 'test-dataverse-mcp-guardrails.ps1', 'test-playwright-guardrails.ps1']) {
    await put(workspace, `scripts/${path}`, 'param([string]$WorkspaceRoot)\n');
  }
  // Every Node test the build runs must be a valid stub, including those added to the inventory.
  for (const path of required.filter(path => /^tests\/[^/]+\.test\.mjs$/.test(path))) {
    await put(workspace, path, stubTest);
  }
  await put(workspace, 'config/mcp.template.json', template);
  await put(workspace, '.vscode/mcp.json', template);
  return { temporary, workspace, zip: join(temporary, 'fixture.zip') };
}

async function files(root, directory = root) {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) result.push(...await files(root, path));
    else result.push(relative(root, path).split(sep).join('/'));
  }
  return result;
}

async function removeFixtureDirectory(f, path) {
  const target = resolve(path);
  assert.ok(target.startsWith(`${resolve(f.temporary)}${sep}`), 'Cleanup must stay inside the fixture.');
  await rm(target, { recursive: true, force: true });
}

async function archive(f, { added, omitted } = {}) {
  const staging = join(f.temporary, 'archive');
  const packageRoot = join(staging, 'mdcc-vscode-agent-suite');
  await removeFixtureDirectory(f, staging);
  await cp(f.workspace, packageRoot, { recursive: true });
  if (added) await put(packageRoot, added, 'synthetic cache canary\n');
  if (omitted) await rm(join(packageRoot, omitted));
  const manifestFiles = [];
  for (const path of await files(packageRoot)) {
    const content = await readFile(join(packageRoot, path));
    manifestFiles.push({ path, sha256: createHash('sha256').update(content).digest('hex'), sizeBytes: content.length });
  }
  await put(packageRoot, 'package-manifest.json', JSON.stringify({ schemaVersion: 1, files: manifestFiles }));
  await rm(f.zip, { force: true });
  const result = powershell(['-Command', '[IO.Compression.ZipFile]::CreateFromDirectory($env:MDCC_TEST_ARCHIVE_SOURCE, $env:MDCC_TEST_ARCHIVE_TARGET)'], {
    MDCC_TEST_ARCHIVE_SOURCE: staging, MDCC_TEST_ARCHIVE_TARGET: f.zip,
  });
  assert.equal(result.status, 0, output(result));
}

function validate(f) {
  return powershell(['-File', join(f.workspace, 'scripts/test-mdcc-package.ps1'), '-WorkspaceRoot', f.workspace, '-PackagePath', f.zip]);
}

function build(f) {
  return powershell(['-File', join(f.workspace, 'scripts/build-mdcc-package.ps1'), '-WorkspaceRoot', f.workspace, '-OutputPath', f.zip]);
}

test('pacote aceita fontes de autenticação e exige módulos, documento e testes de diagnóstico', async t => {
  const f = await fixture(t);
  const result = build(f);
  assert.equal(result.status, 0, output(result));
  for (const omitted of ['tools/dataverse-diagnostics/probe.mjs', 'docs/dataverse-environment-validation.md', 'tests/dataverse-diagnostics.test.mjs']) {
    await archive(f, { omitted });
    const validation = validate(f);
    assert.notEqual(validation.status, 0);
    assert.match(output(validation), /Package entry is missing|diagnostics modules in the ZIP differ/);
  }
  await put(f.workspace, 'tests/dataverse-diagnostics.test.mjs', "throw new Error('synthetic diagnostics test failure');\n");
  const failingTests = build(f);
  assert.notEqual(failingTests.status, 0);
  assert.match(output(failingTests), /synthetic diagnostics test failure/);
});

test('build e validador rejeitam arquivos de credenciais e caches sem ler valores', async t => {
  const f = await fixture(t);
  for (const path of ['config/.env', 'tools/.env.production', 'config/.secrets/value.txt', 'tools/.dataverse/cache.bin', 'scripts/.token_cache.bin', 'config/auth.json', 'config/credentials.json', 'tools/msal_cache.bin', 'tests/.auth/session.json', 'config/storageState.json']) {
    await archive(f, { added: path });
    const validation = validate(f);
    assert.notEqual(validation.status, 0, path);
    assert.match(output(validation), /Sensitive\/generated artifact is present/);
    await put(f.workspace, path, 'synthetic cache canary\n');
    if (process.platform === 'win32') {
      const hidden = powershell(['-Command', '[IO.File]::SetAttributes($env:MDCC_TEST_HIDDEN_PATH, [IO.FileAttributes]::Hidden)'], { MDCC_TEST_HIDDEN_PATH: join(f.workspace, path) });
      assert.equal(hidden.status, 0, output(hidden));
    }
    const rejected = build(f);
    assert.notEqual(rejected.status, 0, path);
    assert.match(output(rejected), /Sensitive\/generated package input found/);
    await rm(join(f.workspace, path), { force: true });
    // Remove the newly created cache directory; otherwise subsequent cases
    // would succeed by rejecting that earlier empty prohibited directory.
    if (/\/(\.secrets|\.dataverse|\.auth)\//.test(path)) await removeFixtureDirectory(f, join(f.workspace, path, '..'));
  }
});
