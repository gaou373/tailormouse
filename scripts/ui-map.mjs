import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const path = process.argv[2] ?? '.local/evidence/rea-ui.json';
const evidence = JSON.parse(readFileSync(path, 'utf8'));
if (evidence.operation !== 'decode_interface_builder') throw new Error('Expected REA Interface Builder Evidence');
const graph = evidence.normalized_result.graph;
const byID = new Map(graph.nodes.map(node => [node.id, node]));
const selectors = new Set(['changeButtonSelector:', 'changeButtonCount:', 'changeScrollText:',
  'scrollWaySelector:', 'restoreCursorSpeed:', 'changeCursorSpeedLocked:', 'changeCursorSpeedDisabled:',
  'changeSmoothScroll:', 'applySetting:']);
const symbols = readFileSync('.local/evidence/static/main-arm64-symbols.txt', 'utf8').split('\n');
const rows = graph.nodes.filter(node => node.kind === 'action' && selectors.has(node.name) &&
  node.evidence.some(source => source.artifact_path?.includes('/en.lproj/'))).map(node => {
  const destination = graph.edges.find(edge => edge.from === node.id && edge.to.includes(':object:'));
  const target = destination ? byID.get(destination.to) : null;
  const implementation = target ? symbols.find(line => line.includes(`-[${target.name}`) &&
    line.endsWith(` ${node.name}]`)) : null;
  return {
    selector: node.name, target_class: target?.name ?? null,
    implementation_address_arm64: implementation ? `0x${implementation.split(' ')[0].replace(/^0+/, '')}` : null,
    resource: node.evidence[0].artifact_path, resource_sha256: node.evidence[0].artifact_sha256,
    connection_id: node.id,
  };
});
const unique = [...new Map(rows.map(row => [`${row.resource}:${row.target_class}:${row.selector}`, row])).values()];
const output = { evidence_id: evidence.evidence_id, target_sha256: evidence.subject.digest.sha256,
  coverage: graph.coverage, connections: unique,
  limitations: ['UI connections plus matching symbol names are static observations, not executed call traces.',
    'Addresses come from the main executable arm64 nm capture and require its exact hash.'] };
mkdirSync('.local/evidence', { recursive: true });
writeFileSync('.local/evidence/ui-map-summary.json', JSON.stringify(output, null, 2) + '\n');
console.log(JSON.stringify(output, null, 2));
