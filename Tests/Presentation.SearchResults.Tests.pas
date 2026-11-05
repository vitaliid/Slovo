unit Presentation.SearchResults.Tests;

{ Presentation.SearchResults (Slovo_04 A.4, C.5) without a form: snippet runs,
  reference lines, the two sections and the Bible grouped by translation (B-27,
  B-31), the status-line numbers (E-12). }

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Core.Domain,
  Core.Catalog,
  Presentation.MainViewModel,
  Presentation.SearchResults;

type
  [TestFixture]
  TSearchResultsTests = class
  private
    FCatalog: TLibraryCatalog;
    FChapterLabel: TChapterLabelFunc;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SplitRuns_NoHighlights_OneRun;
    [Test] procedure SplitRuns_MatchesAreBold;
    [Test] procedure SplitRuns_UnsortedOverlappingAndOutside_SortedMergedClipped;
    [Test] procedure SplitRuns_EmptySnippet_NoRuns;
    [Test] procedure BookRef_WithPage;
    [Test] procedure BookRef_WithoutPageSystem;
    [Test] procedure BibleRef_BookChapterVerse;
    [Test] procedure Sections_EmptyReply_None;
    [Test] procedure Sections_BooksThenBible_BibleGroupedByTranslation;
    [Test] procedure Sections_OnlyBible_OneSection;
    [Test] procedure Count_AndTruncatedFromEitherPage;
  end;

implementation

function Hl(Start, Len: Integer): TSearchHighlight;
begin
  Result.StartOffset := Start;
  Result.Len := Len;
end;

function BookItem(const ModuleId: string; ChapterOrder, Page, OnPage: Integer;
  const Snippet: string): TBookSearchResult;
begin
  Result := Default(TBookSearchResult);
  Result.Ref.Chapter.ModuleId := TModuleId(ModuleId);
  Result.Ref.Chapter.ChapterOrder := ChapterOrder;
  Result.PageNumber := Page;
  Result.ParagraphOnPage := OnPage;
  Result.Snippet := Snippet;
end;

function VerseItem(const ModuleId, BookCode: string; Chapter, Verse: Integer): TBibleSearchResult;
begin
  Result := Default(TBibleSearchResult);
  Result.Ref.Chapter.Book.ModuleId := TModuleId(ModuleId);
  Result.Ref.Chapter.Book.BookCode := TBookCode(BookCode);
  Result.Ref.Chapter.ChapterNumber := Chapter;
  Result.Ref.VerseNumber := Verse;
  Result.Snippet := 'v';
end;

{ TSearchResultsTests }

procedure TSearchResultsTests.Setup;
var
  Modules: TArray<TModule>;
  Books: TArray<TBookInfo>;
  M: TModule;
  B: TBookInfo;
begin
  M := Default(TModule);
  M.Id := 'PP';
  M.Kind := ckBook;
  M.Title := 'Патріархи і пророки';
  Modules := [M];
  M.Id := 'UBIO';
  M.Kind := ckBibleTranslation;
  M.Title := 'Огієнко';
  Modules := Modules + [M];
  M.Id := 'RST';
  M.Title := 'Синодальний';
  Modules := Modules + [M];

  B := Default(TBookInfo);
  B.Ref.ModuleId := 'UBIO';
  B.Ref.BookCode := 'GEN';
  B.OrderInModule := 1;
  B.DisplayTitle := 'Буття';
  B.ChapterCount := 50;
  Books := [B];
  B.Ref.ModuleId := 'RST';
  B.DisplayTitle := 'Бытие';
  Books := Books + [B];

  FCatalog := TLibraryCatalog.Create(Modules, nil, Books);
  FChapterLabel := function(ChapterOrder: Integer): string
    begin
      Result := 'Розділ ' + IntToStr(ChapterOrder);
    end;
end;

procedure TSearchResultsTests.TearDown;
begin
  FreeAndNil(FCatalog);
  FChapterLabel := nil;
end;

procedure TSearchResultsTests.SplitRuns_NoHighlights_OneRun;
var
  Runs: TArray<TTextRun>;
begin
  Runs := SplitRuns('жертва Христа', nil);
  Assert.AreEqual(1, Integer(Length(Runs)));
  Assert.AreEqual('жертва Христа', Runs[0].Text);
  Assert.IsFalse(Runs[0].Bold);
end;

procedure TSearchResultsTests.SplitRuns_MatchesAreBold;
var
  Runs: TArray<TTextRun>;
begin
  // "і жертва Христа": "жертва" at 2..7, "Христа" at 9..14
  Runs := SplitRuns('і жертва Христа', [Hl(2, 6), Hl(9, 6)]);
  Assert.AreEqual(4, Integer(Length(Runs)));
  Assert.AreEqual('і ', Runs[0].Text);
  Assert.IsFalse(Runs[0].Bold);
  Assert.AreEqual('жертва', Runs[1].Text);
  Assert.IsTrue(Runs[1].Bold);
  Assert.AreEqual(' ', Runs[2].Text);
  Assert.AreEqual('Христа', Runs[3].Text);
  Assert.IsTrue(Runs[3].Bold);
end;

