import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const target = resolve(process.argv[2] ?? '/Applications/SteerMouse.app');
const out = resolve('.local/evidence');
const rea = resolve('node_modules/.bin/rea');
mkdirSync(out, { recursive: true });
const environment = { ...process.env };
if (!environment.DEVELOPER_DIR && existsSync('/Applications/Xcode.app/Contents/Developer')) {
  environment.DEVELOPER_DIR = '/Applications/Xcode.app/Contents/Developer';
}

function run(name, args) {
  let raw;
  let exitCode = 0;
  try {
    raw = execFileSync(rea, [...args, '--format', 'json'], {
      encoding: 'utf8', maxBuffer: 128 * 1024 * 1024, timeout: 120_000,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: environment,
    });
  } catch (error) {
    raw = error.stdout?.toString() ?? '';
    exitCode = error.status ?? 1;
    if (!raw.trim()) {
      writeFileSync(join(out, `${name}-error.txt`), error.message + '\n' + (error.stderr ?? ''));
      console.error(`${name}: failed (exit ${exitCode}), see local error log`);
      return null;
    }
  }
  writeFileSync(join(out, `${name}.json`), raw);
  let result;
  try { result = JSON.parse(raw); } catch {
    console.error(`${name}: output was not JSON`);
    return null;
  }
  if (exitCode || result.error) {
    console.error(`${name}: ${result.code ?? 'failed'} (retained locally)`);
    return null;
  }
  console.log(`${name}: ${result.evidence_id ?? 'saved'}`);
  return result;
}

const artifact = run('rea-artifact', ['inspect-artifact', target]);
const inventory = artifact?.normalized_result?.substeps?.find(s => s.operation === 'inventory_artifact')?.evidence;
if (inventory) {
  const input = join(out, 'apple-graph-input.json');
  writeFileSync(input, JSON.stringify({ inventory_evidence: [inventory] }));
  run('rea-apple-graph', ['project-apple-application-graph', input]);
}
run('rea-dylibs', ['trace-dylib-resolution', target]);
run('rea-ui', ['decode-interface-builder', target]);
run('rea-providers', ['providers']);
run('rea-main-macho', ['inspect-macho', target]);
run('rea-main-plist', ['inspect-plist', target]);
run('rea-main-signature', ['inspect-signature', target]);
const helper = join(target, 'Contents/Library/LoginItems/SteerMouse Manager.app');
if (existsSync(helper)) {
  run('rea-manager-macho', ['inspect-macho', helper]);
  run('rea-manager-plist', ['inspect-plist', helper]);
  run('rea-manager-signature', ['inspect-signature', helper]);
}

const files = ['rea-artifact', 'rea-apple-graph', 'rea-dylibs', 'rea-ui',
  'rea-main-macho', 'rea-main-plist', 'rea-main-signature',
  'rea-manager-macho', 'rea-manager-plist', 'rea-manager-signature'];
const summary = files.flatMap(name => {
  try {
    const evidence = JSON.parse(readFileSync(join(out, `${name}.json`), 'utf8'));
    return evidence.evidence_id ? [{ operation: evidence.operation, evidence_id: evidence.evidence_id,
      subject: evidence.subject, limitations: evidence.limitations }] : [];
  } catch { return []; }
});
writeFileSync(join(out, 'evidence-index.json'), JSON.stringify(summary, null, 2) + '\n');
if (!artifact) process.exitCode = 1;
