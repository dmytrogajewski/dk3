#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Resumable, local episode monster capture -> concept -> TRELLIS.2 -> IQM pipeline.

Image generation is an explicit intake: the built-in image tool consumes photo.png
and prompt.txt, then its selected output is admitted with the concept subcommand.
No external game's code is executed. Inputs are this checkout's converted assets.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

import numpy as np

import entities
import dkm2md3
import skeletal_iqm as sk
from neural_assets import read_md3, STORY_CHARACTERS
from neural_package import validate_package, classic_archive

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent.parent
STAGES = ('capture', 'concept', 'trellis', 'convert')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


A_POSE_MODELS = frozenset(('cryotech', 'fatworker', 'mishimaguard',
                          'skinnyworker', 'surgeon', 'inmater', 'ragemaster', 'sludgeminion',
                          'hiro', 'mikiko', 'superfly', 'mishima', 'usagi'))
CHARACTER_SOURCES = {'hiro': 'models/global/m_hiro.dkm', 'mikiko': 'models/global/m_mikiko.dkm',
                     'superfly': 'models/global/m_superfly.dkm', 'mishima': 'models/e4/m_kage.dkm',
                     'usagi': 'models/cinematic/c_usagi_intr.dkm'}
STORY_SOURCES = {name:f'models/cinematic/{stems[0]}.dkm' for name,stems in STORY_CHARACTERS.items()}
STORY_DESIGNS = {
    'casseti': 'Casseti, the original mature lean muscular man with receding dark hair, a short pointed gray beard, brown skin and extensive black chest and arm tattoos. Preserve the open sleeveless blue-gray vest, bare chest, matching work trousers, dark gloves and boots. No laboratory coat or armor.',
    'charon': 'Charon the ferryman, the original skeletal figure with a skull under a deep black hood, skeletal hands and a closed floor-length black robe with wide sleeves. Preserve the hood, skull and robe silhouette. His wooden oar is a separate runtime prop: depict empty hands and no staff. Do not invent flesh, armor or a split skirt.',
    'femaleguard': 'The original lean adult Japanese female guard with short black bobbed hair, close-fitting bronze chest and small shoulder armor, dark short-sleeved undershirt, exposed slim forearms, black gloves, fitted dark trousers and tall narrow boots. Preserve her original facial identity and modest armor bulk. Her two short blades are separate runtime props: empty hands, no blades in this body master.',
    'garroth': 'Garroth, the original broad muscular brown horned nonhuman king with two crooked helmet horns, a stern face, metal chest armor with a skull motif, large shoulder plates, bracers, exposed muscular arms and thighs, tall dark boots and a long teal-blue cape. Preserve the original nonhuman facial features and equipment. His staff is a separate runtime prop: empty hands. No wings, extra horns or redesign.',
    'warriorguard': 'The original lean living human warrior guard: bronze military helmet with a short angular brow peak and circular side hardware, close-fitting bronze chest armor and small shoulder plates, dark short-sleeved shirt, exposed slim forearms, black gloves, straight dark trousers and tall narrow black boots. Preserve the helmet, healthy face, silhouette and modest armor bulk. No zombie, bare head, long sleeves or invented tactical equipment.',
    'ninja': 'The original adult Japanese male ninja in a close-fitting black hood and face mask exposing only his eyes, black long-sleeved martial arts clothing, sash, loose black trousers, black gloves with small metal back-of-hand badges and wrapped dark boots. Preserve the original cloth outfit. No armor or bare face. Replace the crouch with an upright neutral A-pose.',
    'osaka': 'Osaka, the original older Japanese man with a gray topknot, mustache and pointed gray beard, a closed long red robe with a broad black-and-gold embroidered collar and shoulder yoke, short wide red cuffs over black sleeves, exposed forearms and pointed gray-tan shoes. Preserve his age, face, hair and robe. No invented samurai armor or split robe.',
    'priest': 'The original middle-aged light-tan male priest with short dark hair and a clean-shaven severe face, a closed ankle-length brown monastic robe, broad cowl collar, rope belt, dark green trim on the front panel, short wide sleeves exposing his forearms and small brown shoes. Preserve the original robe and human identity. No armor, elaborate priest vestments or split skirt.',
    'tatsuo': 'Tatsuo, the original mature Japanese man with short black hair and rectangular black glasses, a white-silver tailored suit with a long coat and lower coat panels, purple-lined collar and cuffs, white gloves, matching silver-white trousers and boots. Preserve the original face, glasses, costume, proportions and palette. No dragon, samurai or armor reinterpretation.',
    'toshiro': 'Toshiro, the original older Japanese man with a stern lined face under a black hood, a black short-sleeved tunic, exposed tattooed forearms, dark gloves, a two-strand brown rope belt, loose black trousers, dark wrapped shoes and a long black cape behind him. Preserve the original hooded human identity, tattoos, layered black cloth and palette. His wooden staff is a separate runtime prop: empty relaxed hands. No skeleton, armor, skull mask, bare head or costume redesign.',
}
ROBED_CHARACTERS = frozenset(('charon','osaka','priest'))


