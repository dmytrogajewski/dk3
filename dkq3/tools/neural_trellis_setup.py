#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build/download the isolated local TRELLIS.2 deployment; never invokes Git."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import shutil
import tarfile
import urllib.request
import importlib.metadata

ROOT = Path(__file__).resolve().parents[2]
DEPLOY = ROOT / 'zig-out/neural-tools'
TRELLIS = 'TRELLIS.2-75fbf0183001ed9876c8dbb35de6b68552ee08bd'
PACKAGES = ['utils3d-9a4eb15e4021b67b12c460c7057d642626897ec8', 'nvdiffrast-0.4.0',
            'nvdiffrec-renderutils', 'FlexGEMM-main', 'CuMesh-main', TRELLIS+'/o-voxel']


def sources():
    """Admit archived source by content hash; never follow changed branch contents."""
    records = json.loads(Path(__file__).with_name('neural_trellis_sources.json').read_text())
    for name in ('sources','downloads','logs'): (DEPLOY/name).mkdir(parents=True,exist_ok=True)
    for row in records:
        archive = DEPLOY/'downloads'/row['archive']
        if not archive.is_file():
            temporary = archive.with_suffix('.pending')
            with urllib.request.urlopen(row['url'],timeout=120) as response, temporary.open('wb') as stream:
                shutil.copyfileobj(response,stream)
            temporary.replace(archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=row['sha256']:
            raise ValueError('Source archive changed: '+str(archive)+'; retain the admitted snapshot')
        destination = DEPLOY/'sources'/row['directory']
        if destination.is_dir(): continue
        staging = DEPLOY/'sources'/('.unpack-'+row['directory'])
        staging.mkdir(exist_ok=True)
        with tarfile.open(archive) as bundle: bundle.extractall(staging,filter='data')
        roots = list(staging.iterdir())
        if len(roots)!=1 or not roots[0].is_dir(): raise ValueError('Invalid source archive root')
        roots[0].replace(destination)
        staging.rmdir()
    eigen=Path('/usr/include/eigen3')
    if not eigen.is_dir(): raise FileNotFoundError('Install the system Eigen development headers')
    for location,target in [(DEPLOY/'sources/CuMesh-main/third_party/cubvh', DEPLOY/'sources/cubvh-trellis.2'),
                            (DEPLOY/'sources/CuMesh-main/third_party/eigen',eigen),
                            (DEPLOY/'sources'/TRELLIS/'o-voxel/third_party/eigen',eigen)]:
        if location.is_dir() and not location.is_symlink() and not any(location.iterdir()): location.rmdir()
        if not location.exists(): location.symlink_to(target,target_is_directory=True)
    licenses()


def licenses():
    directory=DEPLOY/'licenses';directory.mkdir(exist_ok=True)
    for row in json.loads(Path(__file__).with_name('neural_trellis_licenses.json').read_text()):
        path=directory/row['name']
        if not path.is_file():
            with urllib.request.urlopen(row['url'],timeout=30) as response: path.write_bytes(response.read())
        if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']: raise ValueError('Changed upstream license: '+row['name'])


def bootstrap():
    sources()
    interpreter = DEPLOY/'runtime/bin/python'
    if not interpreter.is_file(): subprocess.run(['uv','venv','--python','/usr/bin/python3.12',str(DEPLOY/'runtime')],check=True)
    requirements=Path(__file__).with_name('requirements-neural-trellis.txt')
    subprocess.run(['uv','pip','install','--cache-dir',str(DEPLOY/'uv-cache'),'--python',str(interpreter),
                    '--index-strategy','unsafe-best-match','-r',str(requirements)],check=True)


def build():
    env = os.environ.copy()
    env.update(CC='/usr/bin/gcc-14', CXX='/usr/bin/g++-14', CUDA_HOME='/usr/local/cuda-12.9',
               TORCH_CUDA_ARCH_LIST='12.0', MAX_JOBS='2', UV_CONCURRENT_BUILDS='1')
    nvidia = DEPLOY/'runtime/lib64/python3.12/site-packages/nvidia'
    env['CPATH'] = ':'.join(str(p) for p in nvidia.glob('*/include'))
    links = DEPLOY/'cuda-link-libraries'
    links.mkdir(exist_ok=True)
    for library in nvidia.glob('*/lib/lib*.so.*'):
        target = links/library.name.split('.so.')[0]
        target = target.with_name(target.name+'.so')
        if not target.exists(): target.symlink_to(library.resolve())
    env['LIBRARY_PATH'] = ':'.join([str(links), *(str(p) for p in nvidia.glob('*/lib'))])
    env['FLEX_GEMM_AUTOTUNE_CACHE_PATH'] = str(DEPLOY/'flex-gemm-cache.json')
    # Redirect the upstream install-time cache as well as the runtime cache.
    setup = DEPLOY/'sources/FlexGEMM-main/setup.py'
    contents = setup.read_text().replace('os.path.expanduser("~/.flex_gemm")',
        'os.path.dirname(os.environ["FLEX_GEMM_AUTOTUNE_CACHE_PATH"])').replace(
        'os.path.expanduser("~/.flex_gemm/autotune_cache.json")',
        'os.environ["FLEX_GEMM_AUTOTUNE_CACHE_PATH"]')
    setup.write_text(contents)
    for name in PACKAGES:
        log = DEPLOY / 'logs' / (name.replace('/', '-')+'.log')
        command = ['uv', 'pip', 'install', '--cache-dir', str(DEPLOY/'uv-cache'), '--python',
                   str(DEPLOY/'runtime/bin/python'), '--no-build-isolation', '--no-deps', str(DEPLOY/'sources'/name)]
        print('Building', name, flush=True)
        with log.open('w') as stream:
            result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode: raise SystemExit(f'Build failed; see {log}')
    receipt()


def weights():
    os.environ['HF_HOME'] = str(DEPLOY/'huggingface')
    from huggingface_hub import snapshot_download
    records = []
    for repository, revision, patterns in [
        ('microsoft/TRELLIS.2-4B','af44b45f2e35a493886929c6d786e563ec68364d', ['pipeline.json', 'ckpts/*', 'LICENSE', 'README.md']),
        ('microsoft/TRELLIS-image-large','25e0d31ffbebe4b5a97464dd851910efc3002d96', ['ckpts/ss_dec_conv3d_16l8_fp16*', 'LICENSE', 'README.md']),
        ('timm/vit_large_patch16_dinov3.lvd1689m','30c1109559f65dea34316b0d4842d35c5771fe11', ['model.safetensors', 'config.json', 'README.md', 'LICENSE*'])]:
        print('Downloading', repository, revision, flush=True)
        path = snapshot_download(repository, revision=revision, allow_patterns=patterns, max_workers=3)
        records.append(dict(repository=repository, revision=revision, path=path))
    (DEPLOY/'weights.json').write_text(json.dumps(records, indent=2)+'\n')


def receipt():
    archives = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (DEPLOY/'downloads').glob('*.tar.gz')}
    licenses = {}
    for name in PACKAGES+[TRELLIS,'cubvh-trellis.2']:
        for pattern in ('LICENSE*', 'COPYING*'):
            for p in (DEPLOY/'sources'/name).glob(pattern):
                if p.is_file(): licenses[str(p.relative_to(DEPLOY))]=hashlib.sha256(p.read_bytes()).hexdigest()
    for p in (DEPLOY/'licenses').glob('*'):
        if p.is_file(): licenses[str(p.relative_to(DEPLOY))]=hashlib.sha256(p.read_bytes()).hexdigest()
    packages=[]
    for distribution in importlib.metadata.distributions():
        notices={}
        for item in distribution.files or ():
            if any(word in str(item).lower() for word in ('license','copying','notice')):
                p=distribution.locate_file(item)
                if p.is_file(): notices[str(item)]=hashlib.sha256(p.read_bytes()).hexdigest()
        packages.append(dict(name=distribution.metadata['Name'],version=distribution.version,
                             license=distribution.metadata.get('License-Expression',distribution.metadata.get('License','unspecified')),
                             notices=notices))
    (DEPLOY/'python-packages.json').write_text(json.dumps(packages,indent=2)+'\n')
    freeze = subprocess.check_output(['uv','pip','freeze','--python',str(DEPLOY/'runtime/bin/python')], text=True)
    (DEPLOY/'environment.txt').write_text(freeze)
    (DEPLOY/'deployment.json').write_text(json.dumps(dict(format=1, trellis_source=TRELLIS,
        cuda_arch='12.0', cuda_toolkit='/usr/local/cuda-12.9', compiler='gcc-14', archives=archives,
        licenses=licenses, environment_sha256=hashlib.sha256(freeze.encode()).hexdigest(),
        runtime='local generation tools only; no deployed game dependency'), indent=2)+'\n')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=('sources','licenses','bootstrap','build','weights','receipt'))
    args=parser.parse_args()
    globals()[args.command]()
