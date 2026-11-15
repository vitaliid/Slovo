unit Presentation.SearchResults.Tests;

{ Presentation.SearchResults (Slovo_04 A.4, C.5) without a form: snippet runs,
  reference lines, the two sections and the Bible grouped by translation (B-27,
  B-31), the status-line numbers (E-12); TSearchResultsModel - the grouped
  list built from counts and read in windows (E-19, E-20, B-34). }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
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

  [TestFixture]
  TResultsModelTests = class
  private
    FCatalog: TLibraryCatalog;
    FChapterLabel: TChapterLabelFunc;
    FCalls: TList<string>;              // 'PP,DA|text|0|50'
    FRowsPerBlock: Integer;             // how many rows the fake windows have in all
    FModel: TSearchResultsModel;
    function Model(const BookCounts: TArray<TBookHitCount>; const BibleCounts: TArray<TBibleHitCount>;
      Order: TSearchOrder): TSearchResultsModel;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure NoCounts_NoParts;
    [Test] procedure Text_BooksInLibraryOrder_ChapterHeadings;
    [Test] procedure Text_Lines_HeadingsAndHitsInOrder;
    [Test] procedure Text_RefIsPageOnly_EmptyWithoutPageSystem;
    [Test] procedure Windows_ReadOnce_OnDemand;
    [Test] procedure Window_ShorterThanCounted_RowNotLoaded;
    [Test] procedure Relevance_Books_OneBlockPerLanguage_FullRef;
    [Test] procedure Bible_Text_TranslationBlocks_BookHeadings;
    [Test] procedure Bible_Relevance_TranslationBlocks_NoHeadings;
    [Test] procedure PinnedText_BlockAndHeading;
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

{ TResultsModelTests }

function BookHits(const Id: string; ChapterOrder, Count: Integer): TBookHitCount;
begin
  Result.ModuleId := TModuleId(Id);
  Result.ChapterOrder := ChapterOrder;
  Result.Count := Count;
end;

function BibleHits(const Id, BookCode: string; Count: Integer): TBibleHitCount;
begin
  Result.ModuleId := TModuleId(Id);
  Result.BookCode := TBookCode(BookCode);
  Result.Count := Count;
end;

procedure TResultsModelTests.Setup;

  function Module(const Id, Title, Language: string; Kind: TContentKind): TModule;
  begin
    Result := Default(TModule);
    Result.Id := TModuleId(Id);
    Result.Title := Title;
    Result.Language := Language;
    Result.Kind := Kind;
  end;

  function Chapter(const Id: string; Order: Integer; const Title: string): TChapterInfo;
  begin
    Result := Default(TChapterInfo);
    Result.Ref.ModuleId := TModuleId(Id);
    Result.Ref.ChapterOrder := Order;
    Result.Title := Title;
  end;

  function Book(const Id, Code: string; Order: Integer; const Title: string): TBookInfo;
  begin
    Result := Default(TBookInfo);
    Result.Ref.ModuleId := TModuleId(Id);
    Result.Ref.BookCode := TBookCode(Code);
    Result.OrderInModule := Order;
    Result.DisplayTitle := Title;
    Result.ChapterCount := 50;
  end;

begin
  FCatalog := TLibraryCatalog.Create(
    [Module('PP', 'Патріархи і пророки', 'ru', ckBook), Module('DA', 'Бажання віків', 'ru', ckBook),
     Module('SC', 'Steps to Christ', 'en', ckBook),
     Module('UBIO', 'Огієнко', 'uk', ckBibleTranslation), Module('RST', 'Синодальний', 'ru', ckBibleTranslation)],
    [Chapter('PP', 1, 'Чому був допущений гріх'), Chapter('PP', 3, 'Спокуса і падіння'),
     Chapter('DA', 2, ''), Chapter('SC', 1, 'God''s Love')],
    [Book('UBIO', 'GEN', 1, 'Буття'), Book('UBIO', 'PSA', 2, 'Псалми'), Book('RST', 'GEN', 1, 'Бытие')]);
  FChapterLabel := function(ChapterOrder: Integer): string
    begin
      Result := 'Розділ ' + IntToStr(ChapterOrder);
    end;
  FCalls := TList<string>.Create;
  FRowsPerBlock := MaxInt;