def concept_prompt(slug):
    subject = {
        'lasergat': 'A compact mounted laser turret: a dark metal cylindrical rear housing, a horizontal elongated twin-emitter gun head, and a square vertical pivot yoke. Entirely mechanical. No creature, face, torso, arms or legs. Keep the two muzzle openings and the same gun orientation.',
        'rockgat': 'A raised rocket gun turret on its fixed mechanical pedestal, with the source gun housing and mounting mechanism. Entirely mechanical. No creature, face, humanoid anatomy, arms or legs.',
        'hiro': 'Hiro Miyamoto, the exact living human protagonist in the original reference. Preserve his face, hairstyle, clothing, armor, colors and equipment. Faithful original character identity with refined human anatomy and modeled costume detail; no generic replacement soldier or invented equipment.',
        'mikiko': 'Mikiko Ebihara, the exact adult human woman in the original reference. Preserve her Japanese facial identity, hairstyle, outfit, boots, colors and original proportions. Anatomically believable adult features, fully modeled fabric and armor. No costume redesign, extra equipment or exaggerated proportions.',
        'superfly': 'Superfly Johnson, the exact living adult human companion in the original reference. Preserve his distinctive face, hairstyle, broad strong build, original costume, equipment and colors. Refine the face and anatomy without redesigning or replacing this character.',
        'mishima': 'Kage Mishima, the exact adult human character in the original reference. Preserve his headwear or hairstyle, facial identity, original layered costume, long cloth panels, equipment and palette. Keep cloth panels separate from the legs for rigging. No generic soldier redesign or invented armor.',
        'usagi': 'Usagi, the exact adult Japanese male swordsman in the original reference: black topknot, mustache and pointed beard, muscular exposed forearms, black short-sleeved martial arts shirt, wide black sash, loose black trousers, black gloves and tall wrapped boots. Preserve his face, hairstyle, original outfit and palette. No female reinterpretation, armor, skirt or costume redesign.',
        'protopod': 'One upright egg-shaped launcher that releases a mechanical mosquito. A closed oval pod with orange-red ribbed shell panels, a metal support framework and greenish lower casing, following the source egg design. A clearly modeled hatching seam. No arms, legs, claws, face or humanoid anatomy. The mosquito is a separate spawned actor: depict only the closed egg, with no mosquito alongside it.',
        'mishimaguard': 'Faithfully restore the ORIGINAL Mishima Guard soldier shown in the front and side references, rather than redesigning his costume. A living lean human soldier with a stern mature face, normal eyes and healthy brown skin. Preserve his bronze military helmet covering the crown, ears and back of the head, its short angular brow peak and circular side hardware: this is a helmet, not hair, and must remain on his head. Preserve the narrow shoulders, slim exposed forearms, dark SHORT-SLEEVED high-collared shirt, close-fitting bronze chest-and-abdomen armor with the original panel layout, small shoulder plates, black gloves, straight dark trousers and tall narrow black boots. One hand rests on his hip exactly as in the reference. Preserve the original silhouette and modest armor bulk. Add sculpted bevels, seams, fabric weave and believable human features without changing the outfit or adding tactical equipment. No bare head, visible hairstyle, broad muscular build, long sleeves, new forearm armor, cargo pockets, pouches, straps, chunky combat boots, zombie, undead, demonic features, corpse-gray skin or glowing eyes.',
        'skinnyworker': 'A living slim human industrial worker wearing a dark work cap, charcoal utility vest over a tan shirt, tan work trousers, gloves and ordinary work boots. Healthy natural human face and skin. Preserve the slim build, no zombie or mutant features.',
        'surgeon': 'A living adult human surgeon in the pictured worn medical work clothes and apron, with gloves and boots. Realistic healthy human skin, face and anatomy. Keep the original medical outfit with faded rust-red fabric stains and modeled folds. No wounds, gore, armor, zombie face, mutated limbs or extra equipment.',
        'slaughterskeet': 'A mechanical mosquito drone with a compact segmented metal insect body, red optical components, long spread slender blade-like wings, six thin jointed metal legs and a needle-like proboscis. Entirely robotic, retaining the source wing arrangement. No humanoid or organic flesh.',
        'thunderskeet': 'A mechanical mosquito drone with a compact segmented dark-metal insect body, green optical components, long spread pointed blade-like wings, six thin jointed metal legs and a long needle proboscis. Entirely robotic, retaining the source wing arrangement. No humanoid or organic flesh.',
        'sludgeminion': 'An industrial humanoid robot with a small square sensor head, bulky torso, two exceptionally long heavy shield-like forearms, two articulated legs, metal boots, dark weathered armor and the source yellow-black chest caution panel. Entirely robotic, no flesh or human face.',
        'venomvermin': 'A hunched brown rat-like nonhuman quadruped with a long pointed snout, large ears, four slender clawed limbs and the exact tail visible in the blueprint. Rounded muscular volumes, sculpted leathery skin and detailed claws. Preserve the source species and proportions, no armor or human anatomy.',
        'psyclaw': 'A hunched brown nonhuman quadruped with a tapered body, back spines, two small projecting eye stalks and four muscular clawed limbs. Follow the pictured head and body plan, with rounded fleshy joints and sculpted claws.',
        'deathsphere': 'A hovering spherical combat drone with dark metallic segmented armor, red optical emitters and three prominent pointed mechanical fins. Fully mechanical, no humanoid anatomy.',
        'cambot': 'A hovering surveillance drone with a rounded bowl-like lower shell, articulated camera and lamp housings, a teal lens, yellow lamp and thin hooked vertical antenna. Fully mechanical, no humanoid anatomy.',
    }.get(slug, 'The exact creature and equipment shown in the source photograph.')
    subject = STORY_DESIGNS.get(slug, subject)
    subject = subject.replace('One hand rests on his hip exactly as in the reference. ', '')
    pose = ('a symmetric neutral A-pose: upright torso and head, straight arms extending outward '
            'and downward at 45 degrees, relaxed open hands, straight legs with feet shoulder-width apart. '
            'Both arms and hands must have a clearly visible air gap from torso and thighs; legs must '
            'have a clear gap. No hand on hip, crossed arms, bent fighting pose or body-part contact. '
            'For an armed technician hold the weapon outside the body alongside one extended arm, '
            'clear of the legs and torso; keep the weapon rigid and recognizable. '
            'This neutral pose replaces the photographed animation pose, while all identity and costume evidence remains authoritative.'
            if slug in A_POSE_MODELS or slug in STORY_SOURCES else 'the same general neutral pose and viewing direction as the blueprint, '
            'with each limb, wing and tail clearly separated from the body wherever the original body plan permits')
    second = ('Input image 2 is the same original soldier in side view; preserve his helmet and uniform.\n'
              if slug == 'mishimaguard' else 'Input image 2, when supplied, is only a sculpting and rendering quality reference. Do not transfer that character, anatomy, clothing, equipment or palette to this monster.\n')
    if slug in CHARACTER_SOURCES or slug in STORY_SOURCES:
        second = 'Input image 2 is an earlier high-detail illustration of THIS SAME CHARACTER. Use it for recognizable facial identity and sculpt quality. Input image 1 remains authoritative for original costume, proportions and colors; rebuild and refine all geometry.\n'
    if slug in STORY_SOURCES:
        second='Input image 2 is the side view of this SAME original character. Both source views are design evidence; faithfully preserve the face, gender, age, hairstyle, costume, helmet, accessories, body plan and colors. Improve sculpt quality without redesigning the subject.\n'
    robe = ('\nThe original closed long robe takes priority over the generic leg-separation instructions. Keep its continuous hem and original silhouette; feet may emerge below it. Only the arms need clear separation. Do not expose or split the covered legs.\n' if slug in ROBED_CHARACTERS else '')
    return (f'Use case: stylized-concept\nAsset type: high-poly creature sculpt reference for image-to-3D\n'
            f'Primary request: rebuild the {slug} monster as a modern cinematic-quality, highly detailed 3D model.\n'
            f'Subject: {subject}\n'
            'Input image 1 is a dated low-polygon DESIGN BLUEPRINT ONLY. Interpret its creature identity, '
            'body plan, approximate proportions, costume, machinery and colors. Reconstruct the actual forms '
            'from scratch with dense sculpted geometry and physically believable materials.\n'
            f'{second}'
            'Geometry: continuous rounded anatomical volumes, smooth muscles and joints, fully sculpted face, '
            'defined fingers and claws where present, natural soft-tissue transitions. Mechanical parts have '
            'thickness, curved housings, machined edge fillets, cylindrical hinges, recessed fasteners and '
            'separate articulated components. Surface markings become plausible modeled seams or relief.\n'
            'Quality target: polished high-poly digital sculpt rendered in a modern offline path tracer, '
            'comparable to the existing neural character references. Detail must read in the shape, silhouette, '
            'occlusion and highlights. Use restrained material wear so the actual sculpt remains clearly visible.\n'
            'Do not copy the old mesh facets, angular flesh, wedge-shaped hands, polygonal limbs, flat '
            'texture-painted anatomy, triangular contour breaks or crude block geometry. Do not merely '
            'add noisy scratches or sharpen the old texture. Retain intended hard armor planes with finely rounded edges.\n'
            f'Bind pose: {pose}\n'
            'Composition: one complete subject, front view with a slight three-quarter angle; '
            'all extremities visible, centered with a margin. Broad soft studio lighting with a gentle rim '
            'reveals the sculpted depth. Sharp, evenly exposed, 2048x2048.\n'
            'Constraints: preserve species, limb count, iconic equipment and color palette; interpret coarse '
            'contours naturally. No invented limbs or equipment, no humanization of nonhuman creatures. '
            'Genuinely transparent background, no floor, external cast shadow, text, labels or watermark.\n'
            + ('\nThe second image is the SAME ORIGINAL SOLDIER in side view, supplied to clarify the helmet, short sleeves and proportions; use both references as design evidence.' if slug=='mishimaguard' else '')
            + ('\nNeutral body master for skeletal animation: empty relaxed hands. Held weapons are separate attached runtime props, do not include a sword or gun in this body sculpt. Keep all original worn clothing and headgear. Precisely frontal view, symmetric A-pose, both arms 45 degrees downward away from the torso, not the narrower pose of the second illustration. Fully separated fingers and individual feet. Dense realistic modeled forms, natural skin and refined face, no faceted game mesh.\n' if slug in CHARACTER_SOURCES or slug in STORY_SOURCES else '') + robe)


