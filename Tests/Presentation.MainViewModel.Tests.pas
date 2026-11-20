unit Presentation.MainViewModel.Tests;

{ TMainViewModel with hand-written fakes of ILibrary and ISearchIndex, the real
  TIniSettings in a temp folder and an in-memory catalog (Slovo_03 Part C).
  Everything is synchronous (C-21). Also TEvent<T>. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Core.Domain,
  Core.Catalog,
  Core.Contracts,
  Core.Events,
  Presentation.MainViewModel,
  Presentation.GoToPage,
  Slovo.TestSupport;

type
  TFakeLibrary = class(TInterfacedObject, ILibrary)
  public
    FailWith: TResultError;              // reNone = success
    Calls: Integer;
    VerseCount: Integer;                 // GetBibleChapter gives verses 1..VerseCount
    PageLookup: TPageLookup;             // every FindPage answers with this
    PageError: TResultError;
    PageCalls: Integer;
    PageModule: string;
    PageNumber: Integer;
    function LoadCatalog: TLibraryCatalog;
    function GetChapterContent(const Ref: TChapterRef): TResult<TChapterContent>;
    function GetBibleChapter(const Ref: TBibleChapterRef): TResult<TBibleChapterContent>;
    function FindPage(const ModuleId: TModuleId; PageNumber: Integer): TResult<TPageLookup>;
  end;

  TFakeSearch = class(TInterfacedObject, ISearchIndex)
  public
    BookQueries: TList<TSearchQuery>;         // CountBook calls
    BibleQueries: TList<TSearchQuery>;        // CountBible calls
    BookWindowQueries: TList<TSearchQuery>;   // SearchBook calls, with their windows
    BookWindows: TList<TSearchWindow>;
    BibleWindowQueries: TList<TSearchQuery>;
    BibleWindows: TList<TSearchWindow>;
    BookCounts: TArray<TBookHitCount>;
    BibleCounts: TArray<TBibleHitCount>;
    BookRows: TArray<TBookSearchResult>;      // every SearchBook answers with these
    BookError, BibleError, WindowError, FindError: TResultError;
    Hits: TArray<TParagraphHit>;
    VerseHits: TArray<TVerseHit>;
    FindCalls: Integer;
    constructor Create;
    destructor Destroy; override;
    function CountBook(const Query: TSearchQuery): TResult<TArray<TBookHitCount>>;
    function CountBible(const Query: TSearchQuery): TResult<TArray<TBibleHitCount>>;
    function SearchBook(const Query: TSearchQuery; const Window: TSearchWindow): TResult<TArray<TBookSearchResult>>;
    function SearchBible(const Query: TSearchQuery; const Window: TSearchWindow): TResult<TArray<TBibleSearchResult>>;
    function FindInChapter(const Query: TSearchQuery; const Ref: TChapterRef): TResult<TArray<TParagraphHit>>;
    function FindInBibleChapter(const Query: TSearchQuery; const Ref: TBibleChapterRef): TResult<TArray<TVerseHit>>;
  end;

  [TestFixture]
  TGoToParseTests = class
  public
    [Test] procedure Empty_AndSpaces;
    [Test] procedure Number;
    [Test] procedure Pair_AnySeparator;
    [Test] procedure SeparatorWithoutSecondNumber_IsANumber;
    [Test] procedure Letters_AreAnotherBook;
    [Test] procedure Bad;
  end;

  [TestFixture]
  TEventTests = class
  public
    [Test] procedure Fire_CallsAllHandlers_RemoveByIdentity;
  end;

  [TestFixture]
  TMainViewModelTests = class
  private
    FDir: string;
    FSettingsFile: string;
    FCatalog: TLibraryCatalog;
    FLibrary: TFakeLibrary;
    FLibraryRef: ILibrary;
    FSearch: TFakeSearch;
    FSearchRef: ISearchIndex;
    FLogger: TTestLogger;
    FLoggerRef: IInterface;
    FVM: TMainViewModel;
    FNodes: TArray<TLibraryNode>;
    FViews: TList<TReaderView>;
    FErrors: TList<TResultError>;
    FLoaded: TList<TChapterLoadedArgs>;
    FBibleLoaded: TList<TBibleChapterLoadedArgs>;
    FReplies: TList<TSearchSummary>;
    procedure WriteSettings(const Text: string);
    procedure CreateViewModel;
    function NodeIndex(Kind: TLibraryNodeKind; const ModuleId: string; const BookCode: string = ''): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test] procedure Start_BuildsTree_ByCategorySeriesAndTitle;
    [Test] procedure Start_TreeIsConsistent_AndHasBibleChapters;
    [Test] procedure Start_NoSavedPosition_ShowsShelf;
    [Test] procedure ShowSeriesShelf_KeepsTheSeries_UntilAnotherShelf;
    [Test] procedure Start_SavedPosition_OpensChapter;
    [Test] procedure Start_InvalidPosition_ShelfAndLog_NoBanner;
    [Test] procedure Start_ChapterFailsToLoad_ShelfAndLog_NoBanner;
    [Test] procedure Start_DropsUnknownCheckedModules;
    [Test] procedure OpenChapter_SavesPosition;
    [Test] procedure OpenChapter_LibraryError_FiresError;
    [Test] procedure OpenChapter_WithActiveSearch_PassesHits;
    [Test] procedure OpenChapter_FindFails_ChapterStillShown;
    [Test] procedure Search_EmptyText_NoCalls;
    [Test] procedure Search_NothingChecked_NoCalls;
    [Test] procedure Search_WholeLibrary_BothCallsWithEmptyScope;
    [Test] procedure Search_OnlyBooksChecked_NoBibleCall;
    [Test] procedure Search_BookError_FiresErrorAndSkipsBible;
    [Test] procedure Search_GivesCounts_ReadsNoRows;
    [Test] procedure FetchBookResults_NoActiveSearch_NoCall;
    [Test] procedure FetchBookResults_IsAWindowOfTheActiveSearch;
    [Test] procedure FetchBookResults_Error_FiresErrorAndGivesNoRows;
    [Test] procedure OpenSearchResult_FocusesThatParagraph;
    [Test] procedure NextPrevious_Bible_CrossesBookButNotModule;
    [Test] procedure ReportUnexpected_LogsAndFires;

    // E-24
    [Test] procedure GoTo_NoPosition_NoScope;
    [Test] procedure GoTo_Scope_TocOfABook_AndPosition;
    [Test] procedure GoTo_Book_PageFound;
    [Test] procedure GoTo_Book_WhatIsNotAPage;
    [Test] procedure GoTo_Book_PageMissing;
    [Test] procedure GoTo_Book_OpensTheChapterWithTarget;
    [Test] procedure GoTo_Bible_ChapterAndVerse;
  end;

