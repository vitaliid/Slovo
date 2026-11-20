r"""Downloads the Russian books of one EGW Writings folder into raw JSON files.

Raw data for build_demo_library.py (--egw): one file per book,
<out>/<book id>.json = {"id", "title", "chapters": [[ [tag, class, refcode, text], ... ], ...]}.
A chapter is one reader page of the site (m.egwwritings.org/ru/book/<id>.<para>),
the chain is followed by its "Next" link. Already downloaded books are skipped,
so the script can be stopped and started again. The files hold the translations'
text - never commit them.

  python tools/scripts/egw_download.py Win64/egw [folder id, default 1216]
"""
import html, json, os, re, sys, time, urllib.request

SITE = 'https://m.egwwritings.org'
DELAY = 0.5                                   # seconds between requests - be gentle with the site
UA = 'Mozilla/5.0 (Slovo library builder)'

BOOK_LINK_RE = re.compile(r'<a[^>]+href="/ru/book/(\d+)\.0"[^>]*>(.*?)</a>', re.S)
PARA_RE = re.compile(r'<(p|h[1-6])\b([^>]*\begw_content_wrapper\b[^>]*)>(.*?)</\1>', re.S)
NEXT_RE = re.compile(r'<li class="next">\s*<a class="btn-large" href="(/ru/book/\d+\.\d+)"', re.S)


def get(path):
    for attempt in range(5):
        try:
            req = urllib.request.Request(SITE + path, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                url = r.geturl()
                return url, r.read().decode('utf-8')
        except Exception as e:                # network hiccup: wait and retry
            print(f'  retry {attempt + 1} {path}: {e}', file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f'cannot download {path}')
    

def text_of(fragment):
    s = re.sub(r'<[^>]+>', '', fragment)
    return re.sub(r'\s+', ' ', html.unescape(s)).strip()


def attr(attrs, name):
    m = re.search(name + r'="([^"]*)"', attrs)
    return html.unescape(m.group(1)) if m else ''


def folder_books(folder):
    _, page = get(f'/ru/folders/{folder}')
    books = {}
    for bid, title in BOOK_LINK_RE.findall(page):
        title = text_of(title)
        if title and title != 'Read':
            books.setdefault(bid, title)
    return books


def book(bid):
    chapters, path, seen = [], f'/ru/book/{bid}.0', set()
    while path and path not in seen:
        seen.add(path)
        _, page = get(path)
        paras = []
        for tag, attrs, inner in PARA_RE.findall(page):
            cls = ' '.join(c for c in attr(attrs, 'class').split() if c != 'egw_content_wrapper')
            t = text_of(inner)
            if t:
                paras.append([tag.lower(), cls, attr(attrs, 'data-refcode'), t])
        if paras:
            chapters.append(paras)
        m = NEXT_RE.search(page)
        path = m.group(1) if m else None
        time.sleep(DELAY)
    return chapters


def main(out, folder='1216'):
    os.makedirs(out, exist_ok=True)
    books = folder_books(folder)
    print(f'{len(books)} books in folder {folder}', file=sys.stderr)
    for n, (bid, title) in enumerate(books.items(), 1):
        target = os.path.join(out, f'{bid}.json')
        if os.path.exists(target):
            continue
        chapters = book(bid)
        tmp = target + '.part'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump({'id': bid, 'title': title, 'chapters': chapters}, f, ensure_ascii=False)
        os.replace(tmp, target)
        print(f'[{n}/{len(books)}] {bid}: {len(chapters)} chapters - {title}', file=sys.stderr, flush=True)


if __name__ == '__main__':
    if len(sys.argv) not in (2, 3):
        sys.exit('usage: egw_download.py <out folder> [folder id]')
    main(*sys.argv[1:])