def prompts(args):
    ledger = args.out.resolve() / 'pipeline.json'
    document = json.loads(ledger.read_text())
    for row in selected(document, args):
        if row['slug'] in ('prisoner','prisonerb') and row['stages'].get('concept',{}).get('state') == 'complete':
            continue  # The owner explicitly preserved their chained poses and appearance.
        path = ledger.parent / row['slug'] / 'prompt.txt'
        content = concept_prompt(row['slug'])
        if path.read_text() != content:
            path.write_text(content)
            if 'concept' in row['stages']:
                prior = row['stages']['concept'].copy()
                prior['state'] = 'needs_revision'
                prior['reason'] = 'Concept specification changed; rebuild the required identity and high-poly forms'
                record_stage(ledger, row['slug'], 'concept', prior, invalidate=('trellis', 'convert'))


def save(path, document):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(document, indent=2, sort_keys=True) + '\n')
    temporary.replace(path)


def record_stage(ledger, slug, stage, record, invalidate=()):
    """Serialize independent actor workers without losing another stage's receipt."""
    with ledger.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        document = json.loads(ledger.read_text())
        actor = next(row for row in document['actors'] if row['slug'] == slug)
        actor['stages'][stage] = record
        for following in invalidate:
            actor['stages'].pop(following, None)
        document['acceptance'] = 'unrun'
        save(ledger, document)


def preserve(args):
    """Freeze the two owner-protected chained performances with explicit lineage."""
    ledger=args.out.resolve()/'pipeline.json'
    for row in selected(json.loads(ledger.read_text()),args):
        if row['slug'] not in ('prisoner','prisonerb'): raise ValueError('Only the two explicitly protected prisoners may be frozen')
        directory=ledger.parent/row['slug'];receipt=row['stages']['convert'].copy()
        if receipt['state']!='complete': raise ValueError('Preservation requires an existing completed conversion')
        for name,sha in receipt['outputs'].items():
            if digest(directory/name)!=sha: raise ValueError('Protected output changed: '+name)
        for name in ('source.npz','source.json'):
            if digest(directory/name)!=receipt['inputs'][name]: raise ValueError('Protected source changed: '+name)
        generation=json.loads((directory/'trellis.json').read_text())
        if generation['input_sha256']!=digest(directory/'concept.png'): raise ValueError('Protected concept changed')
        receipt['preservation']=dict(reason='Owner explicitly preserved chained pose and existing appearance; no refitting.',
            inputs={name:digest(directory/name) for name in ('source.npz','source.json','concept.png','prompt.txt')},
            original_conversion_inputs=receipt['inputs'].copy(),
            note='Any later export of the same concept does not replace this preserved IQM or atlas.')
        record_stage(ledger,row['slug'],'convert',receipt)
        print(row['slug']+': chained performance preserved',flush=True)


