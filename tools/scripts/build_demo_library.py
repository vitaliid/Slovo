r"""Demo library for LOOKING at the program - not the importer.

Turns three books (PP, DA, SC) and the Synodal Bible from an unpacked books.chm
into the SQL that fills Tests/fixtures/schema.sql. The real importer is a
separate project (architecture/Slovo_Import_Deferred.md); this script cuts every
corner it can: no spans, no PageBreakOffset, a page marker simply means "the
next paragraphs are on page N". Good enough to read whole chapters with their
real structure. The result holds the translations' text - never commit it.

From the repository root (Windows):

  hh.exe -decompile %TEMP%\books books.chm
  python tools\scripts\build_demo_library.py %TEMP%\books %TEMP%\demo.sql
  tools\sqlite\out\sqlite3.exe Win64\Debug\library.db ".read Tests/fixtures/schema.sql" ".read %TEMP%/demo.sql"

The custom sqlite3.exe is required: the stemmed tables need snowball (B-31).
The target library.db must not exist yet (and Slovo must not be running).
"""
import html, os, re, sys, unicodedata

BOOKS = [  # folder, ModuleId, title, series, series title, series order, sort order, abbreviation
    ('PP', 'PP', 'Патриархи и пророки', 'conflict-of-ages', 'Конфликт веков', 1, 1, 'ПП'),
    ('DA', 'DA', 'Желание веков',       'conflict-of-ages', 'Конфликт веков', 1, 3, 'ЖВ'),
    ('SC', 'SC', 'Путь ко Христу',      '', '', 0, 0, 'ПкХ'),
]

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


def clean(fragment):
    s = re.sub(r'<[^>]+>', '', fragment)
    s = html.unescape(s)
    s = s.replace('\xad', '').replace('​', '').replace('﻿', '').replace('\xa0', ' ')
    s = re.sub(r'\s+', ' ', s).strip()
    return unicodedata.normalize('NFC', s)


def q(s):
    return "'" + s.replace("'", "''") + "'"


def book(root, folder, module_id, out, ids):
    files = sorted(f for f in os.listdir(os.path.join(root, 'egw_books', folder)) if f.endswith('.htm'))
    page, on_page, order = 0, 0, 0
    for name in files:
        text = open(os.path.join(root, 'egw_books', folder, name), encoding='utf-8-sig').read()
        paras = []
        title = None
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
                title = re.sub(r'^Глава\s+\d+\s*', '', plain).strip() or plain
                paras.append((K_TITLE, title, 0, 0))
                continue
            if cls == 'glava2':
                paras.append((K_SUBTITLE, plain, 0, 0))
                continue
            stripped = inner.strip()
            if 'center' in attrs.lower() and re.fullmatch(r'(?is)<i>.*</i>', stripped):
                paras.append((K_EPIGRAPH, plain, 0, 0))
            elif re.fullmatch(r'(?is)<b>.*</b>', stripped):
                paras.append((K_HEADING, plain, 0, 0))
            else:
                on_page += 1
                paras.append((K_TEXT, plain, page, on_page))
        if title is None:
            continue
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
        text = open(os.path.join(root, 'bible', f'{n:02d}.htm'), encoding='utf-8-sig').read()
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
    out = ["-- Generated by tools/demo-library/build_demo_sql.py - demo data, not a release library.",
           "PRAGMA foreign_keys = ON;", "BEGIN;",
           "INSERT INTO Meta VALUES (1, '2026-11-05T00:00:00Z');"]
    for folder, mid, title, series, stitle, sorder, order, abbr in BOOKS:
        out.append("INSERT INTO Modules (ModuleId, Kind, Category, Language, Title, Author, Series, SeriesTitle, "
                   "SeriesOrder, SortOrder, Abbreviation) VALUES "
                   f"({q(mid)}, 0, 0, 'ru', {q(title)}, 'Э. Уайт', {q(series)}, {q(stitle)}, {sorder}, {order}, {q(abbr)});")
    out.append("INSERT INTO Modules (ModuleId, Kind, Category, Language, Title, Author) VALUES "
               "('synodal-ru', 1, 0, 'ru', 'Библия (Синодальный)', '');")
    ids = [0]
    for folder, mid, *_ in BOOKS:
        count = book(root, folder, mid, out, ids)
        print(f'{mid}: {count} chapters', file=sys.stderr)
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
