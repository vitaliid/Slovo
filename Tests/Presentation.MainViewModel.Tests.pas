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
  Slovo.TestSupport;

type
  TFakeLibrary = class(TInterfacedObject, ILibrary)
  public
    FailWith: TResultError;              // reNone = success
    Calls: Integer;
    function LoadCatalog: TLibraryCatalog;
    function GetChapterContent(const Ref: TChapterRef): TResult<TChapterContent>;
    function GetBibleChapter(const Ref: TBibleChapterRef): TResult<TBibleChapterContent>;
  end;

  TFakeSearch = class(TInterfacedObject, ISearchIndex)
  public
    BookQueries: TList<TSearchQuery>;
    BibleQueries: TList<TSearchQuery>;
    BookError, BibleError, FindError: TResultError;
    Hits: TArray<TParagraphHit>;
    VerseHits: TArray<TVerseHit>;
    FindCalls: Integer;
    constructor Create;
    destructor Destroy; override;
    function SearchBook(const Query: TSearchQuery): TResult<TSearchPage<TBookSearchResult>>;
    function SearchBible(const Query: TSearchQuery): TResult<TSearchPage<TBibleSearchResult>>;
    function FindInChapter(const Query: TSearchQuery; const Ref: TChapterRef): TResult<TArray<TParagraphHit>>;
    function FindInBibleChapter(const Query: TSearchQuery; const Ref: TBibleChapterRef): TResult<TArray<TVerseHit>>;
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
    FReplies: TList<TSearchReply>;
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
    [Test] procedure OpenSearchResult_FocusesThatParagraph;
    [Test] procedure NextPrevious_Bible_CrossesBookButNotModule;
    [Test] procedure ReportUnexpected_LogsAndFires;
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
begin
  Inc(Calls);
  if FailWith <> reNone then
    Exit(TResult<TBibleChapterContent>.Failure(FailWith));
  C := Default(TBibleChapterContent);
  C.Ref := Ref;
  Result := TResult<TBibleChapterContent>.Success(C);
end;

{ TFakeSearch }

constructor TFakeSearch.Create;
begin
  inherited Create;
  BookQueries := TList<TSearchQuery>.Create;
  BibleQueries := TList<TSearchQuery>.Create;
end;

destructor TFakeSearch.Destroy;
begin
  BibleQueries.Free;
  BookQueries.Free;
  inherited;
end;

function TFakeSearch.SearchBook(const Query: TSearchQuery): TResult<TSearchPage<TBookSearchResult>>;
begin
  BookQueries.Add(Query);
  if BookError <> reNone then
    Exit(TResult<TSearchPage<TBookSearchResult>>.Failure(BookError));
  Result := TResult<TSearchPage<TBookSearchResult>>.Success(Default(TSearchPage<TBookSearchResult>));
end;

function TFakeSearch.SearchBible(const Query: TSearchQuery): TResult<TSearchPage<TBibleSearchResult>>;
begin
  BibleQueries.Add(Query);
  if BibleError <> reNone then
    Exit(TResult<TSearchPage<TBibleSearchResult>>.Failure(BibleError));
  Result := TResult<TSearchPage<TBibleSearchResult>>.Success(Default(TSearchPage<TBibleSearchResult>));
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
  FReplies := TList<TSearchReply>.Create;
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
  FVM.OnSearchCompleted.Add(procedure(R: TSearchReply) begin FReplies.Add(R); end);
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
  Assert.AreEqual(0, Integer(Length(FReplies[0].Bible.Items)));
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

initialization
  TDUnitX.RegisterTestFixture(TEventTests);
  TDUnitX.RegisterTestFixture(TMainViewModelTests);

end.
