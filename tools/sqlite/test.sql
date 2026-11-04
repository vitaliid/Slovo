-- Slovo: smoke test for the custom sqlite3.dll (B-31, Slovo_02 «Перевірено 2026-11-01»).
-- Run:  sqlite3.exe :memory: ".read test.sql"
-- Every line of output must start with PASS. The Delphi test (SnowballCheck.dpr)
-- builds the same schema and runs the same cases.

.bail on
.headers off
.mode list

SELECT CASE WHEN sqlite_compileoption_used('ENABLE_FTS5') THEN 'PASS' ELSE 'FAIL' END
       || '  compile option ENABLE_FTS5 (SQLite ' || sqlite_version() || ')';

-- Schema: the Bible part of library.db (Slovo_02, «Схема library.db»)
CREATE TABLE Modules (ModuleId TEXT PRIMARY KEY, Kind INTEGER NOT NULL, Language TEXT NOT NULL);
CREATE TABLE Verses (
  Id INTEGER PRIMARY KEY, ModuleId TEXT NOT NULL, BookCode TEXT NOT NULL,
  ChapterNumber INTEGER NOT NULL, VerseNumber INTEGER NOT NULL, Text TEXT NOT NULL);

CREATE VIRTUAL TABLE VersesFTS USING fts5(Text, content='Verses', content_rowid='Id',
  tokenize='unicode61 remove_diacritics 0');

CREATE VIEW Verses_uk AS SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId WHERE m.Language = 'uk';
CREATE VIEW Verses_ru AS SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId WHERE m.Language = 'ru';
CREATE VIEW Verses_en AS SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId WHERE m.Language = 'en';

CREATE VIRTUAL TABLE VersesStem_uk USING fts5(Text, content='Verses_uk', content_rowid='Id',
  tokenize='snowball ukrainian unicode61 remove_diacritics 0');
CREATE VIRTUAL TABLE VersesStem_ru USING fts5(Text, content='Verses_ru', content_rowid='Id',
  tokenize='snowball russian unicode61 remove_diacritics 0');
CREATE VIRTUAL TABLE VersesStem_en USING fts5(Text, content='Verses_en', content_rowid='Id',
  tokenize='snowball english unicode61 remove_diacritics 0');

-- Test data
INSERT INTO Modules VALUES ('test-uk', 1, 'uk'), ('test-ru', 1, 'ru'), ('test-en', 1, 'en');
INSERT INTO Verses (ModuleId, BookCode, ChapterNumber, VerseNumber, Text) VALUES
  ('test-uk', 'LEV', 1, 1, 'І приніс він жертву Господеві.'),
  ('test-uk', 'PSA', 51, 19, 'Жертви Богові — дух зламаний.'),
  ('test-uk', 'HEB', 10, 12, 'Він приніс одну жертву за гріхи.'),
  ('test-uk', 'GEN', 1, 1, 'На початку Бог створив небо й землю.'),
  ('test-ru', 'PSA', 50, 19, 'Жертва Богу — дух сокрушенный.'),
  ('test-ru', 'HEB', 10, 11, 'Каждый священник приносит одни и те же жертвы.'),
  ('test-ru', 'GEN', 1, 1, 'В начале сотворил Бог небо и землю.'),
  ('test-en', 'PSA', 51, 17, 'The sacrifices of God are a broken spirit.'),
  ('test-en', 'MAT', 27, 42, 'He saved others; himself he cannot save.'),
  ('test-en', 'GEN', 1, 1, 'In the beginning God created the heaven and the earth.');

INSERT INTO VersesFTS(VersesFTS) VALUES('rebuild');
INSERT INTO VersesStem_uk(VersesStem_uk) VALUES('rebuild');
INSERT INTO VersesStem_ru(VersesStem_ru) VALUES('rebuild');
INSERT INTO VersesStem_en(VersesStem_en) VALUES('rebuild');

