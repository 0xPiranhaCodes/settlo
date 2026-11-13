#!/usr/bin/env python3
"""Render the landing page, blog and sitemap for the buildless Pages deploy."""
import argparse
import html
import json
from pathlib import Path
import re
import runpy

ROOT = Path(__file__).resolve().parents[1]

def render(template, flags):
    if any(type(value) is not bool for value in flags.values()):
        raise ValueError('Feature flags must be booleans')
    def conditional(match):
        keys = match[1].split(',')
        if any(key.lstrip('!') not in flags for key in keys):
            raise ValueError('Unknown feature flag: ' + match[1])
        return match[2] if all(not flags[key[1:]] if key.startswith('!') else flags[key] for key in keys) else ''
    result = re.sub(r'<!-- IF ([!a-z_,]+) -->\n(.*?)\n<!-- ENDIF -->', conditional, template, flags=re.S)
    if '<!-- IF ' in result or '<!-- ENDIF -->' in result:
        raise ValueError('Malformed feature block')
    result = re.sub(r'<div class="future-grid">\s*</div>', '', result)
    pairs = re.findall(r'<details><summary>(.*?)</summary><p>(.*?)</p></details>', result, re.S)
    plain = lambda value: html.unescape(re.sub('<[^>]+>', '', value))
    schema = {'@context': 'https://schema.org', '@type': 'FAQPage', 'mainEntity': [
        {'@type': 'Question', 'name': plain(q), 'acceptedAnswer': {'@type': 'Answer', 'text': plain(a)}} for q, a in pairs]}
    return result.replace('<!-- FAQ_SCHEMA -->', '<script type="application/ld+json">\n' + json.dumps(schema, ensure_ascii=False) + '\n</script>')

def build(check=False):
    result = render((ROOT / 'scripts/site-index.template.html').read_text(), json.loads((ROOT / 'scripts/site-features.json').read_text()))
    outputs = {'site/index.html': result}
    blog = runpy.run_path(str(ROOT / 'scripts/site-blog.py'))
    outputs.update(blog['outputs'](ROOT, result))
    # All public index pages, including future hand-written pages, enter the sitemap.
    pages = {path.relative_to(ROOT).as_posix() for path in (ROOT / 'site').rglob('index.html')
             if not path.is_relative_to(ROOT / 'site/blog')}
    pages.update(path for path in outputs if path.endswith('/index.html'))
    urls = ["https://sabkijeb.app/" + path.removeprefix('site/').removesuffix('index.html') for path in sorted(pages)]
    outputs['site/sitemap.xml'] = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'  <url><loc>{html.escape(url)}</loc></url>\n' for url in urls) + '</urlset>\n'
    # Removing a source must also remove its old public page and cover.
    existing = {path.relative_to(ROOT).as_posix() for path in (ROOT / 'site/blog').rglob('*') if path.is_file()}
    stale = existing - outputs.keys()
    if check:
        drift = stale | {name for name, content in outputs.items() if not (ROOT / name).exists() or (ROOT / name).read_text() != content}
        if drift:
            raise SystemExit('Site output is stale; run python3 scripts/site-build.py: ' + ', '.join(sorted(drift)))
    else:
        for name in stale:
            (ROOT / name).unlink()
        for name, content in outputs.items():
            output = ROOT / name
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(content)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    build(parser.parse_args().check)
