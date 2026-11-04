unit Infra.LibraryReader.Tests;

{ TLibrary (ILibrary) on the fixture library: LoadCatalog, chapter content with
  ORDER BY, page fields and inline spans, Bible chapters, not-found answers. }

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
  TLibraryTests = class
  private
    FDir: string;
    FDatabase: TLibraryDatabase;
    FLogger: TTestLogger;
    FLoggerRef: IInterface;
    FLibrary: ILibrary;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;

    [Test] procedure LoadCatalog_ReadsModulesWithSeriesAndCounts;
    [Test] procedure LoadCatalog_ReadsChaptersAndBooks;
    [Test] procedure GetChapterContent_OrderedWithPagesAndSpans;
    [Test] procedure GetChapterContent_UnknownChapter_IsNotFound;
    [Test] procedure GetBibleChapter_OrderedVerses;
    [Test] procedure GetBibleChapter_UnknownChapter_IsNotFound;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Infra.SQLite.LibraryReader;

function ChapterRef(const ModuleId: string; Order: Integer): TChapterRef;
begin
  Result.ModuleId := ModuleId;
  Result.ChapterOrder := Order;
end;

function BibleRef(const ModuleId, Code: string; Chapter: Integer): TBibleChapterRef;
begin
  Result.Book.ModuleId := ModuleId;
  Result.Book.BookCode := Code;
  Result.ChapterNumber := Chapter;
end;

procedure TLibraryTests.SetupFixture;
var
  Error: TResultError;
begin
  FDir := NewTempDir;
  FLogger := TTestLogger.Create;
  FLoggerRef := FLogger;
  FDatabase := TLibraryDatabase.Create(FLogger);
  if not FDatabase.Open(BuildTestLibrary(TPath.Combine(FDir, 'library.db')), Error) then
    raise Exception.Create('Test library did not open');
  FLibrary := TLibrary.Create(FDatabase, FLogger);
end;

procedure TLibraryTests.TearDownFixture;
begin
  FLibrary := nil;
  FDatabase.Free;
  try
    TDirectory.Delete(FDir, True);
  except
  end;
end;

procedure TLibraryTests.LoadCatalog_ReadsModulesWithSeriesAndCounts;
var
  Catalog: TLibraryCatalog;
  M: TModule;
begin
  Catalog := FLibrary.LoadCatalog;
  try
    Assert.AreEqual(6, Integer(Length(Catalog.Modules)));

    Assert.IsTrue(Catalog.FindModule('DA', M));
    Assert.IsTrue(M.Kind = ckBook);
    Assert.IsTrue(M.Category = bcSpiritOfProphecy);
    Assert.AreEqual('ru', M.Language);
    Assert.AreEqual('Желание веков', M.Title);
    Assert.AreEqual('conflict-of-ages', M.Series);
    Assert.AreEqual('Конфликт веков', M.SeriesTitle);
    Assert.AreEqual(1, M.SeriesOrder);
    Assert.AreEqual(3, M.SortOrder);
    Assert.AreEqual(3, M.ChildCount);

    Assert.IsTrue(Catalog.FindModule('ohienko-uk', M));
    Assert.IsTrue(M.Kind = ckBibleTranslation);
    Assert.AreEqual('uk', M.Language);
    Assert.AreEqual('', M.Author);
    Assert.AreEqual(2, M.ChildCount);
  finally
    Catalog.Free;
  end;
end;

procedure TLibraryTests.LoadCatalog_ReadsChaptersAndBooks;
var
  Catalog: TLibraryCatalog;
  Books: TArray<TBookInfo>;
begin
  Catalog := FLibrary.LoadCatalog;
  try
    Assert.AreEqual('Почему был допущен грех', Catalog.ChapterTitle(ChapterRef('PP', 1)));
    Assert.AreEqual('Сотворение', Catalog.Chapters('PP')[1].Title);

    Books := Catalog.Books('ohienko-uk');
    Assert.AreEqual(2, Integer(Length(Books)));
    Assert.AreEqual('GEN', string(Books[0].Ref.BookCode));
    Assert.AreEqual('Буття', Books[0].DisplayTitle);
    Assert.AreEqual(50, Books[0].ChapterCount);
    Assert.AreEqual('PSA', string(Books[1].Ref.BookCode));
    Assert.IsTrue(Catalog.IsValid(BibleRef('ohienko-uk', 'PSA', 150)));
  finally
    Catalog.Free;
  end;