-- Cases: table, MATCH, expected hits (highlighted words, in verse order)
CREATE TEMP TABLE Cases (N INTEGER, Tbl TEXT, Q TEXT, Expected TEXT);
INSERT INTO Cases VALUES
  (1, 'VersesStem_uk', '"жертва"',        'жертву|Жертви|жертву'),
  (2, 'VersesStem_uk', '"жертва Богові"', 'Жертви Богові'),
  (3, 'VersesStem_ru', '"жертва"',        'Жертва|жертвы'),
  (4, 'VersesStem_en', '"sacrifice"',     'sacrifices'),
  (5, 'VersesStem_en', '"saving"',        'saved|save'),
  (6, 'VersesFTS',     '"жертва"',        'Жертва');

-- FTS5 table names cannot be parameters, so one SELECT per table.
-- Hit = text between [ and ] in highlight(); several per verse joined by '|'.
CREATE TEMP TABLE Got (N INTEGER, VerseId INTEGER, Marked TEXT);
INSERT INTO Got SELECT c.N, t.rowid, highlight(VersesStem_uk, 0, '[', ']') FROM Cases c, VersesStem_uk t WHERE c.Tbl = 'VersesStem_uk' AND VersesStem_uk MATCH c.Q;
INSERT INTO Got SELECT c.N, t.rowid, highlight(VersesStem_ru, 0, '[', ']') FROM Cases c, VersesStem_ru t WHERE c.Tbl = 'VersesStem_ru' AND VersesStem_ru MATCH c.Q;
INSERT INTO Got SELECT c.N, t.rowid, highlight(VersesStem_en, 0, '[', ']') FROM Cases c, VersesStem_en t WHERE c.Tbl = 'VersesStem_en' AND VersesStem_en MATCH c.Q;
INSERT INTO Got SELECT c.N, t.rowid, highlight(VersesFTS, 0, '[', ']')     FROM Cases c, VersesFTS t     WHERE c.Tbl = 'VersesFTS'     AND VersesFTS MATCH c.Q;

WITH RECURSIVE Hits(N, VerseId, Rest, Hit) AS (
  SELECT N, VerseId, Marked, NULL FROM Got
  UNION ALL
  SELECT N, VerseId,
         substr(Rest, instr(Rest, ']') + 1),
         substr(Rest, instr(Rest, '[') + 1, instr(Rest, ']') - instr(Rest, '[') - 1)
  FROM Hits WHERE instr(Rest, '[') > 0
),
Actual AS (
  SELECT N, group_concat(Hit, '|') AS Hits
  FROM (SELECT N, Hit FROM Hits WHERE Hit IS NOT NULL ORDER BY N, VerseId, length(Rest) DESC)
  GROUP BY N
)
SELECT CASE WHEN coalesce(a.Hits, '') = c.Expected THEN 'PASS' ELSE 'FAIL' END
       || '  ' || c.N || '. ' || c.Tbl || ' MATCH ' || c.Q
       || '  →  ' || coalesce(a.Hits, '(нічого)')
       || CASE WHEN coalesce(a.Hits, '') = c.Expected THEN '' ELSE '   очікувалось: ' || c.Expected END
FROM Cases c LEFT JOIN Actual a ON a.N = c.N ORDER BY c.N;

-- Startup probe from Slovo_02 (phase 0): one query per *Stem_* table must not fail.
SELECT 'PASS  probe ' || 'VersesStem_uk' FROM (SELECT count(*) FROM (SELECT rowid FROM VersesStem_uk WHERE VersesStem_uk MATCH 'a' LIMIT 1));
SELECT 'PASS  probe ' || 'VersesStem_ru' FROM (SELECT count(*) FROM (SELECT rowid FROM VersesStem_ru WHERE VersesStem_ru MATCH 'a' LIMIT 1));
SELECT 'PASS  probe ' || 'VersesStem_en' FROM (SELECT count(*) FROM (SELECT rowid FROM VersesStem_en WHERE VersesStem_en MATCH 'a' LIMIT 1));
