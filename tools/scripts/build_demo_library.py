r"""Demo library for LOOKING at the program - not the importer.

Turns every book of an unpacked books.chm (E. G. White, history, spiritual life,
prophecy study) and the Synodal Bible into the SQL that fills
Tests/fixtures/schema.sql. "Утренние чтения" stay out (anomalous structure).
The real importer is a separate project (architecture/Slovo_Import_Deferred.md);
this script cuts every corner it can: no spans, no PageBreakOffset, a page marker
simply means "the next paragraphs are on page N". Good enough to read whole
chapters with their real structure. The result holds the translations' text -
never commit it.

From the repository root (Windows):

  "C:\Program Files\7-Zip\7z.exe" x -o%TEMP%\books books.chm
  python tools\scripts\build_demo_library.py %TEMP%\books %TEMP%\demo.sql
  tools\sqlite\out\sqlite3.exe Win64\Debug\library.db ".read Tests/fixtures/schema.sql" ".read %TEMP%/demo.sql"

(hh.exe -decompile also unpacks it, but now and then silently writes nothing.)
The custom sqlite3.exe is required: the stemmed tables need snowball (B-31).
The target library.db must not exist yet (and Slovo must not be running).
"""
import html, os, re, sys, unicodedata

# CHM section folder -> TBookCategory (bcSpiritOfProphecy, bcHistory, bcSpiritualLife, bcProphecyStudy)
SECTIONS = [('egw_books', 0), ('history', 1), ('spiritual', 2), ('prophecy', 3)]

