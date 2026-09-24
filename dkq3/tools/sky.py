"""Package authored moving skies using ioquake3 cloud geometry and shader stages."""
import math
import re
from pathlib import Path


def settings(world, mapname):
    values = {}
    for key, default in dict(cloudxdir=1, cloudydir=.8, cloud1tile=8, cloud1speed=1,
                             cloud2tile=2, cloud2speed=4, cloud2alpha=.7, lightningfreq=.25).items():
        try:
            value = float(world.get(key, default))
        except (ValueError, TypeError) as error:
            raise ValueError(f'map {mapname}: invalid sky {key}={world.get(key)}') from error
        if not math.isfinite(value) or abs(value) > 10000:
            raise ValueError(f'map {mapname}: invalid sky {key}={value}')
        values[key] = value
    if values['cloud1tile'] <= 0 or values['cloud2tile'] < 0:
        raise ValueError(f'map {mapname}: cloud tile sizes must be positive')
    values['cloud2alpha'] = max(0, min(1, values['cloud2alpha']))
    return values


def shader(name, box, image, values):
    def layer(tile, speed):
        # A cloud scrolls in its authored direction independently of camera motion.
        rate = .002 * speed * values['cloud1tile']
        return [f'map {image}', f'tcMod scale {tile:g} {tile:g}',
                f'tcMod scroll {rate * values["cloudxdir"]:g} {rate * values["cloudydir"]:g}']
    stages = [layer(values['cloud1tile'], values['cloud1speed']) + ['rgbGen identity']]
    if values['lightningfreq'] > 0:
        # Flashes stay in the sky pass, behind the second cloud layer. The engine's
        # deterministic noise waveform replaces the original renderer's random timer.
        stages.append(['map $whiteimage', 'blendFunc add',
                       f'rgbGen wave noise -0.25 0.75 0 {1 / max(.01, values["lightningfreq"]):g}'])
    if values['cloud2alpha'] > 0 and values['cloud2tile'] > 0:
        stages.append(layer(values['cloud2tile'], values['cloud2speed']) +
                      ['blendFunc blend', 'rgbGen identity', f'alphaGen const {values["cloud2alpha"]:g}'])
    body = ''.join(' {\n  ' + '\n  '.join(stage) + '\n }\n' for stage in stages)
    return f'{name}\n{{\n surfaceparm sky\n surfaceparm nolightmap\n skyParms {box} 512 -\n{body}}}\n'


def entries(game, images, records, encode_image):
    import convert_all
    import dk2q3
    import dkbsp
    import dkimg
    import entities
    import shadergen
    output, shaders, report = {}, [], []
    for mapname in sorted(convert_all.discover(game)):
        source = game.find(f'maps/{mapname}.bsp')
        raw, _ = dk2q3.entity_text(dkbsp.Bsp(source[1]).raw('entities'), game.find(f'maps/{mapname}.ent'))
        world = dict(next(iter(entities.parse(raw))))
        cloud, sky = world.get('cloudname', '').lower(), world.get('sky', '').lower()
        skies = [sky] + [world.get(f'sky_{i}', '').lower() for i in range(2, 6)]
        if not sky:
            continue
        for value in skies + ([cloud] if cloud and cloud != 'none' else []):
            if value and (not re.fullmatch(r'[a-z0-9_/-]+', value) or '..' in value):
                raise ValueError(f'map {mapname}: unsafe sky or cloud name {value}')
        values = settings(world, mapname)
        names = []
        key = ''
        for i, selected in enumerate(skies):
            if not selected:
                names.append(names[0])
                continue
            box = f'env/32bit/{selected}'
            name = f'dk3/sky/{mapname}/{i + 1}'
            names.append(name)
            for suffix in shadergen.SKY_SUFFIXES:
                side = shadergen.sky_side(records, box, suffix)
                if side:
                    output[f'{box}_{suffix}.tga'] = encode_image(dkimg.read_png(Path(images) / records[side]['files'][0]['file']))
                else:
                    output[f'{box}_{suffix}.tga'] = encode_image(shadergen.notexture_image())
            if i == 0 and cloud and cloud != 'none':
                key = f'env/32bit/{cloud}'
                record = records.get(key, {})
                if record.get('status') != 'image':
                    raise ValueError(f'map {mapname}: missing authored cloud image {key}.tga')
                image = f'dk3/skies/{cloud}.tga'
                output[image] = encode_image(dkimg.read_png(Path(images) / record['files'][0]['file']))
                shaders.append(shader(name, box, image, values))
            else:
                shaders.append(f'{name}\n{{\n surfaceparm sky\n surfaceparm nolightmap\n skyParms {box} 512 -\n}}\n')
        original = f'textures/dkq3/sky/{sky}'
        output[f'dk3/skies/{mapname}.cfg'] = ('dk3_sky 2 "' + original + '" ' + ' '.join('"' + n + '"' for n in names) + '\n').encode('ascii')
        report.append(dict(map=mapname, cloud=key, shader=name, settings=values))
    output['scripts/dk3-skies.shader'] = '\n'.join(shaders).encode('ascii')
    return sorted(output.items()), report
