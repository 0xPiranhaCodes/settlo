#!/usr/bin/env python3
"""Render flags and FAQ schema; commit the output for the buildless Pages deploy."""
import argparse
import html
import json
from pathlib import Path
import re

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
    output = ROOT / 'site/index.html'
    result = render((ROOT / 'scripts/site-index.template.html').read_text(), json.loads((ROOT / 'scripts/site-features.json').read_text()))
    if check:
        if output.read_text() != result:
            raise SystemExit('Site output is stale; run python3 scripts/site-build.py')
    else:
        output.write_text(result)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    build(parser.parse_args().check)
