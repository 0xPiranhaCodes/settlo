#!/usr/bin/env python3
"""Exercise the publication boundary, including each future flag independently."""
import json
from pathlib import Path
import runpy
import re

root = Path(__file__).resolve().parents[1]
module = runpy.run_path(str(root / 'scripts/site-build.py'))
render = module['render']
flags = json.loads((root / 'scripts/site-features.json').read_text())
template = (root / 'scripts/site-index.template.html').read_text()
blocks = re.findall(r'<!-- IF ([!a-z_,]+) -->\n(.*?)\n<!-- ENDIF -->', template, re.S)
assert set(flags) == {key.lstrip('!') for names, _ in blocks for key in names.split(',')}
for enabled in [set(), set(flags), *[{key} for key in flags]]:
    settings = {key: key in enabled for key in flags}
    result = render(template, settings)
    assert ('class="future-grid"' in result) == bool(enabled & {'settle_link', 'person_qr', 'receipt_scan'})
    for names, content in blocks:
        assert (content in result) == all(not settings[key[1:]] if key.startswith('!') else settings[key] for key in names.split(',')), names
    schemas = [json.loads(s) for s in re.findall(r'<script type="application/ld\+json">(.*?)</script>',result,re.S)]
    faq = next(s for s in schemas if s['@type'] == 'FAQPage')
    assert len(faq['mainEntity']) == result.count('<details>')
try:
    render(template, {})
except ValueError:
    pass
else:
    raise AssertionError('Unknown flags accepted')
assert not (root / 'site/features.json').exists(), 'Build flags must stay outside the published site'
module['build'](check=True)
print('PASS: default, every flag independently, all enabled, dependencies, FAQ schema and output freshness')