end;

procedure TResultsModelTests.TearDown;
begin
  FreeAndNil(FModel);
  FreeAndNil(FCalls);
  FreeAndNil(FCatalog);
  FChapterLabel := nil;
end;

// What a window was asked for: 'PP,DA|text|0|50'. Not a local function: an
// anonymous method cannot call one.
function WindowCall(const ModuleIds: TArray<TModuleId>; Order: TSearchOrder; Offset, Count: Integer): string;
var
  Id: TModuleId;
begin
  Result := '';
  for Id in ModuleIds do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + string(Id);
  end;
  if Order = soText then
    Result := Result + '|text'
  else
    Result := Result + '|rank';
  Result := Result + Format('|%d|%d', [Offset, Count]);
end;

// The fake windows: row N of a block is the snippet "hit N", page 70 + N, chapter 3
// of the first module; verse N + 1 of GEN 22.
function TResultsModelTests.Model(const BookCounts: TArray<TBookHitCount>;
  const BibleCounts: TArray<TBibleHitCount>; Order: TSearchOrder): TSearchResultsModel;

begin
  FreeAndNil(FModel);
  FModel := TSearchResultsModel.Create(BookCounts, BibleCounts, FCatalog,
    ['DA', 'PP', 'SC', 'RST', 'UBIO'], Order, FChapterLabel,
    function(const ModuleIds: TArray<TModuleId>; AOrder: TSearchOrder; Offset, Count: Integer): TArray<TBookSearchResult>
    var
      I: Integer;
    begin
      FCalls.Add(WindowCall(ModuleIds, AOrder, Offset, Count));
      Result := nil;
      for I := Offset to Offset + Count - 1 do
        if I < FRowsPerBlock then
          Result := Result + [BookItem(string(ModuleIds[0]), 3, 70 + I, 2, 'hit ' + IntToStr(I))];
    end,
    function(const ModuleIds: TArray<TModuleId>; AOrder: TSearchOrder; Offset, Count: Integer): TArray<TBibleSearchResult>
    var
      I: Integer;
    begin
      FCalls.Add(WindowCall(ModuleIds, AOrder, Offset, Count));
      Result := nil;
      for I := Offset to Offset + Count - 1 do
        if I < FRowsPerBlock then
          Result := Result + [VerseItem(string(ModuleIds[0]), 'GEN', 22, I + 1)];
    end);
  Result := FModel;
end;

procedure TResultsModelTests.NoCounts_NoParts;
var
  M: TSearchResultsModel;
begin
  M := Model(nil, nil, soText);
  Assert.AreEqual(0, Integer(Length(M.Parts)));
  Assert.AreEqual(0, M.TotalHits);
  Assert.IsFalse(M.Line(0, 0, 0).Loaded);
  Assert.AreEqual('', M.PinnedText(0, 0, 0));
end;

procedure TResultsModelTests.Text_BooksInLibraryOrder_ChapterHeadings;
var
  M: TSearchResultsModel;
  PP, DA: TResultBlock;
begin
  // Counts come in the order of the index (PP, then DA); the library lists DA first.
  M := Model([BookHits('PP', 1, 2), BookHits('PP', 3, 1), BookHits('DA', 2, 1)], nil, soText);
  Assert.AreEqual(1, Integer(Length(M.Parts)), 'no Bible part without Bible matches');
  Assert.IsTrue(M.Parts[0].Kind = rsBooks);
  Assert.AreEqual(4, M.TotalHits);
  Assert.AreEqual(2, Integer(Length(M.Parts[0].Blocks)));
  DA := M.Parts[0].Blocks[0];
  PP := M.Parts[0].Blocks[1];
  Assert.AreEqual('Бажання віків', DA.Caption);
  Assert.AreEqual('Патріархи і пророки', PP.Caption);
  Assert.AreEqual(3, PP.HitCount);
  Assert.AreEqual(5, PP.RowCount, 'two headings and three matches');
  Assert.AreEqual('1 · Чому був допущений гріх', PP.Headings[0].Caption);
  Assert.AreEqual('3 · Спокуса і падіння', PP.Headings[1].Caption);
  Assert.AreEqual(3, PP.Headings[1].Row);
  Assert.AreEqual(2, PP.Headings[1].FirstHit);
  Assert.AreEqual('Розділ 2', DA.Headings[0].Caption, 'a chapter without a title');
  Assert.AreEqual(0, Integer(FCalls.Count), 'building the list reads no rows');