def roster(assets, episode):
    with zipfile.ZipFile(assets / 'packages/dk3-data.pk3') as archive:
        rows = [dict(row) for row in entities.parse(archive.read('dk3/tables/aidata.cfg').split(b'\n', 1)[1])]
    result = []
    for row in rows:
        source = row.get('model_name', '')
        if row.get('classname', '').startswith('monster_') and source.startswith(f'models/e{episode}/'):
            slug = row['classname'].removeprefix('monster_')
            result.append(dict(slug=slug, classname=row['classname'], source=source,
                               render_scale=row['render_scale'], physics='anchored' if slug in ('rockgat', 'lasergat', 'protopod') else 'articulated'))
    return sorted(result, key=lambda row: row['slug'])


def prepare(args):
    output, assets = args.out.resolve(), args.assets.resolve()
    output.mkdir(parents=True, exist_ok=True)
    base = assets / 'packages/dk3-models.pk3'
    rows = roster(assets, args.episode)
    old = json.loads((output / 'pipeline.json').read_text()) if (output / 'pipeline.json').is_file() else None
    if args.include_characters or (old and any(r.get('kind') == 'character' for r in old['actors'])):
        rows += [dict(slug=name,kind='character',classname=name,source=path,render_scale='1 1 1',physics='humanoid')
                 for name,path in CHARACTER_SOURCES.items()]
    if args.include_story or (old and any(r.get('slug') in STORY_SOURCES for r in old['actors'])):
        rows += [dict(slug=name,kind='character',classname=name,source=path,render_scale='1 1 1',physics='humanoid')
                 for name,path in STORY_SOURCES.items()]
    identity = digest(base)
    if old and (old['source_models_sha256'] != identity or old['episode'] != args.episode):
        raise ValueError('Output belongs to different source assets; choose a new --out directory')
    with zipfile.ZipFile(base) as archive:
        for row in rows:
            directory = output / row['slug']
            directory.mkdir(exist_ok=True)
            previous = next((r for r in old['actors'] if r['slug'] == row['slug']), None) if old else None
            if previous and previous['source'] == row['source'] and (directory/'source.npz').is_file() and (directory/'source.json').is_file():
                row.update(previous)
                continue
            metadata = json.loads(archive.read(row['source'] + '.json'))
            if metadata['target']['format'] != 'md3':
                raise ValueError('Monster must have an admitted animated MD3 source: ' + row['source'])
            surfaces, tags = read_md3(archive.read(metadata['target']['entry']))
            surfaces = [surface for surface in surfaces if surface['material'] != 'models/dkq3/nodraw']
            idle = next((s for s in metadata['sequences']['frame_data'] if s['animation_name'] == 'amba'), None)
            # Raised turrets, rather than the fully retracted first frame.
            standing = next((s for s in metadata['sequences']['frame_data'] if s['animation_name'] == 'walka'),None)
            frame = (len(metadata['frames']) - 1 if row['slug'] == 'rockgat' else
                     standing['first'] if row['slug']=='toshiro' and standing else idle['first'] if idle else 0)
            row['reference_frame'] = frame
            arrays = {}
            descriptors = []
            for i, surface in enumerate(surfaces):
                material = surface['material']
                skin = next(s for s in metadata['skins'] if s['shader'] == material)
                texture = f'source-texture-{i}.png'
                (directory / texture).write_bytes(archive.read(skin['image']))
                descriptors.append(dict(texture=texture, name=surface['name']))
                for name in ('points', 'uv', 'tri', 'normals'):
                    arrays[f'{i}_{name}'] = surface[name]
            for name, positions in tags.items():
                arrays['tag_' + name] = positions
            np.savez_compressed(directory / 'source.npz', **arrays)
            save(directory / 'source.json', dict(actor=row, surfaces=descriptors, metadata=metadata, tags=list(tags)))
            prompt = concept_prompt(row['slug'])
            (directory / 'prompt.txt').write_text(prompt)
            row['stages'] = (next((r['stages'] for r in old['actors'] if r['slug'] == row['slug']), {}) if old else {})
    document = dict(format=1, topic='neural-episode-monsters', episode=args.episode, assets=str(assets),
                    source_models_sha256=identity, actors=rows, acceptance='unrun')
    ledger=output/'pipeline.json'
    with ledger.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        latest=json.loads(ledger.read_text()) if ledger.is_file() else None
        if latest:
            for row in rows:
                previous=next((r for r in latest['actors'] if r['slug']==row['slug'] and r['source']==row['source']),None)
                if previous: row['stages']=previous['stages']
        save(ledger, document)
    print(f'Prepared {len(rows)} actors (episode {args.episode} monsters and selected characters): {output}', flush=True)


def selected(document, args):
    rows = document['actors']
    names=args.models or ([args.model] if getattr(args,'model',None) else [])
    if names:
        missing = set(names) - {row['slug'] for row in rows}
        if missing:
            raise ValueError(f'Unknown monster names: {sorted(missing)}')
        rows = [row for row in rows if row['slug'] in names]
    return rows


def environment(output):
    env = os.environ.copy()
    env['OPENBLAS_NUM_THREADS'] = '1'
    env['OMP_NUM_THREADS'] = '4'
    env['HF_HOME'] = str(ROOT / 'zig-out/neural-tools/huggingface')
    env['TORCH_EXTENSIONS_DIR'] = str(ROOT / 'zig-out/neural-tools/torch-extensions')
    env['TRITON_CACHE_DIR'] = str(ROOT / 'zig-out/neural-tools/triton-cache')
    # Local Blender/runtime profile mismatch was qualified by the character pass.
    ocio = ROOT / 'zig-out/reports/runtime-zig-317/config.ocio'
    if ocio.is_file():
        env.setdefault('OCIO', str(ocio))
    return env


