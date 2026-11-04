unit Infra.Fts5SearchIndex.Tests;

{ Fts5SearchIndex (Slovo_02 "Пошукові запити", Slovo_03 Part C):
  - pure functions: TryBuildMatchQuery, ExtractHighlights;
  - on the fixture library: exact vs stemmed tables, ModuleIds, LIMIT N+1 ->
    Truncated, language groups in the order uk, ru, en, FindInChapter /
    FindInBibleChapter offsets, fallback for a language without a stemmer. }

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
      const ModuleIds: TArray<TModuleId> = nil; MaxResults: Integer = 0): TSearchQuery;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;

    [Test] procedure Book_Exact_FindsOnlyThatForm;
    [Test] procedure Book_WordForms_FindsOtherForms;
    [Test] procedure Book_ModuleIds_LimitScope;
    [Test] procedure Book_ModuleIdsOfOtherKindOnly_QueriesNothing;
    [Test] procedure Book_MaxResults_SetsTruncated;
    [Test] procedure Book_EmptyText_IsEmptySuccess;
    [Test] procedure Book_SpecialCharacters_DoNotBreakQuery;
    [Test] procedure Bible_WordForms_GroupsByLanguage_UkFirst;
    [Test] procedure Bible_WordForms_English;
    [Test] procedure Bible_ExactPhraseWithWordForms;
    [Test] procedure FindInChapter_Exact_OffsetsPointAtWords;
    [Test] procedure FindInChapter_WordForms;
    [Test] procedure FindInChapter_UnknownModule_IsNotFound;
    [Test] procedure FindInBibleChapter_WordForms;
    [Test] procedure LanguageWithoutStemmer_FallsBackToExact;
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
  const ModuleIds: TArray<TModuleId>; MaxResults: Integer): TSearchQuery;
begin
  Result := Default(TSearchQuery);
  Result.Text := Text;
  Result.WordForms := WordForms;
  Result.ExactPhrase := ExactPhrase;
  Result.ModuleIds := ModuleIds;
  Result.MaxResults := MaxResults;
end;

procedure TFts5SearchIndexTests.Book_Exact_FindsOnlyThatForm;
var
  R: TResult<TSearchPage<TBookSearchResult>>;
  Item: TBookSearchResult;