implementation

uses
  System.IOUtils,
  Infra.Settings.IniSettings;

{ TFakeLibrary }

function TFakeLibrary.LoadCatalog: TLibraryCatalog;
begin
  raise ENotSupportedException.Create('not used by the ViewModel');
end;

function TFakeLibrary.GetChapterContent(const Ref: TChapterRef): TResult<TChapterContent>;
var
  C: TChapterContent;
begin
  Inc(Calls);
  if FailWith <> reNone then
    Exit(TResult<TChapterContent>.Failure(FailWith));
  C := Default(TChapterContent);
  C.Ref := Ref;
  C.Title := Format('%s %d', [string(Ref.ModuleId), Ref.ChapterOrder]);
  Result := TResult<TChapterContent>.Success(C);
end;

function TFakeLibrary.GetBibleChapter(const Ref: TBibleChapterRef): TResult<TBibleChapterContent>;
var
  C: TBibleChapterContent;
  I: Integer;
begin
  Inc(Calls);
  if FailWith <> reNone then
    Exit(TResult<TBibleChapterContent>.Failure(FailWith));
  C := Default(TBibleChapterContent);
  C.Ref := Ref;
  SetLength(C.Verses, VerseCount);
  for I := 0 to VerseCount - 1 do
  begin
    C.Verses[I].Ref.Chapter := Ref;
    C.Verses[I].Ref.VerseNumber := I + 1;
    C.Verses[I].Text := Format('verse %d', [I + 1]);
  end;
  Result := TResult<TBibleChapterContent>.Success(C);
end;

function TFakeLibrary.FindPage(const ModuleId: TModuleId; PageNumber: Integer): TResult<TPageLookup>;
begin
  Inc(PageCalls);
  PageModule := ModuleId;
  Self.PageNumber := PageNumber;
  if PageError <> reNone then
    Exit(TResult<TPageLookup>.Failure(PageError));
  Result := TResult<TPageLookup>.Success(PageLookup);
end;

{ TGoToParseTests }

procedure TGoToParseTests.Empty_AndSpaces;
begin
  Assert.IsTrue(ParseGoTo('').Kind = giEmpty);
  Assert.IsTrue(ParseGoTo('   ').Kind = giEmpty);
end;

procedure TGoToParseTests.Number;
var
  R: TGoToInput;
begin
  R := ParseGoTo(' 71 ');
  Assert.IsTrue(R.Kind = giNumber);
  Assert.AreEqual(71, R.First);
  Assert.AreEqual(0, ParseGoTo('0').First);
  Assert.IsTrue(ParseGoTo('99999').Kind = giNumber);
end;

procedure TGoToParseTests.Pair_AnySeparator;
const
  Texts: array[0..5] of string = ('3:4', '3.4', '3,4', '3 4', ' 3 : 4 ', '3  .  4');
var
  S: string;
  R: TGoToInput;
begin
  for S in Texts do
  begin
    R := ParseGoTo(S);
    Assert.IsTrue(R.Kind = giPair, S);
    Assert.AreEqual(3, R.First, S);
    Assert.AreEqual(4, R.Second, S);
  end;
end;

procedure TGoToParseTests.SeparatorWithoutSecondNumber_IsANumber;
var
  R: TGoToInput;
begin
  R := ParseGoTo('3:');
  Assert.IsTrue(R.Kind = giNumber);
  Assert.AreEqual(3, R.First);
  Assert.IsTrue(ParseGoTo('3 .').Kind = giNumber);
end;

procedure TGoToParseTests.Letters_AreAnotherBook;
begin
  Assert.IsTrue(ParseGoTo('ПП 71').Kind = giLetters);
  Assert.IsTrue(ParseGoTo('Бут 3:4').Kind = giLetters);
  Assert.IsTrue(ParseGoTo('a').Kind = giLetters);
end;

procedure TGoToParseTests.Bad;
const
  Texts: array[0..7] of string = ('3::4', ':4', '3:4:5', '-1', '123456', '3/4', '3 4 5', '+7');
var
  S: string;
begin
  for S in Texts do
    Assert.IsTrue(ParseGoTo(S).Kind = giBad, S);
end;

{ TFakeSearch }

constructor TFakeSearch.Create;
begin
  inherited Create;
  BookQueries := TList<TSearchQuery>.Create;
  BibleQueries := TList<TSearchQuery>.Create;
  BookWindowQueries := TList<TSearchQuery>.Create;
  BookWindows := TList<TSearchWindow>.Create;
  BibleWindowQueries := TList<TSearchQuery>.Create;
  BibleWindows := TList<TSearchWindow>.Create;
end;