end;

procedure TResultsModelTests.Text_Lines_HeadingsAndHitsInOrder;
var
  M: TSearchResultsModel;
  L: TResultLine;
begin
  M := Model([BookHits('PP', 1, 2), BookHits('PP', 3, 1)], nil, soText);
  L := M.Line(0, 0, 0);
  Assert.IsTrue(L.Kind = rlHeading);
  Assert.AreEqual('1 · Чому був допущений гріх', L.RefText);
  L := M.Line(0, 0, 1);
  Assert.IsTrue((L.Kind = rlHit) and L.Loaded);
  Assert.AreEqual('hit 0', L.Runs[0].Text);
  Assert.AreEqual('hit 1', M.Line(0, 0, 2).Runs[0].Text);
  Assert.IsTrue(M.Line(0, 0, 3).Kind = rlHeading);
  L := M.Line(0, 0, 4);
  Assert.AreEqual('hit 2', L.Runs[0].Text, 'the heading takes a row, not a match');
  Assert.AreEqual('PP', string(L.BookRef.Chapter.ModuleId));
  Assert.IsFalse(M.Line(0, 0, 5).Loaded, 'past the last row');
end;

procedure TResultsModelTests.Text_RefIsPageOnly_EmptyWithoutPageSystem;
var
  M: TSearchResultsModel;
begin
  M := Model([BookHits('PP', 3, 1)], nil, soText);
  Assert.AreEqual('70.2', M.Line(0, 0, 1).RefText);

  FreeAndNil(FModel);
  FModel := TSearchResultsModel.Create([BookHits('PP', 3, 1)], nil, FCatalog, nil, soText, FChapterLabel,
    function(const ModuleIds: TArray<TModuleId>; AOrder: TSearchOrder; Offset, Count: Integer): TArray<TBookSearchResult>
    begin
      Result := [BookItem('PP', 3, 0, 0, 'no pages')];
    end, nil);
  Assert.AreEqual('', FModel.Line(0, 0, 1).RefText);
end;

procedure TResultsModelTests.Windows_ReadOnce_OnDemand;
var
  M: TSearchResultsModel;
begin
  M := Model([BookHits('PP', 1, 120)], nil, soText);
  Assert.AreEqual('hit 0', M.Line(0, 0, 1).Runs[0].Text);
  Assert.AreEqual('hit 49', M.Line(0, 0, 50).Runs[0].Text);
  Assert.AreEqual(1, Integer(FCalls.Count));
  Assert.AreEqual('PP|text|0|50', FCalls[0]);

  Assert.AreEqual('hit 119', M.Line(0, 0, 120).Runs[0].Text);
  Assert.AreEqual(2, Integer(FCalls.Count), 'the window between is not read');
  Assert.AreEqual('PP|text|100|50', FCalls[1]);

  M.Line(0, 0, 101);
  M.Line(0, 0, 2);
  Assert.AreEqual(2, Integer(FCalls.Count), 'a window is read once');
end;

procedure TResultsModelTests.Window_ShorterThanCounted_RowNotLoaded;
var
  M: TSearchResultsModel;
begin
  // The window failed or the base changed: the row stays empty and is not asked for again.
  FRowsPerBlock := 1;
  M := Model([BookHits('PP', 1, 3)], nil, soText);
  Assert.IsTrue(M.Line(0, 0, 1).Loaded);
  Assert.IsFalse(M.Line(0, 0, 2).Loaded);
  Assert.IsFalse(M.Line(0, 0, 3).Loaded);
  Assert.AreEqual(1, Integer(FCalls.Count));
end;

procedure TResultsModelTests.Relevance_Books_OneBlockPerLanguage_FullRef;
var
  M: TSearchResultsModel;
  L: TResultLine;
