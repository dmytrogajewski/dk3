# SPDX-License-Identifier: GPL-2.0-or-later
"""Validate local cosmetic packages without conversion dependencies."""
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile
from contextlib import contextmanager
from threading import RLock

MANIFEST = 'dk3/neural-models.cfg'
# This mesh is a torture apparatus with several disconnected parts, not a
# Superfly performance. Fitting one humanoid to its combined bounds magnifies
# the replacement body and drops the apparatus around it.
NON_CHARACTER_MODELS = frozenset({'models/e1/d1_supertorture.dkm'})
_zip_writer_lock = RLock()


@contextmanager
def classic_archive(path):
    """The bundled reader uses ZIP32, whose unsigned offsets reach 4 GiB.

    Python conservatively switches to ZIP64 at 2 GiB. Keep the actual ZIP32
    bound, forbid ZIP64, and restore the interpreter setting after writing.
    Serialized writes share a lock because this setting belongs to zipfile.
    """
    with _zip_writer_lock:
        previous=zipfile.ZIP64_LIMIT
        zipfile.ZIP64_LIMIT=(1<<32)-1
        try:
            with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED,
                                 compresslevel=6,allowZip64=False) as archive:
                yield archive
        finally:
            zipfile.ZIP64_LIMIT=previous


def require_classic_directory(path, archive):
    """Reject unsupported ZIP64 before a package reaches native file listing."""
    with Path(path).open('rb') as stream:
        stream.seek(max(0,Path(path).stat().st_size-65557))
        tail=stream.read();at=tail.rfind(b'PK\x05\x06')
        if at<0 or len(tail)-at<22:raise ValueError('missing ZIP32 directory')
        footer=struct.unpack_from('<4s4H2LH',tail,at)
        if at+22+footer[-1]!=len(tail) or footer[1] or footer[2] or footer[3]!=footer[4]:
            raise ValueError('invalid ZIP32 directory')
        if 65535 in footer[3:5] or 0xffffffff in footer[5:7]:
            raise ValueError('native engine requires ZIP32; rebuild package without ZIP64')
        if at>=20 and tail[at-20:at-16]==b'PK\x06\x07':
            raise ValueError('native engine requires ZIP32; rebuild package without ZIP64')
        for entry in archive.infolist():
            extra=entry.extra
            while len(extra)>=4:
                kind,length=struct.unpack_from('<HH',extra)
                if kind==1:raise ValueError('native engine requires ZIP32; rebuild package without ZIP64')
                extra=extra[4+length:]
            stream.seek(entry.header_offset);raw=stream.read(30)
            if len(raw)!=30:raise ValueError('invalid ZIP32 local header')
            header=struct.unpack('<4s5H3L2H',raw)
            if header[0]!=b'PK\x03\x04' or 0xffffffff in header[7:9]:
                raise ValueError('native engine requires ZIP32; rebuild package without ZIP64')


def physics_rig(data, mode='articulated'):
    """Check the native generic-body contract without NumPy/Blender dependencies."""
    if len(data)<124 or data[:16]!=b'INTERQUAKEMODEL\0' or struct.unpack_from('<I',data,16)[0]!=2:
        raise ValueError('physics target is not IQM v2')
    count,offset = struct.unpack_from('<2I',data,68)
    text_len,text = struct.unpack_from('<2I',data,28)
    if not 2<=count<=64 or offset+count*48>len(data) or text+text_len>len(data):
        raise ValueError('invalid physics skeleton bounds')
    body=0
    labels=set()
    for i in range(count):
        name,parent,*channels=struct.unpack_from('<Ii10f',data,offset+i*48)
        if name>=text_len or parent < -1 or parent>=i or not all(map(math.isfinite,channels)):
            raise ValueError('invalid physics joint')
        end=data.find(b'\0',text+name,text+text_len)
        if end<0: raise ValueError('unterminated physics joint name')
        label=data[text+name:end].decode('ascii').rstrip('_')
        if label in labels: raise ValueError('duplicate physics joint name')
        labels.add(label)
        if label.startswith('creature_'):
            if i!=body or label!=f'creature_{i:02}' or (parent!=-1 if i==0 else parent<0):
                raise ValueError('invalid creature body hierarchy')
            if i and sum(n*n for n in channels[:3])<.0001:
                raise ValueError('coincident creature body anchors')
            body+=1
    if mode == 'humanoid':
        required = {'pelvis', 'chest', 'head'} | {f'{bone}_{side}' for side in ('l','r')
                    for bone in ('upperarm','forearm','hand','thigh','shin','foot','toe')}
        if not required <= labels: raise ValueError('physics target needs an anatomical humanoid skeleton')
    elif body<2: raise ValueError('physics target needs a creature body skeleton')