destructor TFakeSearch.Destroy;
begin
  BibleWindows.Free;
  BibleWindowQueries.Free;
  BookWindows.Free;
  BookWindowQueries.Free;
  BibleQueries.Free;
  BookQueries.Free;
  inherited;
end;

function TFakeSearch.CountBook(const Query: TSearchQuery): TResult<TArray<TBookHitCount>>;
begin
  BookQueries.Add(Query);
  if BookError <> reNone then
    Exit(TResult<TArray<TBookHitCount>>.Failure(BookError));
  Result := TResult<TArray<TBookHitCount>>.Success(BookCounts);
end;

function TFakeSearch.CountBible(const Query: TSearchQuery): TResult<TArray<TBibleHitCount>>;
begin
  BibleQueries.Add(Query);
  if BibleError <> reNone then
    Exit(TResult<TArray<TBibleHitCount>>.Failure(BibleError));
  Result := TResult<TArray<TBibleHitCount>>.Success(BibleCounts);
end;

function TFakeSearch.SearchBook(const Query: TSearchQuery;
  const Window: TSearchWindow): TResult<TArray<TBookSearchResult>>;
begin
  BookWindowQueries.Add(Query);
  BookWindows.Add(Window);
  if WindowError <> reNone then
    Exit(TResult<TArray<TBookSearchResult>>.Failure(WindowError));
  Result := TResult<TArray<TBookSearchResult>>.Success(BookRows);
end;

function TFakeSearch.SearchBible(const Query: TSearchQuery;
  const Window: TSearchWindow): TResult<TArray<TBibleSearchResult>>;
var
  NoRows: TArray<TBibleSearchResult>;
begin
  NoRows := nil;
  BibleWindowQueries.Add(Query);
  BibleWindows.Add(Window);
  if WindowError <> reNone then
    Exit(TResult<TArray<TBibleSearchResult>>.Failure(WindowError));
  Result := TResult<TArray<TBibleSearchResult>>.Success(NoRows);
end;

function TFakeSearch.FindInChapter(const Query: TSearchQuery; const Ref: TChapterRef): TResult<TArray<TParagraphHit>>;
begin
  Inc(FindCalls);
  if FindError <> reNone then
    Exit(TResult<TArray<TParagraphHit>>.Failure(FindError));
  Result := TResult<TArray<TParagraphHit>>.Success(Hits);
end;

function TFakeSearch.FindInBibleChapter(const Query: TSearchQuery; const Ref: TBibleChapterRef): TResult<TArray<TVerseHit>>;
begin
  Inc(FindCalls);
  if FindError <> reNone then
    Exit(TResult<TArray<TVerseHit>>.Failure(FindError));
  Result := TResult<TArray<TVerseHit>>.Success(VerseHits);
end;

{ TEventTests }

procedure TEventTests.Fire_CallsAllHandlers_RemoveByIdentity;
var
  E: TEvent<Integer>;
  Sum: Integer;
  H1, H2: TProc<Integer>;
begin
  Sum := 0;
  H1 := procedure(V: Integer) begin Inc(Sum, V); end;
  H2 := procedure(V: Integer) begin Inc(Sum, V * 10); end;
  E := TEvent<Integer>.Create;
  try
    E.Add(H1);
    E.Add(H2);
    E.Fire(1);
    Assert.AreEqual(11, Sum);
    E.Remove(H2);
    E.Fire(1);
    Assert.AreEqual(12, Sum);
    Assert.AreEqual(1, E.Count);
  finally
    E.Free;
  end;
end;

{ catalog fixture }

function Module(const Id, Title: string; Kind: TContentKind; Category: TBookCategory;
  const Series: string = ''; SeriesOrder: Integer = 0; SortOrder: Integer = 0): TModule;
begin
  Result := Default(TModule);
  Result.Id := Id;
  Result.Title := Title;
  Result.Kind := Kind;
  Result.Category := Category;
  Result.Series := Series;
  if Series <> '' then
    Result.SeriesTitle := 'Конфликт веков';
  Result.SeriesOrder := SeriesOrder;
  Result.SortOrder := SortOrder;
end;

function Chapter(const Id: string; Order: Integer): TChapterInfo;
begin
  Result.Ref.ModuleId := Id;
  Result.Ref.ChapterOrder := Order;
  Result.Title := Format('%s-%d', [Id, Order]);
end;

function Book(const Id, Code: string; Order, Count: Integer): TBookInfo;
begin
  Result.Ref.ModuleId := Id;
  Result.Ref.BookCode := Code;
  Result.OrderInModule := Order;
  Result.DisplayTitle := Code;
  Result.ChapterCount := Count;
end;

function ChapterRef(const Id: string; Order: Integer): TChapterRef;
begin
  Result.ModuleId := Id;
  Result.ChapterOrder := Order;
end;

function BibleRef(const Id, Code: string; Chapter: Integer): TBibleChapterRef;
begin
  Result.Book.ModuleId := Id;
  Result.Book.BookCode := Code;
  Result.ChapterNumber := Chapter;
end;

{ TMainViewModelTests }

