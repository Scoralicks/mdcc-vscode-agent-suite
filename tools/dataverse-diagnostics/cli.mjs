import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { runDiagnostics } from './diagnostics.mjs';

export function parseArguments(args) {
  const options = { live: false, timeoutSeconds: 90 };
  let mode = false, timeout = false;
  for (let i = 0; i < args.length; i++) {
    if (['--preflight', '--live'].includes(args[i]) && !mode) {
      mode = true; options.live = args[i] === '--live';
    } else if (args[i] === '--timeout-seconds' && !timeout && /^\d{1,3}$/.test(args[i + 1] ?? '')) {
      timeout = true; options.timeoutSeconds = Number(args[++i]);
      if (options.timeoutSeconds < 1 || options.timeoutSeconds > 180) throw new Error('invalid-arguments');
    } else throw new Error('invalid-arguments');
  }
  return options;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const controller = new AbortController();
  const cancel = () => controller.abort();
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  let report;
  try { report = await runDiagnostics({ ...parseArguments(process.argv.slice(2)), signal: controller.signal }); }
  catch { report = { schemaVersion: 1, ok: false, reason: 'invalid-arguments' }; }
  process.removeListener('SIGINT', cancel);
  process.removeListener('SIGTERM', cancel);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = report.ok ? 0 : 1;
}
