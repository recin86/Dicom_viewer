#!/usr/bin/env python3
"""Write a path-free record of the exact Cargo graph and experiment source."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--profile', required=True)
    ap.add_argument('--features', required=True)
    ap.add_argument('--binary', type=Path, required=True)
    ap.add_argument('--report', type=Path, required=True)
    args = ap.parse_args()
    exp = Path(__file__).resolve().parent
    manifest = exp / 'rust' / 'Cargo.toml'
    proc = subprocess.run(['cargo', '+1.98.1', 'metadata', '--locked', '--offline',
                           '--format-version', '1', '--filter-platform', 'aarch64-apple-darwin',
                           '--manifest-path', str(manifest),
                           '--no-default-features', '--features', args.features],
                          capture_output=True, text=True, check=True)
    metadata = json.loads(proc.stdout)
    nodes = {n['id']: n['features'] for n in metadata['resolve']['nodes']}
    packages = [{'name': p['name'], 'version': p['version'], 'license': p['license'],
                 'features': sorted(nodes[p['id']])} for p in metadata['packages'] if p['id'] in nodes]
    source_files = [p for p in exp.rglob('*') if p.is_file() and (
        p.suffix in {'.py', '.rs', '.toml', '.lock', '.sh'} or p.name == 'requirements.txt')]
    source_files = [p for p in source_files if 'results' not in p.relative_to(exp).parts]
    hashes = {str(p.relative_to(exp)): digest(p) for p in sorted(source_files)}
    source_digest = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
    linked = subprocess.check_output(['otool', '-L', str(args.binary)], text=True).splitlines()[1:]
    libraries = []
    for line in linked:
        install_name = line.strip().split(' (', 1)[0]
        libraries.append(install_name if install_name.startswith(('/usr/lib/', '/System/Library/', '@'))
                         else 'non-system:' + Path(install_name).name)
    load_commands = subprocess.check_output(['otool', '-l', str(args.binary)], text=True)
    minimum = re.search(r'\bminos\s+(\S+)', load_commands)
    report = {'profile': args.profile, 'features_requested': args.features.split(','),
              'binary_sha256': digest(args.binary), 'source_sha256': source_digest,
              'source_files_sha256': hashes, 'packages': sorted(packages, key=lambda p: p['name']),
              'rustc': subprocess.check_output(['rustc', '+1.98.1', '--version'], text=True).strip(),
              'deployment_target': '27.0', 'minimum_os_from_binary': minimum.group(1) if minimum else None,
              'linked_libraries': libraries, 'mode': 'release', 'architecture': 'aarch64-apple-darwin'}
    args.report.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