begin
  R := FIndex.SearchBook(Q('жертва'));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(1, Integer(Length(R.Value.Items)));
  Item := R.Value.Items[0];
  Assert.AreEqual('PP', string(Item.Ref.Chapter.ModuleId));
  Assert.AreEqual(3, Item.Ref.Chapter.ChapterOrder);
  Assert.AreEqual(2, Item.Ref.LogicalIndex);
  Assert.AreEqual(52, Item.PageNumber);       // B-23
  Assert.AreEqual(1, Item.ParagraphOnPage);
  Assert.AreEqual(1, Integer(Length(Item.Highlights)));
  Assert.AreEqual('Жертва', HighlightedText(Item.Snippet, Item.Highlights[0]));
  Assert.IsFalse(Item.Snippet.Contains(#2), 'markers must be removed');
  Assert.IsFalse(R.Value.Truncated);
end;

procedure TFts5SearchIndexTests.Book_WordForms_FindsOtherForms;
var
  R: TResult<TSearchPage<TBookSearchResult>>;
  Words: string;
  Item: TBookSearchResult;
begin
  R := FIndex.SearchBook(Q('жертва', True));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(3, Integer(Length(R.Value.Items)));
  Words := '';
  for Item in R.Value.Items do
    Words := Words + '|' + HighlightedText(Item.Snippet, Item.Highlights[0]).ToLower;
  Assert.IsTrue(Words.Contains('|жертву'), Words);
  Assert.IsTrue(Words.Contains('|жертва'), Words);
  Assert.IsTrue(Words.Contains('|жертвою'), Words);
end;

procedure TFts5SearchIndexTests.Book_ModuleIds_LimitScope;
var
  R: TResult<TSearchPage<TBookSearchResult>>;
begin
  R := FIndex.SearchBook(Q('жертва', True, False, ['DA']));
  Assert.AreEqual(1, Integer(Length(R.Value.Items)));
  Assert.AreEqual('DA', string(R.Value.Items[0].Ref.Chapter.ModuleId));

  R := FIndex.SearchBook(Q('жертва', False, False, ['DA', 'SC']));
  Assert.AreEqual(0, Integer(Length(R.Value.Items)));
end;

procedure TFts5SearchIndexTests.Book_ModuleIdsOfOtherKindOnly_QueriesNothing;
var
  R: TResult<TSearchPage<TBookSearchResult>>;
begin
  // R4-01: a non-empty scope with no books must not turn into "the whole library".
  R := FIndex.SearchBook(Q('жертва', True, False, ['ohienko-uk']));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(0, Integer(Length(R.Value.Items)));
end;

procedure TFts5SearchIndexTests.Book_MaxResults_SetsTruncated;
var
  R: TResult<TSearchPage<TBookSearchResult>>;
begin
  R := FIndex.SearchBook(Q('жертва', True, False, nil, 2));
  Assert.AreEqual(2, Integer(Length(R.Value.Items)));
  Assert.IsTrue(R.Value.Truncated);

  R := FIndex.SearchBook(Q('жертва', True, False, nil, 3));
  Assert.AreEqual(3, Integer(Length(R.Value.Items)));
  Assert.IsFalse(R.Value.Truncated);
end;

procedure TFts5SearchIndexTests.Book_EmptyText_IsEmptySuccess;
var
  R: TResult<TSearchPage<TBookSearchResult>>;
begin
  R := FIndex.SearchBook(Q(#$00A0'  '));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(0, Integer(Length(R.Value.Items)));
end;

procedure TFts5SearchIndexTests.Book_SpecialCharacters_DoNotBreakQuery;
var
  R: TResult<TSearchPage<TBookSearchResult>>;
begin
  R := FIndex.SearchBook(Q('(жертва AND "*:'));
  Assert.IsTrue(R.IsSuccess, 'sanitized query must not be an FTS5 syntax error');
end;

procedure TFts5SearchIndexTests.Bible_WordForms_GroupsByLanguage_UkFirst;
var
  R: TResult<TSearchPage<TBibleSearchResult>>;
  Items: TArray<TBibleSearchResult>;
begin
  R := FIndex.SearchBible(Q('жертва', True));
  Assert.IsTrue(R.IsSuccess);
  Items := R.Value.Items;
  // uk: GEN 22:8 «жертву», PSA 51:19 «Жертви»; ru: PSA 50:19 «Жертва» - uk group first (B-31).
  Assert.AreEqual(3, Integer(Length(Items)));
  Assert.AreEqual('ohienko-uk', string(Items[0].Ref.Chapter.Book.ModuleId));
  Assert.AreEqual('ohienko-uk', string(Items[1].Ref.Chapter.Book.ModuleId));
  Assert.AreEqual('synodal-ru', string(Items[2].Ref.Chapter.Book.ModuleId));
  Assert.AreEqual(50, Items[2].Ref.Chapter.ChapterNumber);
  Assert.AreEqual(19, Items[2].Ref.VerseNumber);
end;

procedure TFts5SearchIndexTests.Bible_WordForms_English;
var
  R: TResult<TSearchPage<TBibleSearchResult>>;
begin
  Assert.AreEqual(0, Integer(Length(FIndex.SearchBible(Q('sacrifice')).Value.Items)));
  R := FIndex.SearchBible(Q('sacrifice', True));
  Assert.AreEqual(1, Integer(Length(R.Value.Items)));
  Assert.AreEqual('kjv-en', string(R.Value.Items[0].Ref.Chapter.Book.ModuleId));
  Assert.AreEqual('sacrifices', HighlightedText(R.Value.Items[0].Snippet, R.Value.Items[0].Highlights[0]));
end;

procedure TFts5SearchIndexTests.Bible_ExactPhraseWithWordForms;
var
  R: TResult<TSearchPage<TBibleSearchResult>>;
begin
  R := FIndex.SearchBible(Q('жертва Богові', True, True, ['ohienko-uk']));
  Assert.AreEqual(1, Integer(Length(R.Value.Items)));
  Assert.AreEqual('PSA', string(R.Value.Items[0].Ref.Chapter.Book.BookCode));
  // A phrase is highlighted as one range.
  Assert.AreEqual(1, Integer(Length(R.Value.Items[0].Highlights)));
  Assert.AreEqual('Жертви Богові', HighlightedText(R.Value.Items[0].Snippet, R.Value.Items[0].Highlights[0]));

  // Without word forms the exact phrase «жертва Богові» does not exist.
  R := FIndex.SearchBible(Q('жертва Богові', False, True, ['ohienko-uk']));
  Assert.AreEqual(0, Integer(Length(R.Value.Items)));
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

procedure TFts5SearchIndexTests.LanguageWithoutStemmer_FallsBackToExact;
var
  FileName: string;
  Db: TLibraryDatabase;
  Catalog: TLibraryCatalog;
  Index: ISearchIndex;
  Logger: TTestLogger;
  LoggerRef: IInterface;
  Error: TResultError;
  R: TResult<TSearchPage<TBibleSearchResult>>;
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
      R := Index.SearchBible(Q('Opfer', True, False, ['luther-de']));
      Assert.IsTrue(R.IsSuccess);
      Assert.AreEqual(1, Integer(Length(R.Value.Items)));
      Assert.IsTrue(Logger.Contains('VersesStem_de'));

      // Logged once per session, not on every search.
      Index.SearchBible(Q('Gott', True, False, ['luther-de']));
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
