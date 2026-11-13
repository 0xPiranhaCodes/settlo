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

# Publication and drift regressions run in a disposable miniature checkout.
import shutil
import tempfile
from xml.etree import ElementTree
blog = runpy.run_path(str(root / 'scripts/site-blog.py'))
assert '<script>' not in blog['markdown']('<script>alert(1)</script>')
try:
    blog['markdown']('[unsafe](javascript:alert)')
except ValueError:
    pass
else:
    raise AssertionError('Unsafe link accepted')
assert not list((root / 'site').rglob('*.md')), 'Authoring Markdown must not be published'
with tempfile.TemporaryDirectory() as temporary:
    fixture = Path(temporary)
    shutil.copytree(root / 'scripts', fixture / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
    (fixture / 'site').mkdir()
    # Card inputs and outputs that live in the published tree.
    for name in ('images/cards', 'images/art', 'fonts'):
        shutil.copytree(root / 'site' / name, fixture / 'site' / name)
    shutil.copy(root / 'site/images/mark.png', fixture / 'site/images/mark.png')
    build = runpy.run_path(str(fixture / 'scripts/site-build.py'))['build']
    build()
    build(check=True)
    def rejects_drift():
        try:
            build(check=True)
        except SystemExit:
            return
        raise AssertionError('Changed source/output passed freshness check')
    posts = blog['read_posts'](fixture / 'scripts/blog/posts')
    post = posts[0]
    output = fixture / f'site/blog/{post["slug"]}/index.html'
    clean = output.read_text()
    output.write_text(clean + '<p>Unreviewed output</p>')
    rejects_drift()
    build()
    source = fixture / f'scripts/blog/posts/{post["slug"]}.md'
    cover = fixture / f'scripts/blog/covers/{post["cover"]}.svg'
    card = fixture / f'site/images/cards/{post["slug"]}.png'
    spot = fixture / 'site/images/art/chai.svg'
    originals = {path: path.read_bytes() for path in (source, cover, card, spot)}
    def restore():
        for path, content in originals.items():
            path.write_bytes(content)
        build()
        build(check=True)
    source.write_text(source.read_text() + '\nA source edit.\n')
    rejects_drift()
    build()
    assert 'A source edit.' in output.read_text()
    restore()
    # Covers, spots and the rendered PNG cards all guard the committed social cards.
    for path, change in ((cover, b'\n'), (card, b'\0'), (spot, b'\n')):
        path.write_bytes(originals[path] + change)
        rejects_drift()
        restore()
    source.unlink()
    rejects_drift()
    build()
    try:
        build(check=True)
    except SystemExit as error:
        # Pages are clean; only the removed post's card and inputs remain to re-render.
        assert all('site-cards' in name for name in str(error).split(': ', 1)[1].split(', ')), error
    assert not output.exists(), 'Removed posts must leave the publication artifact'
    assert f'/blog/{post["slug"]}/' not in (fixture / 'site/sitemap.xml').read_text()
    assert not list((fixture / 'site').rglob('*.md'))

posts = blog['read_posts'](root / 'scripts/blog/posts')
for post in posts:
    content = (root / f'site/blog/{post["slug"]}/index.html').read_text()
    schema = json.loads(re.search(r'<script type="application/ld\+json">(.*?)</script>', content, re.S)[1])
    assert schema['@type'] == 'Article' and schema['headline'] == post['title']
    assert schema['datePublished'] == post['date']
    assert schema['description'] == post['summary']
    assert schema['mainEntityOfPage'] == f'https://sabkijeb.app/blog/{post["slug"]}/'
urls = {node.text for node in ElementTree.parse(root / 'site/sitemap.xml').iter('{http://www.sitemaps.org/schemas/sitemap/0.9}loc')}
assert 'https://sabkijeb.app/blog/' in urls
assert all(f'https://sabkijeb.app/blog/{post["slug"]}/' in urls for post in posts)
print('PASS: blog metadata, escaping, source/output/cover/social-card drift, post removal, sitemap and unpublished Markdown')

# Transfer budgets: social cards 100 KB, every other published image 150 KB.
images = [path for path in (root / 'site').rglob('*') if path.suffix in {'.png', '.jpg', '.jpeg', '.webp', '.avif', '.gif', '.svg', '.ico'}]
heavy = [f'{name} {size:,} B' for path in images
         if (size := path.stat().st_size) > (100_000 if (name := path.relative_to(root / 'site').as_posix()).startswith('images/cards/') else 150_000)]
assert not heavy, 'Over image budget: ' + ', '.join(heavy)
print(f'PASS: {len(images)} site images within budget (cards 100 KB, others 150 KB)')
