-- Test library: 3 books x 3 chapters, 3 Bible translations x 2 books.
-- Rows are inserted deliberately OUT of order (Ids vs LogicalIndex/VerseNumber),
-- so that tests notice a missing ORDER BY.
-- Enum values: Kind 0 = ckBook, 1 = ckBibleTranslation; Category 0 = bcSpiritOfProphecy;
-- TParagraphKind 0 title, 1 subtitle, 2 epigraph, 3 heading, 4 citation, 6 text;
-- Spans.Kind 0 bold, 1 italic.

PRAGMA foreign_keys = ON;

INSERT INTO Meta VALUES (1, '2026-11-04T00:00:00Z');

INSERT INTO Modules (ModuleId, Kind, Category, Language, Title, Author, Series, SeriesTitle, SeriesOrder, SortOrder, Abbreviation) VALUES
  ('PP', 0, 0, 'ru', 'Патриархи и пророки', 'Э. Уайт', 'conflict-of-ages', 'Конфликт веков', 1, 1, 'ПП'),
  ('DA', 0, 0, 'ru', 'Желание веков', 'Э. Уайт', 'conflict-of-ages', 'Конфликт веков', 1, 3, 'ЖВ'),
  ('SC', 0, 0, 'ru', 'Путь ко Христу', 'Э. Уайт', '', '', 0, 0, ''),
  ('ohienko-uk', 1, 0, 'uk', 'Біблія (Огієнко)', '', '', '', 0, 0, ''),
  ('synodal-ru', 1, 0, 'ru', 'Библия (Синодальный)', '', '', '', 0, 0, ''),
  ('kjv-en', 1, 0, 'en', 'Bible (King James)', '', '', '', 0, 0, '');

INSERT INTO Chapters (ModuleId, ChapterOrder, ChapterTitle) VALUES
  ('PP', 2, 'Сотворение'),
  ('PP', 1, 'Почему был допущен грех'),
  ('PP', 3, 'Искушение и падение'),
  ('DA', 1, 'Бог с нами'),
  ('DA', 2, 'Избранный народ'),
  ('DA', 3, 'Полнота времени'),
  ('SC', 1, 'Любовь Божья к человеку'),
  ('SC', 2, 'Нужда грешника во Христе'),
  ('SC', 3, 'Покаяние');

-- PP 1: title, epigraph, a page-starting paragraph, one crossing pages 33 -> 34,
-- and a heading. Ids are not in LogicalIndex order.
INSERT INTO Paragraphs (Id, ModuleId, ChapterOrder, LogicalIndex, Kind, Text, StartPageNumber, PageBreakOffset, ParagraphOnPage) VALUES
  (13, 'PP', 1, 3, 6, 'Бог есть любовь. Его природа и закон есть любовь.', 33, -1, 1),
  (11, 'PP', 1, 1, 0, 'Почему был допущен грех', 33, -1, 0),
  (15, 'PP', 1, 5, 3, 'Восстание на небе', 34, -1, 0),
  (12, 'PP', 1, 2, 2, '«Бог есть любовь» (1 Иоанна 4:16).', 33, -1, 0),
  (14, 'PP', 1, 4, 6, 'Любовь — основа правления Божьего, и счастье всех существ зависит от этого.', 33, 20, 2),
  (21, 'PP', 2, 1, 0, 'Сотворение', 44, -1, 0),
  (22, 'PP', 2, 2, 6, 'Он принес себя в жертву ради нас.', 44, -1, 1),
  (31, 'PP', 3, 1, 0, 'Искушение и падение', 52, -1, 0),
  (32, 'PP', 3, 2, 6, 'Жертва Христа открыла путь спасения.', 52, -1, 1),
  (41, 'DA', 1, 1, 0, 'Бог с нами', 19, -1, 0),
  (42, 'DA', 1, 2, 6, 'Он стал жертвою за грех мира.', 19, -1, 1),
  (51, 'DA', 2, 1, 0, 'Избранный народ', 27, -1, 0),
  (61, 'DA', 3, 1, 0, 'Полнота времени', 31, -1, 0),
  (71, 'SC', 1, 1, 0, 'Любовь Божья к человеку', 0, -1, 0),
  (72, 'SC', 1, 2, 6, 'Природа и откровение свидетельствуют о любви Божьей.', 0, -1, 0),
  (81, 'SC', 2, 1, 0, 'Нужда грешника во Христе', 0, -1, 0),
  (91, 'SC', 3, 1, 0, 'Покаяние', 0, -1, 0);

INSERT INTO Spans (ParagraphId, StartOffset, Length, Kind) VALUES
  (14, 26, 7, 0),
  (13, 0, 3, 1),
  (13, 17, 11, 1);

INSERT INTO Books (ModuleId, BookCode, OrderInModule, DisplayTitle, Abbreviation, ChapterCount) VALUES
  ('ohienko-uk', 'PSA', 2, 'Псалми', 'Пс', 150),
  ('ohienko-uk', 'GEN', 1, 'Буття', 'Бут', 50),
  ('synodal-ru', 'GEN', 1, 'Бытие', 'Быт', 50),
  ('synodal-ru', 'PSA', 2, 'Псалтирь', 'Пс', 150),
  ('kjv-en', 'GEN', 1, 'Genesis', 'Gen', 50),
  ('kjv-en', 'PSA', 2, 'Psalms', 'Ps', 150);

INSERT INTO Verses (Id, ModuleId, BookCode, ChapterNumber, VerseNumber, Text) VALUES
  (103, 'ohienko-uk', 'GEN', 22, 8, 'І сказав Авраам: Бог Собі нагледить ягня на жертву, мій сину.'),
  (101, 'ohienko-uk', 'GEN', 1, 1, 'На початку Бог створив небо та землю.'),
  (102, 'ohienko-uk', 'GEN', 1, 2, 'А земля була пуста та порожня.'),
  (104, 'ohienko-uk', 'PSA', 51, 19, 'Жертви Богові — зламаний дух.'),
  (201, 'synodal-ru', 'GEN', 1, 1, 'В начале сотворил Бог небо и землю.'),
  (202, 'synodal-ru', 'PSA', 50, 19, 'Жертва Богу — дух сокрушенный.'),
  (301, 'kjv-en', 'GEN', 1, 1, 'In the beginning God created the heaven and the earth.'),
  (302, 'kjv-en', 'PSA', 51, 17, 'The sacrifices of God are a broken spirit.');

-- Build every full-text index, as the producer does at the end (B-08).
INSERT INTO ParagraphsFTS(ParagraphsFTS) VALUES('rebuild');
INSERT INTO VersesFTS(VersesFTS) VALUES('rebuild');
INSERT INTO ParagraphsStem_ru(ParagraphsStem_ru) VALUES('rebuild');
INSERT INTO VersesStem_uk(VersesStem_uk) VALUES('rebuild');
INSERT INTO VersesStem_ru(VersesStem_ru) VALUES('rebuild');
INSERT INTO VersesStem_en(VersesStem_en) VALUES('rebuild');
