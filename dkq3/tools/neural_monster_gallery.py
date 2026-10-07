#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Write a standalone local source/concept/IQM pose review gallery."""
import argparse
import html
import json
from pathlib import Path


def gallery(out):
    document=json.loads((out/'pipeline.json').read_text())
    sections=[]
    for row in document['actors']:
        slug=row['slug'];actor=out/slug
        receipt=actor/'preview.json'
        poses=json.loads(receipt.read_text()).get('poses',[]) if receipt.is_file() else []
        converted=actor/('conversion-head.json' if row['stages'].get('head') else 'conversion.json')
        report=json.loads(converted.read_text()) if converted.is_file() else {}
        status=' · '.join(f'{name}: {stage.get("state","unrun")}' for name,stage in row['stages'].items())
        if slug in document.get('visual_acceptance',{}).get('rejected',[]):
            status='Close-up rejected; replacement in progress · '+status
        figures=[]
        for name,title in [('photo.png','Original model'),('concept.png','Detailed reference')]:
            if (actor/name).is_file(): figures.append(f'<figure class="{"original" if name=="photo.png" else "concept"}"><img loading="lazy" src="{slug}/{name}" alt="{html.escape(title)}"><figcaption>{title}</figcaption></figure>')
        if (actor/'head-source/concept.png').is_file():
            figures.append(f'<figure class="concept"><img loading="lazy" src="{slug}/head-source/concept.png" alt="Dedicated reconstructed head reference"><figcaption>Head reconstruction reference</figcaption></figure>')
        if poses and poses[0].get('source_image'):
            figures[0]=f'<figure class="original"><img loading="lazy" src="{slug}/{poses[0]["source_image"]}" alt="Original authored pose"><figcaption>Original · same animation frame</figcaption></figure>'
        if poses:
            choices=''.join(f'<option value="{slug}/{p["image"]}" data-source="{slug}/{p.get("source_image","photo.png")}">{html.escape(p["name"])} · frame {p["frame"]}</option>' for p in poses)
            figures.append(f'<figure><img loading="lazy" src="{slug}/{poses[0]["image"]}" alt="Converted skeletal pose"><figcaption>Converted IQM <select onchange="this.closest(\'figure\').querySelector(\'img\').src=this.value;this.closest(\'section\').querySelector(\'.original img\').src=this.selectedOptions[0].dataset.source">{choices}</select></figcaption></figure>')
        face=''
        if (actor/'face-review/receipt.json').is_file():
            choices=''.join(f'<option value="{slug}/face-review/{n}.png">{title}</option>' for n,title in [('front','Front'),('quarter','Quarter'),('side','Side'),('other-side','Other side')])
            face=f'<figure><img loading="lazy" src="{slug}/face-review/front.png" alt="Registered face albedo"><figcaption>Registered face albedo <select onchange="this.closest(\'figure\').querySelector(\'img\').src=this.value">{choices}</select></figcaption></figure>'
        if (actor/'face-lit-review/receipt.json').is_file():
            choices=''.join(f'<option value="{slug}/face-lit-review/{n}.png">{title}</option>' for n,title in [('front','Front'),('quarter','Quarter'),('side','Side'),('other-side','Other side')])
            face+=f'<figure><img loading="lazy" src="{slug}/face-lit-review/front.png" alt="Serialized face lighting"><figcaption>Serialized face lighting <select onchange="this.closest(\'figure\').querySelector(\'img\').src=this.value">{choices}</select></figcaption></figure>'
        details=''
        if report:
            motion = f'source-fit RMS {report["rms"]:.3f}' if report.get('rms') is not None else 'independently authored skeletal motion'
            details=f'{report["output_frames"]} frames · {report["joints"]} joints · {report["triangles"]:,} triangles · {motion}'
        conversion_name='conversion-head.json' if row['stages'].get('head') else 'conversion.json'
        links=' '.join(f'<a href="{slug}/{name}">{label}</a>' for name,label in [('prompt.txt','Prompt'),('model.glb','GLB'),('model.iqm','IQM'),(conversion_name,'Conversion report')] if (actor/name).is_file())
        sections.append(f'<section id="{slug}"><h2>{html.escape(slug)}</h2><p class="status">{html.escape(status)}</p><div class="images">{"".join(figures)}{face}</div><p>{details}</p><p>{links}</p></section>')
    content='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Episode monster asset review</title><style>
body{margin:0;background:#15191e;color:#e8edf2;font:16px/1.5 system-ui,sans-serif}main{max-width:1600px;margin:auto;padding:32px}h1{font-size:32px}h2{font-size:24px}.images{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}figure{margin:0;background:#242b33;border-radius:8px;overflow:hidden}img{width:100%;aspect-ratio:1;object-fit:contain;display:block;background:linear-gradient(45deg,#343b42 25%,transparent 25%,transparent 75%,#343b42 75%),linear-gradient(45deg,#343b42 25%,#2c333a 25%,#2c333a 75%,#343b42 75%);background-size:24px 24px;background-position:0 0,12px 12px}figcaption{padding:12px}section{border-top:1px solid #46515d;margin-top:36px;padding-top:16px}.status{color:#b8c5d1;font-size:14px}a{color:#8bceff;margin-right:16px}select{padding:5px;background:#15191e;color:inherit;border:1px solid #667788}nav{display:flex;gap:12px;flex-wrap:wrap}nav a{margin:0}@media(max-width:800px){.images{grid-template-columns:1fr}main{padding:16px}}</style><main><h1>Episode monster asset review</h1><p>Compare original identity, detailed sculpt reference and serialized IQM poses. Select a fitted pose to inspect motion. Stage completion is separate from visual and gameplay acceptance.</p>'''
    review = document.get('visual_acceptance',{})
    if review.get('state') == 'reopened':
        content += '<p role="status" style="padding:16px;border:1px solid #efaa58;background:#33271c"><strong>Visual acceptance reopened.</strong> '+html.escape(review['note'])+'</p>'
    content+='<nav>'+''.join(f'<a href="#{r["slug"]}">{r["slug"]}</a>' for r in document['actors'])+'</nav>'
    content+=''.join(sections)+'</main></html>'
    destination=out/'review.html'
    destination.write_text(content)
    print(destination)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=Path('zig-out/neural-monsters/episode1'))
    args=parser.parse_args();gallery(args.out)