procedure TMainViewModelTests.Setup;
begin
  FDir := NewTempDir;
  FSettingsFile := TPath.Combine(FDir, 'settings.ini');
  // Deliberately mixed order: the ViewModel sorts (B-25).
  FCatalog := TLibraryCatalog.Create(
    [Module('SC', 'Путь ко Христу', ckBook, bcSpiritOfProphecy),
     Module('DA', 'Желание веков', ckBook, bcSpiritOfProphecy, 'conflict-of-ages', 1, 3),
     Module('H1', 'История', ckBook, bcHistory),
     Module('synodal-ru', 'Синодальный', ckBibleTranslation, bcSpiritOfProphecy),
     Module('MB', 'Нагорная проповедь', ckBook, bcSpiritOfProphecy),
     Module('PP', 'Патриархи и пророки', ckBook, bcSpiritOfProphecy, 'conflict-of-ages', 1, 1),
     Module('ohienko-uk', 'Огієнко', ckBibleTranslation, bcSpiritOfProphecy)],
    [Chapter('PP', 1), Chapter('PP', 2), Chapter('PP', 3), Chapter('DA', 1), Chapter('DA', 2),
     Chapter('SC', 1), Chapter('MB', 1), Chapter('H1', 1)],
    [Book('ohienko-uk', 'GEN', 1, 50), Book('ohienko-uk', 'EXO', 2, 40), Book('synodal-ru', 'GEN', 1, 50)]);
  FLibrary := TFakeLibrary.Create;
  FLibraryRef := FLibrary;
  FSearch := TFakeSearch.Create;
  FSearchRef := FSearch;
  FLogger := TTestLogger.Create;
  FLoggerRef := FLogger;
  FViews := TList<TReaderView>.Create;
  FErrors := TList<TResultError>.Create;
  FLoaded := TList<TChapterLoadedArgs>.Create;
  FBibleLoaded := TList<TBibleChapterLoadedArgs>.Create;
  FReplies := TList<TSearchSummary>.Create;
end;

procedure TMainViewModelTests.TearDown;
begin
  FVM.Free;
  FVM := nil;
  FReplies.Free;
  FBibleLoaded.Free;
  FLoaded.Free;
  FErrors.Free;
  FViews.Free;
  FSearchRef := nil;
  FLibraryRef := nil;
  FCatalog.Free;
  try
    TDirectory.Delete(FDir, True);
  except
  end;
end;

procedure TMainViewModelTests.WriteSettings(const Text: string);
begin
  TFile.WriteAllText(FSettingsFile, Text, TEncoding.UTF8);
end;

procedure TMainViewModelTests.CreateViewModel;
begin
  FVM := TMainViewModel.Create(FLibraryRef, FCatalog, FSearchRef,
    TIniSettings.Create(FSettingsFile, FLogger), FLogger);
  FVM.OnLibraryChanged.Add(procedure(Nodes: TArray<TLibraryNode>) begin FNodes := Nodes; end);
  FVM.OnViewChanged.Add(procedure(V: TReaderView) begin FViews.Add(V); end);
  FVM.OnErrorOccurred.Add(procedure(E: TResultError) begin FErrors.Add(E); end);
  FVM.OnChapterLoaded.Add(procedure(A: TChapterLoadedArgs) begin FLoaded.Add(A); end);
  FVM.OnBibleChapterLoaded.Add(procedure(A: TBibleChapterLoadedArgs) begin FBibleLoaded.Add(A); end);
  FVM.OnSearchCompleted.Add(procedure(R: TSearchSummary) begin FReplies.Add(R); end);
end;

