unit Infra.Fts5SearchIndex.Tests;

{ Fts5SearchIndex (Slovo_02 "Пошукові запити", Slovo_03 Part C):
  - pure functions: TryBuildMatchQuery, ExtractHighlights;
  - on the fixture library: exact vs stemmed tables, ModuleIds, counts per
    chapter / Bible book over all matches, windows in text order and by
    relevance (B-34), FindInChapter / FindInBibleChapter offsets, fallback for
    a language without a stemmer. }

interface

uses
  DUnitX.TestFramework,
  Core.Domain,
  Core.Catalog,
  Core.Contracts,
  Infra.SQLite.LibraryDatabase,
  Slovo.TestSupport;

type
  [TestFixture]
  TMatchQueryTests = class
  public
    [Test] procedure EmptyOrBlank_IsNothingToSearch;
    [Test] procedure AllWords_QuotesEveryTerm;
    [Test] procedure SpecialCharactersAndQuotes_AreNeutralized;
    [Test] procedure ExactPhrase_IsOneQuotedPhrase;
    [Test] procedure Separators_NbspTabsNewlines;
    [Test] procedure Prefix_StarOnLastTerm;
    [Test] procedure ExtractHighlights_RemovesMarkersAndKeepsOffsets;
  end;

  [TestFixture]
  TFts5SearchIndexTests = class
  private
    FDir: string;
    FDatabase: TLibraryDatabase;
    FCatalog: TLibraryCatalog;
    FLogger: TTestLogger;
    FLoggerRef: IInterface;
    FIndex: ISearchIndex;
    function Q(const Text: string; WordForms: Boolean = False; ExactPhrase: Boolean = False;
      const ModuleIds: TArray<TModuleId> = nil): TSearchQuery;
    function W(Order: TSearchOrder; Offset: Integer = 0; Count: Integer = 50): TSearchWindow;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;

    [Test] procedure Book_Exact_FindsOnlyThatForm;
    [Test] procedure Book_WordForms_FindsOtherForms;
    [Test] procedure Book_ModuleIds_LimitScope;
    [Test] procedure Book_ModuleIdsOfOtherKindOnly_QueriesNothing;
    [Test] procedure Book_TextOrder_IsChapterThenParagraph;
    [Test] procedure Book_Windows_CoverAllRowsOnce;
    [Test] procedure Book_Window_WithoutModules_IsInvalid;
    [Test] procedure Book_EmptyText_IsEmptySuccess;
    [Test] procedure Book_SpecialCharacters_DoNotBreakQuery;
    [Test] procedure CountBook_PerChapter_OverAllMatches;
    [Test] procedure CountBook_ModuleIds_LimitScope;
    [Test] procedure CountBible_PerBook_AllLanguages;
    [Test] procedure Bible_Window_OverTwoLanguages_IsInvalid;
    [Test] procedure Bible_TextOrder_IsBookOrderNotCode;
    [Test] procedure Bible_WordForms_English;
    [Test] procedure Bible_ExactPhraseWithWordForms;
    [Test] procedure FindInChapter_Exact_OffsetsPointAtWords;
    [Test] procedure FindInChapter_WordForms;
    [Test] procedure FindInChapter_UnknownModule_IsNotFound;
    [Test] procedure FindInBibleChapter_WordForms;
    [Test] procedure LanguageWithoutStemmer_FallsBackToExact;
    [Test] procedure IdsOutOfTextOrder_EverySearchIsCorrupted;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Infra.SQLite.LibraryReader,
  Infra.Search.Fts5SearchIndex;

function HighlightedText(const Text: string; const H: TSearchHighlight): string;
begin
  Result := Copy(Text, H.StartOffset + 1, H.Len);
end;

{ TMatchQueryTests }

procedure TMatchQueryTests.EmptyOrBlank_IsNothingToSearch;
var
  M: string;