def run_stage(args):
    from neural_monster_face import FACE_IDENTITIES
    output = args.out.resolve()
    ledger = output / 'pipeline.json'
    document = json.loads(ledger.read_text())
    failures = []
    for row in selected(document, args):
        directory = output / row['slug']
        if args.command == 'convert' and row['stages'].get('head'):
            raise ValueError('Reviewed head reconstruction freezes the body conversion; rebuild a separate candidate: ' + row['slug'])
        frozen=row['stages'].get('convert',{}).get('preservation')
        if frozen:
            for name,expected in frozen['inputs'].items():
                if digest(directory/name)!=expected: raise ValueError('Protected prisoner input changed: '+name)
            for name,expected in row['stages']['convert']['outputs'].items():
                if digest(directory/name)!=expected: raise ValueError('Protected prisoner output changed: '+name)
            print(f'{row["slug"]}: protected chained assets retained',flush=True)
            continue
        products = {'capture': ['photo.png', 'side.png'], 'trellis': ['model.glb', 'trellis.json'],
                    'convert': ['model.iqm', 'body.png', 'conversion.json']}[args.command]
        if args.command == 'convert' and row.get('kind') == 'character': products += ['model.clips.json','body.face-mask.png']
        face=args.command=='convert' and (directory/'face-projection.png').is_file()
        surface=args.command=='convert'
        closure=surface and (directory/'surface-quality.json').is_file()
        if surface: products+=['surface-normals.json']
        if closure: products+=['surface-closure.json','uv-atlas.json','uv-atlas.npz','uv-atlas.LICENSE.txt']
        if face:
            products+=['body.face.json'];inputs_face=['face-projection.png','face-plan.json']
            if (directory/'face-prompt.txt').is_file():inputs_face+=['face-prompt.txt']
            face_plan=json.loads((directory/'face-plan.json').read_text())
            reference=face_plan.get('reference_front_path','face-source/front.png')
            if reference not in ('face-source/front.png','face-seam-source/front.png','face-quality-source/front.png'):raise ValueError('Invalid face reference')
            if (directory/reference).is_file():inputs_face+=[reference]
            for view in face_plan.get('projections',[]):
                name=view['path']
                if Path(name).name!=name or not name.endswith('.png'):raise ValueError('Invalid independent projection path')
                if name not in inputs_face:inputs_face.append(name)
            if face_plan.get('projections'):
                products += ['face-depth-cache.json']+[f'face-depth-{i}.exr' for i in range(len(face_plan['projections']))]
        inputs = (['source.npz', 'source.json'] if args.command != 'trellis' else ['concept.png', 'prompt.txt'])
        if args.command == 'capture': inputs += [d['texture'] for d in json.loads((directory/'source.json').read_text())['surfaces']]
        if args.command == 'convert': inputs += ['model.glb', 'trellis.json']
        if args.command == 'convert' and (directory/'alignment.json').is_file():inputs+=['alignment.json']
        if closure:inputs+=['surface-quality.json']
        if face: inputs+=inputs_face
        try:
            row = next(r for r in json.loads(ledger.read_text())['actors'] if r['slug'] == row['slug'])
            prerequisite = {'trellis': 'concept', 'convert': 'trellis'}.get(args.command)
            if prerequisite and row['stages'].get(prerequisite, {}).get('state') != 'complete':
                raise ValueError(f'Complete the {prerequisite} stage before {args.command}')
            if prerequisite:
                for name, expected in row['stages'][prerequisite]['outputs'].items():
                    if digest(directory/name) != expected: raise ValueError('Changed prerequisite product: '+name)
            if args.command == 'trellis' and digest(directory/'prompt.txt') != row['stages']['concept']['inputs']['prompt.txt']:
                raise ValueError('Concept belongs to an earlier prompt; revise it before inference')
            key = {name: digest(directory / name) for name in inputs}
            key['tool'] = digest(TOOLS / ('neural_monster_trellis.py' if args.command == 'trellis' else 'neural_monster_blender.py'))
            if args.command == 'convert':
                key['fitter'] = digest(TOOLS/'neural_monster_rig.py')
                key['skeleton'] = digest(TOOLS/'neural_monster_skeleton.py')
                key['character_rig'] = digest(TOOLS/'neural_rig.py')
                key['character_motion'] = digest(TOOLS/'neural_assets.py')
                key['iqm'] = digest(TOOLS/'skeletal_iqm.py')
                if row['slug']=='protopod':key['pod_rig']=digest(TOOLS/'neural_pod.py')
                if row['slug'] in ('sludgeminion','ragemaster'):key['mechanical_rig']=digest(TOOLS/'neural_mechanical.py')
                if row['slug']=='venomvermin':key['quadruped_rig']=digest(TOOLS/'neural_quadruped.py')
                if row.get('kind') == 'character': key['face_protection'] = digest(TOOLS/'neural_character_surface.py')
                if face:
                    key['face_intake']=digest(TOOLS/'neural_monster_face.py')
                    key['face_baker']=digest(TOOLS/'neural_face.py')
                    key['face_topology']=json.loads((directory/'face-plan.json').read_text()).get('seam_repair',{}).get('tool_sha256',digest(TOOLS/'neural_topology.py'))
                    if face_plan.get('projections'):
                        key['projection_baker']=digest(TOOLS/'neural_projection_bake.py')
                        key['feature_registration']=digest(TOOLS/'neural_face_registration.py')
                if closure:
                    key['surface_closure']=digest(TOOLS/'neural_surface_close.py')
                    key['surface_quality']=digest(TOOLS/'neural_surface_quality.py')
                    key['uv_atlas']=digest(TOOLS/'neural_uv.py')
                key['triangles'] = args.triangles
                if surface: key['surface_normals'] = digest(TOOLS/'neural_surface.py')
            if args.command == 'trellis':
                key['resolution'] = args.resolution
                key['memory_adapter'] = digest(TOOLS/'neural_trellis_memory.py')
                key['deployment'] = digest(args.trellis_source.parent.parent/'deployment.json')
                key['weights'] = digest(args.trellis_source.parent.parent/'weights.json')
            prior = row['stages'].get(args.command, {})
            previous_data=previous_conversion=None
            # A first lighting-only upgrade can reuse the exact completed
            # conversion. All original inputs and output bytes must match;
            # changed geometry, motion, face inputs or tools still rebuild.
            if surface and prior.get('state')=='complete' and prior.get('inputs',{}).get('surface_normals')!=key['surface_normals'] and {k:v for k,v in prior.get('inputs',{}).items() if k!='surface_normals'}=={k:v for k,v in key.items() if k!='surface_normals'} and all(
                    (directory/name).is_file() and digest(directory/name)==prior['outputs'].get(name)
                    for name in products if name!='surface-normals.json'):
                from neural_surface import repair_actor
                repair_actor(directory)
                row['stages'][args.command]=dict(state='complete',inputs=key,
                    outputs={name:digest(directory/name) for name in products})
                record_stage(ledger,row['slug'],args.command,row['stages'][args.command])
                print(f'{row["slug"]}: head lighting upgraded; geometry, atlas and motion retained',flush=True)
                continue
            if prior.get('state') == 'complete' and prior.get('inputs') == key and all(
                    (directory / name).is_file() and digest(directory / name) == prior['outputs'].get(name) for name in products):
                print(f'{row["slug"]}: {args.command} retained', flush=True)
                continue
            if face and getattr(args,'repair_uv_seams',False):
                if prior.get('state')!='complete' or any(digest(directory/n)!=prior['outputs'][n] for n in ('model.iqm','body.png','conversion.json')):
                    raise ValueError('Seam repair requires the exact completed previous conversion')
                previous_data=(directory/'model.iqm').read_bytes()
                previous_conversion=json.loads((directory/'conversion.json').read_text())
                checkpoint=directory/('seam-repair-inputs-'+digest(directory/'model.iqm')[:12])
                checkpoint.mkdir(exist_ok=True)
                for name in ('model.iqm','body.png','conversion.json','face-plan.json'):
                    shutil.copy2(directory/name,checkpoint/name)
                save(checkpoint/'stage.json',prior)
            if args.command == 'trellis':
                command = [str(args.python.absolute()), str(TOOLS / 'neural_monster_trellis.py'),
                           '--source', str(args.trellis_source.resolve()), '--actor', str(directory),
                           '--resolution', args.resolution]
            else:
                command = [args.blender, '-b', '--threads', '4', '--python-exit-code', '1', '--python',
                           str(TOOLS / 'neural_monster_blender.py'), '--', '--stage', args.command,
                           '--actor', str(directory), '--triangles', str(args.triangles)]
            row['stages'][args.command] = dict(state='running', inputs=key, command=command)
            record_stage(ledger, row['slug'], args.command, row['stages'][args.command])
            log_path = directory / f'{args.command}.log'
            if log_path.is_file():
                attempt = len(list(directory.glob(f'{args.command}.attempt-*.log'))) + 1
                shutil.copy2(log_path, directory/f'{args.command}.attempt-{attempt:03}.log')
            with log_path.open('w') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=environment(output))
                if not result.returncode and args.command == 'convert':
                    result = subprocess.run([str(args.python.absolute()), str(TOOLS/'neural_monster_rig.py'),
                                             '--actor', str(directory)], stdout=log, stderr=subprocess.STDOUT,
                                             env=environment(output))
            if result.returncode:
                raise RuntimeError(f'exit {result.returncode}; see {directory / (args.command + ".log")}')
            if args.command=='convert' and row['slug']=='venomvermin':
                from neural_quadruped import convert
                convert(directory)
            if closure:
                from neural_surface_quality import close_actor
                close_actor(directory,args.blender,environment(output))
            if face:
                if previous_data is not None:
                    from neural_topology import reregister
                    reregister(directory,previous_data,previous_conversion,prior['inputs'],args.blender,environment(output))
                    # Re-registration changes the plan/reference inputs, while
                    # retaining the original image-tool edit and its history.
                    key.pop(reference,None)
                    reference=json.loads((directory/'face-plan.json').read_text()).get('reference_front_path','face-source/front.png')
                    key['face-plan.json']=digest(directory/'face-plan.json')
                    key[reference]=digest(directory/reference)
                    key['face_topology']=json.loads((directory/'face-plan.json').read_text())['seam_repair']['tool_sha256']
                from neural_monster_face import bake
                bake(directory,args.blender,environment(output))
            if args.command == 'convert' and row.get('kind') == 'character':
                from neural_character_surface import tint_mask
                tint_mask(directory)
            if surface:
                from neural_surface import repair_actor
                repair_actor(directory)
            row['stages'][args.command] = dict(state='complete', inputs=key,
                                              outputs={name: digest(directory / name) for name in products})
            print(f'{row["slug"]}: {args.command} complete', flush=True)
        except (OSError, ValueError, RuntimeError, KeyError, subprocess.SubprocessError) as error:
            row['stages'][args.command] = dict(state='blocked' if isinstance(error, FileNotFoundError) else 'failed', error=str(error))
            failures.append(row['slug'])
            print(f'{row["slug"]}: {args.command}: {error}', flush=True)
        record_stage(ledger, row['slug'], args.command, row['stages'][args.command])
    if failures:
        raise SystemExit(f'{args.command} incomplete: {", ".join(failures)}')