end;

procedure TLibraryTests.GetChapterContent_OrderedWithPagesAndSpans;
var
  R: TResult<TChapterContent>;
  P: TArray<TParagraphContent>;
  I: Integer;
begin
  R := FLibrary.GetChapterContent(ChapterRef('PP', 1));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual('Почему был допущен грех', R.Value.Title);
  Assert.AreEqual('PP', string(R.Value.Ref.ModuleId));

  P := R.Value.Paragraphs;
  Assert.AreEqual(5, Integer(Length(P)));
  for I := 0 to High(P) do
    Assert.AreEqual(I + 1, P[I].Ref.LogicalIndex, 'ORDER BY LogicalIndex');

  Assert.IsTrue(P[0].Kind = pkChapterTitle);
  Assert.IsTrue(P[1].Kind = pkEpigraph);
  Assert.IsTrue(P[2].Kind = pkText);
  Assert.IsTrue(P[4].Kind = pkSectionHeading);

  // Page fields (B-17, B-23)
  Assert.AreEqual(33, P[2].StartPageNumber);
  Assert.AreEqual(1, P[2].ParagraphOnPage);
  Assert.AreEqual(-1, P[2].PageBreakOffset);
  Assert.AreEqual(20, P[3].PageBreakOffset);
  Assert.AreEqual(2, P[3].ParagraphOnPage);

  // Spans (B-18) land on the right paragraph, in offset order; offsets are UTF-16 (B-24)
  Assert.AreEqual(2, Integer(Length(P[2].InlineSpans)));
  Assert.AreEqual('Бог', Copy(P[2].Text, P[2].InlineSpans[0].StartOffset + 1, P[2].InlineSpans[0].Len));
  Assert.IsTrue(P[2].InlineSpans[0].Kind = iskItalic);
  Assert.AreEqual('Его природа', Copy(P[2].Text, P[2].InlineSpans[1].StartOffset + 1, P[2].InlineSpans[1].Len));
  Assert.AreEqual(1, Integer(Length(P[3].InlineSpans)));
  Assert.AreEqual('Божьего', Copy(P[3].Text, P[3].InlineSpans[0].StartOffset + 1, P[3].InlineSpans[0].Len));
  Assert.IsTrue(P[3].InlineSpans[0].Kind = iskBold);
  Assert.AreEqual(0, Integer(Length(P[0].InlineSpans)));
end;

procedure TLibraryTests.GetChapterContent_UnknownChapter_IsNotFound;
var
  R: TResult<TChapterContent>;
begin
  R := FLibrary.GetChapterContent(ChapterRef('PP', 99));
  Assert.IsFalse(R.IsSuccess);
  Assert.IsTrue(R.Error = reNotFound);
  R := FLibrary.GetChapterContent(ChapterRef('NOPE', 1));
  Assert.IsTrue(R.Error = reNotFound);
end;

procedure TLibraryTests.GetBibleChapter_OrderedVerses;
var
  R: TResult<TBibleChapterContent>;
begin
  R := FLibrary.GetBibleChapter(BibleRef('ohienko-uk', 'GEN', 1));
  Assert.IsTrue(R.IsSuccess);
  Assert.AreEqual(2, Integer(Length(R.Value.Verses)));
  Assert.AreEqual(1, R.Value.Verses[0].Ref.VerseNumber);
  Assert.AreEqual(2, R.Value.Verses[1].Ref.VerseNumber);
  Assert.AreEqual('На початку Бог створив небо та землю.', R.Value.Verses[0].Text);
  Assert.AreEqual('GEN', string(R.Value.Verses[0].Ref.Chapter.Book.BookCode));
end;

procedure TLibraryTests.GetBibleChapter_UnknownChapter_IsNotFound;
var
  R: TResult<TBibleChapterContent>;
begin
  R := FLibrary.GetBibleChapter(BibleRef('ohienko-uk', 'GEN', 3));
  Assert.IsTrue(R.Error = reNotFound);
  R := FLibrary.GetBibleChapter(BibleRef('kjv-en', 'MAT', 1));
  Assert.IsTrue(R.Error = reNotFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TLibraryTests);

end.
