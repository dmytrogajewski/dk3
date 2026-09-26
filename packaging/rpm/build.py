#!/usr/bin/env python3
"""Build a private, asset-inclusive RPM from an explicit verified installation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--coordinator', required=True)
    parser.add_argument('--ca', type=Path, required=True, help='public test CA certificate only')
    parser.add_argument('--output', type=Path, default=ROOT / 'zig-out/rpm')
    args = parser.parse_args()
    endpoint = urlsplit(args.coordinator)
    if endpoint.scheme != 'https' or not endpoint.hostname or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment:
        parser.error('coordinator must be an HTTPS service URL without credentials')
    certificate = args.ca.read_bytes()
    if b'PRIVATE KEY' in certificate or b'-----BEGIN CERTIFICATE-----' not in certificate:
        parser.error('--ca must contain a public certificate, never a private key')
    runtime = args.runtime.resolve(strict=True)
    manifest = json.loads((runtime / 'installation.json').read_text())
    allowed_bin = {'dk3', 'dk3ded', 'renderer_opengl1.so', 'renderer_opengl2.so'}
    allowed_data = {'rules.json', 'compatibility.json'}
    modules = {'cgame.so', 'qagame.so', 'ui.so'}
    required = {f'bin/{name}' for name in allowed_bin} | {f'share/dk3/{name}' for name in modules | allowed_data}
    if not required <= manifest['files'].keys():
        parser.error('installation is missing current native products or compatibility metadata')
    # Select only manifest-recorded runtime products, never profile directories.
    selected = []
    for name, checksum in manifest['files'].items():
        path = Path(name)
        if path.is_absolute() or '..' in path.parts:
            parser.error('unsafe installation path')
        source = runtime / path
        if source.is_symlink() or digest(source) != checksum:
            parser.error(f'installation integrity mismatch: {name}')
        if path.parent == Path('bin') and path.name in allowed_bin:
            target = Path('usr/lib64/dk3/bin') / path.name
        elif path.parent == Path('share/dk3') and path.name in modules:
            target = Path('usr/lib64/dk3/modules') / path.name
        elif path.parent == Path('share/dk3') and (path.suffix == '.pk3' or path.name in allowed_data):
            target = Path('usr/share/dk3') / path.name
        elif name == 'share/dk3/scripts/dk3-projectile-weather.shader':
            target = Path('usr/share/dk3/scripts/dk3-projectile-weather.shader')
        else:
            parser.error(f'unreviewed runtime entry: {name}')
        selected.append((source, target))
    out = args.output.resolve();out.mkdir(parents=True, exist_ok=True)
    stage = out / 'payload'
    if stage.exists():
        parser.error(f'output already contains payload: {stage}; select a new --output')
    stage.mkdir()
    def copy(source, target):
        target = stage / target;target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    for source, target in selected:
        copy(source, target)
    for name in modules:
        (stage / 'usr/share/dk3' / name).symlink_to('../../lib64/dk3/modules/' + name)
    for name in ['dkguard', 'dk3-online']:
        copy(ROOT / 'zig-out/bin' / name, Path('usr/lib64/dk3/tools') / name)
    copy(ROOT / 'packaging/rpm/launch.py', 'usr/libexec/dk3/launch.py')
    (stage / 'usr/libexec/dk3/launch.py').chmod(0o755)
    (stage / 'usr/bin').mkdir(parents=True)
    (stage / 'usr/bin/dk3').symlink_to('../libexec/dk3/launch.py')
    (stage / 'usr/bin/dk3-online').symlink_to('../lib64/dk3/tools/dk3-online')
    copy(ROOT / 'packaging/rpm/dk3.desktop', 'usr/share/applications/dk3.desktop')
    copy(args.ca, 'usr/share/dk3/online-root.crt')
    (stage / 'usr/share/dk3/online-defaults.json').write_text(json.dumps({'coordinator': args.coordinator, 'ca_file': '/usr/share/dk3/online-root.crt'}, indent=2)+'\n')
    for name in ['LICENSE', 'COPYRIGHT.md']:
        copy(ROOT / name, Path('usr/share/licenses/dk3') / name)
    copy(ROOT / 'engine/ioquake3/COPYING.txt', 'usr/share/licenses/dk3/ioquake3-COPYING.txt')
    # The admitted vendored headers carry component-specific copyright/licenses.
    thirdparty = ROOT / 'engine/ioquake3/code/thirdparty'
    for source in sorted(thirdparty.rglob('*')):
        if source.is_file() and (source.suffix == '.h' or source.name.lower().startswith(('copying', 'copyright', 'license', 'readme'))):
            copy(source, Path('usr/share/licenses/dk3/thirdparty') / source.relative_to(thirdparty))
    for name in ['status.md', 'rpm.md']:
        copy(ROOT / 'docs' / name, Path('usr/share/doc/dk3') / name)
    (stage / 'usr/share/doc/dk3/build.json').write_text(json.dumps({'runtime_generation': runtime.name, 'asset_generation': manifest.get('asset_generation'), 'profile': manifest.get('asset_profile'), 'public_ca_sha256': digest(args.ca)}, indent=2)+'\n')
    for directory in ['BUILD', 'BUILDROOT', 'RPMS', 'SOURCES', 'SPECS', 'SRPMS']:
        (out / directory).mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'packaging/rpm/dk3.spec', out / 'SPECS/dk3.spec')
    print('Assembled verified runtime, local assets and public server trust.', flush=True)
    with tarfile.open(out / 'SOURCES/payload.tar', 'w') as archive:
        archive.add(stage, arcname='payload')
    subprocess.run(['rpmbuild', '-bb', '--define', '_topdir ' + str(out), str(out / 'SPECS/dk3.spec')], check=True)
    for rpm in (out / 'RPMS').rglob('*.rpm'):
        print(rpm, flush=True)
        rpm.with_suffix(rpm.suffix+'.sha256').write_text(digest(rpm)+'  '+rpm.name+'\n')

if __name__ == '__main__':
    main()