begin
  M := Model([BookHits('SC', 1, 1), BookHits('PP', 1, 2), BookHits('PP', 3, 1), BookHits('DA', 2, 1)], nil, soRelevance);
  Assert.AreEqual(2, Integer(Length(M.Parts[0].Blocks)), 'ru and en');
  Assert.AreEqual('', M.Parts[0].Blocks[0].Caption);
  Assert.AreEqual(0, Integer(Length(M.Parts[0].Blocks[0].Headings)));
  Assert.AreEqual(4, M.Parts[0].Blocks[0].RowCount, 'ru before en: PP and DA');
  Assert.AreEqual(1, M.Parts[0].Blocks[1].RowCount);

  L := M.Line(0, 0, 0);
  Assert.IsTrue((L.Kind = rlHit) and L.Loaded);
  Assert.AreEqual('DA,PP|rank|0|50', FCalls[0], 'modules in library order, by rank');
  Assert.AreEqual('Бажання віків · Розділ 3 · 70.2', L.RefText);
  Assert.AreEqual('', M.PinnedText(0, 0, 0));
end;

procedure TResultsModelTests.Bible_Text_TranslationBlocks_BookHeadings;
var
  M: TSearchResultsModel;
  U: TResultBlock;
begin
  M := Model([BookHits('PP', 1, 1)],
    [BibleHits('UBIO', 'GEN', 2), BibleHits('UBIO', 'PSA', 1), BibleHits('RST', 'GEN', 1)], soText);
  Assert.AreEqual(2, Integer(Length(M.Parts)));
  Assert.IsTrue(M.Parts[1].Kind = rsBible);
  Assert.AreEqual(5, M.TotalHits);
  Assert.AreEqual('Синодальний', M.Parts[1].Blocks[0].Caption, 'library order');
  U := M.Parts[1].Blocks[1];
  Assert.AreEqual('Огієнко', U.Caption);
  Assert.AreEqual(5, U.RowCount);
  Assert.AreEqual('Буття', U.Headings[0].Caption);
  Assert.AreEqual('Псалми', U.Headings[1].Caption);
  Assert.AreEqual('22:1', M.Line(1, 1, 1).RefText);
  Assert.AreEqual('22:3', M.Line(1, 1, 4).RefText, 'the third match stands under the second heading');
  Assert.AreEqual('UBIO|text|0|50', FCalls[0]);
end;

procedure TResultsModelTests.Bible_Relevance_TranslationBlocks_NoHeadings;
var
  M: TSearchResultsModel;
begin
  M := Model(nil, [BibleHits('UBIO', 'GEN', 2), BibleHits('UBIO', 'PSA', 1)], soRelevance);
  Assert.IsTrue(M.Parts[0].Kind = rsBible);
  Assert.AreEqual('Огієнко', M.Parts[0].Blocks[0].Caption);
  Assert.AreEqual(3, M.Parts[0].Blocks[0].RowCount);
  Assert.AreEqual('Буття 22:1', M.Line(0, 0, 0).RefText);
  Assert.AreEqual('UBIO|rank|0|50', FCalls[0]);
end;

procedure TResultsModelTests.PinnedText_BlockAndHeading;
var
  M: TSearchResultsModel;
begin
  M := Model([BookHits('PP', 1, 2), BookHits('PP', 3, 1)], [BibleHits('UBIO', 'GEN', 1)], soText);
  Assert.AreEqual('Патріархи і пророки · 1 · Чому був допущений гріх', M.PinnedText(0, 0, 2));
  Assert.AreEqual('Патріархи і пророки · 3 · Спокуса і падіння', M.PinnedText(0, 0, 3));
  Assert.AreEqual('Патріархи і пророки · 3 · Спокуса і падіння', M.PinnedText(0, 0, 4));
  Assert.AreEqual('Огієнко · Буття', M.PinnedText(1, 0, 1));
  Assert.AreEqual(0, Integer(FCalls.Count), 'the pinned line reads no rows');
end;

initialization
  TDUnitX.RegisterTestFixture(TSearchResultsTests);
  TDUnitX.RegisterTestFixture(TResultsModelTests);

end.