# Series (B-25): code, title, SeriesOrder, members in canonical order.
SERIES = [
    ('conflict-of-ages', 'Конфликт веков', 1, ['PP', 'PK', 'DA', 'AA', 'GC']),
    ('testimonies', 'Свидетельства для Церкви', 2, ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9']),
]

# The CHM table of contents gives PaM the same abbreviation as PM.
ABBREVIATION_FIXES = {'PaM': 'ПС'}

# Synodal order of books/NN.htm -> OSIS code, short title, abbreviation.
BIBLE = [
 ('GEN','Бытие','Быт'),('EXO','Исход','Исх'),('LEV','Левит','Лев'),('NUM','Числа','Чис'),
 ('DEU','Второзаконие','Втор'),('JOS','Иисус Навин','Нав'),('JDG','Судьи','Суд'),('RUT','Руфь','Руф'),
 ('1SA','1 Царств','1Цар'),('2SA','2 Царств','2Цар'),('1KI','3 Царств','3Цар'),('2KI','4 Царств','4Цар'),
 ('1CH','1 Паралипоменон','1Пар'),('2CH','2 Паралипоменон','2Пар'),('EZR','Ездра','Езд'),('NEH','Неемия','Неем'),
 ('EST','Есфирь','Есф'),('JOB','Иов','Иов'),('PSA','Псалтирь','Пс'),('PRO','Притчи','Притч'),
 ('ECC','Екклесиаст','Еккл'),('SNG','Песнь песней','Песн'),('ISA','Исаия','Ис'),('JER','Иеремия','Иер'),
 ('LAM','Плач Иеремии','Плач'),('EZK','Иезекииль','Иез'),('DAN','Даниил','Дан'),('HOS','Осия','Ос'),
 ('JOL','Иоиль','Иоил'),('AMO','Амос','Ам'),('OBA','Авдий','Авд'),('JON','Иона','Ион'),
 ('MIC','Михей','Мих'),('NAM','Наум','Наум'),('HAB','Аввакум','Авв'),('ZEP','Софония','Соф'),
 ('HAG','Аггей','Агг'),('ZEC','Захария','Зах'),('MAL','Малахия','Мал'),('MAT','От Матфея','Мф'),
 ('MRK','От Марка','Мк'),('LUK','От Луки','Лк'),('JHN','От Иоанна','Ин'),('ACT','Деяния','Деян'),
 ('JAS','Иакова','Иак'),('1PE','1 Петра','1Пет'),('2PE','2 Петра','2Пет'),('1JN','1 Иоанна','1Ин'),
 ('2JN','2 Иоанна','2Ин'),('3JN','3 Иоанна','3Ин'),('JUD','Иуды','Иуд'),('ROM','Римлянам','Рим'),
 ('1CO','1 Коринфянам','1Кор'),('2CO','2 Коринфянам','2Кор'),('GAL','Галатам','Гал'),('EPH','Ефесянам','Еф'),
 ('PHP','Филиппийцам','Флп'),('COL','Колоссянам','Кол'),('1TH','1 Фессалоникийцам','1Фес'),('2TH','2 Фессалоникийцам','2Фес'),
 ('1TI','1 Тимофею','1Тим'),('2TI','2 Тимофею','2Тим'),('TIT','Титу','Тит'),('PHM','Филимону','Флм'),
 ('HEB','Евреям','Евр'),('REV','Откровение','Откр'),
]

# TParagraphKind: 0 title, 1 subtitle, 2 epigraph, 3 heading, 4 citation, 6 text.
K_TITLE, K_SUBTITLE, K_EPIGRAPH, K_HEADING, K_TEXT = 0, 1, 2, 3, 6

P_RE = re.compile(r'<p\b([^>]*)>(.*?)</p>', re.S | re.I)
MARKER_RE = re.compile(r'^\[(\d+)\]$')
INLINE_PAGE_RE = re.compile(r'<a\s+name=["\']?page\d+["\']?\s*>\s*\[\d+\]\s*</a>', re.I)
TOC_LINK_RE = re.compile(r'<a\s+href="([^"#]+\.htm)[^"]*"\s+class="l"\s*>(.*?)</a>', re.S | re.I)
CHAPTER_PREFIX_RE = re.compile(r'^Глава\s+[\dIVXLCDM]+\.?\s*', re.I)


def clean(fragment):
    s = re.sub(r'<[^>]+>', '', fragment)
    s = html.unescape(s)
    s = s.replace('\xad', '').replace('\u200b', '').replace('\ufeff', '').replace('\xa0', ' ')
    s = re.sub(r'\s+', ' ', s).strip()
    return unicodedata.normalize('NFC', s)


def q(s):
    return "'" + s.replace("'", "''") + "'"


def read(path):
    return open(path, encoding='utf-8-sig', errors='replace').read()


def toc_abbreviations(root):
    """'egw_books/PP' -> 'ПП', title from the CHM contents (<a name="ПП">Патриархи и пророки</a>)."""
    text = read(os.path.join(root, 'contents.htm'))
    result = {}
    for abbr, title, folder in re.findall(
            r'<a name="([^"]*)">([^<]*)</a>\s*<p><a href="(egw_books/[^/]+)/first\.htm"', text, re.I):
        result[folder.split('/')[1]] = (abbr, clean(title))
    return result


def book_files(folder):
    """Chapter files in the order of the book's own table of contents (first.htm)."""
    first = read(os.path.join(folder, 'first.htm'))
    title = clean(re.search(r'<title>(.*?)</title>', first, re.S | re.I).group(1))
    author = re.search(r'<div class="autor">(.*?)</div>', first, re.S | re.I)
    author = clean(author.group(1)) if author else ''
    present = {f.lower(): f for f in os.listdir(folder) if f.lower().endswith('.htm') and f.lower() != 'first.htm'}
    files = []
    for href, text in TOC_LINK_RE.findall(first):
        name = present.get(href.lower())
        if name and name not in [f for f, _ in files]:
            files.append((name, clean(text)))
    listed = {f for f, _ in files}
    files += [(f, '') for f in sorted(present.values()) if f not in listed]   # not in the TOC: at the end
    return title, author, files


def book(folder, module_id, out, ids):
    _, _, files = book_files(folder)
    chapters = []            # [title, [(kind, text, page, on_page)]]
    page, on_page = 0, 0
    for name, toc_title in files:
        text = INLINE_PAGE_RE.sub('', read(os.path.join(folder, name)))
        current = [toc_title, []]
        chapters.append(current)
        for attrs, inner in P_RE.findall(text):
            cls = re.search(r'class="([^"]+)"', attrs)
            cls = cls.group(1).lower() if cls else ''
            if cls == 'glink':
                continue
            plain = clean(inner)
            if not plain:
                continue
            m = MARKER_RE.match(plain)
            if m:
                page, on_page = int(m.group(1)), 0
                continue
            if cls == 'glava':
                title = CHAPTER_PREFIX_RE.sub('', plain).strip() or plain
                if any(k != K_TITLE for k, *_ in current[1]):
                    current = [title, []]           # one more chapter in the same file
                    chapters.append(current)
                else:
                    current[0], current[1] = title, []
                current[1].append((K_TITLE, title, 0, 0))
                continue
            if cls == 'glava2':
                current[1].append((K_SUBTITLE, plain, 0, 0))
                continue
            stripped = inner.strip()
            if 'center' in attrs.lower() and re.fullmatch(r'(?is)<i>.*</i>', stripped):
                current[1].append((K_EPIGRAPH, plain, 0, 0))
            elif re.fullmatch(r'(?is)<b>.*</b>', stripped):
                current[1].append((K_HEADING, plain, 0, 0))
            else:
                on_page += 1
                current[1].append((K_TEXT, plain, page, on_page))
    order = 0
    for title, paras in chapters:
        if not any(k != K_TITLE for k, *_ in paras):
            continue                                   # empty file / title only
        title = title or next(t for k, t, *_ in paras if k != K_TITLE)[:80]
        if paras[0][0] != K_TITLE:
            paras.insert(0, (K_TITLE, title, 0, 0))
        order += 1
        out.append(f"INSERT INTO Chapters VALUES ({q(module_id)}, {order}, {q(title)});")
        for index, (kind, plain, start_page, para_on_page) in enumerate(paras, 1):
            ids[0] += 1
            out.append("INSERT INTO Paragraphs (Id, ModuleId, ChapterOrder, LogicalIndex, Kind, Text, "
                       "StartPageNumber, PageBreakOffset, ParagraphOnPage) VALUES "
                       f"({ids[0]}, {q(module_id)}, {order}, {index}, {kind}, {q(plain)}, {start_page}, -1, {para_on_page});")
    return order


def bible(root, out, ids):
    for n, (code, short, abbr) in enumerate(BIBLE, 1):
        text = read(os.path.join(root, 'bible', f'{n:02d}.htm'))
        parts = re.split(r'<a name="(\d+)" class="b_glava">', text)
        chapters = 0
        verses = []
        for i in range(1, len(parts), 2):
            chapter = int(parts[i])
            for _, inner in P_RE.findall(parts[i + 1]):
                inner = re.sub(r'<font class="vl">.*?</font>', '', inner, flags=re.S)
                m = re.match(r'\s*<font class="b_vers">(\d+)</font>(.*)', inner, re.S)
                if not m:
                    continue
                verse_text = clean(m.group(2))
                if verse_text:
                    verses.append((chapter, int(m.group(1)), verse_text))
            chapters = max(chapters, chapter)
        out.append(f"INSERT INTO Books VALUES ('synodal-ru', {q(code)}, {n}, {q(short)}, {q(abbr)}, {chapters});")
        seen = set()
        for chapter, verse, verse_text in verses:
            if (chapter, verse) in seen:
                continue                       # the source repeats a verse now and then
            seen.add((chapter, verse))
            ids[0] += 1
            out.append(f"INSERT INTO Verses VALUES ({ids[0]}, 'synodal-ru', {q(code)}, {chapter}, {verse}, {q(verse_text)});")


def main(root, target):
    out = ["-- Generated by tools/scripts/build_demo_library.py - demo data, not a release library.",
           "PRAGMA foreign_keys = ON;", "BEGIN;",
           "INSERT INTO Meta VALUES (1, '2026-11-06T00:00:00Z');"]
    series_of = {mid: (code, title, sorder, members.index(mid) + 1)
                 for code, title, sorder, members in SERIES for mid in members}
    egw = toc_abbreviations(root)
    modules = []
    for section, category in SECTIONS:
        for name in sorted(os.listdir(os.path.join(root, section))):
            folder = os.path.join(root, section, name)
            if not os.path.isfile(os.path.join(folder, 'first.htm')):
                continue
            title, author, _ = book_files(folder)
            abbr, toc_title = egw.get(name, ('', '')) if section == 'egw_books' else ('', '')
            abbr = ABBREVIATION_FIXES.get(name, abbr)
            title = toc_title or title
            code, stitle, sorder, pos = series_of.get(name, ('', '', 0, 0))
            out.append("INSERT INTO Modules (ModuleId, Kind, Category, Language, Title, Author, Series, SeriesTitle, "
                       "SeriesOrder, SortOrder, Abbreviation) VALUES "
                       f"({q(name)}, 0, {category}, 'ru', {q(title)}, {q(author)}, {q(code)}, {q(stitle)}, "
                       f"{sorder}, {pos}, {q(abbr)});")
            modules.append((folder, name, title))
    out.append("INSERT INTO Modules (ModuleId, Kind, Category, Language, Title, Author) VALUES "
               "('synodal-ru', 1, 0, 'ru', 'Библия (Синодальный)', '');")
    ids = [0]
    for folder, mid, title in modules:
        count = book(folder, mid, out, ids)
        print(f'{mid}: {count} chapters - {title}', file=sys.stderr)
    print(f'{len(modules)} books, {ids[0]} paragraphs', file=sys.stderr)
    ids = [0]
    bible(root, out, ids)
    print(f'synodal-ru: {ids[0]} verses', file=sys.stderr)
    out += ["INSERT INTO ParagraphsFTS(ParagraphsFTS) VALUES('rebuild');",
            "INSERT INTO VersesFTS(VersesFTS) VALUES('rebuild');",
            "INSERT INTO ParagraphsStem_ru(ParagraphsStem_ru) VALUES('rebuild');",
            "INSERT INTO VersesStem_ru(VersesStem_ru) VALUES('rebuild');",
            "COMMIT;"]
    with open(target, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out) + '\n')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('usage: build_demo_library.py <unpacked books.chm folder> <out.sql>')
    main(sys.argv[1], sys.argv[2])