def concept(args):
    output = args.out.resolve()
    ledger = output / 'pipeline.json'
    document = json.loads(ledger.read_text())
    row = next(r for r in document['actors'] if r['slug'] == args.model)
    if row['slug'] in ('prisoner','prisonerb'):
        raise ValueError('The owner protected both prisoners: preserve their chained poses and existing appearance')
    directory = output / row['slug']
    if row['stages'].get('capture', {}).get('state') != 'complete':
        raise ValueError('Capture the source monster before admitting its concept')
    from PIL import Image
    image = Image.open(args.image)
    image.verify()
    image = Image.open(args.image)
    if min(image.size) < 1024 or image.mode != 'RGBA' or image.getextrema()[3][0] == 255:
        raise ValueError('Concept must be a high-resolution RGBA cutout, at least 1024 pixels per edge')
    destination = directory / 'concept.png'
    if destination.is_file() and digest(destination) != digest(args.image):
        backup = directory / ('concept-' + digest(destination)[:12] + '.png')
        shutil.copy2(destination, backup)
    image.save(destination)
    row['stages']['concept'] = dict(state='complete', tool='built-in image_gen',
                                    inputs={n: digest(directory / n) for n in ('photo.png', 'prompt.txt')},
                                    outputs={'concept.png': digest(destination)}, size=list(image.size))
    record_stage(ledger, row['slug'], 'concept', row['stages']['concept'], invalidate=('trellis', 'convert'))
    print(f'{args.model}: concept admitted at {destination}')


