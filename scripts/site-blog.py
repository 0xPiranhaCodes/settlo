#!/usr/bin/env python3
"""Dependency-free blog renderer. Markdown sources stay outside the Pages artifact."""
from datetime import date
import html
import json
from pathlib import Path
import re
from urllib.parse import urljoin

ORIGIN = 'https://sabkijeb.app'
TYPES = {'Announcement', 'Guide', 'Product update'}


def inline(text):
    """Text, **strong**, and links to local pages or mailto addresses only."""
    text = html.escape(text, quote=True)
    def link(match):
        label, target = match.groups()
        if not (target.startswith('/') and not target.startswith('//') or target.startswith('mailto:')):
            raise ValueError('Blog links must be site-relative or mailto: ' + target)
        return f'<a href="{target}">{label}</a>'
    text = re.sub(r'\[([^\]\n]+)\]\(([^)\s]+)\)', link, text)
    return re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)


def markdown(source):
    """Deliberately small subset: paragraphs, level-two headings, bullet lists."""
    blocks = []
    for block in re.split(r'\n\s*\n', source.strip()):
        lines = block.splitlines()
        if all(line.startswith('- ') for line in lines):
            blocks.append('<ul>\n' + '\n'.join('<li>' + inline(line[2:]) + '</li>' for line in lines) + '\n</ul>')
        elif len(lines) == 1 and block.startswith('## '):
            blocks.append('<h2>' + inline(block[3:]) + '</h2>')
        elif any(re.match(r'^(#|[-*>]|```|\d+\.)', line) for line in lines):
            raise ValueError('Unsupported Markdown block: ' + block)
        else:
            blocks.append('<p>' + inline(' '.join(lines)) + '</p>')
    return '\n'.join(blocks)


def read_posts(source):
    posts = []
    for path in sorted(source.glob('*.md')):
        if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', path.stem):
            raise ValueError('Invalid post slug: ' + path.stem)
        parts = path.read_text().split('---\n', 2)
        if len(parts) != 3 or parts[0]:
            raise ValueError('Expected JSON front matter: ' + str(path))
        meta = json.loads(parts[1])
        if set(meta) != {'title', 'type', 'date', 'summary', 'cover'} or not all(isinstance(v, str) and v.strip() for v in meta.values()):
            raise ValueError('Invalid metadata: ' + str(path))
        if meta['type'] not in TYPES or not re.fullmatch(r'[a-z]+', meta['cover']):
            raise ValueError('Invalid type or cover: ' + str(path))
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', meta['date']):
            raise ValueError('Expected YYYY-MM-DD date: ' + str(path))
        date.fromisoformat(meta['date'])
        posts.append(dict(meta, slug=path.stem, body=markdown(parts[2])))
    if not posts:
        raise ValueError('Blog needs at least one post')
    return sorted(posts, key=lambda post: (post['date'], post['slug']), reverse=True)


def date_label(value):
    day = date.fromisoformat(value)
    return f'{day.day} {day.strftime("%B")} {day.year}'


def chrome(landing, tag):
    fragment = re.search(fr'<{tag}>.*?</{tag}>', landing, re.S)[0]
    if tag == 'header':
        fragment += re.search(r'<div id="mobile-menu".*?</nav>.*?</div>', landing, re.S)[0]
    fragment = fragment.replace(' aria-current="page"', '')
    # Landing links and assets become root-relative on nested blog routes.
    return re.sub(r'(href|src)="([^\"]+)"', lambda m: f'{m[1]}="{urljoin("/", m[2])}"', fragment)


def outputs(root, landing):
    source = root / 'scripts/blog'
    posts = read_posts(source / 'posts')
    template = (source / 'page.template.html').read_text()
    result = {}
    def page(path, title, summary, content, post=None):
        url = ORIGIN + path
        schema = '<script type="application/ld+json">' + json.dumps({
            '@context': 'https://schema.org', '@type': 'CollectionPage', 'url': url,
            'publisher': {'@type': 'Organization', 'name': 'JOSH Studio', 'url': 'https://hellojosh.studio'}
        }) + '</script>'
        if post:
            article = {'@context': 'https://schema.org', '@type': 'Article',
                       'headline': post['title'], 'description': summary,
                       'datePublished': post['date'], 'mainEntityOfPage': url, 'url': url,
                       'image': ORIGIN + '/blog/covers/' + post['cover'] + '.svg',
                       'author': {'@type': 'Organization', 'name': 'JOSH Studio', 'url': 'https://hellojosh.studio'},
                       'publisher': {'@type': 'Organization', 'name': 'JOSH Studio'}}
            schema = '<script type="application/ld+json">' + json.dumps(article, ensure_ascii=False).replace('<', '\\u003c') + '</script>'
        values = dict(TITLE=html.escape(title + ' · SabkiJeb'), DESCRIPTION=html.escape(summary, quote=True),
                      URL=url, OG_TYPE='article' if post else 'website', SCHEMA=schema,
                      HEADER=chrome(landing, 'header'), FOOTER=chrome(landing, 'footer'), CONTENT=content,
                      IMAGE=ORIGIN + ('/blog/covers/' + post['cover'] + '.svg' if post else '/images/social.png'))
        result['site' + path + 'index.html'] = re.sub(r'\{\{([A-Z_]+)\}\}', lambda m: values[m[1]], template)
    cards = []
    for post in posts:
        slug, cover = post['slug'], post['cover']
        title, summary = html.escape(post['title']), html.escape(post['summary'])
        meta = f'<p class="post-meta"><span>{post["type"]}</span><time datetime="{post["date"]}">{date_label(post["date"])}</time></p>'
        art = f'<img class="post-cover" src="/blog/covers/{cover}.svg" width="1200" height="675" alt="">'
        cards.append(f'<article class="post-card">{art}<div class="post-card-copy">{meta}<h2>{title}</h2><p>{summary}</p><a class="post-link" href="/blog/{slug}/" aria-label="Read the post: {html.escape(post["title"], quote=True)}">Read the post <span aria-hidden="true">→</span></a></div></article>')
        content = f'<article class="post"><a class="back-link" href="/blog/">← All posts</a>{meta}<h1>{title}</h1><p class="lede">{summary}</p>{art}<div class="post-body">{post["body"]}</div><a class="back-link" href="/blog/">← Back to the blog</a></article>'
        page('/blog/' + slug + '/', post['title'], post['summary'], content, post)
        result['site/blog/covers/' + cover + '.svg'] = (source / 'covers' / (cover + '.svg')).read_text()
    page('/blog/', 'The SabkiJeb blog', 'Product updates, practical guides and news from SabkiJeb.',
         '<div class="blog-intro"><p class="eyebrow">The SabkiJeb blog</p><h1>Good friends.<br>Clear stories.</h1><p class="lede">Product news and practical ways to keep shared money clear.</p></div><div class="post-grid">' + '\n'.join(cards) + '</div>')
    return result