def validate_package(path, base, *, allow_props=False):
    """Cosmetic overlay admission: closed namespace, per-entry hashes, exact base models."""
    with zipfile.ZipFile(path) as archive:
        require_classic_directory(path,archive)
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip(): raise ValueError('corrupt neural archive')
        report = json.loads(archive.read('dk3/neural-assets.json'))
        if report.get('format') != 1 or report['source_models_sha256'] != hashlib.sha256(base.read_bytes()).hexdigest():
            raise ValueError('neural package targets another model generation; rebuild it')
        expected = set(report['files']) | {'dk3/neural-assets.json'}
        if set(names) != expected or MANIFEST not in expected:
            raise ValueError('neural package entry manifest mismatch')
        for name, sha in report['files'].items():
            valid = name in (MANIFEST, 'dk3/neural-animations.cfg', 'dk3/neural-physics.cfg') or (name.startswith('models/neural/') and name.endswith(('.iqm', '.skin', '.png'))) or name == 'scripts/dk3-neural.shader'
            if not valid or '..' in name.split('/') or hashlib.sha256(archive.read(name)).hexdigest() != sha:
                raise ValueError('invalid neural package entry: ' + name)
            if name.endswith('.png') and archive.read(name)[:8]!=b'\x89PNG\r\n\x1a\n':
                raise ValueError('invalid PNG texture encoding: '+name)
        sources,targets=set(),set()
        for line in archive.read(MANIFEST).decode().splitlines():
            if not line.strip(): continue
            fields=line.split()
            if len(fields)!=2 or fields[0] in sources or fields[1] not in expected or not fields[1].endswith('.iqm'):
                raise ValueError('invalid neural model mapping')
            original,target=fields
            sources.add(original)
            targets.add(target)
            if not allow_props and original in NON_CHARACTER_MODELS:
                raise ValueError('non-character prop has neural body override: '+original)
        if 'dk3/neural-physics.cfg' in expected:
            admitted=set()
            for line in archive.read('dk3/neural-physics.cfg').decode().splitlines():
                fields=line.split()
                if len(fields)!=2 or fields[0] in admitted or fields[0] not in targets or fields[1] not in ('anchored','articulated','humanoid'):
                    raise ValueError('invalid neural physics mapping')
                admitted.add(fields[0])
                physics_rig(archive.read(fields[0]), fields[1])
                if any(fields[0]+f'.{variant}.skin' not in expected for variant in range(4)):
                    raise ValueError('missing neural creature skin variants')
        return report


def prune_props(source, output, base):
    """Repair an existing local overlay without refitting unrelated performances."""
    report = validate_package(source, base, allow_props=True)
    with zipfile.ZipFile(source) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    kept, targets = [], set()
    for line in files[MANIFEST].decode().splitlines():
        original, target = line.split()
        if original in NON_CHARACTER_MODELS:
            targets.add(target)
        else:
            kept.append(line)
    files[MANIFEST] = ('\n'.join(kept) + '\n').encode()
    files = {name: data for name, data in files.items()
             if not any(name == target or name.startswith(target + '.') for target in targets)}
    report['models'] = [row for row in report.get('models', []) if row['source'] not in NON_CHARACTER_MODELS]
    report['files'] = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()
                       if name != 'dk3/neural-assets.json'}
    files['dk3/neural-assets.json'] = json.dumps(report, sort_keys=True, indent=2).encode()
    temporary = output.with_suffix('.partial')
    with classic_archive(temporary) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    validate_package(temporary, base)
    temporary.replace(output)
    output.with_suffix('.json').write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
    return sorted(targets)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Remove invalid prop substitutions from a local neural overlay.')
    parser.add_argument('--prune-props', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--base-models', type=Path, required=True)
    args = parser.parse_args()
    print(prune_props(args.prune_props, args.output, args.base_models))