function TMainViewModelTests.NodeIndex(Kind: TLibraryNodeKind; const ModuleId, BookCode: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if (FNodes[I].Kind = Kind) and (FNodes[I].ModuleId = ModuleId) and (FNodes[I].BookCode = BookCode) then
      Exit(I);
  Result := -1;
end;

procedure TMainViewModelTests.Start_BuildsTree_ByCategorySeriesAndTitle;
var
  Roots: TArray<string>;
  I, Series, PP, DA, MB, SC: Integer;
begin
  CreateViewModel;
  FVM.Start;
  for I := 0 to High(FNodes) do
    if FNodes[I].Parent = -1 then
      Roots := Roots + [FNodes[I].CaptionKey];
  Assert.AreEqual('category.spiritOfProphecy,category.history,category.bible', string.Join(',', Roots));

  Series := -1;
  for I := 0 to High(FNodes) do
    if FNodes[I].Kind = lnSeries then
      Series := I;
  PP := NodeIndex(lnModule, 'PP');
  DA := NodeIndex(lnModule, 'DA');
  MB := NodeIndex(lnModule, 'MB');
  SC := NodeIndex(lnModule, 'SC');
  Assert.AreEqual('Конфликт веков', FNodes[Series].Caption);
  Assert.AreEqual('conflict-of-ages', FNodes[Series].Series, 'the series shelf needs its code');
  // Series first, by SortOrder; then the rest by Title (B-25).
  Assert.IsTrue((Series < PP) and (PP < DA) and (DA < MB) and (MB < SC),
    Format('series %d, PP %d, DA %d, MB %d, SC %d', [Series, PP, DA, MB, SC]));
  Assert.AreEqual(Series, FNodes[PP].Parent);
  Assert.AreEqual(0, FNodes[MB].Parent);
  Assert.AreEqual(3, FNodes[PP].Count);
  // Translations by title: «Огієнко» before «Синодальный».
  Assert.IsTrue(NodeIndex(lnBibleTranslation, 'ohienko-uk') < NodeIndex(lnBibleTranslation, 'synodal-ru'));
end;

procedure TMainViewModelTests.Start_TreeIsConsistent_AndHasBibleChapters;
var
  I, Gen, Chapters: Integer;
begin
  CreateViewModel;
  FVM.Start;
  for I := 0 to High(FNodes) do
    Assert.IsTrue(FNodes[I].Parent < I, 'a parent must precede its child');
  Gen := NodeIndex(lnBibleBook, 'ohienko-uk', 'GEN');
  Assert.AreEqual(50, FNodes[Gen].Count);
  Chapters := 0;
  for I := 0 to High(FNodes) do
    if FNodes[I].Parent = Gen then
    begin
      Inc(Chapters);
      Assert.IsTrue(FNodes[I].Kind = lnChapter);
    end;
  Assert.AreEqual(50, Chapters);
  Assert.AreEqual(2, FNodes[NodeIndex(lnBibleTranslation, 'ohienko-uk')].Count);
end;

procedure TMainViewModelTests.ShowSeriesShelf_KeepsTheSeries_UntilAnotherShelf;
begin
  CreateViewModel;
  FVM.Start;
  FVM.ShowSeriesShelf(bcSpiritOfProphecy, 'conflict-of-ages');
  Assert.IsTrue(FVM.View = rvShelf);
  Assert.AreEqual('conflict-of-ages', FVM.ShelfSeries);
  Assert.AreEqual('', string(FVM.ShelfTranslation));
  FVM.ShowShelf(bcSpiritOfProphecy);
  Assert.AreEqual('', FVM.ShelfSeries, 'a category shelf is the whole category');
end;

procedure TMainViewModelTests.Start_NoSavedPosition_ShowsShelf;
begin
  CreateViewModel;
  FVM.Start;
  Assert.IsTrue(FVM.View = rvShelf);
  Assert.IsTrue(FVM.ShelfCategory = bcSpiritOfProphecy);
  Assert.AreEqual(0, Integer(FErrors.Count));
  Assert.AreEqual(0, FLibrary.Calls);
end;

procedure TMainViewModelTests.Start_SavedPosition_OpensChapter;
begin
  WriteSettings('[Reading]' + sLineBreak + 'Last=PP' + sLineBreak + '[Positions]' + sLineBreak + 'PP=2' + sLineBreak);
  CreateViewModel;
  FVM.Start;
  Assert.IsTrue(FVM.View = rvRead);
  Assert.AreEqual(1, Integer(FLoaded.Count));
  Assert.AreEqual(2, FLoaded[0].Content.Ref.ChapterOrder);
end;

procedure TMainViewModelTests.Start_InvalidPosition_ShelfAndLog_NoBanner;
begin
  WriteSettings('[Reading]' + sLineBreak + 'Last=PP' + sLineBreak + '[Positions]' + sLineBreak + 'PP=99' + sLineBreak);
  CreateViewModel;
  FVM.Start;
  Assert.IsTrue(FVM.View = rvShelf);
  Assert.AreEqual(0, Integer(FErrors.Count));
  Assert.IsTrue(FLogger.Contains('Saved position'));
end;

procedure TMainViewModelTests.Start_ChapterFailsToLoad_ShelfAndLog_NoBanner;
begin
  WriteSettings('[Reading]' + sLineBreak + 'Last=PP' + sLineBreak + '[Positions]' + sLineBreak + 'PP=2' + sLineBreak);
  FLibrary.FailWith := reModuleCorrupted;
  CreateViewModel;
  FVM.Start;
  Assert.IsTrue(FVM.View = rvShelf);
  Assert.AreEqual(0, Integer(FErrors.Count));
  Assert.IsTrue(FLogger.Contains('failed at startup'));
end;

procedure TMainViewModelTests.Start_DropsUnknownCheckedModules;
begin
  WriteSettings('[Search]' + sLineBreak + 'Checked=PP,GONE,ohienko-uk' + sLineBreak);
  CreateViewModel;
  FVM.Start;
  Assert.IsTrue(FNodes[NodeIndex(lnModule, 'PP')].Checked);
  Assert.IsFalse(FNodes[NodeIndex(lnModule, 'DA')].Checked);
  Assert.IsTrue(FNodes[NodeIndex(lnBibleTranslation, 'ohienko-uk')].Checked);
  FVM.Search('жертва', False, False, False);
  Assert.AreEqual(1, Integer(Length(FSearch.BookQueries[0].ModuleIds)));
  Assert.AreEqual('PP', string(FSearch.BookQueries[0].ModuleIds[0]));
end;

procedure TMainViewModelTests.OpenChapter_SavesPosition;
var
  Saved: ISettings;
  P: TReadingPosition;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(ChapterRef('DA', 2));
  Assert.IsTrue(FVM.View = rvRead);
  Assert.IsTrue(FVM.HasPosition);
  // Written to disk right away (R4-27).
  Saved := TIniSettings.Create(FSettingsFile, FLogger);
  Assert.IsTrue(Saved.GetLastPosition(P));
  Assert.AreEqual('DA', string(P.ModuleId));
  Assert.AreEqual(2, P.Chapter.ChapterOrder);
end;

procedure TMainViewModelTests.OpenChapter_LibraryError_FiresError;
begin
  CreateViewModel;
  FVM.Start;
  FLibrary.FailWith := reIOFailure;
  FVM.OpenChapter(ChapterRef('PP', 1));
  Assert.AreEqual(1, Integer(FErrors.Count));
  Assert.IsTrue(FErrors[0] = reIOFailure);
  Assert.AreEqual(0, Integer(FLoaded.Count));
  Assert.IsFalse(FVM.HasPosition);

  FVM.OpenChapter(ChapterRef('PP', 99));       // not in the catalog
  Assert.IsTrue(FErrors[1] = reNotFound);
end;

procedure TMainViewModelTests.OpenChapter_WithActiveSearch_PassesHits;
var
  H: TParagraphHit;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(ChapterRef('PP', 1));
  Assert.AreEqual(0, FSearch.FindCalls, 'no search yet - no FindInChapter');

  H := Default(TParagraphHit);
  H.LogicalIndex := 4;
  FSearch.Hits := [H];
  FVM.Search('любовь', True, False, False);
  FVM.OpenChapter(ChapterRef('PP', 1));
  Assert.AreEqual(1, FSearch.FindCalls);
  Assert.AreEqual(1, Integer(Length(FLoaded.Last.Hits)));
  Assert.AreEqual(-1, FLoaded.Last.Focus);
end;

procedure TMainViewModelTests.OpenChapter_FindFails_ChapterStillShown;
begin
  CreateViewModel;
  FVM.Start;
  FVM.Search('любовь', True, False, False);
  FSearch.FindError := reModuleCorrupted;
  FVM.OpenChapter(ChapterRef('PP', 1));
  Assert.AreEqual(1, Integer(FLoaded.Count));
  Assert.AreEqual(0, Integer(Length(FLoaded[0].Hits)));
  Assert.AreEqual(0, Integer(FErrors.Count), 'E-08: no banner, only the log');
  Assert.IsTrue(FLogger.Contains('FindInChapter failed'));
end;

procedure TMainViewModelTests.Search_EmptyText_NoCalls;
begin
  CreateViewModel;
  FVM.Start;
  FVM.Search(#$00A0'  ', True, False, False);
  Assert.AreEqual(0, Integer(FSearch.BookQueries.Count));
  Assert.AreEqual(0, Integer(FSearch.BibleQueries.Count));
  Assert.AreEqual(0, Integer(FReplies.Count));
  Assert.AreEqual(0, Integer(FErrors.Count));
end;

procedure TMainViewModelTests.Search_NothingChecked_NoCalls;
begin
  CreateViewModel;
  FVM.Start;
  FVM.Search('жертва', False, False, False);
  Assert.AreEqual(0, Integer(FSearch.BookQueries.Count));
  Assert.AreEqual(0, Integer(FReplies.Count));
end;

procedure TMainViewModelTests.Search_WholeLibrary_BothCallsWithEmptyScope;
begin
  CreateViewModel;
  FVM.Start;
  FVM.Search('жертва', True, True, True);
  Assert.AreEqual(1, Integer(FSearch.BookQueries.Count));
  Assert.AreEqual(1, Integer(FSearch.BibleQueries.Count));
  Assert.AreEqual(0, Integer(Length(FSearch.BookQueries[0].ModuleIds)));
  Assert.AreEqual(0, Integer(Length(FSearch.BibleQueries[0].ModuleIds)));
  Assert.IsTrue(FSearch.BookQueries[0].ExactPhrase and FSearch.BookQueries[0].WordForms);
  Assert.AreEqual(1, Integer(FReplies.Count));
  Assert.IsTrue(FVM.HasActiveQuery);
end;

procedure TMainViewModelTests.Search_OnlyBooksChecked_NoBibleCall;
begin
  CreateViewModel;
  FVM.Start;
  FVM.SetChecked('PP', True);
  FVM.SetChecked('DA', True);
  FVM.SetChecked('DA', False);
  FVM.Search('жертва', False, False, False);
  Assert.AreEqual(1, Integer(FSearch.BookQueries.Count));
  Assert.AreEqual('PP', string(FSearch.BookQueries[0].ModuleIds[0]));
  // R4-01: no translation checked -> no SearchBible call at all.
  Assert.AreEqual(0, Integer(FSearch.BibleQueries.Count));
  Assert.AreEqual(1, Integer(FReplies.Count));
  Assert.AreEqual(0, Integer(Length(FReplies[0].Bible)));
end;

procedure TMainViewModelTests.Search_BookError_FiresErrorAndSkipsBible;
begin
  CreateViewModel;
  FVM.Start;
  FSearch.BookError := reInvalidQuery;
  FVM.Search('жертва', True, False, False);
  Assert.AreEqual(1, Integer(FErrors.Count));
  Assert.IsTrue(FErrors[0] = reInvalidQuery);
  Assert.AreEqual(0, Integer(FSearch.BibleQueries.Count));
  Assert.AreEqual(0, Integer(FReplies.Count));
  Assert.IsFalse(FVM.HasActiveQuery);
end;

function BookHits(const Id: string; ChapterOrder, Count: Integer): TBookHitCount;
begin
  Result.ModuleId := Id;
  Result.ChapterOrder := ChapterOrder;
  Result.Count := Count;
end;

procedure TMainViewModelTests.Search_GivesCounts_ReadsNoRows;
begin
  CreateViewModel;
  FVM.Start;
  // B-34: a search only counts; the list reads its rows in windows afterwards.
  FSearch.BookCounts := [BookHits('PP', 1, 3), BookHits('PP', 3, 1), BookHits('DA', 2, 1)];
  FVM.Search('жертва', True, False, True);
  Assert.AreEqual(1, Integer(FReplies.Count));
  Assert.AreEqual(3, Integer(Length(FReplies[0].Books)));
  Assert.AreEqual(3, FReplies[0].Books[0].Count);
  Assert.AreEqual(0, Integer(Length(FReplies[0].Bible)));
  Assert.AreEqual('жертва', FReplies[0].Query.Text);
  Assert.AreEqual(0, Integer(FSearch.BookWindows.Count));
  Assert.AreEqual(0, Integer(FSearch.BibleWindows.Count));
end;

procedure TMainViewModelTests.FetchBookResults_NoActiveSearch_NoCall;
begin
  CreateViewModel;
  FVM.Start;
  Assert.AreEqual(0, Integer(Length(FVM.FetchBookResults(['PP'], soText, 0, 50))));
  Assert.AreEqual(0, Integer(FSearch.BookWindows.Count));
end;

procedure TMainViewModelTests.FetchBookResults_IsAWindowOfTheActiveSearch;
var
  Rows: TArray<TBookSearchResult>;
begin
  CreateViewModel;
  FVM.Start;
  FVM.Search('жертва', True, True, False);
  FSearch.BookRows := [Default(TBookSearchResult), Default(TBookSearchResult)];
  Rows := FVM.FetchBookResults(['PP'], soText, 50, 50);
  Assert.AreEqual(2, Integer(Length(Rows)));
  Assert.AreEqual(1, Integer(FSearch.BookWindows.Count));
  Assert.AreEqual('жертва', FSearch.BookWindowQueries[0].Text);
  Assert.IsTrue(FSearch.BookWindowQueries[0].ExactPhrase);
  Assert.AreEqual('PP', string(FSearch.BookWindowQueries[0].ModuleIds[0]));
  Assert.IsTrue(FSearch.BookWindows[0].Order = soText);
  Assert.AreEqual(50, FSearch.BookWindows[0].Offset);
  Assert.AreEqual(50, FSearch.BookWindows[0].Count);
end;

procedure TMainViewModelTests.FetchBookResults_Error_FiresErrorAndGivesNoRows;
begin
  CreateViewModel;
  FVM.Start;
  FVM.Search('жертва', True, False, False);
  FSearch.WindowError := reInvalidQuery;
  Assert.AreEqual(0, Integer(Length(FVM.FetchBookResults(['PP'], soText, 0, 50))));
  Assert.AreEqual(1, Integer(FErrors.Count));
  Assert.IsTrue(FErrors[0] = reInvalidQuery);
end;

procedure TMainViewModelTests.OpenSearchResult_FocusesThatParagraph;
var
  H1, H2: TParagraphHit;
  Ref: TParagraphRef;
begin
  CreateViewModel;
  FVM.Start;
  H1 := Default(TParagraphHit);
  H1.LogicalIndex := 2;
  H2 := Default(TParagraphHit);
  H2.LogicalIndex := 5;
  FSearch.Hits := [H1, H2];
  FVM.Search('любовь', True, False, False);
  Ref.Chapter := ChapterRef('PP', 3);
  Ref.LogicalIndex := 5;
  FVM.OpenSearchResult(Ref);
  Assert.AreEqual(1, FLoaded.Last.Focus);
  // The focus is one-shot: plain navigation afterwards has none.
  FVM.OpenChapter(ChapterRef('PP', 3));
  Assert.AreEqual(-1, FLoaded.Last.Focus);
end;

procedure TMainViewModelTests.NextPrevious_Bible_CrossesBookButNotModule;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(BibleRef('ohienko-uk', 'GEN', 50));
  Assert.IsTrue(FVM.CanGoNext);
  FVM.NextChapter;
  Assert.AreEqual('EXO', string(FBibleLoaded.Last.Content.Ref.Book.BookCode));
  Assert.AreEqual(1, FBibleLoaded.Last.Content.Ref.ChapterNumber);
  Assert.AreEqual('EXO', FBibleLoaded.Last.BookTitle);
  FVM.PreviousChapter;
  Assert.AreEqual('GEN', string(FBibleLoaded.Last.Content.Ref.Book.BookCode));
  Assert.AreEqual(50, FBibleLoaded.Last.Content.Ref.ChapterNumber);

  FVM.OpenChapter(BibleRef('ohienko-uk', 'EXO', 40));
  Assert.IsFalse(FVM.CanGoNext, 'never into another translation');
  FVM.NextChapter;
  Assert.AreEqual(40, FBibleLoaded.Last.Content.Ref.ChapterNumber);

  FVM.OpenChapter(ChapterRef('PP', 1));
  Assert.IsFalse(FVM.CanGoPrevious);
  Assert.IsTrue(FVM.CanGoNext);
end;

procedure TMainViewModelTests.ReportUnexpected_LogsAndFires;
begin
  CreateViewModel;
  FVM.ReportUnexpected('EAccessViolation: boom');
  Assert.IsTrue(FErrors[0] = reUnexpected);
  Assert.IsTrue(FLogger.Contains('boom'));
  FVM.ReportRenderProblem('Chapter PP:1 rendered incompletely');
  Assert.AreEqual(1, Integer(FErrors.Count), 'render problems go to the log only (E-01)');
end;

{ E-24: go to a page }

procedure TMainViewModelTests.GoTo_NoPosition_NoScope;
var
  Scope: TGoToScope;
begin
  CreateViewModel;
  FVM.Start;
  Assert.IsFalse(FVM.GoToScope(Scope));
  Assert.IsTrue(FVM.ResolveGoTo('71').Status = gtEmpty);
  Assert.AreEqual(0, FLibrary.PageCalls);
  // the list of books of a translation is no book either
  FVM.ShowToc('ohienko-uk');
  Assert.IsFalse(FVM.GoToScope(Scope));
end;

procedure TMainViewModelTests.GoTo_Scope_TocOfABook_AndPosition;
var
  Scope: TGoToScope;
  Book: TBookRef;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(ChapterRef('PP', 2));
  Assert.IsTrue(FVM.GoToScope(Scope));
  Assert.IsTrue(Scope.Kind = ckBook);
  Assert.AreEqual('PP', string(Scope.ModuleId));

  FVM.ShowToc('DA');
  Assert.IsTrue(FVM.GoToScope(Scope));
  Assert.AreEqual('DA', string(Scope.ModuleId), 'the table of contents shown');

  FVM.ShowShelf(bcHistory);
  Assert.IsTrue(FVM.GoToScope(Scope));
  Assert.AreEqual('PP', string(Scope.ModuleId), 'the shelf: the reading position');

  Book.ModuleId := 'ohienko-uk';
  Book.BookCode := 'EXO';
  FVM.ShowToc(Book);
  Assert.IsTrue(FVM.GoToScope(Scope));
  Assert.IsTrue(Scope.Kind = ckBibleTranslation);
  Assert.AreEqual('EXO', string(Scope.Book.BookCode));
end;

procedure TMainViewModelTests.GoTo_Book_PageFound;
var
  R: TGoToTarget;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(ChapterRef('PP', 1));
  FLibrary.PageLookup.Found := True;
  FLibrary.PageLookup.Paragraph.Chapter := ChapterRef('PP', 3);
  FLibrary.PageLookup.Paragraph.LogicalIndex := 5;
  FLibrary.PageLookup.StartsInside := True;
  FLibrary.PageLookup.FirstPage := 33;
  FLibrary.PageLookup.LastPage := 790;
  R := FVM.ResolveGoTo(' 71 ');
  Assert.IsTrue(R.Status = gtOk);
  Assert.AreEqual('PP', FLibrary.PageModule);
  Assert.AreEqual(71, FLibrary.PageNumber);
  Assert.AreEqual(3, R.Chapter.ChapterOrder);
  Assert.AreEqual(5, R.Paragraph);
  Assert.AreEqual(71, R.Page);
  Assert.IsTrue(R.StartsInside);
end;

procedure TMainViewModelTests.GoTo_Book_WhatIsNotAPage;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(ChapterRef('PP', 1));
  Assert.IsTrue(FVM.ResolveGoTo('').Status = gtEmpty);
  Assert.IsTrue(FVM.ResolveGoTo('71.2').Status = gtPageOnly);
  Assert.IsTrue(FVM.ResolveGoTo('ПП 71').Status = gtOtherBook);
  Assert.IsTrue(FVM.ResolveGoTo('7-1').Status = gtBadFormat);
  Assert.AreEqual(0, FLibrary.PageCalls, 'nothing to look up');
end;

procedure TMainViewModelTests.GoTo_Book_PageMissing;
var
  R: TGoToTarget;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(ChapterRef('PP', 1));
  FLibrary.PageLookup.FirstPage := 33;
  FLibrary.PageLookup.LastPage := 790;
  R := FVM.ResolveGoTo('900');
  Assert.IsTrue(R.Status = gtPageOutOfRange);
  Assert.AreEqual(33, R.First);
  Assert.AreEqual(790, R.Last);

  FLibrary.PageLookup := Default(TPageLookup);
  Assert.IsTrue(FVM.ResolveGoTo('5').Status = gtNoPages);

  FLibrary.PageError := reIOFailure;
  Assert.IsTrue(FVM.ResolveGoTo('5').Status = gtFailed);
  Assert.AreEqual(0, Integer(FErrors.Count), 'resolving shows no banner');
end;

procedure TMainViewModelTests.GoTo_Book_OpensTheChapterWithTarget;
var
  R: TGoToTarget;
  Before: Integer;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(ChapterRef('PP', 1));
  FLibrary.PageLookup.Found := True;
  FLibrary.PageLookup.Paragraph.Chapter := ChapterRef('PP', 3);
  FLibrary.PageLookup.Paragraph.LogicalIndex := 5;
  FLibrary.PageLookup.StartsInside := True;
  FLibrary.PageLookup.FirstPage := 33;
  FLibrary.PageLookup.LastPage := 790;

  Before := FLoaded.Count;
  FVM.GoToPage(FVM.ResolveGoTo('900x'));
  Assert.AreEqual(Before, Integer(FLoaded.Count), 'not gtOk - nothing opens');

  R := FVM.ResolveGoTo('71');
  FVM.GoToPage(R);
  Assert.AreEqual(3, FLoaded.Last.Content.Ref.ChapterOrder);
  Assert.AreEqual(5, FLoaded.Last.Target);
  Assert.IsTrue(FLoaded.Last.TargetStartsInside);
  Assert.AreEqual(-1, FLoaded.Last.Focus);
  Assert.IsTrue(FVM.View = rvRead);
  // one-shot: plain navigation afterwards has no target
  FVM.OpenChapter(ChapterRef('PP', 3));
  Assert.AreEqual(-1, FLoaded.Last.Target);
  Assert.IsFalse(FLoaded.Last.TargetStartsInside);
end;

procedure TMainViewModelTests.GoTo_Bible_ChapterAndVerse;
var
  R: TGoToTarget;
begin
  CreateViewModel;
  FVM.Start;
  FVM.OpenChapter(BibleRef('ohienko-uk', 'GEN', 1));
  FLibrary.VerseCount := 24;

  R := FVM.ResolveGoTo('51');
  Assert.IsTrue(R.Status = gtChapterOutOfRange);
  Assert.AreEqual(1, R.First);
  Assert.AreEqual(50, R.Last);
  Assert.IsTrue(FVM.ResolveGoTo('0').Status = gtChapterOutOfRange);

  R := FVM.ResolveGoTo('3');
  Assert.IsTrue(R.Status = gtOk);
  Assert.AreEqual(0, R.Verse);
  FVM.GoToPage(R);
  Assert.AreEqual(3, FBibleLoaded.Last.Content.Ref.ChapterNumber);
  Assert.AreEqual(-1, FBibleLoaded.Last.Target, 'a chapter alone - its top');

  R := FVM.ResolveGoTo('3:30');
  Assert.IsTrue(R.Status = gtVerseOutOfRange);
  Assert.AreEqual(1, R.First);
  Assert.AreEqual(24, R.Last);

  R := FVM.ResolveGoTo('3:4');
  Assert.IsTrue(R.Status = gtOk);
  FVM.GoToPage(R);
  Assert.AreEqual('GEN', string(FBibleLoaded.Last.Content.Ref.Book.BookCode));
  Assert.AreEqual(3, FBibleLoaded.Last.Content.Ref.ChapterNumber);
  Assert.AreEqual(4, FBibleLoaded.Last.Target);
  Assert.AreEqual(0, FLibrary.PageCalls, 'the Bible has no pages');
end;

initialization
  TDUnitX.RegisterTestFixture(TGoToParseTests);
  TDUnitX.RegisterTestFixture(TEventTests);
  TDUnitX.RegisterTestFixture(TMainViewModelTests);

end.
