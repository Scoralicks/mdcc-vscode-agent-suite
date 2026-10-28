// Núcleo JSON-RPC (stdio) mínimo usado pelos servidores MCP locais da suíte.
import { appendFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { secretDirectory } from './secrets.mjs';

export function annotateTools(readTools, writeTools) {
  return [
    ...readTools.map((tool) => ({ ...tool, annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: true } })),
    ...writeTools.map((tool) => ({ ...tool, annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true } })),
  ];
}

// Registra somente metadados da escrita (ferramenta, alvo, ids de campo), nunca valores.
export function fileAuditor(fileName) {
  return (entry) => {
    const dir = secretDirectory();
    mkdirSync(dir, { recursive: true });
    appendFileSync(join(dir, fileName), `${JSON.stringify({ at: new Date().toISOString(), ...entry })}\n`);
  };
}

export function createMcpHandler({ serverInfo, tools, instructions, loadClient, callTool, audit }) {
  let client;
  return async function handle(message) {
    const { id, method, params } = message;
    const reply = (result) => ({ jsonrpc: '2.0', id, result });
    if (id === undefined) return undefined; // notificações não têm resposta
    switch (method) {
      case 'initialize':
        return reply({ protocolVersion: params?.protocolVersion ?? '2025-06-18', capabilities: { tools: {} }, serverInfo, instructions });
      case 'ping':
        return reply({});
      case 'tools/list':
        return reply({ tools });
      case 'tools/call':
        try {
          client ??= loadClient();
          const result = await callTool(client, params?.name, params?.arguments ?? {}, { audit });
          return reply({ content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] });
        } catch (error) {
          return reply({ content: [{ type: 'text', text: error.message }], isError: true });
        }
      default:
        return { jsonrpc: '2.0', id, error: { code: -32601, message: `Método não suportado: ${method}` } };
    }
  };
}

export function runStdio(handle) {
  const rl = createInterface({ input: process.stdin });
  rl.on('line', async (line) => {
    if (!line.trim()) return;
    let message;
    try { message = JSON.parse(line); } catch {
      process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } })}\n`);
      return;
    }
    const response = await handle(message);
    if (response) process.stdout.write(`${JSON.stringify(response)}\n`);
  });
}

export function truncate(text, max) {
  const clean = String(text).replace(/\n{3,}/g, '\n\n').trim();
  return clean.length > max ? `${clean.slice(0, max)}… [truncado, ${clean.length} caracteres]` : clean;
}

export const intIn = (value, min, max, fallback) => (Number.isInteger(value) ? Math.min(Math.max(value, min), max) : fallback);