def package(args):
    output = args.out.resolve()
    document = json.loads((output / 'pipeline.json').read_text())
    rows = document['actors']
    if any(row['stages'].get('convert', {}).get('state') != 'complete' for row in rows):
        raise ValueError('Whole-episode package requires every roster entry to finish conversion')
    base = Path(document['assets']) / 'packages/dk3-models.pk3'
    if digest(base) != document['source_models_sha256']:
        raise ValueError('Source model generation changed')
    # Validate the entire chain before generating any character variants.
    for row in rows:
        directory=output/row['slug']
        head_stage=row['stages'].get('head',{})
        if head_stage and head_stage.get('state')!='complete':
            raise ValueError('Incomplete head reconstruction: '+row['slug'])
        for stage in STAGES:
            receipt=row['stages'].get(stage,{})
            if receipt.get('state')!='complete': raise ValueError('Incomplete stage: '+row['slug']+' '+stage)
            for name,expected in receipt.get('outputs',{}).items():
                product=directory/name
                if stage=='convert' and name in head_stage.get('base_products',{}):
                    product=directory/head_stage['base_products'][name]
                if not product.is_file() or digest(product)!=expected:
                    raise ValueError('Changed stage product: '+str(directory/name))
            required={'capture':('source.npz','source.json'), 'concept':('photo.png','prompt.txt'),
                      'trellis':('concept.png','prompt.txt'), 'convert':('source.npz','source.json','model.glb','trellis.json')}[stage]
            if stage=='convert' and receipt.get('preservation'):
                for name,expected in receipt['preservation']['inputs'].items():
                    if digest(directory/name)!=expected: raise ValueError('Protected prisoner input changed: '+name)
                required=('source.npz','source.json')
            if stage=='convert' and 'face-projection.png' in receipt.get('inputs',{}):
                required+=tuple(n for n in ('face-projection.png','face-plan.json','face-prompt.txt','face-source/front.png','face-seam-source/front.png','face-quality-source/front.png') if n in receipt['inputs'])
                plan=json.loads((directory/'face-plan.json').read_text())
                required+=tuple(v['path'] for v in plan.get('projections',[]) if v['path'] not in required)
            if stage=='convert' and 'surface-quality.json' in receipt.get('inputs',{}):required+=('surface-quality.json',)
            if stage=='convert' and 'alignment.json' in receipt.get('inputs',{}):required+=('alignment.json',)
            for name in required:
                expected=receipt.get('inputs',{}).get(name)
                if expected and digest(directory/name)!=expected: raise ValueError('Changed stage input: '+str(directory/name))
        if head_stage:
            for collection in ('inputs','outputs'):
                for name,expected in head_stage[collection].items():
                    if digest(directory/name)!=expected:
                        raise ValueError('Changed head '+collection+': '+row['slug']+'/'+name)
    files = {}
    character_report = {}
    character_rows=[row for row in rows if row.get('kind')=='character']
    character_package=args.characters
    if character_rows:
        from neural_assets import build, CHARACTERS
        if not set(CHARACTERS)<={r['slug'] for r in character_rows}:
            raise ValueError('Rebuilding character variants requires all five character masters')
        masters=output/'character-masters';masters.mkdir(exist_ok=True)
        for row in character_rows:
            actor=output/row['slug'];name=row['slug']
            for source,suffix in (('model.iqm','.iqm'),('body.png','.png'),('conversion.json','.json'),
                                  ('model.clips.json','.clips.json'),('body.face-mask.png','.face-mask.png')):
                if source=='conversion.json' and row['stages'].get('head'):
                    source='conversion-head.json'
                shutil.copy2(actor/source,masters/(name+suffix))
            if (actor/'body.face.json').is_file():shutil.copy2(actor/'body.face.json',masters/(name+'.face.json'))
            if row['stages'].get('head'):
                shutil.copy2(actor/'head.png',masters/(name+'.head.png'))
                shutil.copy2(actor/'head-reconstruction.json',masters/(name+'.head.json'))
        if character_package:
            # Explicit reuse is valid only for the exact rebuilt masters. A
            # monster-only repair must not silently reintroduce old characters.
            admitted=validate_package(character_package,base)
            expected={r['slug'] for r in character_rows}
            if set(admitted.get('inputs',{}))!=expected:
                raise ValueError('Character package has a different master roster')
            for row in character_rows:
                actor=output/row['slug'];prior=admitted['inputs'][row['slug']]
                for source,key in (('model.iqm','iqm_sha256'),('body.png','texture_sha256')):
                    if prior.get(key)!=digest(actor/source):
                        raise ValueError('Character package has an outdated master: '+row['slug'])
                conversion='conversion-head.json' if row['stages'].get('head') else 'conversion.json'
                if prior.get('mesh')!=json.loads((actor/conversion).read_text()):
                    raise ValueError('Character package has outdated conversion metadata: '+row['slug'])
                if row['stages'].get('head') and prior.get('head_texture_sha256')!=digest(actor/'head.png'):
                    raise ValueError('Character package has outdated head atlas: '+row['slug'])
                face_path=actor/'body.face.json'
                face_report=json.loads(face_path.read_text()) if face_path.is_file() else None
                if prior.get('face_repair')!=face_report:
                    raise ValueError('Character package has outdated face provenance: '+row['slug'])
        else:
            character_package=output/'dk3-neural-characters.pk3'
            build(output,Path(document['assets']),character_package,meshes=masters,characters=tuple(r['slug'] for r in character_rows))
    if character_package:
        character_report = validate_package(character_package, base)
        with zipfile.ZipFile(character_package) as archive:
            files = {n: archive.read(n) for n in archive.namelist() if n != 'dk3/neural-assets.json'}
    mapping = files.get('dk3/neural-models.cfg', b'').decode()
    shader = files.get('scripts/dk3-neural.shader', b'').decode()
    physics = files.get('dk3/neural-physics.cfg',b'').decode()
    human_motion = {}
    for row in rows:
        if row.get('kind')=='character': continue
        directory = output / row['slug']
        target = f'models/neural/e{document["episode"]}_{row["slug"]}.iqm'
        texture = f'models/neural/e{document["episode"]}_{row["slug"]}/body.png'
        files[target] = (directory / 'model.iqm').read_bytes()
        files[texture] = (directory / 'body.png').read_bytes()
        model=sk.read(files[target])
        from neural_human_motion import HUMANS, human_clips
        if row['slug'] in HUMANS:
            source=json.loads((directory/'source.json').read_text())
            conversion=json.loads((directory/'conversion.json').read_text())
            model,clips=human_clips(model,source['metadata'],conversion['landmarks'],HUMANS[row['slug']])
            before_sha=hashlib.sha256(files[target]).hexdigest()
            files[target]=sk.write(model)
            files['dk3/neural-animations.cfg']=files.get('dk3/neural-animations.cfg',b'')+''.join(
                f'{row["source"]} {c["first"]} {c["last"]} {c["playback_first"]} {c["playback_last"]} {c["rate"]} 0 0\n' for c in clips).encode()
            human_motion[row['slug']]=dict(master_sha256=before_sha,output_sha256=hashlib.sha256(files[target]).hexdigest(),clips=clips)
        for variant,suffix in enumerate(dkm2md3.RENDER_VARIANTS):
            files[target+f'.{variant}.skin']=''.join(f'{name},{material}{suffix}\n' for name,material,*_ in model.meshes).encode()
        mapping += f'{row["source"]} {target}\n'
        shader += f'\n{texture[:-4]}\n{{\n cull none\n {{\n map {texture}\n rgbGen lightingDiffuse\n }}\n}}\n'
        shader += dkm2md3.variant_stanzas(texture[:-4],texture,True)
        conversion=json.loads((directory/'conversion.json').read_text())
        physics += f'{target} {conversion.get("physics",row["physics"])}\n'
    files['dk3/neural-models.cfg'] = mapping.encode()
    files['dk3/neural-physics.cfg'] = physics.encode()
    files['scripts/dk3-neural.shader'] = shader.encode()
    report = {k:value for k,value in character_report.items() if k not in ('files','losses')}
    report['human_motion']=dict(models=human_motion,geometry_bind_weights_atlases='unchanged',native_acceptance='unverified')
    report.update(dict(format=1, source_models_sha256=document['source_models_sha256'], episode=document['episode'],
                  actors=rows, files={n: hashlib.sha256(data).hexdigest() for n, data in files.items()},
                  losses=['Single-image geometry and material inference; anatomical biped and Venomvermin quadruped motion is authored independently, other creature motion is fitted to the source.',
                          'No facial morphs or PBR metallic/roughness in the current runtime material path.']))
    files['dk3/neural-assets.json'] = (json.dumps(report, indent=2, sort_keys=True) + '\n').encode()
    destination = output / 'dk3-neural-episode.pk3'
    temporary = destination.with_suffix('.tmp')
    with classic_archive(temporary) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    validate_package(temporary, base)
    temporary.replace(destination)
    save(output / 'package.json', report)
    print(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'prompts', 'capture', 'concept', 'trellis', 'convert', 'face', 'face-quality', 'face-quality-preview', 'face-preview', 'preserve', 'package', 'status'))
    parser.add_argument('--assets', type=Path, default=ROOT / 'zig-out/assets/current')
    parser.add_argument('--out', type=Path, default=ROOT / 'zig-out/neural-monsters/episode1')
    parser.add_argument('--episode', type=int, choices=(1, 2, 3, 4), default=1)
    parser.add_argument('--include-characters', action='store_true', help='also rebuild the five existing neural character identities and all their established variants')
    parser.add_argument('--include-story', action='store_true', help='also rebuild the remaining story identities and their cinematic variants')
    parser.add_argument('--models', nargs='+')
    parser.add_argument('--model')
    parser.add_argument('--image', type=Path)
    parser.add_argument('--candidate',type=Path,help='reviewed closed-surface face candidate directory')
    parser.add_argument('--blender', default='blender')
    parser.add_argument('--python', type=Path, default=ROOT / 'zig-out/neural-tools/runtime/bin/python')
    parser.add_argument('--trellis-source', type=Path, default=ROOT / 'zig-out/neural-tools/sources/TRELLIS.2-75fbf0183001ed9876c8dbb35de6b68552ee08bd')
    parser.add_argument('--resolution', choices=('512', '1024_cascade', '1536_cascade'), default='1024_cascade')
    parser.add_argument('--triangles', type=int, default=36000)
    parser.add_argument('--repair-uv-seams',action='store_true',help='qualify re-registration of existing face projections after welding the same GLB')
    parser.add_argument('--characters', type=Path, help='merge an existing validated neural character package')
    args = parser.parse_args()
    if args.command == 'prepare': prepare(args)
    elif args.command == 'prompts': prompts(args)
    elif args.command == 'preserve': preserve(args)
    elif args.command == 'concept':
        if not args.model or not args.image: parser.error('concept requires --model and --image')
        concept(args)
    elif args.command == 'face':
        if not args.model or not args.image:parser.error('face requires --model and --image')
        from neural_monster_face import admit
        admit(args)
    elif args.command == 'face-preview':
        from neural_monster_face import preview
        preview(args)
    elif args.command == 'face-quality':
        if not args.model or not args.candidate:parser.error('face-quality requires --model and --candidate')
        from neural_monster_face import admit_quality
        admit_quality(args)
    elif args.command == 'face-quality-preview':
        from neural_monster_face import quality_preview
        quality_preview(args)
    elif args.command == 'package': package(args)
    elif args.command == 'status':
        document = json.loads((args.out / 'pipeline.json').read_text())
        for row in document['actors']:
            print(row['slug'], ' '.join(f'{s}={row["stages"].get(s, {}).get("state", "unrun")}' for s in STAGES))
    else: run_stage(args)


if __name__ == '__main__': main()