begin
  Assert.IsFalse(TryBuildMatchQuery('', mmAllWords, M));
  Assert.IsFalse(TryBuildMatchQuery('   ', mmAllWords, M));
  Assert.IsFalse(TryBuildMatchQuery(#$00A0#9#13#10, mmExactPhrase, M));
  Assert.AreEqual('', M);
end;

procedure TMatchQueryTests.AllWords_QuotesEveryTerm;
var
  M: string;
begin
  Assert.IsTrue(TryBuildMatchQuery('  благодать   спасіння ', mmAllWords, M));
  Assert.AreEqual('"благодать" "спасіння"', M);
end;

procedure TMatchQueryTests.SpecialCharactersAndQuotes_AreNeutralized;
var
  M: string;
begin
  Assert.IsTrue(TryBuildMatchQuery('благодать (спасіння', mmAllWords, M));
  Assert.AreEqual('"благодать" "(спасіння"', M);
  Assert.IsTrue(TryBuildMatchQuery('a"b NOT c*', mmAllWords, M));
  Assert.AreEqual('"a""b" "NOT" "c*"', M);
end;

procedure TMatchQueryTests.ExactPhrase_IsOneQuotedPhrase;
var
  M: string;
begin
  Assert.IsTrue(TryBuildMatchQuery('через  Його благодать', mmExactPhrase, M));
  Assert.AreEqual('"через Його благодать"', M);
end;

procedure TMatchQueryTests.Separators_NbspTabsNewlines;
var
  M: string;
begin
  Assert.IsTrue(TryBuildMatchQuery(#$00A0'жертва'#9'Богові'#13#10, mmAllWords, M));
  Assert.AreEqual('"жертва" "Богові"', M);
end;

procedure TMatchQueryTests.Prefix_StarOnLastTerm;
var
  M: string;
begin
  Assert.IsTrue(TryBuildMatchQuery('жертва Бог', mmPrefix, M));
  Assert.AreEqual('"жертва" "Бог"*', M);
end;

procedure TMatchQueryTests.ExtractHighlights_RemovesMarkersAndKeepsOffsets;
var
  Clean: string;
  H: TArray<TSearchHighlight>;
begin
  H := ExtractHighlights('Он принес себя в '#2'жертву'#3' ради '#2'нас'#3'.', Clean);
  Assert.AreEqual('Он принес себя в жертву ради нас.', Clean);
  Assert.AreEqual(2, Integer(Length(H)));
  Assert.AreEqual('жертву', HighlightedText(Clean, H[0]));
  Assert.AreEqual('нас', HighlightedText(Clean, H[1]));
  H := ExtractHighlights('без збігів', Clean);
  Assert.AreEqual(0, Integer(Length(H)));
  Assert.AreEqual('без збігів', Clean);
end;

{ TFts5SearchIndexTests }

procedure TFts5SearchIndexTests.SetupFixture;
var
  Error: TResultError;
  Lib: ILibrary;
begin
  FDir := NewTempDir;
  FLogger := TTestLogger.Create;
  FLoggerRef := FLogger;
  FDatabase := TLibraryDatabase.Create(FLogger);
  if not FDatabase.Open(BuildTestLibrary(TPath.Combine(FDir, 'library.db')), Error) then
    raise Exception.Create('Test library did not open');
  Lib := TLibrary.Create(FDatabase, FLogger);
  FCatalog := Lib.LoadCatalog;
  FIndex := TFts5SearchIndex.Create(FDatabase, FCatalog, FLogger);
end;

procedure TFts5SearchIndexTests.TearDownFixture;
begin
  FIndex := nil;
  FCatalog.Free;
  FDatabase.Free;
  try
    TDirectory.Delete(FDir, True);
  except
  end;
end;

function TFts5SearchIndexTests.Q(const Text: string; WordForms, ExactPhrase: Boolean;
  const ModuleIds: TArray<TModuleId>): TSearchQuery;
begin
  Result := Default(TSearchQuery);
  Result.Text := Text;
  Result.WordForms := WordForms;
  Result.ExactPhrase := ExactPhrase;
  Result.ModuleIds := ModuleIds;
end;

function TFts5SearchIndexTests.W(Order: TSearchOrder; Offset, Count: Integer): TSearchWindow;
begin
  Result.Order := Order;
  Result.Offset := Offset;
  Result.Count := Count;
end;

procedure TFts5SearchIndexTests.Book_Exact_FindsOnlyThatForm;
var
  R: TResult<TArray<TBookSearchResult>>;
  Item: TBookSearchResult;
begin
  R := FIndex.SearchBook(Q('жертва', False, False, ['PP', 'DA', 'SC']), W(soRelevance));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(1, Integer(Length(R.Value)));
  Item := R.Value[0];
  Assert.AreEqual('PP', string(Item.Ref.Chapter.ModuleId));
  Assert.AreEqual(3, Item.Ref.Chapter.ChapterOrder);
  Assert.AreEqual(2, Item.Ref.LogicalIndex);
  Assert.AreEqual(52, Item.PageNumber);       // B-23
  Assert.AreEqual(1, Item.ParagraphOnPage);
  Assert.AreEqual(1, Integer(Length(Item.Highlights)));
  Assert.AreEqual('Жертва', HighlightedText(Item.Snippet, Item.Highlights[0]));
  Assert.IsFalse(Item.Snippet.Contains(#2), 'markers must be removed');
end;

procedure TFts5SearchIndexTests.Book_WordForms_FindsOtherForms;
var
  R: TResult<TArray<TBookSearchResult>>;
  Words: string;
  Item: TBookSearchResult;
begin
  R := FIndex.SearchBook(Q('жертва', True, False, ['PP', 'DA', 'SC']), W(soRelevance));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(3, Integer(Length(R.Value)));
  Words := '';
  for Item in R.Value do
    Words := Words + '|' + HighlightedText(Item.Snippet, Item.Highlights[0]).ToLower;
  Assert.IsTrue(Words.Contains('|жертву'), Words);
  Assert.IsTrue(Words.Contains('|жертва'), Words);
  Assert.IsTrue(Words.Contains('|жертвою'), Words);
end;

procedure TFts5SearchIndexTests.Book_ModuleIds_LimitScope;
var
  R: TResult<TArray<TBookSearchResult>>;
begin
  R := FIndex.SearchBook(Q('жертва', True, False, ['DA']), W(soText));
  Assert.AreEqual(1, Integer(Length(R.Value)));
  Assert.AreEqual('DA', string(R.Value[0].Ref.Chapter.ModuleId));

  R := FIndex.SearchBook(Q('жертва', False, False, ['DA', 'SC']), W(soText));
  Assert.AreEqual(0, Integer(Length(R.Value)));
end;

procedure TFts5SearchIndexTests.Book_ModuleIdsOfOtherKindOnly_QueriesNothing;
var
  R: TResult<TArray<TBookSearchResult>>;
begin
  // R4-01: a scope with no books is nothing to search in - not an error.
  R := FIndex.SearchBook(Q('жертва', True, False, ['ohienko-uk']), W(soRelevance));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(0, Integer(Length(R.Value)));
  Assert.AreEqual(0, Integer(Length(FIndex.CountBook(Q('жертва', True, False, ['ohienko-uk'])).Value)));
end;

procedure TFts5SearchIndexTests.Book_TextOrder_IsChapterThenParagraph;
var
  R: TResult<TArray<TBookSearchResult>>;
begin
  // «любовь» in PP: chapter 1 - the epigraph (2), paragraphs 3 and 4.
  R := FIndex.SearchBook(Q('любовь', False, False, ['PP']), W(soText));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(3, Integer(Length(R.Value)));
  Assert.AreEqual(2, R.Value[0].Ref.LogicalIndex);
  Assert.AreEqual(3, R.Value[1].Ref.LogicalIndex);
  Assert.AreEqual(4, R.Value[2].Ref.LogicalIndex);

  // With word forms: PP chapter 2, then chapter 3.
  R := FIndex.SearchBook(Q('жертва', True, False, ['PP']), W(soText));
  Assert.AreEqual(2, Integer(Length(R.Value)));
  Assert.AreEqual(2, R.Value[0].Ref.Chapter.ChapterOrder);
  Assert.AreEqual(3, R.Value[1].Ref.Chapter.ChapterOrder);
end;

procedure TFts5SearchIndexTests.Book_Windows_CoverAllRowsOnce;
var
  Order: TSearchOrder;
  Seen: string;
  Offset: Integer;
  R: TResult<TArray<TBookSearchResult>>;
  Key: string;
begin
  // Three matches read one row at a time: no row twice, none skipped, then nothing.
  for Order := Low(TSearchOrder) to High(TSearchOrder) do
  begin
    Seen := '';
    for Offset := 0 to 2 do
    begin
      R := FIndex.SearchBook(Q('жертва', True, False, ['PP', 'DA']), W(Order, Offset, 1));
      Assert.IsTrue(R.IsSuccess);
      Assert.AreEqual(1, Integer(Length(R.Value)));
      Key := Format('|%s:%d', [string(R.Value[0].Ref.Chapter.ModuleId), R.Value[0].Ref.Chapter.ChapterOrder]);
      Assert.IsFalse(Seen.Contains(Key), 'twice: ' + Key);
      Seen := Seen + Key;
    end;
    R := FIndex.SearchBook(Q('жертва', True, False, ['PP', 'DA']), W(Order, 3, 1));
    Assert.AreEqual(0, Integer(Length(R.Value)));
    R := FIndex.SearchBook(Q('жертва', True, False, ['PP', 'DA']), W(Order, 0, 0));
    Assert.IsTrue(R.IsSuccess);
    Assert.AreEqual(0, Integer(Length(R.Value)), 'Count 0 is an empty answer');
  end;
end;

procedure TFts5SearchIndexTests.Book_Window_WithoutModules_IsInvalid;
begin
  // B-34: a window names its modules; "the whole library" is for counting only.
  Assert.IsTrue(FIndex.SearchBook(Q('жертва'), W(soRelevance)).Error = reInvalidQuery);
  Assert.IsTrue(FIndex.SearchBook(Q('жертва', False, False, ['PP']), W(soText, -1)).Error = reInvalidQuery);
end;

procedure TFts5SearchIndexTests.Book_EmptyText_IsEmptySuccess;
var
  R: TResult<TArray<TBookSearchResult>>;
begin
  R := FIndex.SearchBook(Q(#$00A0'  ', False, False, ['PP']), W(soText));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(0, Integer(Length(R.Value)));
  Assert.IsTrue(FIndex.CountBook(Q(#$00A0'  ')).IsSuccess);
  Assert.AreEqual(0, Integer(Length(FIndex.CountBook(Q(#$00A0'  ')).Value)));
end;

procedure TFts5SearchIndexTests.Book_SpecialCharacters_DoNotBreakQuery;
begin
  Assert.IsTrue(FIndex.CountBook(Q('(жертва AND "*:')).IsSuccess,
    'sanitized query must not be an FTS5 syntax error');
  Assert.IsTrue(FIndex.SearchBook(Q('(жертва AND "*:', False, False, ['PP']), W(soRelevance)).IsSuccess);
end;

procedure TFts5SearchIndexTests.CountBook_PerChapter_OverAllMatches;
var
  R: TResult<TArray<TBookHitCount>>;
  C: TBookHitCount;
  Seen: string;
begin
  // Exact «любовь», the whole library: PP chapter 1 - three paragraphs, SC chapter 1 - its title.
  R := FIndex.CountBook(Q('любовь'));
  Assert.IsTrue(R.IsSuccess);
  Seen := '';
  for C in R.Value do
    Seen := Seen + Format('|%s:%d=%d', [string(C.ModuleId), C.ChapterOrder, C.Count]);
  Assert.AreEqual('|PP:1=3|SC:1=1', Seen);

  // Word forms «жертва»: within a module by chapter.
  R := FIndex.CountBook(Q('жертва', True));
  Seen := '';
  for C in R.Value do
    Seen := Seen + Format('|%s:%d=%d', [string(C.ModuleId), C.ChapterOrder, C.Count]);
  Assert.AreEqual('|DA:1=1|PP:2=1|PP:3=1', Seen);
end;

procedure TFts5SearchIndexTests.CountBook_ModuleIds_LimitScope;
var
  R: TResult<TArray<TBookHitCount>>;
begin
  R := FIndex.CountBook(Q('жертва', True, False, ['DA', 'SC']));
  Assert.AreEqual(1, Integer(Length(R.Value)));
  Assert.AreEqual('DA', string(R.Value[0].ModuleId));
  Assert.AreEqual(1, R.Value[0].Count);
end;

procedure TFts5SearchIndexTests.CountBible_PerBook_AllLanguages;
var
  R: TResult<TArray<TBibleHitCount>>;
  C: TBibleHitCount;
  Seen: string;
begin
  // uk: GEN 22:8 «жертву», PSA 51:19 «Жертви»; ru: PSA 50:19 «Жертва» - one array for
  // all language tables, the uk group first (B-31), books in OrderInModule.
  R := FIndex.CountBible(Q('жертва', True));
  Assert.IsTrue(R.IsSuccess);
  Seen := '';
  for C in R.Value do
    Seen := Seen + Format('|%s:%s=%d', [string(C.ModuleId), string(C.BookCode), C.Count]);
  Assert.AreEqual('|ohienko-uk:GEN=1|ohienko-uk:PSA=1|synodal-ru:PSA=1', Seen);
end;

procedure TFts5SearchIndexTests.Bible_Window_OverTwoLanguages_IsInvalid;
begin
  // Ranks of VersesStem_uk and VersesStem_ru are not comparable: one window - one table.
  Assert.IsTrue(FIndex.SearchBible(Q('жертва', True, False, ['ohienko-uk', 'synodal-ru']),
    W(soRelevance)).Error = reInvalidQuery);
  // The exact table is one for all languages.
  Assert.IsTrue(FIndex.SearchBible(Q('Бог', False, False, ['ohienko-uk', 'synodal-ru']),
    W(soRelevance)).IsSuccess);
end;

procedure TFts5SearchIndexTests.Bible_TextOrder_IsBookOrderNotCode;
var
  R: TResult<TArray<TBibleSearchResult>>;
begin
  // GEN (OrderInModule 1) before PSA (2), whatever the rowids and ranks are.
  R := FIndex.SearchBible(Q('жертва', True, False, ['ohienko-uk']), W(soText));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(2, Integer(Length(R.Value)));
  Assert.AreEqual('GEN', string(R.Value[0].Ref.Chapter.Book.BookCode));
  Assert.AreEqual(22, R.Value[0].Ref.Chapter.ChapterNumber);
  Assert.AreEqual(8, R.Value[0].Ref.VerseNumber);
  Assert.AreEqual('PSA', string(R.Value[1].Ref.Chapter.Book.BookCode));
end;

procedure TFts5SearchIndexTests.Bible_WordForms_English;
var
  R: TResult<TArray<TBibleSearchResult>>;
begin
  Assert.AreEqual(0, Integer(Length(FIndex.SearchBible(Q('sacrifice', False, False, ['kjv-en']),
    W(soRelevance)).Value)));
  R := FIndex.SearchBible(Q('sacrifice', True, False, ['kjv-en']), W(soRelevance));
  Assert.AreEqual(1, Integer(Length(R.Value)));
  Assert.AreEqual('kjv-en', string(R.Value[0].Ref.Chapter.Book.ModuleId));
  Assert.AreEqual('sacrifices', HighlightedText(R.Value[0].Snippet, R.Value[0].Highlights[0]));
end;

procedure TFts5SearchIndexTests.Bible_ExactPhraseWithWordForms;
var
  R: TResult<TArray<TBibleSearchResult>>;
begin
  R := FIndex.SearchBible(Q('жертва Богові', True, True, ['ohienko-uk']), W(soRelevance));
  Assert.AreEqual(1, Integer(Length(R.Value)));
  Assert.AreEqual('PSA', string(R.Value[0].Ref.Chapter.Book.BookCode));
  // A phrase is highlighted as one range.
  Assert.AreEqual(1, Integer(Length(R.Value[0].Highlights)));
  Assert.AreEqual('Жертви Богові', HighlightedText(R.Value[0].Snippet, R.Value[0].Highlights[0]));

  // Without word forms the exact phrase «жертва Богові» does not exist.
  R := FIndex.SearchBible(Q('жертва Богові', False, True, ['ohienko-uk']), W(soRelevance));
  Assert.AreEqual(0, Integer(Length(R.Value)));
end;

procedure TFts5SearchIndexTests.FindInChapter_Exact_OffsetsPointAtWords;
var
  R: TResult<TArray<TParagraphHit>>;
  Content: TResult<TChapterContent>;
  Ref: TChapterRef;
  Lib: ILibrary;
  Text: string;
  H: TSearchHighlight;
begin
  Ref.ModuleId := 'PP';
  Ref.ChapterOrder := 1;
  R := FIndex.FindInChapter(Q('любовь'), Ref);
  Assert.IsTrue(R.IsSuccess);
  // epigraph (2), paragraph 3 (twice), paragraph 4 - in chapter order
  Assert.AreEqual(3, Integer(Length(R.Value)));
  Assert.AreEqual(2, R.Value[0].LogicalIndex);
  Assert.AreEqual(3, R.Value[1].LogicalIndex);
  Assert.AreEqual(4, R.Value[2].LogicalIndex);
  Assert.AreEqual(2, Integer(Length(R.Value[1].Highlights)));

  // Offsets are positions in Paragraphs.Text (B-24, E-08).
  Lib := TLibrary.Create(FDatabase, FLogger);
  Content := Lib.GetChapterContent(Ref);
  Text := Content.Value.Paragraphs[2].Text;      // LogicalIndex 3
  for H in R.Value[1].Highlights do
    Assert.AreEqual('любовь', HighlightedText(Text, H).ToLower);
  Text := Content.Value.Paragraphs[3].Text;      // LogicalIndex 4
  Assert.AreEqual('Любовь', HighlightedText(Text, R.Value[2].Highlights[0]));
end;

procedure TFts5SearchIndexTests.FindInChapter_WordForms;
var
  R: TResult<TArray<TParagraphHit>>;
  Ref: TChapterRef;
begin
  Ref.ModuleId := 'PP';
  Ref.ChapterOrder := 2;
  Assert.AreEqual(0, Integer(Length(FIndex.FindInChapter(Q('жертва'), Ref).Value)));
  R := FIndex.FindInChapter(Q('жертва', True), Ref);
  Assert.AreEqual(1, Integer(Length(R.Value)));
  Assert.AreEqual(2, R.Value[0].LogicalIndex);
  Assert.AreEqual('жертву', HighlightedText('Он принес себя в жертву ради нас.', R.Value[0].Highlights[0]));
end;

procedure TFts5SearchIndexTests.FindInChapter_UnknownModule_IsNotFound;
var
  Ref: TChapterRef;
begin
  Ref.ModuleId := 'NOPE';
  Ref.ChapterOrder := 1;
  Assert.IsTrue(FIndex.FindInChapter(Q('любовь'), Ref).Error = reNotFound);
end;

procedure TFts5SearchIndexTests.FindInBibleChapter_WordForms;
var
  R: TResult<TArray<TVerseHit>>;
  Ref: TBibleChapterRef;
begin
  Ref.Book.ModuleId := 'ohienko-uk';
  Ref.Book.BookCode := 'GEN';
  Ref.ChapterNumber := 22;
  R := FIndex.FindInBibleChapter(Q('жертва', True), Ref);
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(1, Integer(Length(R.Value)));
  Assert.AreEqual(8, R.Value[0].VerseNumber);
  Assert.AreEqual('жертву', HighlightedText(
    'І сказав Авраам: Бог Собі нагледить ягня на жертву, мій сину.', R.Value[0].Highlights[0]));
end;

// R8-03: the rowid is the address, so a library whose ids are not in text order
// cannot be searched - and says so, instead of answering in a wrong order.
procedure TFts5SearchIndexTests.IdsOutOfTextOrder_EverySearchIsCorrupted;
var
  FileName: string;
  Db: TLibraryDatabase;
  Catalog: TLibraryCatalog;
  Index: ISearchIndex;
  Logger: TTestLogger;
  LoggerRef: IInterface;
  Error: TResultError;
  Ref: TChapterRef;
begin
  // PP chapter 1: its first row (Id 11) becomes the last paragraph of the chapter.
  FileName := BuildTestLibrary(TPath.Combine(FDir, 'disorder.db'));
  ExecOnLibrary(FileName, 'UPDATE Paragraphs SET LogicalIndex = 9 WHERE Id = 11;');

  Logger := TTestLogger.Create;
  LoggerRef := Logger;
  Db := TLibraryDatabase.Create(Logger);
  try
    Assert.IsTrue(Db.Open(FileName, Error));
    Catalog := TLibrary.Create(Db, Logger).LoadCatalog;
    try
      Index := TFts5SearchIndex.Create(Db, Catalog, Logger);
      Assert.AreEqual(Ord(reModuleCorrupted), Ord(Index.CountBook(Q('любовь')).Error));
      Assert.IsTrue(Logger.Contains('not in text order'));
      Assert.AreEqual(Ord(reModuleCorrupted),
        Ord(Index.SearchBible(Q('Бог', False, False, ['synodal-ru']), W(soText)).Error));
      Ref.ModuleId := 'DA';
      Ref.ChapterOrder := 1;
      Assert.IsFalse(Index.FindInChapter(Q('жертвою'), Ref).IsSuccess);
      Index := nil;
    finally
      Catalog.Free;
    end;
  finally
    Db.Free;
  end;
end;

procedure TFts5SearchIndexTests.LanguageWithoutStemmer_FallsBackToExact;
var
  FileName: string;
  Db: TLibraryDatabase;
  Catalog: TLibraryCatalog;
  Index: ISearchIndex;
  Logger: TTestLogger;
  LoggerRef: IInterface;
  Error: TResultError;
  R: TResult<TArray<TBibleSearchResult>>;
begin
  // A German translation: there is no VersesStem_de table.
  FileName := BuildTestLibrary(TPath.Combine(FDir, 'with-de.db'));
  ExecOnLibrary(FileName,
    'INSERT INTO Modules (ModuleId, Kind, Category, Language, Title, Author) ' +
    'VALUES (''luther-de'', 1, 0, ''de'', ''Luther'', '''');' +
    'INSERT INTO Books (ModuleId, BookCode, OrderInModule, DisplayTitle, ChapterCount) ' +
    'VALUES (''luther-de'', ''PSA'', 1, ''Psalmen'', 150);' +
    'INSERT INTO Verses (Id, ModuleId, BookCode, ChapterNumber, VerseNumber, Text) ' +
    'VALUES (401, ''luther-de'', ''PSA'', 51, 19, ''Die Opfer, die Gott gefallen, sind ein geängsteter Geist.'');' +
    'INSERT INTO VersesFTS(VersesFTS) VALUES(''rebuild'');');

  Logger := TTestLogger.Create;
  LoggerRef := Logger;
  Db := TLibraryDatabase.Create(Logger);
  try
    Assert.IsTrue(Db.Open(FileName, Error));
    Catalog := TLibrary.Create(Db, Logger).LoadCatalog;
    try
      Index := TFts5SearchIndex.Create(Db, Catalog, Logger);
      R := Index.SearchBible(Q('Opfer', True, False, ['luther-de']), W(soRelevance));
      Assert.IsTrue(R.IsSuccess);
      Assert.AreEqual(1, Integer(Length(R.Value)));
      Assert.IsTrue(Logger.Contains('VersesStem_de'));

      // Logged once per session, not on every search.
      Index.SearchBible(Q('Gott', True, False, ['luther-de']), W(soRelevance));
      Assert.AreEqual(1, Logger.Count);
      Index := nil;
    finally
      Catalog.Free;
    end;
  finally
    Db.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMatchQueryTests);
  TDUnitX.RegisterTestFixture(TFts5SearchIndexTests);

end.
