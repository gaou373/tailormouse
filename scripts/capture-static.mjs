import { execFileSync } from 'node:child_process';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, join } from 'node:path';

const app = resolve(process.argv[2] ?? '/Applications/SteerMouse.app');
const out = resolve('.local/evidence/static');
mkdirSync(out, { recursive: true });
const env = { ...process.env, DEVELOPER_DIR: process.env.DEVELOPER_DIR ?? '/Applications/Xcode.app/Contents/Developer' };
const captures = [];
for (const [role, relative] of [['main', 'Contents/MacOS/SteerMouse'],
  ['helper', 'Contents/Library/LoginItems/SteerMouse Manager.app/Contents/MacOS/SteerMouse Manager']]) {
  const binary = join(app, relative);
  const sha256 = createHash('sha256').update(readFileSync(binary)).digest('hex');
  for (const [label, tool, args] of [
    ['file', '/usr/bin/file', [binary]],
    ['loads', '/usr/bin/xcrun', ['otool', '-L', binary]],
    ['imports', '/usr/bin/xcrun', ['nm', '-u', binary]],
    ['arm64-symbols', '/usr/bin/xcrun', ['nm', '-arch', 'arm64', '-nm', binary]],
    ['arm64-disassembly', '/usr/bin/xcrun', ['otool', '-arch', 'arm64', '-tvV', binary]],
    ['objc', '/usr/bin/xcrun', ['otool', '-arch', 'arm64', '-ov', binary]],
  ]) {
    const output = execFileSync(tool, args, { env, maxBuffer: 128 * 1024 * 1024, timeout: 120_000 });
    const name = `${role}-${label}.txt`;
    writeFileSync(join(out, name), output);
    captures.push({ role, target: binary, target_sha256: sha256, tool, arguments: args, output: name,
      output_sha256: createHash('sha256').update(output).digest('hex') });
    console.log(name);
  }
}
writeFileSync(join(out, 'capture-manifest.json'), JSON.stringify({
  capturedAt: new Date().toISOString(), captures,
  limitations: ['Static inspection only. No target execution, process attachment, event monitoring or mutation.',
    'Tool disassembly is analysis output; it is not original source or decompiler pseudocode.'],
}, null, 2) + '\n');
