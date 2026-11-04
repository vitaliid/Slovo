-- library.db format, SchemaVersion 1 (architecture\Slovo_02, "Схема library.db").
-- The reference schema: tests build their database from it, and the library
-- producer (Slovo_Import_Deferred) uses the same file. Needs the custom
-- sqlite3.dll with the snowball tokenizer (B-31).

CREATE TABLE Meta (
  SchemaVersion  INTEGER NOT NULL,
  BuiltAt        TEXT    NOT NULL
);

CREATE TABLE Modules (
  ModuleId       TEXT    PRIMARY KEY,
  Kind           INTEGER NOT NULL,
  Category       INTEGER NOT NULL,
  Language       TEXT    NOT NULL,
  Title          TEXT    NOT NULL,
  Author         TEXT    NOT NULL,
  Series         TEXT    NOT NULL DEFAULT '',
  SeriesTitle    TEXT    NOT NULL DEFAULT '',
  SeriesOrder    INTEGER NOT NULL DEFAULT 0,
  SortOrder      INTEGER NOT NULL DEFAULT 0,
  Abbreviation   TEXT    NOT NULL DEFAULT ''
);

-- ===================== Books (ckBook) =====================

CREATE TABLE Chapters (
  ModuleId      TEXT    NOT NULL REFERENCES Modules(ModuleId),
  ChapterOrder  INTEGER NOT NULL,
  ChapterTitle  TEXT    NOT NULL,
  PRIMARY KEY (ModuleId, ChapterOrder)
) WITHOUT ROWID;

CREATE TABLE Paragraphs (
  Id               INTEGER PRIMARY KEY,
  ModuleId         TEXT    NOT NULL,
  ChapterOrder     INTEGER NOT NULL,
  LogicalIndex     INTEGER NOT NULL,
  Kind             INTEGER NOT NULL,
  Text             TEXT    NOT NULL,
  StartPageNumber  INTEGER NOT NULL DEFAULT 0,
  PageBreakOffset  INTEGER NOT NULL DEFAULT -1,
  ParagraphOnPage  INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (ModuleId, ChapterOrder) REFERENCES Chapters(ModuleId, ChapterOrder),
  UNIQUE (ModuleId, ChapterOrder, LogicalIndex),
  CHECK (Kind <> 5)
);

CREATE TABLE Spans (
  ParagraphId  INTEGER NOT NULL REFERENCES Paragraphs(Id),
  StartOffset  INTEGER NOT NULL,
  Length       INTEGER NOT NULL,
  Kind         INTEGER NOT NULL,
  PRIMARY KEY (ParagraphId, StartOffset)
) WITHOUT ROWID;

CREATE VIRTUAL TABLE ParagraphsFTS USING fts5(
  Text,
  content='Paragraphs',
  content_rowid='Id',
  tokenize='unicode61 remove_diacritics 0'
);

-- ===================== Bible (ckBibleTranslation) =====================

CREATE TABLE Books (
  ModuleId       TEXT    NOT NULL REFERENCES Modules(ModuleId),
  BookCode       TEXT    NOT NULL,
  OrderInModule  INTEGER NOT NULL,
  DisplayTitle   TEXT    NOT NULL,
  Abbreviation   TEXT    NOT NULL DEFAULT '',
  ChapterCount   INTEGER NOT NULL CHECK (ChapterCount > 0),
  PRIMARY KEY (ModuleId, BookCode)
) WITHOUT ROWID;

CREATE TABLE Verses (
  Id             INTEGER PRIMARY KEY,
  ModuleId       TEXT    NOT NULL,
  BookCode       TEXT    NOT NULL,
  ChapterNumber  INTEGER NOT NULL,
  VerseNumber    INTEGER NOT NULL,
  Text           TEXT    NOT NULL,
  FOREIGN KEY (ModuleId, BookCode) REFERENCES Books(ModuleId, BookCode),
  UNIQUE (ModuleId, BookCode, ChapterNumber, VerseNumber)
);

CREATE VIRTUAL TABLE VersesFTS USING fts5(
  Text,
  content='Verses',
  content_rowid='Id',
  tokenize='unicode61 remove_diacritics 0'
);

-- ===================== Stemmed indexes (B-31) =====================
-- Books: ru only (the whole CHM corpus is Russian, IMP-3). Bible: uk, ru, en.

CREATE VIEW Paragraphs_ru AS
  SELECT p.Id, p.Text FROM Paragraphs p JOIN Modules m ON m.ModuleId = p.ModuleId
  WHERE m.Language = 'ru';

CREATE VIRTUAL TABLE ParagraphsStem_ru USING fts5(
  Text, content='Paragraphs_ru', content_rowid='Id',
  tokenize='snowball russian unicode61 remove_diacritics 0'
);

CREATE VIEW Verses_uk AS
  SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId
  WHERE m.Language = 'uk';

CREATE VIRTUAL TABLE VersesStem_uk USING fts5(
  Text, content='Verses_uk', content_rowid='Id',
  tokenize='snowball ukrainian unicode61 remove_diacritics 0'
);

CREATE VIEW Verses_ru AS
  SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId
  WHERE m.Language = 'ru';

CREATE VIRTUAL TABLE VersesStem_ru USING fts5(
  Text, content='Verses_ru', content_rowid='Id',
  tokenize='snowball russian unicode61 remove_diacritics 0'
);

CREATE VIEW Verses_en AS
  SELECT v.Id, v.Text FROM Verses v JOIN Modules m ON m.ModuleId = v.ModuleId
  WHERE m.Language = 'en';

CREATE VIRTUAL TABLE VersesStem_en USING fts5(
  Text, content='Verses_en', content_rowid='Id',
  tokenize='snowball english unicode61 remove_diacritics 0'
);