procedure TSearchResultsTests.SplitRuns_UnsortedOverlappingAndOutside_SortedMergedClipped;
var
  Runs: TArray<TTextRun>;
begin
  // abcdefghij: [6,+10) clipped to "ghij"; [3,+2) and [2,+2) merge into "cde".
  Runs := SplitRuns('abcdefghij', [Hl(6, 10), Hl(3, 2), Hl(2, 2), Hl(-5, 3), Hl(20, 2)]);
  Assert.AreEqual(4, Integer(Length(Runs)));
  Assert.AreEqual('ab', Runs[0].Text);
  Assert.AreEqual('cde', Runs[1].Text);
  Assert.IsTrue(Runs[1].Bold);
  Assert.AreEqual('f', Runs[2].Text);
  Assert.AreEqual('ghij', Runs[3].Text);
  Assert.IsTrue(Runs[3].Bold);
end;

procedure TSearchResultsTests.SplitRuns_EmptySnippet_NoRuns;
begin
  Assert.AreEqual(0, Integer(Length(SplitRuns('', [Hl(0, 3)]))));
end;

procedure TSearchResultsTests.BookRef_WithPage;
begin
  Assert.AreEqual('Патріархи і пророки · Розділ 3 · 71.2',
    BookResultRef(FCatalog, BookItem('PP', 3, 71, 2, ''), FChapterLabel));
end;

procedure TSearchResultsTests.BookRef_WithoutPageSystem;
begin
  Assert.AreEqual('Патріархи і пророки · Розділ 3',
    BookResultRef(FCatalog, BookItem('PP', 3, 0, 0, ''), FChapterLabel));
end;

procedure TSearchResultsTests.BibleRef_BookChapterVerse;
begin
  Assert.AreEqual('Буття 22:8', BibleResultRef(FCatalog, VerseItem('UBIO', 'GEN', 22, 8)));
end;

procedure TSearchResultsTests.Sections_EmptyReply_None;
begin
  Assert.AreEqual(0, Integer(Length(BuildResultSections(Default(TSearchReply), FCatalog, FChapterLabel))));
end;

procedure TSearchResultsTests.Sections_BooksThenBible_BibleGroupedByTranslation;
var
  Reply: TSearchReply;
  S: TArray<TResultSection>;
begin
  Reply := Default(TSearchReply);
  Reply.Books.Items := [BookItem('PP', 1, 10, 1, 'a'), BookItem('PP', 2, 20, 1, 'b')];
  Reply.Bible.Items := [VerseItem('UBIO', 'GEN', 1, 1), VerseItem('UBIO', 'GEN', 1, 2),
    VerseItem('RST', 'GEN', 3, 4)];
  S := BuildResultSections(Reply, FCatalog, FChapterLabel);

  Assert.AreEqual(2, Integer(Length(S)));
  Assert.IsTrue(S[0].Kind = rsBooks);
  Assert.AreEqual(1, Integer(Length(S[0].Groups)));
  Assert.AreEqual('', S[0].Groups[0].Caption);
  Assert.AreEqual(2, Integer(Length(S[0].Groups[0].Rows)));
  Assert.AreEqual(1, S[0].Groups[0].Rows[1].Index);

  Assert.IsTrue(S[1].Kind = rsBible);
  Assert.AreEqual(2, Integer(Length(S[1].Groups)));
  Assert.AreEqual('Огієнко', S[1].Groups[0].Caption);
  Assert.AreEqual(2, Integer(Length(S[1].Groups[0].Rows)));
  Assert.AreEqual('Синодальний', S[1].Groups[1].Caption);
  Assert.AreEqual(1, Integer(Length(S[1].Groups[1].Rows)));
  Assert.AreEqual('Бытие 3:4', S[1].Groups[1].Rows[0].RefText);
  Assert.AreEqual(2, S[1].Groups[1].Rows[0].Index, 'index into Reply.Bible.Items');
end;

procedure TSearchResultsTests.Sections_OnlyBible_OneSection;
var
  Reply: TSearchReply;
  S: TArray<TResultSection>;
begin
  Reply := Default(TSearchReply);
  Reply.Bible.Items := [VerseItem('RST', 'GEN', 1, 1)];
  S := BuildResultSections(Reply, FCatalog, FChapterLabel);
  Assert.AreEqual(1, Integer(Length(S)));
  Assert.IsTrue(S[0].Kind = rsBible);
  Assert.AreEqual(1, Integer(Length(S[0].Groups)));
end;

procedure TSearchResultsTests.Count_AndTruncatedFromEitherPage;
var
  Reply: TSearchReply;
begin
  Reply := Default(TSearchReply);
  Reply.Books.Items := [BookItem('PP', 1, 0, 0, 'a')];
  Reply.Bible.Items := [VerseItem('RST', 'GEN', 1, 1), VerseItem('RST', 'GEN', 1, 2)];
  Assert.AreEqual(3, ResultCount(Reply));
  Assert.IsFalse(ResultTruncated(Reply));
  Reply.Bible.Truncated := True;
  Assert.IsTrue(ResultTruncated(Reply));
end;

initialization
  TDUnitX.RegisterTestFixture(TSearchResultsTests);

end.
